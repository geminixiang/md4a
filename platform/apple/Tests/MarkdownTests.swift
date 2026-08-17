import XCTest
import Combine
import WebKit
#if os(macOS)
@testable import md4aMac
#else
@testable import md4aiOS
#endif

final class MarkdownTests: XCTestCase {
    func testDefaultAppOnboardingOffersOnlyBeforeUserDecision() {
        var onboarding = MarkdownDefaultAppOnboarding(decision: .notAsked)
        XCTAssertTrue(onboarding.shouldOfferInWelcome)

        onboarding.dismiss()
        XCTAssertEqual(onboarding.decision, .dismissed)
        XCTAssertFalse(onboarding.shouldOfferInWelcome)

        onboarding.resetForSettings()
        XCTAssertTrue(onboarding.shouldOfferInWelcome)
        onboarding.confirmRequest()
        XCTAssertEqual(onboarding.decision, .requested)
        XCTAssertFalse(onboarding.shouldOfferInWelcome)
    }

    func testMarkdownTypeUsesImportedDaringFireballIdentifier() {
        XCTAssertEqual(MarkdownDocument.markdownType.identifier, "net.daringfireball.markdown")
        XCTAssertTrue(MarkdownDocument.readableContentTypes.contains(MarkdownDocument.markdownType))
    }

