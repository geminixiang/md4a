package app.md4a.benchmark

import app.md4a.editor.DocumentSession
import app.md4a.editor.TextRange
import java.io.Writer
import kotlin.math.ceil

internal data class Metric(val operation: String, val samplesMs: List<Double>) {
    val medianMs get() = percentile(0.50)
    val p95Ms get() = percentile(0.95)
    private fun percentile(fraction: Double): Double {
        val ordered = samplesMs.sorted()
        return ordered[(ceil(ordered.size * fraction).toInt() - 1).coerceIn(0, ordered.lastIndex)]
    }
}

internal data class FixtureResult(
    val fixture: BenchmarkFixture,
    val metrics: List<Metric>,
    val checksum: Long,
)

internal class BufferBenchmark(private val warmups: Int = 1, private val repetitions: Int = 5) {
    fun run(fixture: BenchmarkFixture): FixtureResult {
        require(repetitions > 0 && warmups >= 0)
        repeat(warmups) { exercise(fixture, record = null) }
        val values = linkedMapOf<String, MutableList<Double>>()
        var checksum = 0L
        repeat(repetitions) { checksum = exercise(fixture, values) }
        return FixtureResult(fixture, values.map { Metric(it.key, it.value) }, checksum)
    }

    private fun exercise(fixture: BenchmarkFixture, record: MutableMap<String, MutableList<Double>>?): Long {
        lateinit var document: DocumentSession
        measure("buffer_construct", record) { document = DocumentSession(fixture.text, historyLimit = 1_100) }
        var checksum = document.length + document.lineCount
        val probes = intArrayOf(0, document.lineCount / 4, document.lineCount / 2, document.lineCount * 3 / 4, document.lineCount - 1)
        measure("line_lookup_1000", record) {
            repeat(1_000) { i ->
                val line = probes[i % probes.size].coerceAtLeast(0)
                checksum += document.positionAt(line, 0)
                checksum += document.locationAt((document.length * i / 1_000).coerceAtMost(document.length)).line
            }
        }
        measure("viewport_read_1000", record) {
            repeat(1_000) { i -> checksum += document.line(probes[i % probes.size].coerceAtLeast(0)).length }
        }
        val middle = document.length / 2
        measure("single_insert", record) { checksum += document.replace(middle, middle, "x") }
        measure("single_delete", record) { checksum += document.replace(middle, middle + 1, "") }
        measure("sequential_edits_1000", record) {
            repeat(1_000) { checksum += document.replace(middle, middle, "x") }
        }
        measure("undo_1000", record) { repeat(1_000) { if (document.undo()) checksum++ } }
        measure("redo_1000", record) { repeat(1_000) { if (document.redo()) checksum++ } }
        measure("immutable_snapshot", record) {
            val snapshot = document.snapshot().document
            checksum += snapshot.length + snapshot.lineCount
        }
        measure("streaming_save", record) {
            val writer = CountingWriter()
            document.snapshot().document.appendTo(writer)
            checksum += writer.count
        }
        return checksum
    }

    private inline fun measure(name: String, destination: MutableMap<String, MutableList<Double>>?, block: () -> Unit) {
        val start = System.nanoTime()
        block()
        val elapsed = (System.nanoTime() - start) / 1_000_000.0
        destination?.getOrPut(name) { mutableListOf() }?.add(elapsed)
    }

    private class CountingWriter : Writer() {
        var count = 0L
        override fun write(buffer: CharArray, offset: Int, length: Int) { count += length }
        override fun write(text: String, offset: Int, length: Int) { count += length }
        override fun flush() = Unit
        override fun close() = Unit
    }
}

internal fun FixtureResult.toJson(environment: Map<String, String>): String {
    fun quote(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    val metricJson = metrics.joinToString(",") { metric ->
        "{\"operation\":${quote(metric.operation)},\"median_ms\":${"%.3f".format(java.util.Locale.US, metric.medianMs)},\"p95_ms\":${"%.3f".format(java.util.Locale.US, metric.p95Ms)},\"samples_ms\":[${metric.samplesMs.joinToString(",") { "%.3f".format(java.util.Locale.US, it) }}]}"
    }
    val environmentJson = environment.entries.sortedBy { it.key }.joinToString(",") { "${quote(it.key)}:${quote(it.value)}" }
    return "{\"schema\":1,\"fixture\":${quote(fixture.name)},\"source\":${quote(fixture.source)},\"utf8_bytes\":${fixture.text.toByteArray().size},\"utf16_units\":${fixture.text.length},\"checksum\":$checksum,\"environment\":{$environmentJson},\"metrics\":[$metricJson]}"
}
