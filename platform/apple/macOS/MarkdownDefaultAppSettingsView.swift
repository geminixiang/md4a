import AppKit
import SwiftUI

struct MarkdownDefaultAppSettingsView: View {
    @State private var isDefault = false
    @State private var message: String?
    @State private var showConfirmation = false

    private let service = WorkspaceMarkdownDefaultApplicationService()

    var body: some View {
        Form {
            LabeledContent("Markdown files") {
                Text(isDefault ? "md4a is the default" : "Another app is the default")
                    .foregroundStyle(.secondary)
            }

            Button("Make md4a Default…") {
                showConfirmation = true
            }
            .disabled(isDefault)

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Fallback: select a Markdown file in Finder, choose Get Info, select md4a under Open with, then click Change All.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task { refresh() }
        .alert("Make md4a the default Markdown app?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Make Default") { requestChange() }
        } message: {
            Text("This asks macOS to open .md and .markdown files with md4a.")
        }
    }

    private func refresh() {
        isDefault = service.isCurrentApplicationDefault()
    }

    private func requestChange() {
        Task { @MainActor in
            do {
                try await service.setCurrentApplicationAsDefault()
                refresh()
                message = isDefault
                    ? "Default app updated."
                    : "macOS did not confirm the change; use the Finder fallback below."
            } catch {
                message = "Couldn’t update the default app: \(error.localizedDescription)"
            }
        }
    }
}
