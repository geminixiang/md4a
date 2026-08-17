import Foundation
import XCTest
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Darwin

struct AppleBenchmarkFixture {
    static let exactByteCount = 8_841_392

    let data: Data
    let text: String
    let source: String

    static func unicodeHeavy() -> AppleBenchmarkFixture {
        let pattern = Data("繁體中文 简体中文 日本語 한글 e\u{301} हिन्दी العربية 👨‍👩‍👧‍👦 👍🏽 🇹🇼 ❤️ 1️⃣ ✈️\r\n".utf8)
        var data = Data()
        data.reserveCapacity(exactByteCount)
        while data.count + pattern.count <= exactByteCount { data.append(pattern) }
        data.append(Data(repeating: 0x20, count: exactByteCount - data.count))
        return AppleBenchmarkFixture(
            data: data,
            text: String(decoding: data, as: UTF8.self),
            source: "deterministic-exact-byte-unicode-heavy"
        )
    }

    static func load() throws -> AppleBenchmarkFixture {
        if let path = ProcessInfo.processInfo.environment["MD4A_BENCHMARK_FIXTURE"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return AppleBenchmarkFixture(data: data, text: text, source: url.path)
        }

        // ASCII makes byte count and decoded character count identical. Filling a
        // single allocation keeps fixture setup out of the stages under test.
        let pattern = Array("# Synthetic md4a benchmark\r\nA deterministic Markdown paragraph with **bold**, `code`, and UTF-8-safe ASCII.\r\n\r\n".utf8)
        var data = Data(count: exactByteCount)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for index in 0..<exactByteCount {
                base[index] = pattern[index % pattern.count]
            }
        }
        return AppleBenchmarkFixture(
            data: data,
            text: String(decoding: data, as: UTF8.self),
            source: "deterministic-exact-byte-fallback"
        )
    }
}

struct AppleBenchmarkSummary {
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let samplesMilliseconds: [Double]
}

enum AppleBenchmark {
    static let repetitions = 5
    static let warmups = 1

    static func measure(_ operation: () throws -> Void) rethrows -> AppleBenchmarkSummary {
        for _ in 0..<warmups { try operation() }
        var values: [Double] = []
        values.reserveCapacity(repetitions)
        for _ in 0..<repetitions {
            let start = ContinuousClock.now
            try operation()
            let duration = start.duration(to: .now)
            values.append(milliseconds(duration))
        }
        return summarize(values)
    }

    static func summarize(_ values: [Double]) -> AppleBenchmarkSummary {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let p95Index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1))
        return AppleBenchmarkSummary(
            medianMilliseconds: median,
            p95Milliseconds: sorted[p95Index],
            samplesMilliseconds: values
        )
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }

    static func log(
        metric: String,
        summary: AppleBenchmarkSummary,
        fixture: AppleBenchmarkFixture,
        extra: [String: Any] = [:],
        gateMilliseconds: Double? = nil
    ) {
        var record: [String: Any] = [
            "platform": platform,
            "metric": metric,
            "fixture_source": fixture.source,
            "fixture_bytes": fixture.data.count,
            "warmups": warmups,
            "runs": repetitions,
            "median_ms": rounded(summary.medianMilliseconds),
            "p95_ms": rounded(summary.p95Milliseconds),
            "samples_ms": summary.samplesMilliseconds.map(rounded),
            "device": deviceMetadata,
            "simulator": isSimulator,
            "gating": shouldEnforcePhysicalGates
        ]
        if let gateMilliseconds {
            record["gate_ms"] = gateMilliseconds
            record["gate_passed"] = summary.p95Milliseconds <= gateMilliseconds
        }
        extra.forEach { record[$0] = $1 }
        emit(record)

        if shouldEnforcePhysicalGates, let gateMilliseconds {
            XCTAssertLessThanOrEqual(summary.p95Milliseconds, gateMilliseconds, "Physical-device benchmark gate failed: \(metric)")
        }
    }

    static func logMemory(metric: String, fixture: AppleBenchmarkFixture) {
        var record: [String: Any] = [
            "platform": platform,
            "metric": metric,
            "fixture_source": fixture.source,
            "fixture_bytes": fixture.data.count,
            "resident_mib": rounded(Double(memoryResidentBytes()) / 1_048_576),
            "device": deviceMetadata,
            "simulator": isSimulator,
            "gating": shouldEnforcePhysicalGates
        ]
        if let footprint = memoryFootprintBytes() {
            record["footprint_mib"] = rounded(Double(footprint) / 1_048_576)
        }
        emit(record)
    }

    static var shouldEnforcePhysicalGates: Bool {
        !isSimulator && ProcessInfo.processInfo.environment["MD4A_ENFORCE_BENCHMARK_GATES"] == "1"
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var platform: String {
        #if os(macOS)
        "macOS"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
    }

    static var deviceMetadata: [String: String] {
        #if os(macOS)
        return [
            "model": sysctlString("hw.model") ?? "unknown",
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "processor_count": String(ProcessInfo.processInfo.processorCount)
        ]
        #else
        return [
            "name": UIDevice.current.name,
            "model": UIDevice.current.model,
            "idiom": UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone",
            "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        ]
        #endif
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }

    private static func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        print("MD4A_BENCHMARK \(json)")
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        let utf8Bytes = bytes.dropLast().map { UInt8(bitPattern: $0) }
        return String(decoding: utf8Bytes, as: UTF8.self)
    }

    private static func memoryResidentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private static func memoryFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
    }
}
