import XCTest
import WebKit
#if os(macOS)
import AppKit
@testable import md4aMac
#else
import UIKit
@testable import md4aiOS
#endif

@MainActor
final class AppleLargeDocumentUIBenchmarks: XCTestCase {
    private var fixture: AppleBenchmarkFixture!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixture = try AppleBenchmarkFixture.load()
        XCTAssertEqual(fixture.data.count, AppleBenchmarkFixture.exactByteCount)
    }

    func testProductionViewportEditor() throws {
        var creation: [Double] = []
        var insertion: [Double] = []
        var scroll: [Double] = []

        for run in 0..<(AppleBenchmark.warmups + AppleBenchmark.repetitions) {
            autoreleasepool {
                let start = ContinuousClock.now
                let session = AppleDocumentSession(text: fixture.text)
                attachAndLayout(session)
                let creationElapsed = AppleBenchmark.milliseconds(start.duration(to: .now))

                let insertStart = ContinuousClock.now
                session.replace(NSRange(location: 0, length: 0), with: "X")
                layoutViewport(session)
                let insertionElapsed = AppleBenchmark.milliseconds(insertStart.duration(to: .now))

                let scrollStart = ContinuousClock.now
                scrollToEnd(session)
                layoutViewport(session)
                let scrollElapsed = AppleBenchmark.milliseconds(scrollStart.duration(to: .now))

                if run >= AppleBenchmark.warmups {
                    creation.append(creationElapsed)
                    insertion.append(insertionElapsed)
                    scroll.append(scrollElapsed)
                }
                XCTAssertEqual(session.utf16Count, fixture.text.utf16.count + 1)
            }
        }

        AppleBenchmark.log(
            metric: "viewport_editor_construction_first_frame",
            summary: AppleBenchmark.summarize(creation),
            fixture: fixture,
            gateMilliseconds: 1_500
        )
        AppleBenchmark.log(
            metric: "viewport_editor_insert_to_frame",
            summary: AppleBenchmark.summarize(insertion),
            fixture: fixture,
            gateMilliseconds: 100
        )
        AppleBenchmark.log(
            metric: "viewport_editor_scroll_end_frame",
            summary: AppleBenchmark.summarize(scroll),
            fixture: fixture,
            gateMilliseconds: 100
        )
        AppleBenchmark.logMemory(metric: "viewport_editor_memory", fixture: fixture)
    }

    func testUnicodeHeavyVisibleLayoutAndInput() throws {
        let unicode = AppleBenchmarkFixture.unicodeHeavy()
        let session = AppleDocumentSession(text: unicode.text)
        attachAndLayout(session)

        let layout = AppleBenchmark.measure { layoutViewport(session) }
        AppleBenchmark.log(
            metric: "unicode_viewport_layout",
            summary: layout,
            fixture: unicode,
            gateMilliseconds: 100
        )

        let input = AppleBenchmark.measure {
            let caret = session.utf16Count
            session.replace(NSRange(location: caret, length: 0), with: "👍🏽")
            session.undo()
        }
        AppleBenchmark.log(
            metric: "unicode_grapheme_input",
            summary: input,
            fixture: unicode,
            gateMilliseconds: 100
        )

        #if os(macOS)
        let editor = try XCTUnwrap(session.editorView.documentView as? AppleViewportEditorView)
        #else
        let editor = session.editorView
        #endif
        XCTAssertNotNil(editor)
    }

    func testPreviewPageLoadToDidFinish() async throws {
        let data = try MarkdownRenderer.pageData(for: fixture.text)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "md4a-preview-benchmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pageURL = directory.appending(path: "preview.html")
        try data.write(to: pageURL)
        defer { try? FileManager.default.removeItem(at: directory) }
        var samples: [Double] = []

        for run in 0..<(AppleBenchmark.warmups + AppleBenchmark.repetitions) {
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
            let observer = NavigationFinishObserver()
            webView.navigationDelegate = observer
            let start = ContinuousClock.now
            async let finished: Void = observer.waitForFinish()
            webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL)
            try await finished
            let elapsed = AppleBenchmark.milliseconds(start.duration(to: .now))
            if run >= AppleBenchmark.warmups { samples.append(elapsed) }
            webView.stopLoading()
        }

        AppleBenchmark.log(
            metric: "preview_webview_file_did_finish",
            summary: AppleBenchmark.summarize(samples),
            fixture: fixture,
            extra: ["page_utf8_bytes": data.count],
            gateMilliseconds: 5_000
        )
        AppleBenchmark.logMemory(metric: "preview_webview_memory", fixture: fixture)
    }

    private func layoutViewport(_ session: AppleDocumentSession) {
        #if os(macOS)
        session.editorView.documentView?.displayIfNeeded()
        session.editorView.layoutSubtreeIfNeeded()
        #else
        session.editorView.setNeedsDisplay()
        session.editorView.layoutIfNeeded()
        session.editorView.layer.displayIfNeeded()
        #endif
    }

    private func attachAndLayout(_ session: AppleDocumentSession) {
        #if os(macOS)
        session.editorView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(contentRect: session.editorView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = session.editorView
        session.editorView.layoutSubtreeIfNeeded()
        #else
        session.editorView.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        let window = UIWindow(frame: session.editorView.frame)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(session.editorView)
        window.layoutIfNeeded()
        #endif
        layoutViewport(session)
    }

    private func scrollToEnd(_ session: AppleDocumentSession) {
        #if os(macOS)
        session.editorView.contentView.scroll(to: NSPoint(x: 0, y: session.editorView.documentView?.frame.height ?? 0))
        session.editorView.reflectScrolledClipView(session.editorView.contentView)
        #else
        session.editorView.setContentOffset(
            CGPoint(x: 0, y: max(0, session.editorView.contentSize.height - session.editorView.bounds.height)),
            animated: false
        )
        #endif
    }

}

@MainActor
private final class NavigationFinishObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
