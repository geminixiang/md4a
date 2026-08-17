import SwiftUI
import WebKit

#if os(macOS)
struct PreviewWebView: NSViewRepresentable {
    let markdown: String
    let revision: UInt64
    let documentIdentity: UUID

    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(
            markdown,
            revision: revision,
            documentIdentity: documentIdentity,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: PreviewCoordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
}
#else
struct PreviewWebView: UIViewRepresentable {
    let markdown: String
    let revision: UInt64
    let documentIdentity: UUID

    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(
            markdown,
            revision: revision,
            documentIdentity: documentIdentity,
            in: webView
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: PreviewCoordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
}
#endif

struct PreviewRenderRequest: Sendable {
    let generation: UInt64
    let markdown: String
}

struct PreviewRenderResult: Sendable {
    let generation: UInt64
    let fileURL: URL
}

/// Owns privacy-sensitive preview files under one app cache root. Active
/// sessions are registered process-wide so opening another document cannot
/// sweep a directory that WebKit is currently reading. A fresh process has an
/// empty registry and therefore removes directories left by a crash or jetsam.
final class PreviewCacheStore: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var activeDirectories: Set<String> = []

    let rootDirectory: URL
    let sessionDirectory: URL

    init(
        rootDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "md4a-previews", directoryHint: .isDirectory),
        sessionID: UUID = UUID()
    ) {
        self.rootDirectory = rootDirectory
        sessionDirectory = rootDirectory.appending(
            path: "session-\(sessionID.uuidString)",
            directoryHint: .isDirectory
        )
    }

    func prepare() throws {
        _ = Self.lock.withLock { Self.activeDirectories.insert(sessionDirectory.lastPathComponent) }
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            try protectAndExcludeFromBackup(rootDirectory)
            let active = Self.lock.withLock { Self.activeDirectories }
            for candidate in try FileManager.default.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) where candidate.lastPathComponent.hasPrefix("session-")
                && !active.contains(candidate.lastPathComponent) {
                try? FileManager.default.removeItem(at: candidate)
            }
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try protectAndExcludeFromBackup(sessionDirectory)
        } catch {
            _ = Self.lock.withLock {
                Self.activeDirectories.remove(sessionDirectory.lastPathComponent)
            }
            throw error
        }
    }

    func prepareFile(_ url: URL) throws {
        try protectAndExcludeFromBackup(url)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: sessionDirectory)
        _ = Self.lock.withLock {
            Self.activeDirectories.remove(sessionDirectory.lastPathComponent)
        }
    }

    private func protectAndExcludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        #if os(iOS)
        // Preview is only produced and consumed while the protected document
        // UI is active; complete protection avoids leaving readable Markdown
        // after the device locks.
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }
}

actor PreviewRenderPipeline {
    typealias RenderPage = @Sendable (String) throws -> Data

    private let debounce: Duration
    private let cacheStore: PreviewCacheStore
    private let cacheDirectory: URL
    private let renderPage: RenderPage
    private var pendingRequest: PreviewRenderRequest?
    private var worker: Task<Void, Never>?
    private var filesByGeneration: [UInt64: URL] = [:]
    private var stopped = false

    init(
        debounce: Duration = .milliseconds(250),
        cacheRootDirectory: URL? = nil,
        sessionID: UUID = UUID(),
        renderPage: @escaping RenderPage = MarkdownRenderer.pageData
    ) {
        self.debounce = debounce
        let store = PreviewCacheStore(
            rootDirectory: cacheRootDirectory ?? FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )[0].appending(path: "md4a-previews", directoryHint: .isDirectory),
            sessionID: sessionID
        )
        cacheStore = store
        cacheDirectory = store.sessionDirectory
        self.renderPage = renderPage
        try? store.prepare()
    }

    func submit(
        _ request: PreviewRenderRequest,
        deliver: @escaping @MainActor @Sendable (PreviewRenderResult) -> Void
    ) {
        guard !stopped else { return }
        pendingRequest = request
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.run(deliver: deliver)
        }
    }

    func stop() {
        stopped = true
        pendingRequest = nil
        worker?.cancel()
        worker = nil
        removeAllFiles()
        cacheStore.cleanup()
    }

    private func run(
        deliver: @escaping @MainActor @Sendable (PreviewRenderResult) -> Void
    ) async {
        defer { worker = nil }

        while !stopped, !Task.isCancelled {
            guard let candidate = pendingRequest else { return }
            pendingRequest = nil

            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }

            // A request arriving during debounce replaces the candidate
            // without starting an unnecessary full render.
            if pendingRequest != nil { continue }

            let data: Data
            do {
                // md4c does not expose cancellation. Run exactly one native
                // render at a time off the actor, then suppress its result if
                // a newer request arrived while it was executing.
                let renderPage = self.renderPage
                data = try await Task.detached(priority: .userInitiated) {
                    try renderPage(candidate.markdown)
                }.value
            } catch {
                // Preserve the last successfully loaded preview.
                continue
            }
            guard !stopped, !Task.isCancelled, pendingRequest == nil else { continue }

            do {
                try FileManager.default.createDirectory(
                    at: cacheDirectory,
                    withIntermediateDirectories: true
                )
                let destination = cacheDirectory.appending(path: "preview-\(candidate.generation).html")
                let temporary = cacheDirectory.appending(path: "preview-\(candidate.generation).tmp")
                try data.write(to: temporary, options: .atomic)
                try cacheStore.prepareFile(temporary)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
                try cacheStore.prepareFile(destination)

                guard !stopped, !Task.isCancelled, pendingRequest == nil else {
                    try? FileManager.default.removeItem(at: destination)
                    continue
                }
                filesByGeneration[candidate.generation] = destination
                await deliver(PreviewRenderResult(generation: candidate.generation, fileURL: destination))
            } catch {
                // A failed cache write leaves the existing page in place.
            }
        }
    }

    func removeFiles(except generation: UInt64) {
        let staleFiles = filesByGeneration.filter { $0.key != generation }
        for (fileGeneration, url) in staleFiles {
            try? FileManager.default.removeItem(at: url)
            filesByGeneration.removeValue(forKey: fileGeneration)
        }
    }

    private func removeAllFiles() {
        for url in filesByGeneration.values {
            try? FileManager.default.removeItem(at: url)
        }
        filesByGeneration.removeAll()
    }
}

