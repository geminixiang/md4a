import Foundation

enum MarkdownRenderError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

enum MarkdownRenderer {
    static func render(_ markdown: String) throws -> String {
        let bytes = Array(markdown.utf8)
        var result = bytes.withUnsafeBytes { buffer in
            md4a_render(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), buffer.count, nil)
        }
        defer { md4a_result_free(&result) }

        guard result.status.rawValue == 0, let html = result.html else {
            let message = result.error.map(String.init(cString:)) ?? "Markdown rendering failed"
            throw MarkdownRenderError.failed(message)
        }
        let data = Data(bytes: html, count: result.html_size)
        return String(decoding: data, as: UTF8.self)
    }

    static func page(for markdown: String) -> String {
        let body: String
        do {
            body = try render(markdown)
        } catch {
            body = "<p class=\"error\">\(escape(error.localizedDescription))</p>"
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; font: -apple-system-body; }
        body { max-width: 48rem; margin: 0 auto; padding: 2rem; line-height: 1.55; overflow-wrap: break-word; }
        img { max-width: 100%; } pre { overflow: auto; padding: 1rem; background: color-mix(in srgb, currentColor 8%, transparent); border-radius: .5rem; }
        code { font-family: ui-monospace, monospace; } table { border-collapse: collapse; } th, td { border: 1px solid currentColor; padding: .4rem; }
        blockquote { margin-inline: 0; padding-left: 1rem; border-left: 3px solid currentColor; opacity: .8; } .error { color: #c00; }
        </style></head><body>\(body)</body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
