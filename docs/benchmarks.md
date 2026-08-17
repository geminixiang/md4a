# Android large-document benchmarks

The model and UI harness import the same production `DocumentSession`, `PieceTreeBuffer`, and `LargeDocumentView` classes shipped by `main`; benchmark source sets contain fixtures and orchestration only, not copied editor implementations. The harness is dependency-free (apart from AndroidX test components already used only by the test APK), is not referenced by `main`, and does not bundle document fixtures in release APKs.

## Fixtures

The matrix is deterministic and every generated fixture is exactly **8,841,392 UTF-8 bytes**, matching `~/Downloads/8mb.md`:

- `8mb-md` when an exact file path is supplied; otherwise `synthetic-8mb`
- `long-line`: repeated 65,536-character lines
- `crlf`: CRLF-only line endings
- `unicode`: mixed CJK, emoji, combining/Latin, Indic, Arabic, Japanese, and Korean
- `markup-heavy`: headings, tasks, emphasis, links, quote, and fenced code

Fixtures are generated at runtime. The real document must be supplied by the operator and is never checked in or packaged.

## JVM buffer benchmark

Use a release JDK 17. One warmup and five measured repetitions are defaults:

```sh
cd platform/android
./gradlew largeDocumentBenchmark \
  -Pfixture="$HOME/Downloads/8mb.md" \
  -Pwarmups=1 -Prepetitions=5 | tee /tmp/md4a-buffer-benchmark.log
```

Omit `-Pfixture` for the synthetic fallback. Machine-readable records are one-line JSON prefixed by `MD4A_BENCHMARK`. Operations are buffer construction, 1,000 line/offset lookups, 1,000 viewport line reads, single insert/delete, 1,000 sequential inserts, 1,000 undo and redo operations, immutable snapshot creation, and streaming save to a counting writer.

JVM timings are excellent for deterministic data-structure regressions, but are not Android UI acceptance numbers. Avoid comparing runs with different JDKs, CPU power modes, or thermal state.

## Android profileable benchmark

Build the profileable, non-debuggable benchmark app and test APK:

```sh
cd platform/android
./gradlew assembleBenchmark assembleBenchmarkAndroidTest
adb install -r app/build/outputs/apk/benchmark/app-benchmark.apk
adb install -r app/build/outputs/apk/androidTest/benchmark/app-benchmark-androidTest.apk
adb push "$HOME/Downloads/8mb.md" /data/local/tmp/8mb.md
adb logcat -c
adb shell am instrument -w \
  -e fixture /data/local/tmp/8mb.md \
  -e class app.md4a.benchmark.LargeDocumentInstrumentationBenchmark \
  app.md4a.benchmark.test/androidx.test.runner.AndroidJUnitRunner \
  | tee /tmp/md4a-android-benchmark.log
adb logcat -d -s MD4A_BENCHMARK:I '*:S'
```

If fixture access is denied by a device policy, the lifecycle test uses the exact-size deterministic synthetic fallback and reports that source; the real-document JVM benchmark remains the authoritative content-specific run. Android UI gates exercise the same production editor and exact byte size either way. The benchmark runs five samples. It always enforces IME composition correctness, timeout/ANR guards, and a 100 ms hard commit-to-frame limit. On physical devices it additionally enforces the documented launch, construction, 32 ms frame, 5% jank, PSS, and RSS gates. Emulator absolute launch/fling/memory values are always logged but explicitly marked as non-gating because host scheduling is not representative.

Measure process memory externally after first frame and after the run (PSS is in `TOTAL`; RSS is available on newer Android versions):

```sh
adb shell dumpsys meminfo app.md4a | tee /tmp/md4a-meminfo.txt
adb shell pidof app.md4a | xargs -I{} adb shell cat /proc/{}/status \
  | grep -E 'VmRSS|VmHWM'
adb shell logcat -d | grep -E 'ANR in app.md4a|FATAL EXCEPTION|OutOfMemoryError'
```

Use a cold launch after force-stop when checking launch time:

```sh
adb shell am force-stop app.md4a
```

Record manufacturer/model, SDK, ABI, build fingerprint, refresh rate, thermal state, and whether an emulator was used:

```sh
adb shell getprop ro.product.manufacturer
adb shell getprop ro.product.model
adb shell getprop ro.build.version.sdk
adb shell getprop ro.product.cpu.abi
adb shell getprop ro.build.fingerprint
adb shell dumpsys display | grep -m1 -E 'refreshRate|fps'
adb shell dumpsys thermalservice
```

## Acceptance thresholds

These are initial regression gates, grounded in the measured Sora non-code reference (setText 847 ms, first frame 1,008 ms, insert 0–3 ms, next frame 3–17 ms) and the unacceptable native editor behavior (13.25 s/ANR before optimization). They intentionally allow early custom-editor overhead while still catching structural regressions.

These gates implement the architectural decision in [ADR 0001: Use an incremental buffer and virtualized Android editor](adr/0001-android-incremental-virtualized-editor.md). Performance is treated as correctness: functional success does not compensate for violating the latency, memory, frame-time, or stability contract.

On a representative physical device using the **profileable benchmark** build and exact fixture:

| Metric | Gate |
|---|---:|
| launch to first frame | p95 <= 1,500 ms |
| buffer construction | p95 <= 1,000 ms |
| IME commit to next frame | p95 <= 32 ms; hard fail at 100 ms |
| fling frame interval | p95 <= 32 ms; <= 5% frames over 32 ms |
| single insert/delete (buffer) | p95 <= 5 ms each |
| 1,000 sequential edits | p95 <= 250 ms total |
| 1,000 line lookups | p95 <= 250 ms total |
| 1,000 viewport reads | p95 <= 250 ms total |
| immutable snapshot handle | p95 <= 5 ms (must not flatten text) |
| streaming save | p95 <= 500 ms |
| memory after first frame | PSS <= 250 MiB, RSS <= 350 MiB |
| stability | zero crash, OOM, or ANR |

Run one unrecorded warmup and at least five repetitions for buffer metrics. UI acceptance should use five cold launches and at least five commit/fling runs; report median and p95. Do not gate CI on emulator absolute timing—emulators are useful for correctness and trend detection only. Debug builds include assertions, debugger/JIT behavior, and Compose/debug overhead; their values are diagnostic and must not be compared to the release/profileable gates.

A result is comparable only when fixture byte count, app revision, device/build fingerprint, refresh rate, power/thermal conditions, warmups, and repetitions are recorded. Keep raw JSON/logcat and `dumpsys meminfo` output with regression reports.
