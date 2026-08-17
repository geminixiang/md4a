import XCTest
#if os(macOS)
@testable import md4aMac
#else
@testable import md4aiOS
#endif

final class AppleLargeDocumentCoreBenchmarks: XCTestCase {
    private var fixture: AppleBenchmarkFixture!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixture = try AppleBenchmarkFixture.load()
        XCTAssertEqual(fixture.data.count, AppleBenchmarkFixture.exactByteCount, "The acceptance fixture must be exactly 8,841,392 bytes")
    }

    func testLargeDocumentCorePipeline() throws {
        var decoded = ""
        let loadDecode = try AppleBenchmark.measure {
            let data: Data
            if fixture.source == "deterministic-exact-byte-fallback" {
                data = fixture.data.withUnsafeBytes { Data($0) }
            } else {
                data = try Data(contentsOf: URL(fileURLWithPath: fixture.source), options: .mappedIfSafe)
            }
            guard let value = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            decoded = value
        }
        AppleBenchmark.log(metric: "utf8_load_decode", summary: loadDecode, fixture: fixture, gateMilliseconds: 250)
        XCTAssertEqual(decoded.utf8.count, fixture.data.count)

        var copied = ""
        let stringCopy = AppleBenchmark.measure {
            copied = String(fixture.text)
            withExtendedLifetime(copied) {}
        }
        AppleBenchmark.log(metric: "document_string_copy", summary: stringCopy, fixture: fixture, gateMilliseconds: 50)
        XCTAssertEqual(copied.utf8.count, fixture.data.count)

        var encoded = Data()
        let utf8Snapshot = AppleBenchmark.measure {
            encoded = fixture.text.data(using: .utf8)!
        }
        AppleBenchmark.log(metric: "utf8_snapshot_encode", summary: utf8Snapshot, fixture: fixture, gateMilliseconds: 250)
        XCTAssertEqual(encoded.count, fixture.data.count)

        var rendered = ""
        let render = try AppleBenchmark.measure {
            rendered = try MarkdownRenderer.render(fixture.text)
        }
        AppleBenchmark.log(
            metric: "markdown_render",
            summary: render,
            fixture: fixture,
            extra: ["output_utf8_bytes": rendered.utf8.count],
            gateMilliseconds: 250
        )
        XCTAssertFalse(rendered.isEmpty)

        var page = Data()
        let pageCreation = try AppleBenchmark.measure {
            page = try MarkdownRenderer.pageData(for: fixture.text)
        }
        AppleBenchmark.log(
            metric: "preview_page_creation",
            summary: pageCreation,
            fixture: fixture,
            extra: ["output_utf8_bytes": page.count],
            gateMilliseconds: 350
        )
        XCTAssertTrue(page.starts(with: Data("<!doctype html>".utf8)))
        AppleBenchmark.logMemory(metric: "core_pipeline_memory", fixture: fixture)
    }

    @MainActor
    func testDocumentOpenSaveReopenScaffolding() throws {
        let opened = MarkdownDocument(text: fixture.text)
        opened.session().replace(NSRange(location: 0, length: 0), with: "X")
        let snapshot = opened.session().snapshot().text()

        let data = try XCTUnwrap(snapshot.data(using: .utf8))
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("md4a-apple-e2e-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)

        let reopenedData = try Data(contentsOf: temporaryURL)
        let reopened = try XCTUnwrap(String(data: reopenedData, encoding: .utf8))
        XCTAssertEqual(reopened, snapshot)
        XCTAssertEqual(reopened.utf8.count, fixture.data.count + 1)

        print("MD4A_ACCEPTANCE Open→Edit→Preview(page benchmark)→Save→reopen core lifecycle passed; UI mode switching remains a documented manual/XCUITest step")
    }
}
