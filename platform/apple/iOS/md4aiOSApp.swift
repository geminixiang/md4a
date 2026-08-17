import SwiftUI

@main
struct md4aiOSApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document)
        }

        if #available(iOS 18.0, *) {
            DocumentGroupLaunchScene("md4a") {
                NewDocumentButton(
                    "New Document",
                    for: MarkdownDocument.self,
                    contentType: MarkdownDocument.markdownType
                )
            } background: {
                Color(uiColor: .systemBackground)
            }
        }
    }
}
