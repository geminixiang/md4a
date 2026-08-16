import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    @State private var mode: DocumentMode = .preview

    var body: some View {
        Group {
            switch mode {
            case .preview:
                PreviewWebView(markdown: document.text)
            case .edit:
                editor
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Mode", selection: $mode) {
                    ForEach(DocumentMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch between Preview and Edit")
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $document.text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .padding(4)
    }
}

private enum DocumentMode: String, CaseIterable, Identifiable {
    case preview
    case edit

    var id: Self { self }

    var title: String {
        switch self {
        case .preview: "Preview"
        case .edit: "Edit"
        }
    }

    var systemImage: String {
        switch self {
        case .preview: "doc.richtext"
        case .edit: "square.and.pencil"
        }
    }
}
