import XCTest
#if os(macOS)
@testable import md4aMac
#else
@testable import md4aiOS
#endif

final class ApplePieceTreeBenchmarks: XCTestCase {
    private var fixture: AppleBenchmarkFixture!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixture = try AppleBenchmarkFixture.load()
        XCTAssertEqual(fixture.data.count, AppleBenchmarkFixture.exactByteCount)
    }

    func testExactFixturePieceTreeGates() throws {
        var buffer: ApplePieceTreeBuffer!
        let construction = try AppleBenchmark.measure {
            buffer = try ApplePieceTreeBuffer(data: fixture.data)
        }
        AppleBenchmark.log(metric: "piece_tree_construction", summary: construction, fixture: fixture, gateMilliseconds: 1_000)
        XCTAssertEqual(buffer.snapshot().text().utf8.count, AppleBenchmarkFixture.exactByteCount)

        let snapshot = buffer.snapshot()
        var checksum = 0
        let lookups = AppleBenchmark.measure {
            for index in 0..<1_000 {
                let line = index * 7_919 % snapshot.lineCount
                checksum &+= snapshot.lineStart(line)
            }
        }
        AppleBenchmark.log(metric: "piece_tree_1000_line_lookups", summary: lookups, fixture: fixture, gateMilliseconds: 250)

        let viewport = AppleBenchmark.measure {
            for index in 0..<1_000 {
                let line = index * 7_919 % snapshot.lineCount
                checksum &+= snapshot.lineText(line).utf16.count
            }
        }
        AppleBenchmark.log(metric: "piece_tree_1000_viewport_reads", summary: viewport, fixture: fixture, gateMilliseconds: 250)

        let editable = ApplePieceTreeBuffer(text: fixture.text, historyLimit: 1)
        let offset = editable.length / 2
        var editCounter = 0
        let insert = AppleBenchmark.measure {
            editable.insert(at: offset, text: "x")
            editCounter &+= editable.snapshot()[offset] == 120 ? 1 : 0
            XCTAssertTrue(editable.undo())
        }
        AppleBenchmark.log(metric: "piece_tree_single_insert", summary: insert, fixture: fixture, gateMilliseconds: 5)

        var retained: [AppleDocumentSnapshot] = []
        let snapshotCreation = AppleBenchmark.measure {
            retained.append(buffer.snapshot())
        }
        AppleBenchmark.log(metric: "piece_tree_snapshot", summary: snapshotCreation, fixture: fixture, gateMilliseconds: 5)
        XCTAssertEqual(retained.last?.length, buffer.length)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("md4a-apple-save-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let save = try AppleBenchmark.measure {
            try snapshot.writeUTF8(to: url)
        }
        AppleBenchmark.log(metric: "piece_tree_streaming_save", summary: save, fixture: fixture, gateMilliseconds: 500)
        XCTAssertEqual((try Data(contentsOf: url)).count, AppleBenchmarkFixture.exactByteCount)
        XCTAssertNotEqual(checksum + editCounter, 0)
    }
}
