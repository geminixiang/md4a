import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(macOS)
        HSplitView {
            editor
            PreviewWebView(markdown: document.text)
                .frame(minWidth: 320)
        }
        #else
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                editor.navigationTitle("Markdown")
            } detail: {
                PreviewWebView(markdown: document.text).navigationTitle("Preview")
            }
        } else {
            TabView {
                editor
                    .tabItem { Label("Edit", systemImage: "square.and.pencil") }
                PreviewWebView(markdown: document.text)
                    .tabItem { Label("Preview", systemImage: "doc.richtext") }
            }
        }
        #endif
    }

    private var editor: some View {
        TextEditor(text: $document.text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .padding(4)
    }
}
