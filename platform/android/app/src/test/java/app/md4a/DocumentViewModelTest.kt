package app.md4a

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentViewModelTest {
    @Test
    fun largeDocumentsAreNotEditable() {
        val document = DocumentViewModel()

        assertTrue(document.isEditable)

        document.edit("a".repeat(8 * 1024 * 1024))

        assertFalse(document.isEditable)
    }
}
