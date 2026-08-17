---
status: accepted
---

# Use an incremental buffer and virtualized Android editor

Android edits a Document through an md4a-owned plain-text editor built from a persistent Piece Tree and a custom viewport-rendered `View`: edits mutate only affected pieces, rendering reads only visible lines, and Preview or Save crosses the full-document seam only when it actually needs a snapshot or stream. This replaces whole-document `BasicTextField`/`EditText` behavior because the 8.84 MB acceptance Document made those controls copy or lay out the full text on interactive paths, causing roughly 474–495 MB RSS and a 13.25-second input ANR before mitigation; the target architecture makes normal edit cost depend on the changed range and visible viewport rather than total Document size.

## Considered options

- **Compose `BasicTextField`: rejected.** It treated the full value as Compose state and could not edit the acceptance Document responsively.
- **Android `EditText`: rejected.** Removing per-keystroke `String` snapshots improved one-character input to roughly 94 ms, but entering Edit mode and continued editing still performed whole-document text-system work.
- **Sora Editor: benchmark reference only.** A throwaway prototype demonstrated the desired performance class, but its LGPL-2.1-or-later license conflicts with the decision to keep md4a and its editor implementation MIT. No Sora source is copied, adapted, linked, or shipped.
- **Disable editing for large Documents: rejected.** Avoiding the feature is not a performance solution; the acceptance Document must remain directly editable.
- **One editable widget per line: rejected.** It fragments selection, IME composition, history, accessibility, and cross-line edits.

## Consequences

The Android editor intentionally remains a minimal document editor, not an IDE: one cursor and selection, plain text, no word wrap, viewport-only drawing, vertical and horizontal scrolling, IME composition, clipboard operations, and bounded undo/redo. Syntax highlighting, minimap, multiple cursors, folding, diagnostics, and inline widgets stay outside the initial scope.

The text model uses UTF-16 offsets to match Android input contracts, but all cursor movement, selection normalization, backward/forward deletion, and `InputConnection` surrounding-text deletion preserve Unicode code-point boundaries and therefore never split a surrogate pair. Extended grapheme clusters (for example combining sequences, emoji ZWJ families, and flags made from multiple regional indicators) intentionally remain a future enhancement; the initial correctness boundary is one Unicode code point. The model preserves ordinary UTF-8 file content and CRLF boundaries, structurally shares unchanged text across edits and snapshots, and streams Save output without flattening the entire Document. `LargeDocumentView` accesses the model through the small `EditorDocument` seam and must not request off-screen lines during drawing. Preview may take one immutable full-document snapshot, but rendering remains off the UI thread.

Performance is part of correctness. The exact `~/Downloads/8mb.md` fixture—8,841,392 bytes and about 82,364 lines—plus deterministic synthetic fixtures define the acceptance workload. The reproducible harness and current latency, memory, frame-time, and stability gates are documented in [`../benchmarks.md`](../benchmarks.md). A change that passes functional tests but regresses those gates is not acceptable.

Implementation must be clean-room MIT code based only on standard published data-structure algorithms and Android SDK contracts. Public behavior and broad architectural concepts from mature editors may inform evaluation, but code from license-incompatible editors must not be copied, translated, or adapted.
