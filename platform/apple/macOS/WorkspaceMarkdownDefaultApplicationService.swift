#if os(macOS)
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct WorkspaceMarkdownDefaultApplicationService: MarkdownDefaultApplicationService {
    private let workspace: NSWorkspace
    private let applicationURL: URL
    private let contentType: UTType

    init(
        workspace: NSWorkspace = .shared,
        applicationURL: URL = Bundle.main.bundleURL,
        contentType: UTType = MarkdownDocument.markdownType
    ) {
        self.workspace = workspace
        self.applicationURL = applicationURL
        self.contentType = contentType
    }

    func isCurrentApplicationDefault() -> Bool {
        workspace.urlForApplication(toOpen: contentType)?.standardizedFileURL
            == applicationURL.standardizedFileURL
    }

    func setCurrentApplicationAsDefault() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.setDefaultApplication(at: applicationURL, toOpen: contentType) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
