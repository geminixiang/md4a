package app.md4a

import org.junit.Assert.assertTrue
import org.junit.Test

class PreviewDocumentTest {
    @Test
    fun wrapsRenderedHtmlInLocalDocument() {
        val document = previewDocument("<h1>Hello</h1>")

        assertTrue(document.startsWith("<!doctype html>"))
        assertTrue(document.contains("<h1>Hello</h1>"))
        assertTrue(document.contains("color-scheme: light dark"))
    }
}
