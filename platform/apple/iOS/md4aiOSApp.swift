import SwiftUI

@main
struct md4aiOSApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document)
        }

        if #available(iOS 18.0, *) {
            DocumentGroupLaunchScene("md4a") {
                IOSDocumentLaunchActions()
            } background: {
                Color(uiColor: .systemBackground)
            }
        }
    }
}

@available(iOS 18.0, *)
private struct IOSDocumentLaunchActions: View {
    @AppStorage("didExplainMarkdownOpenIn") private var didExplainMarkdownOpenIn = false

    var body: some View {
        NewDocumentButton(
            "New Document",
            for: MarkdownDocument.self,
            contentType: MarkdownDocument.markdownType
        )

        if !didExplainMarkdownOpenIn {
            VStack(spacing: 8) {
                Text("Open Markdown from Files")
                    .font(.headline)
                Text("md4a appears in Files and Open In for Markdown documents. iPhone and iPad do not support choosing a default app for this file type.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Got It") {
                    didExplainMarkdownOpenIn = true
                }
            }
            .padding()
        }
    }
}