@MainActor
final class PreviewCoordinator: NSObject, WKNavigationDelegate {
    private var requestedGeneration: UInt64?
    private var documentIdentity: UUID?
    private var loadedGeneration: UInt64?
    private var loadingGeneration: UInt64?
    private var savedScrollY: Double = 0
    private let pipeline: PreviewRenderPipeline

    override init() {
        pipeline = PreviewRenderPipeline()
        super.init()
    }

    func render(
        _ markdown: String,
        revision: UInt64,
        documentIdentity: UUID,
        in webView: WKWebView
    ) {
        if self.documentIdentity != documentIdentity {
            self.documentIdentity = documentIdentity
            requestedGeneration = nil
            loadedGeneration = nil
            loadingGeneration = nil
            savedScrollY = 0
        }
        guard requestedGeneration != revision else { return }
        requestedGeneration = revision
        let request = PreviewRenderRequest(generation: revision, markdown: markdown)
        Task { [pipeline, weak self, weak webView] in
            await pipeline.submit(request) { result in
                guard let self, let webView,
                      self.requestedGeneration == result.generation else { return }
                self.load(result, in: webView)
            }
        }
    }

    func stop() {
        requestedGeneration = nil
        Task { [pipeline] in await pipeline.stop() }
    }

    private func load(_ result: PreviewRenderResult, in webView: WKWebView) {
        loadingGeneration = result.generation
        guard loadedGeneration != nil else {
            webView.loadFileURL(result.fileURL, allowingReadAccessTo: result.fileURL)
            return
        }
        webView.evaluateJavaScript("window.scrollY") { [weak self, weak webView] value, _ in
            guard let self, let webView,
                  self.requestedGeneration == result.generation else { return }
            self.savedScrollY = (value as? NSNumber)?.doubleValue ?? 0
            webView.loadFileURL(result.fileURL, allowingReadAccessTo: result.fileURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let loadingGeneration {
            loadedGeneration = loadingGeneration
            self.loadingGeneration = nil
            Task { [pipeline] in await pipeline.removeFiles(except: loadingGeneration) }
        }
        guard savedScrollY > 0 else { return }
        webView.evaluateJavaScript("window.scrollTo(0, \(savedScrollY))")
        savedScrollY = 0
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           ["http", "https", "mailto"].contains(url.scheme ?? "") {
            openExternally(url)
        }
        decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        let scheme = navigationResponse.response.url?.scheme
        decisionHandler(scheme == "file" ? .allow : .cancel)
    }
}

@MainActor
private func openExternally(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}

@MainActor
private func makeWebView(coordinator: PreviewCoordinator) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    // Match the document background before the page paints, so switching
    // modes doesn't flash white in dark appearance.
    #if os(macOS)
    webView.underPageBackgroundColor = .textBackgroundColor
    #else
    webView.underPageBackgroundColor = .systemBackground
    #endif
    return webView
}
