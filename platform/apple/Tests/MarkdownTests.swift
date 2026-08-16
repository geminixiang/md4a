import XCTest
#if os(macOS)
@testable import md4aMac
#else
@testable import md4aiOS
#endif

final class MarkdownTests: XCTestCase {
    func testRendererUsesGFMAndSuppressesRawHTML() throws {
        let html = try MarkdownRenderer.render("~~old~~\n\n<script>alert(1)</script>")
        XCTAssertTrue(html.contains("<del>old</del>"))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testRendererHandlesUTF8() throws {
        let html = try MarkdownRenderer.render("# 橘子\n")
        XCTAssertEqual(html, "<h1>橘子</h1>\n")
    }
}
