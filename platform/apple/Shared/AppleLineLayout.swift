import CoreText
import Foundation

#if os(macOS)
import AppKit
typealias ApplePlatformFont = NSFont
private typealias ApplePlatformColor = NSColor
#else
import UIKit
typealias ApplePlatformFont = UIFont
private typealias ApplePlatformColor = UIColor
#endif

/// One shaped, newline-free logical line. String indices remain UTF-16 so they
/// can be translated directly to the piece tree's global offsets.
struct AppleShapedLine {
    let number: Int
    let revision: UInt64
    let documentRange: NSRange
    let text: String
    let line: CTLine
    let width: CGFloat

    func x(forGlobalOffset offset: Int) -> CGFloat {
        let local = min(max(offset - documentRange.location, 0), text.utf16.count)
        return CGFloat(CTLineGetOffsetForStringIndex(line, local, nil))
    }

    func globalOffset(forX x: CGFloat) -> Int {
        let local = CTLineGetStringIndexForPosition(line, CGPoint(x: max(0, x), y: 0))
        let resolved = local == kCFNotFound ? text.utf16.count : min(max(local, 0), text.utf16.count)
        return documentRange.location + resolved
    }
}

/// Bounded LRU of CoreText layouts. Only viewport and overscan lines are ever
/// requested by the views; revisions make stale entries impossible to reuse.
@MainActor
final class AppleVisibleLineLayoutCache {
    struct Key: Hashable {
        let line: Int
        let revision: UInt64
        let fontName: String
        let fontSizeBits: UInt64
        let appearance: Int
    }

    private let capacity: Int
    private var values: [Key: AppleShapedLine] = [:]
    private var recency: [Key] = []

    init(capacity: Int = 128) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { values.count }
    var limit: Int { capacity }

    func layout(
        line number: Int,
        document: AppleEditorDocument,
        font: ApplePlatformFont,
        color: CGColor,
        appearance: Int
    ) -> AppleShapedLine {
        let key = Key(
            line: number,
            revision: document.revision,
            fontName: font.fontName,
            fontSizeBits: Double(font.pointSize).bitPattern,
            appearance: appearance
        )
        if let cached = values[key] {
            touch(key)
            return cached
        }

        let range = document.lineRange(at: number)
        let contentLength = document.text(in: range).utf16.prefix { $0 != 10 && $0 != 13 }.count
        let contentRange = NSRange(location: range.location, length: contentLength)
        let text = document.text(in: contentRange)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let shaped = AppleShapedLine(
            number: number,
            revision: document.revision,
            documentRange: contentRange,
            text: text,
            line: ctLine,
            width: CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        )
        values[key] = shaped
        recency.append(key)
        evictIfNeeded()
        return shaped
    }

    func removeAll() {
        values.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
    }

    private func touch(_ key: Key) {
        if let index = recency.firstIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }

    private func evictIfNeeded() {
        while values.count > capacity, !recency.isEmpty {
            values.removeValue(forKey: recency.removeFirst())
        }
    }
}

/// Finds Swift `Character` boundaries from a bounded UTF-16 window around the
/// caret. Normal documents need only a handful of units; the cap prevents a
/// malicious combining-mark run from flattening a large document.
@MainActor
enum AppleGraphemeBoundary {
    static let contextLimit = 2_048

    static func previous(before offset: Int, in document: AppleEditorDocument) -> Int {
        guard offset > 0 else { return 0 }
        let context = localContext(around: offset, in: document)
        let local = offset - context.range.location
        let boundaries = utf16Boundaries(context.text)
        return context.range.location + (boundaries.last(where: { $0 < local }) ?? max(0, local - 1))
    }

    static func next(after offset: Int, in document: AppleEditorDocument) -> Int {
        guard offset < document.utf16Count else { return document.utf16Count }
        let context = localContext(around: offset, in: document)
        let local = offset - context.range.location
        let boundaries = utf16Boundaries(context.text)
        return context.range.location + (boundaries.first(where: { $0 > local }) ?? min(context.text.utf16.count, local + 1))
    }

    static func range(containing offset: Int, in document: AppleEditorDocument) -> NSRange {
        guard document.utf16Count > 0 else { return NSRange(location: 0, length: 0) }
        let probe = min(max(offset, 0), document.utf16Count - 1)
        let start = previousOrEqual(probe, in: document)
        return NSRange(location: start, length: next(after: start, in: document) - start)
    }

    private static func previousOrEqual(_ offset: Int, in document: AppleEditorDocument) -> Int {
        let context = localContext(around: offset, in: document)
        let local = offset - context.range.location
        let boundary = utf16Boundaries(context.text).last(where: { $0 <= local }) ?? 0
        return context.range.location + boundary
    }

    private static func localContext(around offset: Int, in document: AppleEditorDocument) -> (range: NSRange, text: String) {
        let half = contextLimit / 2
        var start = max(0, offset - half)
        var end = min(document.utf16Count, offset + half)
        // Include spare UTF-16 units so a window edge never asks the piece tree
        // to decode an isolated surrogate. Character clusters at the artificial
        // edge are ignored because only boundaries around `offset` are used.
        if start > 0 { start -= 1 }
        if end < document.utf16Count { end += 1 }
        let range = NSRange(location: start, length: end - start)
        return (range, document.text(in: range))
    }

    private static func utf16Boundaries(_ text: String) -> [Int] {
        var result = [0]
        result.reserveCapacity(min(text.count + 1, contextLimit + 1))
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            result.append(offset)
        }
        return result
    }
}
