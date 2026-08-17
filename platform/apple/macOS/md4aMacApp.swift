import SwiftUI

@main
struct md4aMacApp: App {
    init() {
        // Smart substitution would silently rewrite Markdown syntax ("" for ", — for --).
        // Written to the app domain so it beats the user's global keyboard preference.
        for key in [
            "NSAutomaticQuoteSubstitutionEnabled",
            "NSAutomaticDashSubstitutionEnabled",
            "NSAutomaticTextReplacementEnabled",
        ] where UserDefaults.standard.object(forKey: key) as? Bool != false {
            UserDefaults.standard.set(false, forKey: key)
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(before: .toolbar) {
                DocumentModeCommands()
                Divider()
            }
        }
    }
}

private struct DocumentModeCommands: View {
    @FocusedBinding(\.documentMode) private var mode: DocumentMode?

    var body: some View {
        Group {
            ForEach(Array(DocumentMode.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { mode = item }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
        }
        // Menu items stay disabled until a document window is focused.
        .disabled(mode == nil)
    }
}
