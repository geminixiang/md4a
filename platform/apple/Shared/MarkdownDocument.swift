import Foundation
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

/// Thread-safe bridge between SwiftUI's background document callbacks and the
/// main-actor editing session. Values are immutable persistent-tree snapshots,
/// so reads and publication remain O(1).
final class AppleDocumentCore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MarkdownDocumentSnapshot

    init(_ value: MarkdownDocumentSnapshot) {
        self.value = value
    }

    convenience init(data: Data) throws {
        let buffer = try ApplePieceTreeBuffer(data: data)
        self.init(MarkdownDocumentSnapshot(document: buffer.snapshot(), revision: buffer.revision))
    }

    func snapshot() -> MarkdownDocumentSnapshot {
        lock.withLock { value }
    }

    func publish(_ snapshot: MarkdownDocumentSnapshot) {
        lock.withLock { value = snapshot }
    }
}

/// Reference document whose protocol witnesses are deliberately nonisolated:
/// AppKit opens NSDocument instances on its background opening queue. The live
/// editor is created only when a DocumentView first requests it on MainActor.
final class MarkdownDocument: ReferenceFileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static let readableContentTypes: [UTType] = [markdownType, .plainText]
    static let writableContentTypes: [UTType] = [markdownType]

    typealias Snapshot = MarkdownDocumentSnapshot

    private let core: AppleDocumentCore
    @MainActor private var sessionStorage: AppleDocumentSession?
    let previewIdentity = UUID()

    init(text: String = "# Untitled\n") {
        let buffer = ApplePieceTreeBuffer(text: text)
        core = AppleDocumentCore(.init(document: buffer.snapshot(), revision: buffer.revision))
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // ApplePieceTreeBuffer performs strict UTF-8 decoding. This initializer
        // intentionally stays synchronous because ReferenceFileDocument already
        // invokes it on its document-opening worker queue.
        core = try AppleDocumentCore(data: data)
    }

    @MainActor
    func session() -> AppleDocumentSession {
        if let sessionStorage { return sessionStorage }

        let initial = core.snapshot()
        let session = AppleDocumentSession(
            snapshot: initial.document,
            revision: initial.revision
        )
        session.onEdit = { [weak self, weak session] in
            guard let self, let session else { return }
            let current = MarkdownDocumentSnapshot(
                document: session.snapshot(),
                revision: session.revision
            )
            // Autosave may request a snapshot as soon as change publication is
            // observed, so publish the immutable revision first.
            self.core.publish(current)
            self.objectWillChange.send()
        }
        sessionStorage = session
        return session
    }

    func snapshot(contentType: UTType) throws -> MarkdownDocumentSnapshot {
        core.snapshot()
    }

    func fileWrapper(
        snapshot: MarkdownDocumentSnapshot,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        try snapshot.fileWrapper()
    }
}
