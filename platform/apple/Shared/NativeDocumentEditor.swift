import SwiftUI
#if os(macOS)
import AppKit

struct NativeDocumentEditor: NSViewRepresentable {
    let session: AppleDocumentSession

    func makeNSView(context: Context) -> NSScrollView { session.editorView }
    func updateNSView(_ scrollView: NSScrollView, context: Context) {}
}
#else
import UIKit

struct NativeDocumentEditor: UIViewRepresentable {
    let session: AppleDocumentSession

    func makeUIView(context: Context) -> AppleViewportEditorView { session.editorView }
    func updateUIView(_ editor: AppleViewportEditorView, context: Context) {
        editor.setNeedsDisplay()
    }
}
#endif
