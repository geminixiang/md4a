package app.md4a.benchmark

import android.content.Intent
import android.os.Build
import android.os.Debug
import android.os.ParcelFileDescriptor
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.ceil
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LargeDocumentInstrumentationBenchmark {
    @Test(timeout = 120_000) fun launchCommitAndFlingMeetDeviceAwareAcceptancePolicy() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val supplied = InstrumentationRegistry.getArguments().getString("fixture")
        val fixture = supplied?.let { copyShellFixture(it) }
        val expectedBytes = supplied?.let { shellByteCount(it) }
        if (supplied != null) assertEquals("the supplied fixture must have the acceptance byte count", TARGET_BYTES.toLong(), expectedBytes)

        val launches = mutableListOf<Double>()
        val constructions = mutableListOf<Double>()
        val commitSamples = mutableListOf<Double>()
        val flingRuns = mutableListOf<List<Double>>()
        var pssMb = 0.0
        var rssMb = 0.0
        val source = fixture?.absolutePath ?: "deterministic-generated"

        repeat(RUNS) { run ->
            val intent = Intent(instrumentation.targetContext, BenchmarkActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                fixture?.let { putExtra("fixture", it.absolutePath) }
                supplied?.let { putExtra("fixture_source", it) }
                expectedBytes?.let { putExtra("expected_fixture_bytes", it) }
            }
            ActivityScenario.launch<BenchmarkActivity>(intent).use { scenario ->
                val ready = CountDownLatch(1)
                scenario.onActivity { activity -> activity.onFirstFrame { ready.countDown() } }
                assertTrue("first frame timed out (possible ANR)", ready.await(ANR_TIMEOUT_SECONDS, TimeUnit.SECONDS))
                scenario.onActivity { activity ->
                    launches += activity.firstFrameMs
                    constructions += activity.constructionMs
                    assertEquals(source, activity.fixtureLocalSource)
                    assertEquals(expectedBytes ?: TARGET_BYTES.toLong(), activity.fixtureBytes)
                    if (run == 0) {
                        val connection = activity.editor.onCreateInputConnection(android.view.inputmethod.EditorInfo())
                        assertTrue(connection.setSelection(0, 0))
                        assertTrue(connection.setComposingText("n", 1))
                        assertTrue(connection.setComposingText("ni", 1))
                        assertTrue(connection.commitText("你", 1))
                        assertEquals("你", activity.document.text(0, 1).toString())
                    }
                }

                val commitLatch = CountDownLatch(1)
                scenario.onActivity { activity -> activity.commitAndMeasure { commitSamples += it; commitLatch.countDown() } }
                assertTrue("commit frame timed out (possible ANR)", commitLatch.await(ANR_TIMEOUT_SECONDS, TimeUnit.SECONDS))
                assertTrue("commit-to-frame hard gate exceeded 100 ms: ${commitSamples.last()} ms", commitSamples.last() < COMMIT_HARD_MS)

                val flingLatch = CountDownLatch(1)
                scenario.onActivity { activity -> activity.flingAndMeasure { flingRuns += it; flingLatch.countDown() } }
                assertTrue("fling timed out (possible ANR)", flingLatch.await(ANR_TIMEOUT_SECONDS, TimeUnit.SECONDS))
                assertTrue("fling produced no frame samples", flingRuns.last().isNotEmpty())

                if (run == 0) scenario.onActivity { activity ->
                    val memory = Debug.MemoryInfo().also(Debug::getMemoryInfo)
                    pssMb = memory.totalPss / 1024.0
                    rssMb = activity.currentRssMb()
                }
            }
        }

        val physical = !isEmulator()
        val allFlingFrames = flingRuns.flatten()
        val commitP95 = percentile(commitSamples, .95)
        val flingP95 = percentile(allFlingFrames, .95)
        val jankPercent = allFlingFrames.count { it > FRAME_GATE_MS } * 100.0 / allFlingFrames.size
        val launchP95 = percentile(launches, .95)
        val constructionP95 = percentile(constructions, .95)
        val policy = if (physical) "physical-gates-enforced" else "emulator-absolute-gates-skipped-hard-guards-enforced"
        println("MD4A_BENCHMARK {\"schema\":2,\"runtime\":\"android\",\"fixture_source\":\"${escape(supplied ?: source)}\",\"fixture_bytes\":${expectedBytes ?: TARGET_BYTES},\"device\":\"${escape(Build.MANUFACTURER + " " + Build.MODEL)}\",\"fingerprint\":\"${escape(Build.FINGERPRINT)}\",\"sdk\":${Build.VERSION.SDK_INT},\"policy\":\"$policy\",\"runs\":$RUNS,\"launch_median_ms\":${format(percentile(launches, .5))},\"launch_p95_ms\":${format(launchP95)},\"construction_median_ms\":${format(percentile(constructions, .5))},\"construction_p95_ms\":${format(constructionP95)},\"commit_median_ms\":${format(percentile(commitSamples, .5))},\"commit_p95_ms\":${format(commitP95)},\"fling_runs\":${flingRuns.size},\"fling_frame_p95_ms\":${format(flingP95)},\"fling_jank_percent\":${format(jankPercent)},\"pss_mb\":${format(pssMb)},\"rss_mb\":${format(rssMb)},\"physical_gates_enforced\":$physical}")

        if (physical) {
            assertTrue("launch p95 exceeded 1500 ms", launchP95 <= 1_500)
            assertTrue("construction p95 exceeded 1000 ms", constructionP95 <= 1_000)
            assertTrue("commit p95 exceeded 32 ms", commitP95 <= FRAME_GATE_MS)
            assertTrue("fling frame p95 exceeded 32 ms", flingP95 <= FRAME_GATE_MS)
            assertTrue("fling jank exceeded 5%", jankPercent <= 5.0)
            assertTrue("PSS exceeded 250 MiB", pssMb <= 250)
            assertTrue("RSS exceeded 350 MiB", rssMb <= 350)
        } else {
            assertTrue("emulator fling guard indicates stall/ANR", flingP95 < 1_000)
        }
    }

    private fun copyShellFixture(path: String): File {
        val destination = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "benchmark-8mb.md")
        val descriptor: ParcelFileDescriptor = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cat ${shellQuote(path)}")
        ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input -> FileOutputStream(destination).use(input::copyTo) }
        assertEquals(TARGET_BYTES.toLong(), destination.length())
        return destination
    }

    private fun shellByteCount(path: String): Long {
        val descriptor = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("wc -c < ${shellQuote(path)}")
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText().trim().toLong() }
    }

    private fun shellQuote(value: String) = "'" + value.replace("'", "'\\''") + "'"
    private fun isEmulator(): Boolean = Build.FINGERPRINT.startsWith("generic") || Build.FINGERPRINT.contains("emulator") ||
        Build.MODEL.contains("Emulator") || Build.MODEL.contains("sdk_gphone") || Build.PRODUCT.contains("sdk")
    private fun percentile(values: List<Double>, quantile: Double): Double = values.sorted()[(ceil(values.size * quantile).toInt() - 1).coerceIn(0, values.lastIndex)]
    private fun format(value: Double) = String.format(Locale.US, "%.3f", value)
    private fun escape(value: String) = value.replace("\\", "\\\\").replace("\"", "\\\"")

    private companion object {
        const val RUNS = 5
        const val ANR_TIMEOUT_SECONDS = 10L
        const val COMMIT_HARD_MS = 100.0
        const val FRAME_GATE_MS = 32.0
    }
}
