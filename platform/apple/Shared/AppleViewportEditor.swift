import Foundation

/// Provisional seam used by the clean-room Apple viewport editor.
///
/// Offsets and ranges are UTF-16, matching AppKit, UIKit, and `NSRange`. The
/// production buffer may be a piece tree; the editor never asks it to flatten
/// the complete document while drawing or handling an input event.
@MainActor
protocol AppleEditorDocument: AnyObject {
    var utf16Count: Int { get }
    var lineCount: Int { get }
    var revision: UInt64 { get }
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var editorSelection: NSRange { get }

    func lineRange(at line: Int) -> NSRange
    func text(in range: NSRange) -> String
    func setEditorSelection(_ range: NSRange)
    func replace(_ range: NSRange, with text: String)
    func undo()
    func redo()
}

struct AppleViewportSelection: Equatable {
    var range: NSRange

    init(_ range: NSRange = NSRange(location: 0, length: 0)) {
        self.range = range
    }

    mutating func clamp(to length: Int) {
        let start = min(max(range.location, 0), length)
        let end = min(max(range.location + range.length, start), length)
        range = NSRange(location: start, length: end - start)
    }

    mutating func collapse(to offset: Int, documentLength: Int) {
        range = NSRange(location: min(max(offset, 0), documentLength), length: 0)
    }
}

/// Pure range logic shared by the AppKit and UIKit input adapters.
@MainActor
final class AppleEditorInputModel {
    let document: AppleEditorDocument
    private(set) var selection = AppleViewportSelection()
    private(set) var markedRange: NSRange?
    private(set) var preferredVisualX: CGFloat?
    var didChange: (() -> Void)?

    init(document: AppleEditorDocument) {
        self.document = document
    }

    func setSelection(_ range: NSRange) {
        selection.range = range
        selection.clamp(to: document.utf16Count)
        document.setEditorSelection(selection.range)
        didChange?()
    }

    func replaceSelection(with text: String) {
        replace(selection.range, with: text, markInsertedText: false)
    }

    func setMarkedText(_ text: String, selectedRange: NSRange) {
        let target = markedRange ?? selection.range
        replace(target, with: text, markInsertedText: true)
        let inserted = NSRange(location: target.location, length: text.utf16.count)
        markedRange = inserted
        let localStart = min(max(selectedRange.location, 0), inserted.length)
        let localEnd = min(max(selectedRange.location + selectedRange.length, localStart), inserted.length)
        selection.range = NSRange(
            location: inserted.location + localStart,
            length: localEnd - localStart
        )
        document.setEditorSelection(selection.range)
        didChange?()
    }

    func unmarkText() {
        markedRange = nil
        didChange?()
    }

    func deleteBackward() {
        if selection.range.length > 0 {
            replaceSelection(with: "")
        } else if selection.range.location > 0 {
            let start = AppleGraphemeBoundary.previous(before: selection.range.location, in: document)
            replace(NSRange(location: start, length: selection.range.location - start), with: "", markInsertedText: false)
        }
    }

    func moveHorizontal(_ delta: Int, extending: Bool = false) {
        let edge = delta < 0 ? selection.range.location : NSMaxRange(selection.range)
        let destination = delta < 0
            ? AppleGraphemeBoundary.previous(before: edge, in: document)
            : AppleGraphemeBoundary.next(after: edge, in: document)
        preferredVisualX = nil
        if extending {
            let fixed = delta < 0 ? NSMaxRange(selection.range) : selection.range.location
            selection.range = NSRange(location: min(fixed, destination), length: abs(destination - fixed))
        } else {
            selection.collapse(to: destination, documentLength: document.utf16Count)
        }
        markedRange = nil
        document.setEditorSelection(selection.range)
        didChange?()
    }

    func moveToLineBoundary(end: Bool, extending: Bool = false) {
        let caret = extending ? NSMaxRange(selection.range) : selection.range.location
        let line = lineContaining(caret)
        let range = document.lineRange(at: line)
        let destination = end ? range.location + contentLength(of: range) : range.location
        updateSelection(destination: destination, extending: extending)
    }

    func moveVertical(
        _ lines: Int,
        extending: Bool = false,
        xForOffset: (Int) -> CGFloat,
        offsetForLineX: (Int, CGFloat) -> Int
    ) {
        let caret = extending ? NSMaxRange(selection.range) : selection.range.location
        let currentLine = lineContaining(caret)
        let x = preferredVisualX ?? xForOffset(caret)
        preferredVisualX = x
        let destinationLine = min(max(currentLine + lines, 0), max(document.lineCount - 1, 0))
        updateSelection(destination: offsetForLineX(destinationLine, x), extending: extending)
    }