    func testRendererUsesGFMAndSuppressesRawHTML() throws {
        let html = try MarkdownRenderer.render("~~old~~\n\n<script>alert(1)</script>")
        XCTAssertTrue(html.contains("<del>old</del>"))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testRendererHandlesUTF8() throws {
        let html = try MarkdownRenderer.render("# 橘子\n")
        XCTAssertEqual(html, "<h1>橘子</h1>\n")
    }

    @MainActor
    func testPreviewWebKitDOMPreservesUnicodeText() async throws {
        let corpus = "繁體中文 简体中文 日本語 한글 e\u{301} हिन्दी العربية 👨‍👩‍👧‍👦 👍🏽 🇹🇼 ❤️ 1️⃣ ✈️"
        let page = try MarkdownRenderer.pageData(for: corpus)
        let directory = FileManager.default.temporaryDirectory.appending(path: "md4a-unicode-dom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "preview.html")
        try page.write(to: url)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let observer = UnicodeNavigationObserver()
        webView.navigationDelegate = observer
        async let loaded: Void = observer.wait()
        webView.loadFileURL(url, allowingReadAccessTo: directory)
        try await loaded
        let value = try await webView.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertEqual(value?.trimmingCharacters(in: .whitespacesAndNewlines), corpus)
    }

    func testPreviewPipelineCoalescesRequestsAndSuppressesStaleResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "md4a-preview-test-root-\(UUID().uuidString)")
        let recorder = RenderRecorder()
        let pipeline = PreviewRenderPipeline(
            debounce: .milliseconds(30),
            cacheRootDirectory: root,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ) { markdown in
            recorder.record(markdown)
            return Data("<html>\(markdown)</html>".utf8)
        }
        let delivery = DeliveryRecorder()

        await pipeline.submit(.init(generation: 1, markdown: "one")) { result in
            delivery.record(result.generation)
        }
        await pipeline.submit(.init(generation: 2, markdown: "two")) { result in
            delivery.record(result.generation)
        }
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(recorder.values, ["two"])
        let deliveredValues = await delivery.values
        XCTAssertEqual(deliveredValues, [2])
        await pipeline.stop()
        XCTAssertEqual(
            (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [],
            []
        )
        try? FileManager.default.removeItem(at: root)
    }

    func testEightPointEightMegabytePreviewRenderDoesNotBlockMainActor() async throws {
        let markdown = makeLargeFixture(byteCount: 8_841_392)
        let heartbeat = expectation(description: "main actor remained responsive")
        let rendered = expectation(description: "large preview rendered")
        let root = FileManager.default.temporaryDirectory
            .appending(path: "md4a-large-preview-test-root-\(UUID().uuidString)")
        let pipeline = PreviewRenderPipeline(
            debounce: .zero,
            cacheRootDirectory: root,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        await pipeline.submit(.init(generation: 1, markdown: markdown)) { result in
            XCTAssertEqual(result.generation, 1)
            XCTAssertGreaterThan((try? Data(contentsOf: result.fileURL).count) ?? 0, 8_000_000)
            rendered.fulfill()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            heartbeat.fulfill()
        }

        await fulfillment(of: [heartbeat, rendered], timeout: 10, enforceOrder: true)
        await pipeline.stop()
        try? FileManager.default.removeItem(at: root)
    }

    func testPreviewCacheSweepsStaleSessionsAndKeepsCurrentSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "md4a-preview-cache-root-\(UUID().uuidString)")
        let stale = root.appending(path: "session-stale", directoryHint: .isDirectory)
        let unrelated = root.appending(path: "other-data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: stale.appending(path: "preview.html"))
        defer { try? FileManager.default.removeItem(at: root) }

        let store = PreviewCacheStore(
            rootDirectory: root,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        )
        try store.prepare()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sessionDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        store.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sessionDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testPreviewCacheDoesNotSweepAnotherActiveSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "md4a-preview-active-root-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = PreviewCacheStore(rootDirectory: root)
        let second = PreviewCacheStore(rootDirectory: root)
        try first.prepare()
        try second.prepare()

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.sessionDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.sessionDirectory.path))
        second.cleanup()
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.sessionDirectory.path))
        first.cleanup()
    }

    @MainActor
    func testClipboardRangeOperationsDoNotRequireWholeDocumentText() {
        let document = TestAppleEditorDocument("prefix selected suffix")
        let input = AppleEditorInputModel(document: document)
        input.setSelection(NSRange(location: 7, length: 8))

        XCTAssertEqual(document.text(in: input.selection.range), "selected")
        input.replaceSelection(with: "pasted")
        XCTAssertEqual(document.value, "prefix pasted suffix")
        input.selectAll()
        XCTAssertEqual(input.selection.range.length, document.utf16Count)
    }

    @MainActor
    func testReferenceDocumentSessionNotifiesAndSnapshotsEdits() throws {
        let document = MarkdownDocument(text: "# Before\r\n")
        let changed = expectation(description: "document announced an edit")
        let observation = document.objectWillChange.sink { changed.fulfill() }

        document.session().replace(
            NSRange(location: document.session().utf16Count, length: 0),
            with: "After"
        )

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(document.session().snapshot().text(), "# Before\r\nAfter")
        XCTAssertEqual(document.session().revision, 1)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testNativeSessionPreservesUnicodeAndUndo() throws {
        let document = MarkdownDocument(text: "橘子\r\n")
        document.session().replace(
            NSRange(location: document.session().utf16Count, length: 0),
            with: "🙂"
        )
        XCTAssertEqual(document.session().snapshot().text(), "橘子\r\n🙂")
        document.session().undo()
        XCTAssertEqual(document.session().snapshot().text(), "橘子\r\n")
        document.session().redo()
        XCTAssertEqual(document.session().snapshot().text(), "橘子\r\n🙂")
    }

    @MainActor
    func testProductionSnapshotFileWrapperRoundTripsSurrogateBoundaryWithoutMarkingClean() throws {
        let text = String(repeating: "a", count: 16_383) + "🙂\r\n橘"
        let document = MarkdownDocument(text: text)
        document.session().replace(NSRange(location: 0, length: 0), with: "!")
        XCTAssertTrue(document.session().isDirty)

        let snapshot = try document.snapshot(contentType: MarkdownDocument.markdownType)
        let wrapper = try snapshot.fileWrapper()
        XCTAssertEqual(wrapper.regularFileContents, Data(("!" + text).utf8))
        XCTAssertTrue(document.session().isDirty, "Serialization is not a completed coordinated save")
    }

    func testSnapshotFileWrapperCanRunOffMainActor() async throws {
        let snapshot = await MainActor.run {
            let document = MarkdownDocument(text: String(repeating: "a", count: 16_383) + "🙂")
            return try! document.snapshot(contentType: MarkdownDocument.markdownType)
        }
        let bytes = try await Task.detached { try snapshot.fileWrapper().regularFileContents }.value
        XCTAssertEqual(bytes, Data((String(repeating: "a", count: 16_383) + "🙂").utf8))
    }

    func testDocumentCoreSupportsConcurrentBackgroundSnapshotsAndPublication() async throws {
        let firstText = String(repeating: "first 橘子\r\n", count: 2_000)
        let secondText = String(repeating: "second 🙂\n", count: 2_000)
        let first = try ApplePieceTreeBuffer(data: Data(firstText.utf8))
        let second = try ApplePieceTreeBuffer(data: Data(secondText.utf8))
        let firstSnapshot = MarkdownDocumentSnapshot(document: first.snapshot(), revision: 1)
        let secondSnapshot = MarkdownDocumentSnapshot(document: second.snapshot(), revision: 2)
        let core = AppleDocumentCore(firstSnapshot)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    if index.isMultiple(of: 3) {
                        core.publish(secondSnapshot)
                    } else {
                        let value = core.snapshot()
                        XCTAssertTrue(value.revision == 1 || value.revision == 2)
                        let bytes = try value.fileWrapper().regularFileContents
                        XCTAssertTrue(bytes == Data(firstText.utf8) || bytes == Data(secondText.utf8))
                    }
                }
            }
            try await group.waitForAll()
        }

        XCTAssertEqual(core.snapshot().revision, 2)
    }

    func testDocumentCoresKeepConcurrentDocumentsIsolated() async throws {
        let alpha = try AppleDocumentCore(data: Data("alpha 橘子".utf8))
        let beta = try AppleDocumentCore(data: Data("beta 🙂".utf8))

        async let alphaBytes = Task.detached { try alpha.snapshot().fileWrapper().regularFileContents }.value
        async let betaBytes = Task.detached { try beta.snapshot().fileWrapper().regularFileContents }.value

        let values = try await (alphaBytes, betaBytes)
        XCTAssertEqual(values.0, Data("alpha 橘子".utf8))
        XCTAssertEqual(values.1, Data("beta 🙂".utf8))
    }

    func testDocumentCoreStrictlyRejectsInvalidUTF8OffMainActor() async {
        let invalid = Data([0xF0, 0x28, 0x8C, 0x28])
        do {
            _ = try await Task.detached { try AppleDocumentCore(data: invalid) }.value
            XCTFail("Invalid UTF-8 unexpectedly opened")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadInapplicableStringEncoding)
        }
    }

    @MainActor
    func testUndoRedoRestoresInputSelection() {
        let document = TestAppleEditorDocument("abcdef")
        let input = AppleEditorInputModel(document: document)
        input.setSelection(NSRange(location: 2, length: 2))
        input.replaceSelection(with: "X")
        XCTAssertEqual(input.selection.range, NSRange(location: 3, length: 0))
        input.undo()
        XCTAssertEqual(input.selection.range, NSRange(location: 2, length: 2))
        input.redo()
        XCTAssertEqual(input.selection.range, NSRange(location: 3, length: 0))
    }

    @MainActor
    func testViewportEditorInputCompositionAndUnicodeDeletion() {
        let document = TestAppleEditorDocument("a🙂\r\norange")
        let input = AppleEditorInputModel(document: document)

        input.setSelection(NSRange(location: 1, length: 0))
        input.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0))
        input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        input.commitText("你")
        input.unmarkText()
        XCTAssertEqual(document.value, "a你🙂\r\norange")
        XCTAssertEqual(input.selection.range, NSRange(location: 2, length: 0))
        XCTAssertNil(input.markedRange)

        input.setSelection(NSRange(location: 4, length: 0))
        input.deleteBackward()
        XCTAssertEqual(document.value, "a你\r\norange")
    }

    @MainActor
    func testIMECommitReplacesActiveCompositionWithoutDuplicatingText() {
        let cases: [(marked: [String], committed: String)] = [
            (["n", "ni"], "你"),
            (["中"], "中文"),
            (["ㅎ", "하"], "한"),
            (["k", "か"], "漢"),
        ]

        for value in cases {
            let document = TestAppleEditorDocument("A🙂B")
            let input = AppleEditorInputModel(document: document)
            input.setSelection(NSRange(location: 1, length: 0))
            for marked in value.marked {
                input.setMarkedText(
                    marked,
                    selectedRange: NSRange(location: marked.utf16.count, length: 0)
                )
            }

            input.commitText(value.committed)
            input.unmarkText()

            XCTAssertEqual(document.value, "A\(value.committed)🙂B")
            XCTAssertEqual(
                input.selection.range,
                NSRange(location: 1 + value.committed.utf16.count, length: 0)
            )
            XCTAssertNil(input.markedRange)
            XCTAssertEqual(Data(document.value.utf8), Data("A\(value.committed)🙂B".utf8))
        }
    }

    @MainActor
    func testIMEExplicitReplacementRangeTakesPrecedenceAndRepeatedCompositionReplacesMark() {
        let document = TestAppleEditorDocument("before target after")
        let input = AppleEditorInputModel(document: document)
        let target = (document.value as NSString).range(of: "target")

        input.setMarkedText(
            "n",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: target
        )
        input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(document.value, "before ni after")
        XCTAssertEqual(input.markedRange, NSRange(location: target.location, length: 2))

        input.commitText("你", replacementRange: input.markedRange)
        XCTAssertEqual(document.value, "before 你 after")
        XCTAssertEqual(input.selection.range, NSRange(location: target.location + 1, length: 0))
        XCTAssertNil(input.markedRange)
    }

    @MainActor
    func testPlatformInputAdapterCommitsMarkedTextExactlyOnce() {
        let document = TestAppleEditorDocument("A")
        let editor = AppleViewportEditorView(document: document)
        #if os(macOS)
        let notFound = NSRange(location: NSNotFound, length: 0)
        editor.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0), replacementRange: notFound)
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: notFound)
        editor.insertText("你", replacementRange: notFound)
        #else
        editor.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0))
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        editor.insertText("你")
        #endif

        XCTAssertEqual(document.value, "你A")
        XCTAssertEqual(editor.model.selection.range, NSRange(location: 1, length: 0))
        XCTAssertNil(editor.model.markedRange)
    }

    @MainActor
    func testViewportEditorBoundsSelectionsAndIMEContext() {
        let document = TestAppleEditorDocument(String(repeating: "x", count: 10_000))
        let input = AppleEditorInputModel(document: document)

        input.setSelection(NSRange(location: 20_000, length: 10))
        XCTAssertEqual(input.selection.range, NSRange(location: 10_000, length: 0))

        let context = input.boundedContext(limit: 128)
        XCTAssertEqual(context.range, NSRange(location: 9_872, length: 128))
        XCTAssertEqual(context.text.utf16.count, 128)
    }

    private func makeLargeFixture(byteCount: Int) -> String {
        let line = "## Deterministic fixture 橘子\n\nA paragraph with **Markdown** and a [link](https://example.com).\n"
        let repetitions = byteCount / line.utf8.count + 1
        let bytes = Data(String(repeating: line, count: repetitions).utf8).prefix(byteCount)
        return String(decoding: bytes, as: UTF8.self)
    }
}

