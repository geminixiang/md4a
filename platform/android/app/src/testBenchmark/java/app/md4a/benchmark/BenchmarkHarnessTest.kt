package app.md4a.benchmark

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BenchmarkHarnessTest {
    @Test fun syntheticFixturesAreExactAndDeterministic() {
        val first = BenchmarkFixtures.matrix(null)
        val second = BenchmarkFixtures.matrix(null)
        assertEquals(listOf("synthetic-8mb", "long-line", "crlf", "unicode", "markup-heavy"), first.map { it.name })
        first.zip(second).forEach { (a, b) ->
            assertEquals(TARGET_BYTES, a.text.toByteArray().size)
            assertEquals(a.text, b.text)
        }
        assertTrue(first.first { it.name == "crlf" }.text.contains("\r\n"))
        assertTrue(first.first { it.name == "unicode" }.text.contains("😀"))
    }

    @Test fun eightMegabyteLineIndexOperationsStayWithinComplexityGate() {
        val fixture = BenchmarkFixtures.primary(null)
        val result = BufferBenchmark(warmups = 1, repetitions = 5).run(fixture)
        val measured = result.metrics.associateBy { it.operation }

        assertTrue("line lookup p95 was ${measured.getValue("line_lookup_1000").p95Ms} ms",
            measured.getValue("line_lookup_1000").p95Ms <= 250.0)
        assertTrue("viewport read p95 was ${measured.getValue("viewport_read_1000").p95Ms} ms",
            measured.getValue("viewport_read_1000").p95Ms <= 250.0)
    }

    @Test fun benchmarkCoversAcceptanceOperationsAndEmitsStableJson() {
        val result = BufferBenchmark(warmups = 0, repetitions = 1).run(BenchmarkFixture("tiny", "a\r\nb\n", "test"))
        assertEquals(listOf(
            "buffer_construct", "line_lookup_1000", "viewport_read_1000", "single_insert", "single_delete",
            "sequential_edits_1000", "undo_1000", "redo_1000", "immutable_snapshot", "streaming_save",
        ), result.metrics.map { it.operation })
        val json = result.toJson(mapOf("runtime" to "test"))
        assertTrue(json.startsWith("{\"schema\":1"))
        assertTrue(json.contains("\"fixture\":\"tiny\""))
        assertTrue(result.checksum > 0)
    }
}
