# Document title conventions

md4a uses one semantic title model while preserving native document conventions.

| Surface | Clean untitled document | Clean named document | Modified named document |
| --- | --- | --- | --- |
| Android app bar | `Untitled.md` | `README.md` | `• README.md` |
| iPhone/iPad document scene | system-native document title | system-native `README.md` | system-native edited indicator |
| macOS document window | system-native document title | system-native `README.md` | system-native edited indicator |
| macOS welcome window | `md4a` | not applicable | not applicable |
| Windows title bar | `Untitled.md — md4a` | `README.md — md4a` | `• README.md — md4a` |
| Linux title bar | `Untitled.md — md4a` | `README.md — md4a` | `• README.md — md4a` |

Rules:

1. User-facing document names include their real extension.
2. Android resolves `content://` names through `OpenableColumns.DISPLAY_NAME`; opaque document IDs are not filenames.
3. Custom mobile chrome omits the app name to preserve space.
4. Custom desktop title bars use `[• ]filename — md4a`.
5. Apple `DocumentGroup` scenes retain the system title and edited indicator rather than simulating them in content.
6. `• ` means the document has changes not represented by its last successful save. Initialization and programmatic loading must not leave a false modified marker.
