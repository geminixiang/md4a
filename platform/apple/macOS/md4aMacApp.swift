import SwiftUI

@main
struct md4aMacApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document)
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}
