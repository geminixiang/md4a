import SwiftUI
import WebKit

#if os(macOS)
struct PreviewWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, markdown: markdown, coordinator: context.coordinator)
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
}
#else
struct PreviewWebView: UIViewRepresentable {
    let markdown: String

    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, markdown: markdown, coordinator: context.coordinator)
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
}
#endif

final class PreviewCoordinator: NSObject, WKNavigationDelegate {
    var markdown: String?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
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

private func makeWebView(coordinator: PreviewCoordinator) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    return webView
}

private func update(_ webView: WKWebView, markdown: String, coordinator: PreviewCoordinator) {
    guard coordinator.markdown != markdown else { return }
    coordinator.markdown = markdown
    webView.loadHTMLString(MarkdownRenderer.page(for: markdown), baseURL: nil)
}
