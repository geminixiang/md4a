# Renderer package format

A Renderer package (`.md4apkg`) is a ZIP archive. It contains no native libraries, bytecode, shell scripts, or installer hooks.

The package format is shared across platforms, but installation policy is not. iOS and Mac App Store builds treat packages as application resources bundled at review time; they do not download renderer JavaScript that changes app functionality. Other distributions may enable verified remote installation when their current store and sandbox policies allow it.

## Archive layout

```text
manifest.json
SIGNATURE
assets/
  renderer.js
  renderer.css
  ...
```

`manifest.json` is UTF-8 JSON serialized in the canonical form specified by the catalog protocol. Unknown manifest keys are rejected until versioning rules say otherwise.

## Manifest version 1

```json
{
  "schemaVersion": 1,
  "id": "org.mermaidjs.mermaid",
  "version": "1.0.0",
  "name": "Mermaid",
  "publisher": "org.mermaidjs",
  "minimumHostVersion": "0.1.0",
  "renderers": [
    {
      "fence": "mermaid",
      "script": "assets/renderer.js",
      "style": "assets/renderer.css"
    }
  ],
  "files": {
    "assets/renderer.js": "sha256-BASE64_DIGEST",
    "assets/renderer.css": "sha256-BASE64_DIGEST"
  }
}
```

Required validation:

- `id`, publisher, and renderer fence names use a restricted ASCII grammar;
- versions use SemVer;
- paths are relative, normalized, unique, and remain below the package root;
- every archive payload is listed once in `files` and every listed file exists;
- extracted and total sizes remain below host limits;
- SHA-256 hashes match before signature verification;
- `SIGNATURE` verifies the canonical manifest with a trusted Ed25519 publisher key;
- one installed version owns a given package ID; conflicting fenced languages require explicit user selection.

## Renderer contract

The host creates an isolated container for every matching fenced block and calls:

```js
export async function render(context) {
  // context.source: untrusted plain text
  // context.container: the only element owned by this renderer
  // context.theme: "light" | "dark"
}
```

A renderer may mutate only `context.container`. The host does not expose filesystem, credential, clipboard, arbitrary native messaging, or network interfaces. Rendering is cancellable and subject to time and memory limits available on the platform.

The Preview uses a strict content-security policy. Script and style URLs resolve only from verified package assets through a host-controlled custom scheme. Navigation and downloads are intercepted and denied unless they correspond to an explicit user action handled by the native shell.

## Catalog

A Package catalog is a signed JSON document containing package metadata, archive URL, archive hash, publisher key identifier, and revocation status. Catalog signatures and publisher signatures are separate: the catalog says which release is offered; the publisher signature proves who authored the package.

The MVP supports one built-in catalog and manual installation from a local file only on distributions where downloaded renderer code is permitted. Adding third-party catalogs is deferred until permission and trust UX is designed.

## Mermaid

Mermaid ships as the reference Renderer package rather than special-case native code. Its JavaScript distribution and license notices are bundled in `assets/`; it receives the fenced source and renders SVG inside its assigned container. Mermaid security mode must remain strict, and generated links or HTML labels must follow the Preview content policy.
