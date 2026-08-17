package app.md4a.editor

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DraftStoreTest {
    @Test
    fun olderReservationCannotOverwriteNewerDraft() {
        val directory = Files.createTempDirectory("md4a-draft").toFile()
        val store = DraftStore(directory)
        val older = store.reserve()
        val newer = store.reserve()

        assertTrue(store.write(newer, metadata("new", 2)) { it.append("new text") })
        assertFalse(store.write(older, metadata("old", 1)) { it.append("old text") })

        val recovered = store.recover()!!
        assertEquals("new", recovered.metadata.token)
        assertEquals("new text", recovered.text)
        directory.deleteRecursively()
    }

    @Test
    fun clearInvalidatesInFlightReservation() {
        val directory = Files.createTempDirectory("md4a-draft").toFile()
        val store = DraftStore(directory)
        val stale = store.reserve()

        store.clear()

        assertFalse(store.write(stale, metadata("stale", 1)) { it.append("lost") })
        assertNull(store.recover())
        directory.deleteRecursively()
    }

    @Test
    fun corruptManifestIsQuarantinedAndNotRecoveredAgain() {
        val directory = Files.createTempDirectory("md4a-draft").toFile()
        directory.mkdirs()
        directory.resolve("draft.properties").writeText("revision=oops")
        val store = DraftStore(directory)

        val failure = runCatching { store.recover() }.exceptionOrNull()

        assertTrue(failure is java.io.IOException)
        assertTrue(failure?.message?.contains("corrupt") == true)
        assertNull(store.recover())
        assertTrue(directory.listFiles()!!.any { it.name.startsWith("corrupt-") })
        directory.deleteRecursively()
    }

    private fun metadata(token: String, revision: Long) =
        DraftMetadata(token, revision, "Document.md", "content://document/$token")
}
