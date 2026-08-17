package app.md4a.editor

import java.io.StringWriter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentSessionTest {
    @Test
    fun editUpdatesRevisionAndDirtyWithoutFlattening() {
        val session = DocumentSession("alpha\r\nbeta")
        val original = session.snapshot()

        session.replace(5, 5, "!")

        assertTrue(session.isDirty)
        assertTrue(session.revision > original.revision)
        assertEquals("alpha!\r\nbeta", session.snapshot().document.toString())
        assertEquals("alpha\r\nbeta", original.document.toString())
        assertEquals(2, session.lineCount)
    }

    @Test
    fun successfulSaveMarksOnlyTheWrittenRevision() {
        val session = DocumentSession("one")
        val written = session.snapshot()
        val output = StringWriter()
        written.document.appendTo(output)

        assertTrue(session.markSavedIfRevision(written.revision))
        assertFalse(session.isDirty)
        assertEquals("one", output.toString())
    }

    @Test
    fun staleSaveDoesNotClearLaterEdits() {
        val session = DocumentSession("one")
        val stale = session.snapshot()
        session.replace(session.length, session.length, " two")

        assertFalse(session.markSavedIfRevision(stale.revision))
        assertTrue(session.isDirty)
        assertEquals("one", stale.document.toString())
        assertEquals("one two", session.snapshot().document.toString())
    }

    @Test
    fun snapshotsAreConstantIdentityHandlesAndRemainImmutable() {
        val session = DocumentSession("a\r\nb")
        val first = session.snapshot()
        val sameRevision = session.snapshot()
        session.replace(0, 1, "A")
        val second = session.snapshot()

        assertEquals(first.revision, sameRevision.revision)
        assertNotSame(first.document, sameRevision.document)
        assertEquals("a\r\nb", first.document.toString())
        assertEquals("A\r\nb", second.document.toString())
    }

    @Test
    fun undoRedoRestoreTextSelectionAndDirtyState() {
        val session = DocumentSession("abc")
        assertTrue(session.markSavedIfRevision(session.revision))
        session.setSelection(1, 2)
        session.replace(1, 2, "XYZ")
        session.setSelection(4, 4)

        assertTrue(session.undo())
        assertEquals("abc", session.snapshot().document.toString())
        assertEquals(EditorSelection(1, 2), session.selection())
        assertFalse(session.isDirty)

        assertTrue(session.redo())
        assertEquals("aXYZc", session.snapshot().document.toString())
        assertTrue(session.isDirty)
    }
}
