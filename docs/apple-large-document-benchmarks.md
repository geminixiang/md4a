# Apple large-document benchmarks

This acceptance harness measures the production clean-room MIT Apple editor and Preview pipeline. `ApplePieceTreeBuffer` owns incremental document storage; `AppleViewportEditorView` draws only visible no-wrap lines and does not give the full document to `NSTextView` or `UITextView`. Preview rendering is serialized off the MainActor and loaded through a narrowly scoped cache file. The harness has no third-party dependencies and does not package the private fixture.

## Fixture and output

Set `MD4A_BENCHMARK_FIXTURE` to the exact UTF-8 fixture:

```text
~/Downloads/8mb.md
8,841,392 bytes
```

The test fails if a supplied fixture has another byte count. If the variable is omitted, it creates a deterministic ASCII Markdown fallback of exactly 8,841,392 bytes in memory. Each test uses one warmup and five measured runs and prints one-line, sorted JSON records prefixed by:

```text
MD4A_BENCHMARK
```

Records include source, bytes, samples, median, p95, OS/device/idiom, simulator status, gate status, and memory where applicable.

Physical gates are opt-in with `MD4A_ENFORCE_BENCHMARK_GATES=1`. Simulator timings are always marked `"gating": false`; they are useful for correctness and trends but must not be treated as device acceptance results.

Initial physical gates:

| Stage | p95 gate |
|---|---:|
| UTF-8 load/decode | 250 ms |
| document String copy | 50 ms |
| UTF-8 snapshot encode | 250 ms |
| md4c render | 250 ms |
| preview page creation | 350 ms |
| Piece Tree construction | 1,000 ms |
| 1,000 line lookups / viewport reads | 250 ms |
| single insertion / immutable snapshot | 5 ms |
| streaming save | 500 ms |
| viewport editor construction + first frame | 1,500 ms |
| one-character insertion + frame | 100 ms |
| scroll to end + frame | 100 ms |
| WKWebView load to `didFinish` | 5,000 ms |

These are initial regression bounds, not claims that the existing editor is good enough. Preserve raw logs and record thermal/power state for comparisons.

## Generate the project

`project.yml` is authoritative. Regenerate after checkout or target changes:

```sh
cd platform/apple
xcodegen generate
```

## macOS

Run the benchmark target with the real fixture:

```sh
cd platform/apple
MD4A_BENCHMARK_FIXTURE="$HOME/Downloads/8mb.md" \
MD4A_ENFORCE_BENCHMARK_GATES=1 \
xcodebuild test \
  -project md4a.xcodeproj \
  -scheme md4aMacBenchmarks \
  -configuration Release \
  -destination 'platform=macOS' \
  -resultBundlePath /tmp/md4a-macos-benchmark.xcresult \
  | tee /tmp/md4a-macos-benchmark.log

grep 'MD4A_BENCHMARK ' /tmp/md4a-macos-benchmark.log
```

The production harness measures Piece Tree operations, viewport-editor construction/first frame, insertion/frame, scroll/frame, page creation, scoped cache-file `WKWebView.didFinish`, and process resident/physical footprint. A TextKit 2 prototype was measured and rejected after taking roughly 4.17 seconds for first viewport layout, 996 ms for insertion/layout, 6.55 seconds to scroll/layout the end, and about 2 GiB resident memory in the benchmark process.

## iOS Simulator

List available destinations if needed:

```sh
xcrun simctl list devices available
```

Run correctness and diagnostic timing (never gated):

```sh
cd platform/apple
MD4A_BENCHMARK_FIXTURE="$HOME/Downloads/8mb.md" \
xcodebuild test \
  -project md4a.xcodeproj \
  -scheme md4aiOSBenchmarks \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -resultBundlePath /tmp/md4a-ios-simulator-benchmark.xcresult \
  | tee /tmp/md4a-ios-simulator-benchmark.log
```

## Connected iPhone or iPad