@MainActor
private final class TestAppleEditorDocument: AppleEditorDocument {
    private(set) var value: String
    private var undoValues: [(String, NSRange)] = []
    private var redoValues: [(String, NSRange)] = []
    private(set) var revision: UInt64 = 0
    private(set) var editorSelection = NSRange(location: 0, length: 0)

    init(_ value: String) { self.value = value }

    var utf16Count: Int { value.utf16.count }
    var lineCount: Int { (value as NSString).components(separatedBy: "\n").count }
    var canUndo: Bool { !undoValues.isEmpty }
    var canRedo: Bool { !redoValues.isEmpty }

    func lineRange(at line: Int) -> NSRange {
        let string = value as NSString
        var current = 0
        var range = NSRange(location: 0, length: 0)
        while current <= line {
            guard range.location < string.length || current == 0 else {
                return NSRange(location: string.length, length: 0)
            }
            range = string.lineRange(for: NSRange(location: range.location, length: 0))
            if current == line { return range }
            range.location = NSMaxRange(range)
            current += 1
        }
        return range
    }

    func text(in range: NSRange) -> String { (value as NSString).substring(with: range) }

    func setEditorSelection(_ range: NSRange) { editorSelection = range }

    func replace(_ range: NSRange, with text: String) {
        undoValues.append((value, editorSelection))
        redoValues.removeAll()
        value = (value as NSString).replacingCharacters(in: range, with: text)
        editorSelection = NSRange(location: range.location + text.utf16.count, length: 0)
        revision &+= 1
    }

    func undo() {
        guard let previous = undoValues.popLast() else { return }
        redoValues.append((value, editorSelection))
        value = previous.0
        editorSelection = previous.1
        revision &+= 1
    }

    func redo() {
        guard let next = redoValues.popLast() else { return }
        undoValues.append((value, editorSelection))
        value = next.0
        editorSelection = next.1
        revision &+= 1
    }
}

@MainActor
private final class UnicodeNavigationObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private final class RenderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func record(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

@MainActor
private final class DeliveryRecorder {
    private(set) var values: [UInt64] = []

    func record(_ value: UInt64) {
        values.append(value)
    }
}
