# Large-document performance audit

The acceptance workload is the external fixture `~/Downloads/8mb.md`: 8,841,392 UTF-8 bytes, approximately 82,364 lines, CRLF line endings. It is never committed or bundled. Each platform should also provide an exact-size deterministic fallback.

The shared `md4a_render()`/md4c path is not the primary bottleneck for this fixture: optimized isolated runs completed in roughly 17–20 ms and produced 10,332,202 HTML bytes. Platform shells must separately measure editor layout/state, full-document snapshots and transcoding, WebView transport/DOM layout, memory, frame timing, save/reopen correctness, and stale-result publication.

## Current platform risks

| Platform | Editor | Preview | Priority |
| --- | --- | --- | --- |
| Android | Addressed with an MIT Piece Tree and viewport-only custom View | Background render; full String remains only at the existing JNI seam | Implemented and benchmarked |
| macOS | MIT `ApplePieceTreeBuffer` + viewport-only AppKit editor | Serialized background render + scoped cache-file `WKWebView` load | Implemented; physical benchmark passes algorithm/editor gates |
| iPhone/iPad | MIT `ApplePieceTreeBuffer` + viewport-only UIKit editor | Same serialized Preview pipeline with scoped cache-file loading | Implemented; Simulator build passes, physical-device gates pending |
| Windows | WinUI `TextBox`; no 8.8 MB acceptance benchmark | Every `TextChanged` synchronously snapshots, transcodes, renders and calls WebView2 `NavigateToString` on the UI thread | P0 after Apple |
| Linux | Full `GtkSourceView` with highlighting, line numbers and word wrap | 120 ms debounce exists, but snapshot/render/HTML assembly still execute on the GTK main thread | P0 after Apple |

## Apple decision and measured impact

TextKit 2 viewport layout was prototyped before replacing the editor. On the exact-size workload it failed decisively: first viewport layout p95 was about 4.17 s, insertion-to-layout p95 about 996 ms, scroll-to-end p95 about 6.55 s, and the benchmark process reached roughly 2.0 GiB resident memory. Apple therefore uses the same architectural principle as Android, implemented independently in Swift: persistent incremental storage plus viewport-only rendering.

The production macOS custom editor benchmark on an exact-size deterministic fixture measured approximately 31 ms p95 for construction/first frame, 0.028 ms for insertion-to-frame, and 0.046 ms for scroll-to-end/frame. Piece-tree construction was about 28 ms p95, 1,000 line lookups 0.134 ms, 1,000 viewport reads 0.496 ms, and streaming save 43 ms. Preview rendering no longer blocks the MainActor; rendering is serialized/coalesced by revision and delivered through a narrowly scoped cache file. WebKit navigation/DOM layout remains the largest Preview cost at roughly 1.7 s p95 on the benchmark Mac.

Physical iPhone and iPad latency, memory pressure, IME, selection, VoiceOver and WebKit child-process behavior remain release gates; Simulator results are diagnostic only.

## Required acceptance scenario

For every platform:

1. Open the exact fixture and reach a usable editor frame.
2. Insert Unicode at the beginning, middle and end through the real keyboard/IME path.
3. Scroll through the document and record frame intervals.
4. Enter Preview, wait for the WebView navigation-complete event, then return to Edit.
5. Save, close, reopen and byte-compare the result.
6. Repeat rapid edits and assert only the latest revision becomes visible in Preview.
7. Record app and WebView child-process memory and assert zero crash, OOM, UI hang or lost edit.

Initial physical-device gates align with the Android contract:

| Metric | Gate |
| --- | ---: |
| Open/Edit first usable frame | p95 ≤ 1,500 ms |
| Input/IME to next frame | p95 ≤ 32 ms; 100 ms hard failure |
| Scroll frame interval | p95 ≤ 32 ms; ≤ 5% over 32 ms |
| Save | p95 ≤ 500 ms |
| Memory after first frame | PSS ≤ 250 MiB; RSS ≤ 350 MiB, with WebView children reported separately |
| Stability/correctness | 0 crash, OOM or hang; exact save/reopen bytes; no stale Preview |

Emulator/simulator timing is diagnostic and must not be used as a physical-device release gate. Release/profileable builds, fixture hash, device model, OS/build fingerprint, refresh rate, thermal state, warmups and repetitions must accompany comparable results.

## Fix direction

Do not solve failures by disabling large-document editing. First remove synchronous Preview work and redundant full-buffer copies. Benchmark each native text system before replacing it. If a platform editor fails the same interaction gates, adopt the Android design principle—incremental document storage plus viewport-only layout—using platform-native MIT code rather than sharing UI implementation.

Detailed Android design and measurements are recorded in [ADR 0001](../adr/0001-android-incremental-virtualized-editor.md) and [the benchmark guide](../benchmarks.md).
