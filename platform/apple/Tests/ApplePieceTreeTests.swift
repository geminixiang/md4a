import XCTest
#if os(macOS)
@testable import md4aMac
#else
@testable import md4aiOS
#endif

final class ApplePieceTreeTests: XCTestCase {
    func testUTF16OffsetsSelectionRevisionDirtyAndHistory() {
        let buffer = ApplePieceTreeBuffer(text: "A🙂B\r\nC", historyLimit: 2)
        XCTAssertEqual(buffer.length, 7)
        XCTAssertEqual(buffer.snapshot().text(in: AppleTextRange(1, 3)), "🙂")

        buffer.setSelection(AppleEditorSelection(anchor: 3, caret: 1))
        buffer.replace(AppleTextRange(1, 3), with: "橘", selectionAfter: AppleEditorSelection(anchor: 2, caret: 2))
        XCTAssertEqual(buffer.snapshot().text(), "A橘B\r\nC")
        XCTAssertEqual(buffer.selection, AppleEditorSelection(anchor: 2, caret: 2))
        XCTAssertEqual(buffer.revision, 1)
        XCTAssertTrue(buffer.isDirty)
        XCTAssertEqual(buffer.lastEditMetrics.existingCodeUnitsCopied, 0)
        XCTAssertEqual(buffer.lastEditMetrics.insertedCodeUnits, 1)

        buffer.markSaved()
        XCTAssertFalse(buffer.isDirty)
        XCTAssertTrue(buffer.undo())
        XCTAssertEqual(buffer.snapshot().text(), "A🙂B\r\nC")
        XCTAssertTrue(buffer.isDirty)
        XCTAssertTrue(buffer.redo())
        XCTAssertEqual(buffer.snapshot().text(), "A橘B\r\nC")
        XCTAssertFalse(buffer.isDirty)
    }

    func testImmutableSnapshotSurvivesLaterEdits() {
        let buffer = ApplePieceTreeBuffer(text: "before")
        let snapshot = buffer.snapshot()
        buffer.replace(AppleTextRange(0, 6), with: "after")
        XCTAssertEqual(snapshot.text(), "before")
        XCTAssertEqual(buffer.snapshot().text(), "after")
    }

    func testCRLFAggregatesAcrossInitialAndEditedPieceBoundaries() {
        let prefix = String(repeating: "x", count: 16 * 1024 - 1)
        let buffer = ApplePieceTreeBuffer(text: prefix + "\r\nlast")
        assertLines(buffer.snapshot(), [prefix, "last"])

        buffer.delete(AppleTextRange(prefix.utf16.count + 1, prefix.utf16.count + 2))
        assertLines(buffer.snapshot(), [prefix, "last"])
        buffer.insert(at: prefix.utf16.count + 1, text: "\n")
        assertLines(buffer.snapshot(), [prefix, "last"])

        let split = ApplePieceTreeBuffer(text: "left\rright")
        split.insert(at: 5, text: "\n")
        assertLines(split.snapshot(), ["left", "right"])
        XCTAssertEqual(split.snapshot().line(forOffset: 4), 0)
        XCTAssertEqual(split.snapshot().line(forOffset: 5), 0)
        XCTAssertEqual(split.snapshot().line(forOffset: 6), 1)
    }

    func testStreamingUTF8SavePreservesExactBytes() throws {
        let text = "橘子🙂\r\nline\nlast\r"
        let buffer = ApplePieceTreeBuffer(text: text)
        buffer.insert(at: 2, text: "ABC")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("md4a-piece-tree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try buffer.snapshot().writeUTF8(to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data(buffer.snapshot().text().utf8))
    }

    func testSurrogateAtChunkBoundaryAndLaterPieceSplitsRoundTrips() throws {
        let original = String(repeating: "a", count: 16_383) + "🙂tail"
        let buffer = ApplePieceTreeBuffer(text: original)
        XCTAssertEqual(buffer.snapshot().text(), original)

        buffer.insert(at: 16_383, text: "橘")
        buffer.insert(at: 16_386, text: "!")
        buffer.delete(AppleTextRange(16_386, 16_387))
        let expected = String(repeating: "a", count: 16_383) + "橘🙂tail"
        XCTAssertEqual(buffer.snapshot().text(), expected)

        let stream = OutputStream.toMemory()
        try buffer.snapshot().writeUTF8(to: stream)
        XCTAssertEqual(
            stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data,
            Data(expected.utf8)
        )
    }

    func testInsertionInsideSurrogateDoesNotCreateInvalidPieceBoundary() {
        let buffer = ApplePieceTreeBuffer(text: "A🙂B")
        buffer.insert(at: 2, text: "x")
        XCTAssertEqual(buffer.snapshot().text(), "Ax🙂B")
        XCTAssertFalse(buffer.snapshot().text().contains("�"))
    }

    func testRandomizedDifferentialEditingAndLineLookup() {
        var generator = SeededGenerator(seed: 0x4D443441)
        let buffer = ApplePieceTreeBuffer(text: "start\r\n🙂\nend", historyLimit: 20)
        let reference = NSMutableString(string: "start\r\n🙂\nend")
        let replacements = ["", "a", "\n", "\r", "\r\n", "橘", "🙂", "xyz"]

        for iteration in 0..<1_000 {
            let safeBoundaries = utf16Boundaries(reference as String)
            let firstIndex = Int.random(in: 0..<safeBoundaries.count, using: &generator)
            let secondIndex = Int.random(in: firstIndex..<safeBoundaries.count, using: &generator)
            let start = safeBoundaries[firstIndex]
            let end = safeBoundaries[secondIndex]
            let replacement = replacements.randomElement(using: &generator)!
            reference.replaceCharacters(in: NSRange(location: start, length: end - start), with: replacement)
            buffer.replace(AppleTextRange(start, end), with: replacement)

            let snapshot = buffer.snapshot()
            XCTAssertEqual(snapshot.text(), reference as String, "Mismatch after edit \(iteration)")
            let expectedLines = logicalLines(reference as String)
            XCTAssertEqual(snapshot.lineCount, expectedLines.count)
            for line in expectedLines.indices {
                XCTAssertEqual(snapshot.lineText(line), expectedLines[line], "Line \(line), edit \(iteration)")
                XCTAssertEqual(snapshot.line(forOffset: snapshot.lineStart(line)), line)
            }
        }
    }

    private func assertLines(_ snapshot: AppleDocumentSnapshot, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(snapshot.lineCount, expected.count, file: file, line: line)
        XCTAssertEqual((0..<snapshot.lineCount).map(snapshot.lineText), expected, file: file, line: line)
    }

    private func logicalLines(_ text: String) -> [String] {
        let source = text as NSString
        var lines: [String] = []
        var lineStart = 0
        var offset = 0
        while offset < source.length {
            let value = source.character(at: offset)
            if value == 13 || value == 10 {
                lines.append(source.substring(with: NSRange(location: lineStart, length: offset - lineStart)))
                if value == 13, offset + 1 < source.length, source.character(at: offset + 1) == 10 {
                    offset += 1
                }
                lineStart = offset + 1
            }
            offset += 1
        }
        lines.append(source.substring(from: lineStart))
        return lines
    }

    private func utf16Boundaries(_ text: String) -> [Int] {
        var result = [0]
        var offset = 0
        for scalar in text.unicodeScalars {
            offset += scalar.value > 0xFFFF ? 2 : 1
            result.append(offset)
        }
        return result
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
