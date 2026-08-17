package app.md4a.benchmark

import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.md4a.MainActivity
import app.md4a.editor.LargeDocumentView
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProductionDocumentLifecycleTest {
    @Test(timeout = 120_000) fun exactFixtureOpenEditPreviewSaveAndReopenPreservesBytes() {
        val fixturePath = InstrumentationRegistry.getArguments().getString("fixture") ?: "/data/local/tmp/8mb.md"
        val shellFixture = shellBytes(fixturePath)
        val original = if (shellFixture.isEmpty()) {
            BenchmarkFixtures.primary(null).text.toByteArray(Charsets.UTF_8)
        } else {
            shellFixture
        }
        assertTrue("8mb fixture wrong size: ${original.size}", original.size == TARGET_BYTES)
        val uri = Uri.parse("content://app.md4a.benchmark.documents/lifecycle.md")
        write(uri, original)
        val insertion = "驗收😀\r\n".toByteArray(Charsets.UTF_8)

        launch(uri).use { scenario ->
            waitFor("production document open") { activity(scenario) { !it.document.isLoading && !it.document.isRestoring && it.document.session.length > 8_000_000 } }
            scenario.onActivity { activity ->
                val editor = findView<LargeDocumentView>(activity.window.decorView)
                val input = requireNotNull(editor).onCreateInputConnection(EditorInfo())
                assertTrue(input.setSelection(0, 0))
                assertTrue(input.setComposingText("驗", 1))
                assertTrue(input.commitText("驗收😀\r\n", 1))
                assertTrue(activity.document.isDirty)
                activity.showPreviewForTest(true)
            }
            waitFor("preview render") { activity(scenario) { it.showingPreview && findView<android.webkit.WebView>(it.window.decorView) != null } }
            scenario.onActivity { activity ->
                activity.showPreviewForTest(false)
                activity.document.save(activity.contentResolver, uri)
            }
            waitFor("production save") { activity(scenario) { !it.document.isSaving && !it.document.isDirty } }
        }

        val expected = insertion + original
        assertArrayEquals(expected, read(uri))
        launch(uri).use { scenario ->
            waitFor("saved document reopen") { activity(scenario) { !it.document.isLoading && !it.document.isRestoring } }
            scenario.onActivity { activity ->
                assertFalse(activity.document.isDirty)
                assertTrue(activity.document.previewSnapshot().document.toString().startsWith("驗收😀\r\n"))
            }
        }
    }

    @Test(timeout = 120_000) fun dirtyDraftRecoversWithoutUiAutomationTextDump() {
        val original = "draft base\r\n".toByteArray()
        val uri = Uri.parse("content://app.md4a.benchmark.documents/draft.md")
        write(uri, original)
        launch(uri).use { scenario ->
            waitFor("draft source open") { activity(scenario) { !it.document.isLoading && !it.document.isRestoring } }
            scenario.onActivity { activity ->
                val input = requireNotNull(findView<LargeDocumentView>(activity.window.decorView)).onCreateInputConnection(EditorInfo())
                assertTrue(input.setSelection(0, 0))
                assertTrue(input.commitText("未儲存😀\r\n", 1))
                assertTrue(activity.document.isDirty)
            }
            Thread.sleep(1_500) // production debounce plus atomic I/O
        }
        launch(null).use { scenario ->
            waitFor("draft recovery") { activity(scenario) { !it.document.isRestoring } }
            scenario.onActivity { activity ->
                assertTrue(activity.document.isDirty)
                assertTrue(activity.document.previewSnapshot().document.toString().startsWith("未儲存😀\r\n"))
                activity.document.discardRecoveryDraft()
            }
        }
    }

    private fun launch(uri: Uri?): ActivityScenario<MainActivity> = ActivityScenario.launch(Intent(
        InstrumentationRegistry.getInstrumentation().targetContext,
        MainActivity::class.java,
    ).apply {
        action = if (uri == null) Intent.ACTION_MAIN else Intent.ACTION_VIEW
        data = uri
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
    })

    private fun write(uri: Uri, bytes: ByteArray) {
        InstrumentationRegistry.getInstrumentation().context.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(bytes) }
    }

    private fun read(uri: Uri): ByteArray = InstrumentationRegistry.getInstrumentation().context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }

    private fun shellBytes(path: String): ByteArray {
        val escaped = path.replace("'", "'\\''")
        val descriptor = InstrumentationRegistry.getInstrumentation().uiAutomation
            .executeShellCommand("sh -c 'cat \\\"$escaped\\\"'")
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input -> ByteArrayOutputStream().also(input::copyTo).toByteArray() }
    }

    private inline fun <reified T : View> findView(root: View): T? = findView(root, T::class.java)

    private fun <T : View> findView(root: View, type: Class<T>): T? {
        if (type.isInstance(root)) return type.cast(root)
        if (root is ViewGroup) for (index in 0 until root.childCount) findView(root.getChildAt(index), type)?.let { return it }
        return null
    }

    private fun waitFor(description: String, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(50)
        }
        throw AssertionError("Timed out waiting for $description (possible ANR)")
    }

    private fun <T> activity(scenario: ActivityScenario<MainActivity>, block: (MainActivity) -> T): T {
        var result: Result<T>? = null
        scenario.onActivity { result = runCatching { block(it) } }
        return requireNotNull(result).getOrThrow()
    }
}
