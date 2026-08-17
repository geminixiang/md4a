package app.md4a.editor

import org.junit.Assert.assertEquals
import org.junit.Test

class EditorInputLogicTest {
    @Test
    fun repeatedCompositionAndCommitReplaceTheActiveRange() {
        var text = ""
        var selectionStart = 0L
        var selectionEnd = 0L
        var composingStart = -1L
        var composingEnd = -1L

        fun apply(value: String, composing: Boolean, newCursorPosition: Int = 1) {
            val edit = InputEdits.replacement(
                selectionStart, selectionEnd, composingStart, composingEnd,
                value.length, newCursorPosition, composing, text.length.toLong(),
            )
            text = text.replaceRange(edit.replaceStart.toInt(), edit.replaceEnd.toInt(), value)
            selectionStart = edit.selection
            selectionEnd = edit.selection
            composingStart = edit.composingStart
            composingEnd = edit.composingEnd
        }

        apply("n", composing = true)
        assertEquals("n", text)
        apply("ni", composing = true)
        assertEquals("ni", text)
        apply("你", composing = false)
        assertEquals("你", text)
        assertEquals(1L, selectionStart)
        assertEquals(-1L, composingStart)
    }

    @Test
    fun androidNewCursorPositionIsRelativeToInsertionBoundaries() {
        val after = InputEdits.replacement(2, 2, -1, -1, 2, 2, false, 5)
        assertEquals(5L, after.selection) // inserted end (4) + 2 - 1

        val before = InputEdits.replacement(2, 4, -1, -1, 1, 0, false, 6)
        assertEquals(2L, before.selection) // insertion start + 0

        val oneBefore = InputEdits.replacement(2, 2, -1, -1, 1, -1, false, 5)
        assertEquals(1L, oneBefore.selection)
    }

    @Test
    fun boundedWindowsExpandInsteadOfSplittingSurrogatePairs() {
        val text = "A😀B𐐷C"

        assertEquals(UnicodeOffsets.Window(1, 3), UnicodeOffsets.window(text, 2, 2))
        assertEquals(UnicodeOffsets.Window(0, 3), UnicodeOffsets.window(text, 0, 2))
        assertEquals(UnicodeOffsets.Window(4, 6), UnicodeOffsets.window(text, 5, 5))
    }

    @Test
    fun unicodeOffsetsNeverLandInsideSurrogatePairs() {
        val text = "A😀𐐷B"
        assertEquals(1, UnicodeOffsets.normalizeBackward(text, 2))
        assertEquals(3, UnicodeOffsets.normalizeForward(text, 2))
        assertEquals(1, UnicodeOffsets.previous(text, 3))
        assertEquals(3, UnicodeOffsets.next(text, 1))
        assertEquals(5, UnicodeOffsets.moveCodePoints(text, 1, 2))
        assertEquals(1, UnicodeOffsets.moveCodePoints(text, 5, -2))
    }
}
