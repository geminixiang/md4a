import SwiftUI

struct DocumentView: View {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject private var session: AppleDocumentSession
    @State private var mode: DocumentMode = .preview

    init(document: MarkdownDocument) {
        self.document = document
        session = document.session
    }

    var body: some View {
        content
            .toolbar {
                #if os(macOS)
                ToolbarItemGroup {
                    ForEach(DocumentMode.allCases) { item in
                        Toggle(isOn: isOn(item)) {
                            Label(item.title, systemImage: item.systemImage)
                        }
                        .help(item.title)
                    }
                }
                #else
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
                #endif
            }
            #if os(macOS)
            // No backdrop or hairline under the toolbar — the window
            // background runs seamlessly from the title bar to the cards.
            .toolbarBackground(.hidden, for: .windowToolbar)
            .focusedSceneValue(\.documentMode, $mode)
            #endif
    }

    private func isOn(_ target: DocumentMode) -> Binding<Bool> {
        Binding(get: { mode == target }, set: { if $0 { mode = target } })
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch mode {
            case .preview:
                pane(preview)
            case .split:
                #if os(macOS)
                splitPanes
                #else
                pane(preview) // Unreachable: allCases omits .split off macOS.
                #endif
            case .edit:
                pane(editor)
            }
        }
        #if os(macOS)
        .padding(8)
        #endif
    }

    #if os(macOS)
    @State private var editorFraction: CGFloat = 0.5
    @State private var dragBaseFraction: CGFloat?

    // A hand-rolled split so the gap between the cards stays a plain,
    // divider-free strip of window background, still draggable to resize.
    private var splitPanes: some View {
        GeometryReader { proxy in
            let total = max(proxy.size.width - 8, 1)
            let editorWidth = min(max(editorFraction * total, 280), max(total - 320, 280))
            HStack(spacing: 0) {
                pane(editor)
                    .frame(width: editorWidth)
                splitHandle(total: total)
                pane(preview)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func splitHandle(total: CGFloat) -> some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let base = dragBaseFraction ?? editorFraction
                        dragBaseFraction = base
                        editorFraction = min(max(base + value.translation.width / total, 0.15), 0.85)
                    }
                    .onEnded { _ in dragBaseFraction = nil }
            )
    }
    #endif

    // On macOS each pane is an inset rounded card on the window background,
    // which also keeps the toolbar backdrop identical across panes.
    private func pane(_ view: some View) -> some View {
        #if os(macOS)
        // Concentric with the window corner: its radius minus the 8pt inset.
        view.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        #else
        view
        #endif
    }

    private var preview: some View {
        PreviewWebView(
            markdown: session.previewText,
            revision: session.previewRevision,
            documentIdentity: document.previewIdentity
        )
    }

    private var editor: some View {
        NativeDocumentEditor(session: session)
            .background(editorBackground)
    }

    private var editorBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

enum DocumentMode: String, CaseIterable, Identifiable {
    case preview
    case split
    case edit

    // Split needs side-by-side space; only macOS offers it.
    static var allCases: [DocumentMode] {
        #if os(macOS)
        [.preview, .split, .edit]
        #else
        [.preview, .edit]
        #endif
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .preview: "Preview"
        case .split: "Split"
        case .edit: "Edit"
        }
    }

    var systemImage: String {
        switch self {
        case .preview: "doc.richtext"
        case .split: "rectangle.split.2x1"
        case .edit: "square.and.pencil"
        }
    }
}

#if os(macOS)
extension FocusedValues {
    @Entry var documentMode: Binding<DocumentMode>?
}
#endif
