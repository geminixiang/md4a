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
    /// Renders a complete, self-contained preview page as UTF-8 bytes.
    ///
    /// The C API owns its output buffer, so one copy into `Data` is still
    /// required before `md4a_result_free`. Keeping the page as bytes avoids
    /// the former C buffer -> Data -> body String -> page String copy chain.
    static func pageData(for markdown: String) throws -> Data {
        var result = withUTF8Bytes(of: markdown) { buffer in
            md4a_render(
                buffer.baseAddress?.assumingMemoryBound(to: CChar.self),
                buffer.count,
                nil
            )
        }
        defer { md4a_result_free(&result) }

        guard result.status.rawValue == 0, let html = result.html else {
            let message = result.error.map(String.init(cString:)) ?? "Markdown rendering failed"
            throw MarkdownRenderError.failed(message)
        }

        var page = Data()
        page.reserveCapacity(pageHeader.count + result.html_size + pageFooter.count)
        page.append(pageHeader)
        page.append(contentsOf: UnsafeRawBufferPointer(start: html, count: result.html_size))
        page.append(pageFooter)
        return page
    }

    static func render(_ markdown: String) throws -> String {
        let page = try pageData(for: markdown)
        let bodyStart = pageHeader.count
        let bodyEnd = page.count - pageFooter.count
        return String(decoding: page[bodyStart..<bodyEnd], as: UTF8.self)
    }

    private static func withUTF8Bytes<Result>(
        of text: String,
        _ body: (UnsafeRawBufferPointer) -> Result
    ) -> Result {
        if let result = text.utf8.withContiguousStorageIfAvailable({ storage in
            body(UnsafeRawBufferPointer(storage))
        }) {
            return result
        }

        // Non-contiguous Strings are uncommon here, but Data is a bounded
        // fallback that avoids allocating an Array<UInt8> plus its storage.
        let data = Data(text.utf8)
        return data.withUnsafeBytes(body)
    }

    private static let pageHeader = Data(
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>
        :root {
          color-scheme: light dark; font: -apple-system-body;
          --rule: color-mix(in srgb, currentColor 14%, transparent);
          --chip: color-mix(in srgb, currentColor 6.5%, transparent);
          --secondary: color-mix(in srgb, currentColor 62%, transparent);
        }
        html { -webkit-text-size-adjust: 100%; background: Canvas; }
        body {
          max-width: 42rem; margin: 0 auto; padding: 2.5rem 1.5rem 5rem;
          font-size: max(1em, 16px); line-height: 1.6; overflow-wrap: break-word;
        }
        body > :first-child { margin-top: 0; }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; margin: 1.75em 0 0.6em; }
        h1 { font-size: 2em; font-weight: 700; letter-spacing: -0.02em; line-height: 1.15; }
        h2 { font-size: 1.5em; letter-spacing: -0.015em; line-height: 1.2; }
        h3 { font-size: 1.25em; letter-spacing: -0.01em; }
        h4 { font-size: 1.05em; }
        h5, h6 { font-size: 1em; }
        h6 { color: var(--secondary); }
        h1 + h2, h2 + h3, h3 + h4 { margin-top: 0; }
        p { margin: 0 0 1em; }
        ul, ol { margin: 0 0 1em; padding-left: 1.6em; }
        li { margin: 0.25em 0; }
        li > ul, li > ol { margin-bottom: 0; }
        li:has(> input[type="checkbox"]:first-child) { list-style: none; margin-left: -1.35em; }
        input[type="checkbox"] { margin: 0 0.5em 0 0; vertical-align: -0.15em; }
        a { text-underline-offset: 2px; text-decoration-thickness: 1px;
            text-decoration-color: color-mix(in srgb, currentColor 35%, transparent); }
        code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.875em; }
        :not(pre) > code { background: var(--chip); border-radius: 5px; padding: 0.12em 0.35em; }
        pre { background: var(--chip); border-radius: 10px; padding: 0.875rem 1rem;
              margin: 0 0 1.25em; overflow-x: auto; line-height: 1.5; }
        pre code { background: none; border-radius: 0; padding: 0; }
        blockquote { margin: 1.25em 0; padding: 0.1em 0 0.1em 1em; color: var(--secondary);
                     border-left: 3px solid color-mix(in srgb, currentColor 22%, transparent); }
        blockquote > :last-child { margin-bottom: 0; }
        table { border-collapse: collapse; display: block; max-width: 100%;
                overflow-x: auto; margin: 0 0 1.25em; }
        th, td { padding: 0.45em 0.75em; text-align: left; vertical-align: top;
                 border-bottom: 1px solid var(--rule); }
        th:first-child, td:first-child { padding-left: 0; }
        th { border-bottom: 1.5px solid color-mix(in srgb, currentColor 30%, transparent); }
        img { max-width: 100%; height: auto; }
        hr { border: 0; height: 1px; background: var(--rule); margin: 2.5rem 0; }
        del { color: var(--secondary); }
        .error { color: #d00021; }
        @media (prefers-color-scheme: dark) { .error { color: #ff6b6b; } }
        @media print { body { max-width: none; padding: 0; } }
        </style></head><body>
        """.utf8
    )

    private static let pageFooter = Data("</body></html>".utf8)
}
