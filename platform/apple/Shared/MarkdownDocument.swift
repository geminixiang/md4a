import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocumentSnapshot: @unchecked Sendable {
    let document: AppleDocumentSnapshot
    let revision: UInt64

    /// FileWrapper creation is deliberately independent of the live session.
    /// ReferenceFileDocument may invoke it away from the main actor.
    func fileWrapper() throws -> FileWrapper {
        let stream = OutputStream.toMemory()
        try document.writeUTF8(to: stream)
        guard let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

/// Reference document whose source of truth is a persistent piece tree.
/// SwiftUI receives lightweight change notifications for autosave; full UTF-8
/// materialization occurs only because FileWrapper requires Data at save time.
@MainActor
final class MarkdownDocument: @preconcurrency ReferenceFileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static let readableContentTypes: [UTType] = [markdownType, .plainText]
    static let writableContentTypes: [UTType] = [markdownType]

    typealias Snapshot = MarkdownDocumentSnapshot

    let session: AppleDocumentSession
    let previewIdentity = UUID()

    init(text: String = "# Untitled\n") {
        session = AppleDocumentSession(text: text)
        connectAutosaveNotification()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        session = try AppleDocumentSession(data: data)
        connectAutosaveNotification()
    }

    func snapshot(contentType: UTType) throws -> MarkdownDocumentSnapshot {
        MarkdownDocumentSnapshot(document: session.snapshot(), revision: session.revision)
    }

    nonisolated func fileWrapper(
        snapshot: MarkdownDocumentSnapshot,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        try snapshot.fileWrapper()
    }

    private func connectAutosaveNotification() {
        // ReferenceFileDocument owns the dirty lifecycle: an edit notification
        // schedules a coordinated write, and SwiftUI clears its dirty state only
        // after that write succeeds. There is intentionally no eager
        // `session.markSaved()` in fileWrapper because serialization is not a
        // successful coordinated write and the protocol has no completion hook.
        session.onEdit = { [weak self] in self?.objectWillChange.send() }
    }
}
