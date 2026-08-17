import XCTest
#if os(macOS)
import AppKit
@testable import md4aMac
#else
import UIKit
@testable import md4aiOS
#endif

final class AppleUnicodeEditorTests: XCTestCase {
    private let corpus = "繁體中文、简体中文、日本語、한글 e\u{301} हिन्दी العربية 👨‍👩‍👧‍👦 👍🏽 🇹🇼 ❤️ 1️⃣ ✈️\r\n第二行"
    private let clusters = ["中", "e\u{301}", "हिन्दी", "👨‍👩‍👧‍👦", "👍🏽", "🇹🇼", "❤️", "1️⃣", "✈️"]

    @MainActor
    func testDeleteBackwardRemovesOneComposedCharacter() {
        for value in clusters {
            let cluster = String(value.last!)
            let prefix = String(value.dropLast())
            let document = UnicodeEditorDocument("A\(value)B")
            let input = AppleEditorInputModel(document: document)
            input.setSelection(NSRange(location: 1 + value.utf16.count, length: 0))
            input.deleteBackward()
            XCTAssertEqual(document.value, "A\(prefix)B", "Failed cluster: \(cluster)")
        }
    }

    @MainActor
    func testHorizontalMovementStopsOnlyAtCharacterBoundaries() {
        let document = UnicodeEditorDocument(corpus)
        let input = AppleEditorInputModel(document: document)
        var expected = [0]
        var offset = 0
        for character in corpus {
            offset += String(character).utf16.count
            expected.append(offset)
        }
        for boundary in expected.dropFirst() {
            input.moveHorizontal(1)
            XCTAssertEqual(input.selection.range.location, boundary)
        }
        for boundary in expected.dropLast().reversed() {
            input.moveHorizontal(-1)
            XCTAssertEqual(input.selection.range.location, boundary)
        }
    }

    @MainActor
    func testCoreTextRoundTripAndBoundedCache() {
        let document = UnicodeEditorDocument((0..<200).map { "\($0) \(corpus)\n" }.joined())
        let cache = AppleVisibleLineLayoutCache(capacity: 16)
        #if os(macOS)
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let color = NSColor.textColor.cgColor
        #else
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let color = UIColor.label.cgColor
        #endif
        for line in 0..<document.lineCount {
            let shaped = cache.layout(line: line, document: document, font: font, color: color, appearance: 0)
            let validBoundaries = Set(characterBoundaries(shaped.text).map { shaped.documentRange.location + $0 })
            var offset = shaped.documentRange.location
            for character in shaped.text {
                let x = shaped.x(forGlobalOffset: offset)
                XCTAssertTrue(x.isFinite)
                XCTAssertTrue(validBoundaries.contains(shaped.globalOffset(forX: x)))
                offset += String(character).utf16.count
            }
        }
        XCTAssertLessThanOrEqual(cache.count, 16)
    }

    private func characterBoundaries(_ text: String) -> [Int] {
        var boundaries = [0]
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            boundaries.append(offset)
        }
        return boundaries
    }

    func testUnicodeCorpusSaveReopenIsByteExact() throws {
        let original = Data(corpus.utf8)
        let buffer = try ApplePieceTreeBuffer(data: original)
        let stream = OutputStream.toMemory()
        try buffer.snapshot().writeUTF8(to: stream)
        let saved = try XCTUnwrap(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
        XCTAssertEqual(saved, original)
        XCTAssertEqual(try ApplePieceTreeBuffer(data: saved).snapshot().text(), corpus)
    }

    func testPreviewPageDeclaresUTF8AndPreservesUnicodeBytes() throws {
        let page = try MarkdownRenderer.pageData(for: corpus)
        let decoded = try XCTUnwrap(String(data: page, encoding: .utf8))
        XCTAssertTrue(decoded.contains("<meta charset=\"utf-8\">"))
        for value in ["繁體中文", "简体中文", "日本語", "한글", "العربية", "👨‍👩‍👧‍👦", "🇹🇼"] {
            XCTAssertTrue(decoded.contains(value), "Missing preview value: \(value)")
        }
    }
}

@MainActor
private final class UnicodeEditorDocument: AppleEditorDocument {
    private(set) var value: String
    private(set) var revision: UInt64 = 0
    private(set) var editorSelection = NSRange(location: 0, length: 0)

    init(_ value: String) { self.value = value }
    var utf16Count: Int { value.utf16.count }
    var lineCount: Int { value.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline).count }
    var canUndo: Bool { false }
    var canRedo: Bool { false }

    func lineRange(at line: Int) -> NSRange {
        let source = value as NSString
        var location = 0
        for current in 0...line {
            if location == source.length { return NSRange(location: location, length: 0) }
            let range = source.lineRange(for: NSRange(location: location, length: 0))
            if current == line { return range }
            location = NSMaxRange(range)
        }
        return NSRange(location: source.length, length: 0)
    }
    func text(in range: NSRange) -> String { (value as NSString).substring(with: range) }
    func setEditorSelection(_ range: NSRange) { editorSelection = range }
    func replace(_ range: NSRange, with text: String) {
        value = (value as NSString).replacingCharacters(in: range, with: text)
        revision &+= 1
    }
    func undo() {}
    func redo() {}
}
