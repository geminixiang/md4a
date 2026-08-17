import Foundation
import SwiftUI

/// Main-actor owner of the persistent document buffer and the one native
/// viewport editor instance. The editor survives Preview/Edit mode switches,
/// preserving selection, scrolling, undo history, and IME state.
@MainActor
final class AppleDocumentSession: ObservableObject, AppleEditorDocument {
    private let buffer: ApplePieceTreeBuffer
    @Published private(set) var previewText: String
    @Published private(set) var previewRevision: UInt64
    var onEdit: (() -> Void)?
    private var previewTask: Task<Void, Never>?

    #if os(macOS)
    private(set) lazy var editorView = makeAppleViewportEditor(document: self)
    #else
    private(set) lazy var editorView = AppleViewportEditorView(document: self)
    #endif

    init(data: Data, initiallyDirty: Bool = false) throws {
        let buffer = try ApplePieceTreeBuffer(data: data, initiallyDirty: initiallyDirty)
        self.buffer = buffer
        previewText = buffer.snapshot().text()
        previewRevision = buffer.revision
    }

    convenience init(text: String, initiallyDirty: Bool = false) {
        try! self.init(data: Data(text.utf8), initiallyDirty: initiallyDirty)
    }

    deinit { previewTask?.cancel() }

    var utf16Count: Int { buffer.length }
    var lineCount: Int { buffer.lineCount }
    var revision: UInt64 { buffer.revision }
    var isDirty: Bool { buffer.isDirty }
    var canUndo: Bool { buffer.canUndo }
    var canRedo: Bool { buffer.canRedo }
    var editorSelection: NSRange {
        buffer.selection.range.withNSRange
    }

    func snapshot() -> AppleDocumentSnapshot { buffer.snapshot() }

    func lineRange(at line: Int) -> NSRange {
        let range = buffer.snapshot().lineRange(line)
        return NSRange(location: range.start, length: range.length)
    }

    func text(in range: NSRange) -> String {
        let safe = clampedRange(range)
        return buffer.snapshot().text(in: AppleTextRange(safe.location, NSMaxRange(safe)))
    }

    func setEditorSelection(_ range: NSRange) {
        let safe = clampedRange(range)
        buffer.setSelection(AppleEditorSelection(anchor: safe.location, caret: NSMaxRange(safe)))
    }

    func replace(_ range: NSRange, with text: String) {
        let safe = boundaryAlignedRange(clampedRange(range))
        buffer.replace(AppleTextRange(safe.location, NSMaxRange(safe)), with: text)
        didEdit()
    }

    func undo() {
        guard buffer.undo() else { return }
        didEdit()
    }

    func redo() {
        guard buffer.redo() else { return }
        didEdit()
    }

    func markSaved(revision savedRevision: UInt64) {
        guard buffer.revision == savedRevision else { return }
        buffer.markSaved()
    }

    func previousCharacterBoundary(before offset: Int) -> Int {
        let offset = min(max(offset, 0), utf16Count)
        guard offset > 0 else { return 0 }
        let snapshot = buffer.snapshot()
        if offset >= 2, isHighSurrogate(snapshot[offset - 2]), isLowSurrogate(snapshot[offset - 1]) {
            return offset - 2
        }
        return offset - 1
    }

    func nextCharacterBoundary(after offset: Int) -> Int {
        let offset = min(max(offset, 0), utf16Count)
        guard offset < utf16Count else { return utf16Count }
        let snapshot = buffer.snapshot()
        if offset + 1 < utf16Count, isHighSurrogate(snapshot[offset]), isLowSurrogate(snapshot[offset + 1]) {
            return offset + 2
        }
        return offset + 1
    }

    private func didEdit() {
        onEdit?()
        schedulePreviewSnapshot(revision: buffer.revision, snapshot: buffer.snapshot())
    }

    private func schedulePreviewSnapshot(revision: UInt64, snapshot: AppleDocumentSnapshot) {
        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.buffer.revision == revision else { return }
            let text = await Task.detached(priority: .userInitiated) { snapshot.text() }.value
            guard self.buffer.revision == revision else { return }
            self.previewText = text
            self.previewRevision = revision
        }
    }

    private func clampedRange(_ range: NSRange) -> NSRange {
        let start = min(max(range.location, 0), utf16Count)
        let end = min(max(NSMaxRange(range), start), utf16Count)
        return NSRange(location: start, length: end - start)
    }

    private func boundaryAlignedRange(_ range: NSRange) -> NSRange {
        let snapshot = buffer.snapshot()
        var start = range.location
        var end = NSMaxRange(range)
        if start > 0, start < snapshot.length,
           isHighSurrogate(snapshot[start - 1]), isLowSurrogate(snapshot[start]) { start -= 1 }
        if end > 0, end < snapshot.length,
           isHighSurrogate(snapshot[end - 1]), isLowSurrogate(snapshot[end]) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}

private extension AppleTextRange {
    var withNSRange: NSRange { NSRange(location: start, length: length) }
}

private func isHighSurrogate(_ value: unichar) -> Bool { (0xD800...0xDBFF).contains(value) }
private func isLowSurrogate(_ value: unichar) -> Bool { (0xDC00...0xDFFF).contains(value) }
