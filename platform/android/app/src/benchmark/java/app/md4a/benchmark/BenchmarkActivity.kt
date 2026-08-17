package app.md4a.benchmark

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.InputDevice
import android.view.MotionEvent
import android.view.inputmethod.EditorInfo
import app.md4a.editor.DocumentSession
import app.md4a.editor.LargeDocumentView
import java.io.File
import java.util.Locale

class BenchmarkActivity : Activity() {
    lateinit var editor: LargeDocumentView
        private set
    internal lateinit var document: DocumentSession
        private set
    var firstFrameMs: Double = Double.NaN
        private set
    var constructionMs: Double = Double.NaN
        private set
    var fixtureBytes: Long = -1
        private set
    lateinit var fixtureLocalSource: String
        private set
    private var launchNs = 0L
    private var firstFrameDelivered = false
    private val firstFrameListeners = mutableListOf<() -> Unit>()

    override fun onCreate(state: Bundle?) {
        launchNs = SystemClock.elapsedRealtimeNanos()
        super.onCreate(state)
        val path = intent.getStringExtra("fixture")
        val requestedSource = intent.getStringExtra("fixture_source") ?: path ?: "deterministic-generated"
        val fixture = BenchmarkFixtures.primary(path)
        fixtureLocalSource = fixture.source
        fixtureBytes = fixture.text.toByteArray(Charsets.UTF_8).size.toLong()
        intent.extras?.takeIf { it.containsKey("expected_fixture_bytes") }?.getLong("expected_fixture_bytes")?.let {
            check(fixtureBytes == it) { "Fixture byte count $fixtureBytes did not match supplied $it" }
        }
        val constructStart = System.nanoTime()
        document = DocumentSession(fixture.text, historyLimit = 1_100)
        constructionMs = elapsedMs(constructStart)
        editor = LargeDocumentView(this).apply {
            setPadding(24, 24, 24, 24)
            setDocument(document)
        }
        setContentView(editor)
        Choreographer.getInstance().postFrameCallback {
            firstFrameMs = (SystemClock.elapsedRealtimeNanos() - launchNs) / 1_000_000.0
            firstFrameDelivered = true
            firstFrameListeners.toList().also { firstFrameListeners.clear() }.forEach { listener -> listener() }
            log("activity_first_frame", firstFrameMs, mapOf(
                "fixture" to fixture.name,
                "fixture_source" to requestedSource,
                "fixture_local_source" to fixture.source,
                "fixture_bytes" to fixtureBytes.toString(),
                "construct_ms" to format(constructionMs),
            ))
        }
    }

    fun onFirstFrame(listener: () -> Unit) {
        if (firstFrameDelivered) listener() else firstFrameListeners += listener
    }

    fun commitAndMeasure(onComplete: (Double) -> Unit) {
        val connection = editor.onCreateInputConnection(EditorInfo())
        val start = System.nanoTime()
        check(connection.commitText("x", 1))
        Choreographer.getInstance().postFrameCallback { onComplete(elapsedMs(start)) }
    }

    fun flingAndMeasure(onComplete: (List<Double>) -> Unit) {
        val frames = mutableListOf<Long>()
        var previous = 0L
        var remaining = 90
        val callback = object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                if (previous != 0L) frames += frameTimeNanos - previous
                previous = frameTimeNanos
                if (--remaining > 0) Choreographer.getInstance().postFrameCallback(this)
                else onComplete(frames.map { it / 1_000_000.0 })
            }
        }
        Choreographer.getInstance().postFrameCallback(callback)
        val now = SystemClock.uptimeMillis()
        fun event(action: Int, y: Float, time: Long) = MotionEvent.obtain(now, time, action, width() / 2f, y, 0).apply {
            source = InputDevice.SOURCE_TOUCHSCREEN
        }
        editor.dispatchTouchEvent(event(MotionEvent.ACTION_DOWN, height() * .8f, now))
        editor.dispatchTouchEvent(event(MotionEvent.ACTION_MOVE, height() * .2f, now + 16))
        editor.dispatchTouchEvent(event(MotionEvent.ACTION_UP, height() * .1f, now + 32))
    }

    fun currentRssMb(): Double = runCatching {
        File("/proc/self/status").useLines { lines ->
            lines.first { it.startsWith("VmRSS:") }.split(Regex("\\s+"))[1].toLong() / 1024.0
        }
    }.getOrDefault(Double.NaN)

    private fun width() = resources.displayMetrics.widthPixels
    private fun height() = resources.displayMetrics.heightPixels
    private fun elapsedMs(start: Long) = (System.nanoTime() - start) / 1_000_000.0
    private fun format(value: Double) = String.format(Locale.US, "%.3f", value)
    private fun log(operation: String, value: Double, extra: Map<String, String> = emptyMap()) {
        val metadata = mapOf("operation" to operation, "ms" to format(value), "device" to "${Build.MANUFACTURER} ${Build.MODEL}", "sdk" to Build.VERSION.SDK_INT.toString()) + extra
        Log.i("MD4A_BENCHMARK", metadata.entries.joinToString(prefix = "{", postfix = "}") { "\"${it.key}\":\"${it.value.replace("\\", "\\\\").replace("\"", "\\\"")}\"" })
    }
}