    func undo() {
        document.undo()
        restoreDocumentSelection()
    }

    func redo() {
        document.redo()
        restoreDocumentSelection()
    }

    func selectAll() { setSelection(NSRange(location: 0, length: document.utf16Count)) }

    func boundedContext(around range: NSRange? = nil, limit: Int = 4_096) -> (range: NSRange, text: String) {
        let focus = range ?? selection.range
        let caret = min(max(focus.location, 0), document.utf16Count)
        let half = max(1, limit / 2)
        var start = max(0, caret - half)
        let end = min(document.utf16Count, start + limit)
        start = max(0, end - limit)
        let bounded = NSRange(location: start, length: end - start)
        return (bounded, document.text(in: bounded))
    }

    private func restoreDocumentSelection() {
        selection.range = document.editorSelection
        selection.clamp(to: document.utf16Count)
        document.setEditorSelection(selection.range)
        markedRange = nil
        didChange?()
    }

    private func lineContaining(_ offset: Int) -> Int {
        var low = 0, high = max(document.lineCount - 1, 0)
        while low < high {
            let middle = (low + high + 1) / 2
            if document.lineRange(at: middle).location <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    private func contentLength(of range: NSRange) -> Int {
        document.text(in: range).utf16.prefix { $0 != 10 && $0 != 13 }.count
    }

    private func updateSelection(destination: Int, extending: Bool) {
        if extending {
            let anchor = selection.range.location
            selection.range = NSRange(location: min(anchor, destination), length: abs(destination - anchor))
        } else {
            selection.collapse(to: destination, documentLength: document.utf16Count)
        }
        markedRange = nil
        document.setEditorSelection(selection.range)
        didChange?()
    }

    private func replace(_ range: NSRange, with text: String, markInsertedText: Bool) {
        document.replace(range, with: text)
        let end = range.location + text.utf16.count
        selection.collapse(to: end, documentLength: document.utf16Count)
        if !markInsertedText { markedRange = nil }
        document.setEditorSelection(selection.range)
        didChange?()
    }
}

#if os(macOS)
import AppKit

@MainActor
final class AppleViewportEditorView: NSView, @preconcurrency NSTextInputClient {
    let model: AppleEditorInputModel
    private let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private let layoutCache = AppleVisibleLineLayoutCache(capacity: 128)
    private let inset = CGSize(width: 12, height: 10)
    private lazy var lineHeight = ceil(font.ascender - font.descender + font.leading + 3)
    private var caretVisible = true
    private var caretTimer: Timer?
    private var dragAnchor: Int?

    init(document: AppleEditorDocument) {
        model = AppleEditorInputModel(document: document)
        super.init(frame: .zero)
        model.didChange = { [weak self] in self?.documentDidChange() }
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.firstResponder === self else { return }
                self.caretVisible.toggle()
                self.needsDisplay = true
            }
        }
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Markdown editor")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            caretTimer?.invalidate()
            caretTimer = nil
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateDocumentSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        let first = max(0, Int((dirtyRect.minY - inset.height) / lineHeight))
        let last = min(model.document.lineCount - 1, Int((dirtyRect.maxY - inset.height) / lineHeight) + 1)
        guard last >= first, let context = NSGraphicsContext.current?.cgContext else { return }
        for lineNumber in first...last {
            let shaped = shapedLine(lineNumber)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: inset.width, y: inset.height + CGFloat(lineNumber) * lineHeight + font.ascender)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(shaped.line, context)
            context.restoreGState()
        }
        drawSelection()
        drawCaret()
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = offset(at: convert(event.locationInWindow, from: nil))
        dragAnchor = location
        model.setSelection(NSRange(location: location, length: 0))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor else { return }
        let location = offset(at: convert(event.locationInWindow, from: nil))
        model.setSelection(NSRange(location: min(anchor, location), length: abs(location - anchor)))
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) { dragAnchor = nil }

    override func moveUp(_ sender: Any?) { moveVertical(-1) }
    override func moveDown(_ sender: Any?) { moveVertical(1) }
    override func moveUpAndModifySelection(_ sender: Any?) { moveVertical(-1, extending: true) }
    override func moveDownAndModifySelection(_ sender: Any?) { moveVertical(1, extending: true) }
    override func moveToBeginningOfLine(_ sender: Any?) { model.moveToLineBoundary(end: false) }
    override func moveToEndOfLine(_ sender: Any?) { model.moveToLineBoundary(end: true) }
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) { model.moveToLineBoundary(end: false, extending: true) }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) { model.moveToLineBoundary(end: true, extending: true) }
    override func pageUp(_ sender: Any?) { moveVertical(-visibleLineCount) }
    override func pageDown(_ sender: Any?) { moveVertical(visibleLineCount) }
    override func pageUpAndModifySelection(_ sender: Any?) { moveVertical(-visibleLineCount, extending: true) }
    override func pageDownAndModifySelection(_ sender: Any?) { moveVertical(visibleLineCount, extending: true) }

    override func moveLeft(_ sender: Any?) { model.moveHorizontal(-1) }
    override func moveRight(_ sender: Any?) { model.moveHorizontal(1) }
    override func moveLeftAndModifySelection(_ sender: Any?) { model.moveHorizontal(-1, extending: true) }
    override func moveRightAndModifySelection(_ sender: Any?) { model.moveHorizontal(1, extending: true) }
    override func deleteBackward(_ sender: Any?) { model.deleteBackward() }
    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    override func selectAll(_ sender: Any?) { model.selectAll() }

    @objc func copy(_ sender: Any?) {
        guard model.selection.range.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.document.text(in: model.selection.range), forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        guard model.selection.range.length > 0 else { return }
        let value = model.document.text(in: model.selection.range)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(value, forType: .string) else { return }
        model.replaceSelection(with: "")
    }
    @objc func paste(_ sender: Any?) { if let value = NSPasteboard.general.string(forType: .string) { model.replaceSelection(with: value) } }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if replacementRange.location != NSNotFound { model.setSelection(replacementRange) }
        model.replaceSelection(with: value)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if replacementRange.location != NSNotFound { model.setSelection(replacementRange) }
        model.setMarkedText(value, selectedRange: selectedRange)
    }

    func unmarkText() { model.unmarkText() }
    func selectedRange() -> NSRange { model.selection.range }
    func markedRange() -> NSRange { model.markedRange ?? NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { model.markedRange != nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound else {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            return nil
        }
        let start = min(max(range.location, 0), model.document.utf16Count)
        let requestedEnd = range.length > model.document.utf16Count - start
            ? model.document.utf16Count
            : start + range.length
        let context = model.boundedContext(around: NSRange(location: start, length: requestedEnd - start))
        let actual = NSIntersectionRange(NSRange(location: start, length: requestedEnd - start), context.range)
        actualRange?.pointee = actual
        guard actual.length > 0 else { return NSAttributedString(string: "", attributes: [.font: font]) }
        return NSAttributedString(string: model.document.text(in: actual), attributes: [.font: font])
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let location = range.location == NSNotFound ? model.selection.range.location : min(range.location, model.document.utf16Count)
        actualRange?.pointee = NSRange(location: location, length: 0)
        return window?.convertToScreen(convert(caretRect(at: location), to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int { offset(at: convert(point, from: nil)) }

    override func accessibilityValue() -> Any? { model.boundedContext().text }
    override func accessibilitySelectedTextRange() -> NSRange {
        let context = model.boundedContext()
        let intersection = NSIntersectionRange(model.selection.range, context.range)
        return NSRange(location: max(0, intersection.location - context.range.location), length: intersection.length)
    }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        let context = model.boundedContext()
        model.setSelection(NSRange(location: context.range.location + range.location, length: range.length))
    }

    private func documentDidChange() {
        caretVisible = true
        updateDocumentSize()
        scrollCaretToVisible()
        needsDisplay = true
        inputContext?.invalidateCharacterCoordinates()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func updateDocumentSize() {
        let visibleWidth = enclosingScrollView?.contentSize.width ?? bounds.width
        frame.size = CGSize(width: max(visibleWidth, 2_000), height: inset.height * 2 + CGFloat(model.document.lineCount) * lineHeight)
    }

    private func offset(at point: NSPoint) -> Int {
        let line = min(max(Int((point.y - inset.height) / lineHeight), 0), max(model.document.lineCount - 1, 0))
        return shapedLine(line).globalOffset(forX: point.x - inset.width)
    }

    private func caretRect(at offset: Int) -> NSRect {
        let line = line(containing: offset)
        let x = shapedLine(line).x(forGlobalOffset: offset)
        return NSRect(x: inset.width + x, y: inset.height + CGFloat(line) * lineHeight, width: 1, height: lineHeight)
    }

    private func line(containing offset: Int) -> Int {
        var low = 0, high = max(model.document.lineCount - 1, 0)
        while low < high {
            let middle = (low + high + 1) / 2
            if model.document.lineRange(at: middle).location <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    private var visibleLineCount: Int {
        max(1, Int((enclosingScrollView?.contentSize.height ?? bounds.height) / lineHeight) - 1)
    }

    private func scrollCaretToVisible() {
        scrollToVisible(caretRect(at: NSMaxRange(model.selection.range)).insetBy(dx: -8, dy: -lineHeight))
    }

    private func drawSelection() {
        guard model.selection.range.length > 0 else { return }
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let visibleFirst = max(0, Int((visible.minY - inset.height) / lineHeight))
        let visibleLast = min(model.document.lineCount - 1, Int((visible.maxY - inset.height) / lineHeight) + 1)
        let startLine = max(visibleFirst, line(containing: model.selection.range.location))
        let endLine = min(visibleLast, line(containing: NSMaxRange(model.selection.range)))
        guard endLine >= startLine else { return }
        NSColor.selectedTextBackgroundColor.setFill()
        for line in startLine...endLine {
            let range = model.document.lineRange(at: line)
            let start = max(model.selection.range.location, range.location)
            let end = min(NSMaxRange(model.selection.range), NSMaxRange(range))
            guard end > start else { continue }
            let shaped = shapedLine(line)
            let startX = shaped.x(forGlobalOffset: start)
            let endX = shaped.x(forGlobalOffset: end)
            NSRect(
                x: inset.width + min(startX, endX),
                y: inset.height + CGFloat(line) * lineHeight,
                width: max(1, abs(endX - startX)),
                height: lineHeight
            ).fill()
        }
    }

    private func shapedLine(_ number: Int) -> AppleShapedLine {
        layoutCache.layout(
            line: number,
            document: model.document,
            font: font,
            color: NSColor.textColor.cgColor,
            appearance: effectiveAppearance.name.rawValue.hashValue
        )
    }

    private func moveVertical(_ lines: Int, extending: Bool = false) {
        model.moveVertical(
            lines,
            extending: extending,
            xForOffset: { [weak self] offset in
                guard let self else { return 0 }
                return self.shapedLine(self.line(containing: offset)).x(forGlobalOffset: offset)
            },
            offsetForLineX: { [weak self] line, x in self?.shapedLine(line).globalOffset(forX: x) ?? 0 }
        )
    }

    private func drawCaret() {
        guard caretVisible, model.selection.range.length == 0, window?.firstResponder === self else { return }
        NSColor.labelColor.setFill()
        caretRect(at: model.selection.range.location).fill()
    }
}

@MainActor
func makeAppleViewportEditor(document: AppleEditorDocument) -> NSScrollView {
    let editor = AppleViewportEditorView(document: document)
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = editor
    return scroll
}

#elseif os(iOS)
import UIKit

final class AppleUITextPosition: UITextPosition {
    let offset: Int
    init(_ offset: Int) { self.offset = offset }
}

final class AppleUITextRange: UITextRange {
    let value: NSRange
    init(_ value: NSRange) { self.value = value }
    override var start: UITextPosition { AppleUITextPosition(value.location) }
    override var end: UITextPosition { AppleUITextPosition(NSMaxRange(value)) }
    override var isEmpty: Bool { value.length == 0 }
}

@MainActor
final class AppleViewportEditorView: UIScrollView, UITextInput {
    let model: AppleEditorInputModel
    weak var inputDelegate: UITextInputDelegate?
    lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)
    var markedTextStyle: [NSAttributedString.Key: Any]?

    private let font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    private let layoutCache = AppleVisibleLineLayoutCache(capacity: 128)
    private let inset = CGSize(width: 12, height: 10)
    private lazy var lineHeight = ceil(font.lineHeight + 3)
    private var caretVisible = true
    private var caretTimer: Timer?
    private var selectionAnchor: Int?
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)
    private lazy var longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))

    init(document: AppleEditorDocument) {
        model = AppleEditorInputModel(document: document)
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        alwaysBounceVertical = true
        alwaysBounceHorizontal = true
        delaysContentTouches = false
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityLabel = "Markdown editor"
        model.didChange = { [weak self] in self?.documentDidChange() }
        longPressRecognizer.minimumPressDuration = 0.45
        longPressRecognizer.allowableMovement = 12
        addGestureRecognizer(longPressRecognizer)
        addInteraction(editMenuInteraction)
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isFirstResponder else { return }
                self.caretVisible.toggle()
                self.setNeedsDisplay()
            }
        }
        updateDocumentSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            caretTimer?.invalidate()
            caretTimer = nil
        }
        super.willMove(toWindow: newWindow)
    }

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { model.document.utf16Count > 0 }

    override func draw(_ rect: CGRect) {
        let viewport = CGRect(origin: contentOffset, size: bounds.size).intersection(rect)
        let first = max(0, Int((viewport.minY - inset.height) / lineHeight))
        let last = min(model.document.lineCount - 1, Int((viewport.maxY - inset.height) / lineHeight) + 1)
        guard last >= first, let context = UIGraphicsGetCurrentContext() else { return }
        for lineNumber in first...last {
            let shaped = shapedLine(lineNumber)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: inset.width, y: inset.height + CGFloat(lineNumber) * lineHeight + font.ascender)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(shaped.line, context)
            context.restoreGState()
        }
        drawSelection()
        if caretVisible, model.selection.range.length == 0, isFirstResponder {
            UIColor.label.setFill()
            UIRectFill(caretRect(for: AppleUITextPosition(model.selection.range.location)))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard longPressRecognizer.state == .possible,
              let point = touches.first?.location(in: self) else { return }
        becomeFirstResponder()
        model.setSelection(NSRange(location: offset(at: point), length: 0))
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            becomeFirstResponder()
            let range = wordRange(at: offset(at: point))
            selectionAnchor = range.location
            model.setSelection(range)
        case .changed:
            guard let anchor = selectionAnchor else { return }
            let extent = offset(at: point)
            model.setSelection(NSRange(location: min(anchor, extent), length: abs(extent - anchor)))
            scrollSelectionPointToVisible(point)
        case .ended:
            selectionAnchor = nil
            presentEditMenu()
        case .cancelled, .failed:
            selectionAnchor = nil
        default:
            break
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return model.selection.range.length > 0
        case #selector(paste(_:)):
            return UIPasteboard.general.hasStrings
        case #selector(selectAll(_:)):
            return model.document.utf16Count > 0
                && model.selection.range != NSRange(location: 0, length: model.document.utf16Count)
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    override func copy(_ sender: Any?) {
        let range = model.selection.range
        guard range.length > 0 else { return }
        UIPasteboard.general.string = model.document.text(in: range)
    }

    override func cut(_ sender: Any?) {
        let range = model.selection.range
        guard range.length > 0 else { return }
        let selectedText = model.document.text(in: range)
        UIPasteboard.general.string = selectedText
        guard UIPasteboard.general.string == selectedText else { return }
        performTextChange { model.replaceSelection(with: "") }
    }

    override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string else { return }
        performTextChange { model.replaceSelection(with: text) }
    }

    override func selectAll(_ sender: Any?) {
        performSelectionChange { model.selectAll() }
        presentEditMenu()
    }

    func insertText(_ text: String) { performTextChange { model.replaceSelection(with: text) } }
    func deleteBackward() { performTextChange { model.deleteBackward() } }

    var selectedTextRange: UITextRange? {
        get { AppleUITextRange(model.selection.range) }
        set {
            guard let range = (newValue as? AppleUITextRange)?.value else { return }
            performSelectionChange { model.setSelection(range) }
        }
    }
    var markedTextRange: UITextRange? { model.markedRange.map(AppleUITextRange.init) }
    var beginningOfDocument: UITextPosition { AppleUITextPosition(0) }
    var endOfDocument: UITextPosition { AppleUITextPosition(model.document.utf16Count) }

    func text(in range: UITextRange) -> String? { (range as? AppleUITextRange).map { model.document.text(in: $0.value) } }
    func replace(_ range: UITextRange, withText text: String) {
        guard let value = (range as? AppleUITextRange)?.value else { return }
        performTextChange { model.setSelection(value); model.replaceSelection(with: text) }
    }
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        performTextChange { model.setMarkedText(markedText ?? "", selectedRange: selectedRange) }
    }
    func unmarkText() { performSelectionChange { model.unmarkText() } }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let from = (fromPosition as? AppleUITextPosition)?.offset, let to = (toPosition as? AppleUITextPosition)?.offset else { return nil }
        return AppleUITextRange(NSRange(location: min(from, to), length: abs(to - from)))
    }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let start = (position as? AppleUITextPosition)?.offset else { return nil }
        var result = start
        if offset < 0 {
            for _ in 0..<(-offset) { result = AppleGraphemeBoundary.previous(before: result, in: model.document) }
        } else {
            for _ in 0..<offset { result = AppleGraphemeBoundary.next(after: result, in: model.document) }
        }
        return AppleUITextPosition(result)
    }
    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        let delta = direction == .left || direction == .up ? -offset : offset
        return self.position(from: position, offset: delta)
    }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let lhs = (position as? AppleUITextPosition)?.offset ?? 0, rhs = (other as? AppleUITextPosition)?.offset ?? 0
        return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        ((toPosition as? AppleUITextPosition)?.offset ?? 0) - ((from as? AppleUITextPosition)?.offset ?? 0)
    }
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        guard let value = (range as? AppleUITextRange)?.value else { return nil }
        return AppleUITextPosition(direction == .left || direction == .up ? value.location : NSMaxRange(value))
    }
    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let offset = (position as? AppleUITextPosition)?.offset else { return nil }
        let start = direction == .left || direction == .up
            ? AppleGraphemeBoundary.previous(before: offset, in: model.document)
            : offset
        let end = direction == .left || direction == .up
            ? offset
            : AppleGraphemeBoundary.next(after: offset, in: model.document)
        return AppleUITextRange(NSRange(location: start, length: end - start))
    }
    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection { .leftToRight }
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}
    func firstRect(for range: UITextRange) -> CGRect {
        guard let value = (range as? AppleUITextRange)?.value else { return .zero }
        return convert(caretRect(for: AppleUITextPosition(value.location)), to: window)
    }
    func caretRect(for position: UITextPosition) -> CGRect {
        let offset = (position as? AppleUITextPosition)?.offset ?? 0
        let line = line(containing: offset)
        return CGRect(x: inset.width + shapedLine(line).x(forGlobalOffset: offset),
                      y: inset.height + CGFloat(line) * lineHeight, width: 2, height: lineHeight)
    }
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let value = (range as? AppleUITextRange)?.value, value.length > 0 else { return [] }
        let viewport = CGRect(origin: contentOffset, size: bounds.size)
        let visibleFirst = max(0, Int((viewport.minY - inset.height) / lineHeight))
        let visibleLast = min(model.document.lineCount - 1, Int((viewport.maxY - inset.height) / lineHeight) + 1)
        let startLine = max(visibleFirst, line(containing: value.location))
        let endLine = min(visibleLast, line(containing: NSMaxRange(value)))
        guard endLine >= startLine else { return [] }
        return (startLine...endLine).compactMap { line in
            let lineRange = model.document.lineRange(at: line)
            let start = max(value.location, lineRange.location)
            let end = min(NSMaxRange(value), NSMaxRange(lineRange))
            guard end > start else { return nil }
            let shaped = shapedLine(line)
            let startX = shaped.x(forGlobalOffset: start)
            let endX = shaped.x(forGlobalOffset: end)
            return AppleUITextSelectionRect(
                rect: CGRect(
                    x: inset.width + min(startX, endX),
                    y: inset.height + CGFloat(line) * lineHeight,
                    width: max(1, abs(endX - startX)),
                    height: lineHeight
                ),
                containsStart: start == value.location,
                containsEnd: end == NSMaxRange(value)
            )
        }
    }
    func closestPosition(to point: CGPoint) -> UITextPosition? { AppleUITextPosition(offset(at: point)) }
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? { closestPosition(to: point) }
    func characterRange(at point: CGPoint) -> UITextRange? {
        let value = offset(at: point)
        return AppleUITextRange(AppleGraphemeBoundary.range(containing: value, in: model.document))
    }

    override var accessibilityValue: String? {
        get { model.boundedContext().text }
        set {}
    }

    private func performTextChange(_ change: () -> Void) {
        inputDelegate?.textWillChange(self)
        inputDelegate?.selectionWillChange(self)
        change()
        inputDelegate?.selectionDidChange(self)
        inputDelegate?.textDidChange(self)
    }

    private func performSelectionChange(_ change: () -> Void) {
        inputDelegate?.selectionWillChange(self)
        change()
        inputDelegate?.selectionDidChange(self)
    }

    private func documentDidChange() {
        caretVisible = true
        updateDocumentSize()
        scrollRectToVisible(
            caretRect(for: AppleUITextPosition(NSMaxRange(model.selection.range))).insetBy(dx: -8, dy: -lineHeight),
            animated: false
        )
        setNeedsDisplay()
        UIAccessibility.post(notification: .layoutChanged, argument: self)
    }

    private func presentEditMenu() {
        let sourceRect: CGRect
        if model.selection.range.length > 0,
           let first = selectionRects(for: AppleUITextRange(model.selection.range)).first?.rect {
            sourceRect = first
        } else {
            sourceRect = caretRect(for: AppleUITextPosition(model.selection.range.location))
        }
        editMenuInteraction.presentEditMenu(
            with: UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: CGPoint(x: sourceRect.midX, y: sourceRect.midY)
            )
        )
    }

    private func wordRange(at offset: Int) -> NSRange {
        guard model.document.utf16Count > 0 else { return NSRange(location: 0, length: 0) }
        let context = model.boundedContext(around: NSRange(location: offset, length: 0))
        let localOffset = min(max(offset - context.range.location, 0), context.text.utf16.count)
        let text = context.text as NSString
        let probe = min(localOffset, max(text.length - 1, 0))
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        if text.length == 0 || UnicodeScalar(text.character(at: probe)).map(separators.contains) == true {
            return NSRange(location: context.range.location + probe, length: min(1, text.length - probe))
        }
        var start = probe
        var end = probe + 1
        while start > 0,
              UnicodeScalar(text.character(at: start - 1)).map(separators.contains) != true { start -= 1 }
        while end < text.length,
              UnicodeScalar(text.character(at: end)).map(separators.contains) != true { end += 1 }
        return NSRange(location: context.range.location + start, length: end - start)
    }

    private func scrollSelectionPointToVisible(_ point: CGPoint) {
        let margin: CGFloat = 36
        let visible = CGRect(origin: contentOffset, size: bounds.size).insetBy(dx: 0, dy: margin)
        guard !visible.contains(point) else { return }
        scrollRectToVisible(
            CGRect(x: point.x, y: point.y, width: 1, height: 1).insetBy(dx: -8, dy: -margin),
            animated: false
        )
    }

    private func drawSelection() {
        guard model.selection.range.length > 0 else { return }
        UIColor.systemBlue.withAlphaComponent(0.3).setFill()
        for selectionRect in selectionRects(for: AppleUITextRange(model.selection.range)) {
            UIRectFill(selectionRect.rect)
        }
    }

    private func updateDocumentSize() {
        contentSize = CGSize(width: max(bounds.width, 2_000), height: inset.height * 2 + CGFloat(model.document.lineCount) * lineHeight)
    }

    private func offset(at point: CGPoint) -> Int {
        let line = min(max(Int((point.y - inset.height) / lineHeight), 0), max(model.document.lineCount - 1, 0))
        return shapedLine(line).globalOffset(forX: point.x - inset.width)
    }

    private func shapedLine(_ number: Int) -> AppleShapedLine {
        layoutCache.layout(
            line: number,
            document: model.document,
            font: font,
            color: UIColor.label.cgColor,
            appearance: traitCollection.userInterfaceStyle.rawValue
        )
    }

    private func line(containing offset: Int) -> Int {
        var low = 0, high = max(model.document.lineCount - 1, 0)
        while low < high {
            let middle = (low + high + 1) / 2
            if model.document.lineRange(at: middle).location <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }
}

private final class AppleUITextSelectionRect: UITextSelectionRect {
    private let value: CGRect
    private let starts: Bool
    private let ends: Bool

    init(rect: CGRect, containsStart: Bool, containsEnd: Bool) {
        value = rect
        starts = containsStart
        ends = containsEnd
    }

    override var rect: CGRect { value }
    override var writingDirection: NSWritingDirection { .leftToRight }
    override var containsStart: Bool { starts }
    override var containsEnd: Bool { ends }
    override var isVertical: Bool { false }
}

extension AppleViewportEditorView: @preconcurrency UIEditMenuInteractionDelegate {
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? { UIMenu(children: suggestedActions) }
}
#endif