The fixture path is read by the macOS test runner and injected through the test process environment. Connect and trust the device, enable Developer Mode, select the development team/signing identity in Xcode if automatic signing is not already configured, and obtain the destination ID:

```sh
xcrun xctrace list devices
```

Then run, replacing the ID:

```sh
cd platform/apple
MD4A_BENCHMARK_FIXTURE="$HOME/Downloads/8mb.md" \
MD4A_ENFORCE_BENCHMARK_GATES=1 \
xcodebuild test \
  -project md4a.xcodeproj \
  -scheme md4aiOSBenchmarks \
  -configuration Release \
  -destination 'platform=iOS,id=DEVICE_UDID' \
  -allowProvisioningUpdates \
  -resultBundlePath /tmp/md4a-ios-device-benchmark.xcresult \
  | tee /tmp/md4a-ios-device-benchmark.log
```

Run separately on an iPhone and iPad. JSON identifies phone/pad idiom and system version. Keep each `.xcresult` and log with the hardware model, battery/charging state, thermal state, and app revision.

If command-line environment propagation is restricted by a signing/test-plan setup, open `md4a.xcodeproj`, edit the `md4aiOSBenchmarks` scheme Test action, add `MD4A_BENCHMARK_FIXTURE` and `MD4A_ENFORCE_BENCHMARK_GATES`, select the connected device, and run Product → Test.

## Production Open → Edit → Preview → Save → reopen

`testDocumentOpenSaveReopenScaffolding` validates the data-level lifecycle byte-for-byte. The current production `DocumentGroup` file importer/exporter and mode controls require UI/manual coverage. For each physical form factor:

1. Copy `8mb.md` to iCloud Drive/Files (iPhone/iPad) or use the original file (Mac).
2. Open it with md4a and start a Time Profiler/Hangs recording.
3. Switch to Edit; record time to responsive cursor and first editable frame.
4. Insert a unique Unicode marker, e.g. `測試🙂`, near the beginning and end.
5. Scroll through beginning/middle/end and note stalls.
6. Switch to Preview; wait for the page to finish and verify both markers.
7. Save, close the document, reopen it, and verify both markers byte-for-byte in another tool.
8. Repeat five times after one warmup; report median/p95 and any crash, jetsam, hang, or WebKit process termination.

Future production XCUITests can automate mode controls and document picker setup; this harness intentionally avoids brittle private document-picker automation.

## Instruments

Build once for the selected destination, then profile from Xcode (`Product → Profile`) or Instruments. Use a Release build and the exact lifecycle above.

Recommended templates:

- **Time Profiler** — inspect Piece Tree construction/range edits, viewport drawing, `String` UTF-8 conversion, md4c, and WebKit navigation setup.
- **Allocations** — mark generations before Open, Edit, Preview, Save; inspect simultaneous 8–10 MB buffers and persistent growth.
- **Leaks** — repeat Edit/Preview transitions and document close/reopen.
- **Hangs** — capture main-thread stalls entering Edit, scrolling, and creating/loading Preview.

Command-line launch (replace app/device identifiers as appropriate):

```sh
xcrun xctrace record \
  --template 'Time Profiler' \
  --device 'DEVICE NAME OR UDID' \
  --output /tmp/md4a-time-profile.trace \
  --launch -- md4a
```

For Allocations, Leaks, and Hangs, replace the template name. Environment fixture injection applies to XCTest benchmarks; production profiling opens the fixture through Finder/Files so it exercises the real `DocumentGroup` lifecycle.

## Interpretation

- Core render time excludes WebKit parsing/layout; `preview_webview_did_finish` includes page navigation through delegate completion.
- Production editor metrics exercise the Piece Tree and viewport-only AppKit/UIKit views, not TextKit full-document layout.
- Process memory does not include all out-of-process WebKit memory. Capture Instruments and OS memory diagnostics alongside the JSON.
- A passing simulator run proves compilation/correctness only. Physical iPhone and iPad runs are the acceptance evidence.
