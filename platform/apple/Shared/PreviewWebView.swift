import SwiftUI
import WebKit

#if os(macOS)
struct PreviewWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(markdown, in: webView)
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
}
#else
struct PreviewWebView: UIViewRepresentable {
    let markdown: String

    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(markdown, in: webView)
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
}
#endif

@MainActor
final class PreviewCoordinator: NSObject, WKNavigationDelegate {
    private var renderedMarkdown: String?
    private var pendingRender: Task<Void, Never>?
    private var savedScrollY: Double = 0

    func render(_ markdown: String, in webView: WKWebView) {
        guard renderedMarkdown != markdown else { return }
        pendingRender?.cancel()
        guard renderedMarkdown != nil else {
            loadPage(MarkdownRenderer.page(for: markdown), markdown: markdown, in: webView)
            return
        }
        // Re-render shortly after typing pauses so the preview doesn't reload
        // on every keystroke; the page is assembled off the main actor.
        pendingRender = Task { [weak self, weak webView] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let page = await Task.detached { MarkdownRenderer.page(for: markdown) }.value
            guard !Task.isCancelled, let self, let webView else { return }
            self.loadPage(page, markdown: markdown, in: webView)
        }
    }

    private func loadPage(_ page: String, markdown: String, in webView: WKWebView) {
        let isFirstRender = renderedMarkdown == nil
        renderedMarkdown = markdown
        guard !isFirstRender else {
            webView.loadHTMLString(page, baseURL: nil)
            return
        }
        webView.evaluateJavaScript("window.scrollY") { [weak self, weak webView] value, _ in
            self?.savedScrollY = (value as? NSNumber)?.doubleValue ?? 0
            webView?.loadHTMLString(page, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
        decisionHandler(scheme == "about" ? .allow : .cancel)
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
