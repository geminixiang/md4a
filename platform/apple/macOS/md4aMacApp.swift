import AppKit
import SwiftUI

@main
struct md4aMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        // The first scene is a normal welcome window, so launching md4a never
        // presents an open panel or creates an empty Untitled document.
        WindowGroup("md4a", id: "welcome") {
            WelcomeView()
                .frame(minWidth: 560, minHeight: 560)
                .background(WindowSizer())
        }
        .defaultSize(WindowDefaults.size)

        Settings {
            MarkdownDefaultAppSettingsView()
                .frame(width: 460)
                .padding()
        }

        // Finder/Open With activation is still routed to the native document
        // scene. The welcome window intentionally remains available as a home
        // for opening another document, matching Preview and other Mac apps.
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document)
                .frame(minWidth: 720, minHeight: 560)
                .frame(idealWidth: WindowDefaults.size.width, idealHeight: WindowDefaults.size.height)
                .background(WindowSizer())
        }
        .defaultSize(WindowDefaults.size)
        .commands {
            CommandGroup(before: .toolbar) {
                DocumentModeCommands()
                Divider()
            }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool { false }
}

private struct WelcomeView: View {
    @Environment(\.openDocument) private var openDocument
    @Environment(\.newDocument) private var newDocument
    @State private var errorMessage: String?
    @State private var showDefaultConfirmation = false
    @State private var defaultAppMessage: String?
    @State private var isDefaultApplication = false
    @AppStorage("markdownDefaultAppDecision") private var defaultAppDecision = MarkdownDefaultAppDecision.notAsked.rawValue

    private let defaultApplicationService = WorkspaceMarkdownDefaultApplicationService()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 42)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)

            Text("md4a")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .padding(.top, 18)

            Text("Read and edit Markdown, beautifully.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(spacing: 12) {
                Button(action: chooseFile) {
                    Label("Open File…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o")

                Button("New Document") {
                    newDocument { MarkdownDocument() }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut("n")
            }
            .frame(width: 240)
            .padding(.top, 30)

            if shouldOfferDefaultApplication {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Open Markdown with md4a", systemImage: "doc.text")
                        .font(.headline)
                    Text("You can make md4a the default app for .md and .markdown files. This changes only after you confirm.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Not Now") {
                            defaultAppDecision = MarkdownDefaultAppDecision.dismissed.rawValue
                        }
                        Spacer()
                        Button("Make Default…") {
                            showDefaultConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 24)
            }

            if let defaultAppMessage {
                Text(defaultAppMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 12)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .padding(.top, 14)
            }

            Spacer(minLength: 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("md4a.welcome")
        .task {
            isDefaultApplication = defaultApplicationService.isCurrentApplicationDefault()
        }
        .alert("Make md4a the default Markdown app?", isPresented: $showDefaultConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Make Default") { setAsDefaultApplication() }
        } message: {
            Text("Future .md and .markdown files will open in md4a. You can change this later in Finder or System Settings.")
        }
    }

    private var shouldOfferDefaultApplication: Bool {
        defaultAppDecision == MarkdownDefaultAppDecision.notAsked.rawValue && !isDefaultApplication
    }

    private func setAsDefaultApplication() {
        defaultAppDecision = MarkdownDefaultAppDecision.requested.rawValue
        Task { @MainActor in
            do {
                try await defaultApplicationService.setCurrentApplicationAsDefault()
                isDefaultApplication = defaultApplicationService.isCurrentApplicationDefault()
                defaultAppMessage = isDefaultApplication
                    ? "md4a is now the default Markdown app."
                    : "macOS did not report md4a as the default. Use Finder’s Get Info → Open with → Change All as a fallback."
            } catch {
                defaultAppMessage = "Couldn’t change the default app: \(error.localizedDescription). You can use Finder’s Get Info → Open with → Change All."
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.readableContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await openDocument(at: url)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct WindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { resizeWindow(containing: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { resizeWindow(containing: view) }
    }

    private func resizeWindow(containing view: NSView) {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
        let target = WindowDefaults.size(for: screen.visibleFrame)
        guard window.frame.height < target.height * 0.9 else { return }
        var frame = window.frame
        frame.size = target
        frame.origin.x = screen.visibleFrame.midX - target.width / 2
        frame.origin.y = screen.visibleFrame.midY - target.height / 2
        window.setFrame(frame, display: true, animate: false)
    }
}

private enum WindowDefaults {
    static var size: CGSize {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return CGSize(width: 960, height: 760)
        }
        return size(for: visibleFrame)
    }

    static func size(for visibleFrame: CGRect) -> CGSize {
        let height = min(max(visibleFrame.height * 0.85, 640), visibleFrame.height)
        let width = min(max(height * 1.15, 760), visibleFrame.width * 0.9)
        return CGSize(width: width.rounded(), height: height.rounded())
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
