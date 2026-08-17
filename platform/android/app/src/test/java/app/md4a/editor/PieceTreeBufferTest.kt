package app.md4a.editor

import java.lang.StringBuilder
import java.util.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PieceTreeBufferTest {
    @Test
    fun readsRangesAndIndexesMixedNewlinesAcrossPieces() {
        val buffer = PieceTreeBuffer("zero\r\none\rtwo\nthree")
        buffer.replace(TextRange(5, 5), "X") // Split the original CRLF across pieces.
        buffer.replace(TextRange(5, 6), "")
        val snapshot = buffer.snapshot()

        assertEquals("zero\r\none\rtwo\nthree", snapshot.toString())
        assertEquals(4, snapshot.lineCount)
        assertEquals(listOf(0, 6, 10, 14), (0 until snapshot.lineCount).map(snapshot::lineStart))
        assertEquals(listOf(4, 9, 13, 19), (0 until snapshot.lineCount).map(snapshot::lineEnd))
        assertEquals(0, snapshot.lineForOffset(0))
        assertEquals(0, snapshot.lineForOffset(5)) // Between CR and LF is still the first line.
        assertEquals(1, snapshot.lineForOffset(6))
        assertEquals(3, snapshot.lineForOffset(snapshot.length))
        assertEquals("one\rtwo", snapshot.text(TextRange(6, 13)))

        val destination = StringBuilder("prefix:")
        snapshot.appendTo(destination, TextRange(10, 19))
        assertEquals("prefix:two\nthree", destination.toString())
    }

    @Test
    fun crlfRemainsOneBreakWhenPiecesSplitAtEveryBoundary() {
        val chunkBoundaryText = "x".repeat(16 * 1024 - 1) + "\r\nend"
        val buffer = PieceTreeBuffer(chunkBoundaryText)
        assertEquals(2, buffer.lineCount)
        assertEquals(16 * 1024 + 1, buffer.snapshot().lineStart(1))

        // Force CR and LF into independently inserted pieces, then split on either side again.
        val edited = PieceTreeBuffer("leftend")
        edited.replace(TextRange(4, 4), "\r")
        edited.replace(TextRange(5, 5), "\n")
        edited.replace(TextRange(4, 4), "X")
        edited.replace(TextRange(4, 5), "")
        val snapshot = edited.snapshot()

        assertEquals("left\r\nend", snapshot.toString())
        assertEquals(2, snapshot.lineCount)
        assertEquals(6, snapshot.lineStart(1))
        assertEquals(4, snapshot.lineEnd(0))
        assertEquals(0, snapshot.lineForOffset(5))
        assertEquals(1, snapshot.lineForOffset(6))
    }

    @Test
    fun trailingTerminatorsAndEmptyLinesHaveStableLineRanges() {
        val snapshot = PieceTreeBuffer("\r\n\n\r").snapshot()

        assertEquals(4, snapshot.lineCount)
        assertEquals(listOf(0, 2, 3, 4), (0..3).map(snapshot::lineStart))
        assertEquals(listOf(0, 2, 3, 4), (0..3).map(snapshot::lineEnd))
        assertEquals(listOf(0, 0, 0, 0), (0..3).map { snapshot.lineEnd(it) - snapshot.lineStart(it) })
    }

    @Test
    fun offsetsAreUtf16AndSurrogatePairsSurviveCrossPieceEdits() {
        val buffer = PieceTreeBuffer("A😀B\r\n𐐷C")
        assertEquals(9, buffer.length)

        buffer.replace(TextRange(1, 1), "[")
        buffer.replace(TextRange(4, 4), "]")
        assertEquals("A[😀]B\r\n𐐷C", buffer.snapshot().toString())

        buffer.replace(TextRange(2, 4), "🙂")
        assertEquals("A[🙂]B\r\n𐐷C", buffer.snapshot().toString())
        assertEquals(1, buffer.snapshot().lineForOffset(9))
    }

    @Test
    fun immutableSnapshotsRemainIsolatedAcrossEdits() {
        val buffer = PieceTreeBuffer("alpha\nbeta")
        val first = buffer.snapshot()
        buffer.replace(TextRange(0, 5), "A")
        val second = buffer.snapshot()
        buffer.replace(TextRange(buffer.length, buffer.length), "!")

        assertEquals("alpha\nbeta", first.toString())
        assertEquals("A\nbeta", second.toString())
        assertEquals("A\nbeta!", buffer.snapshot().toString())
    }

    @Test
    fun selectionDirtyRevisionAndUndoRedoFollowDocumentStates() {
        val buffer = PieceTreeBuffer("abc", historyLimit = 3)
        buffer.setSelection(EditorSelection(1, 2))
        buffer.markSaved()

        buffer.replace(TextRange(1, 2), "XYZ", EditorSelection(4, 1))
        assertEquals("aXYZc", buffer.snapshot().toString())
        assertEquals(EditorSelection(4, 1), buffer.selection)
        assertTrue(buffer.isDirty)
        assertTrue(buffer.canUndo())
        assertFalse(buffer.canRedo())

        assertTrue(buffer.undo())
        assertEquals("abc", buffer.snapshot().toString())
        assertEquals(EditorSelection(1, 2), buffer.selection)
        assertFalse(buffer.isDirty)
        assertTrue(buffer.redo())
        assertEquals("aXYZc", buffer.snapshot().toString())
        assertTrue(buffer.isDirty)

        buffer.markSaved()
        assertFalse(buffer.isDirty)
        buffer.replace(TextRange(0, 1), "A")
        assertTrue(buffer.isDirty)
        buffer.undo()
        assertFalse(buffer.isDirty)
        buffer.redo()
        assertTrue(buffer.isDirty)
    }

    @Test
    fun historyIsBoundedAndNewEditClearsRedo() {
        val buffer = PieceTreeBuffer("", historyLimit = 2)
        repeat(3) { buffer.replace(TextRange(buffer.length, buffer.length), "$it") }
        assertEquals("012", buffer.snapshot().toString())
        assertTrue(buffer.undo())
        assertTrue(buffer.undo())
        assertFalse(buffer.undo())
        assertEquals("0", buffer.snapshot().toString())

        assertTrue(buffer.redo())
        buffer.replace(TextRange(buffer.length, buffer.length), "x")
        assertFalse(buffer.canRedo())
        assertEquals("01x", buffer.snapshot().toString())
    }

    @Test
    fun invalidReplacementSelectionIsAtomic() {
        val buffer = PieceTreeBuffer("abc")
        buffer.setSelection(EditorSelection(1, 2))
        buffer.replace(TextRange(0, 0), "x")
        assertTrue(buffer.undo())
        val text = buffer.snapshot().toString()
        val selection = buffer.selection
        val revision = buffer.revision
        val dirty = buffer.isDirty
        val canUndo = buffer.canUndo()
        val canRedo = buffer.canRedo()
        val metrics = buffer.lastEditMetrics

        assertThrows(IllegalArgumentException::class.java) {
            buffer.replace(TextRange(1, 2), "replacement", EditorSelection(99, 99))
        }

        assertEquals(text, buffer.snapshot().toString())
        assertEquals(selection, buffer.selection)
        assertEquals(revision, buffer.revision)
        assertEquals(dirty, buffer.isDirty)
        assertEquals(canUndo, buffer.canUndo())
        assertEquals(canRedo, buffer.canRedo())
        assertEquals(metrics, buffer.lastEditMetrics)
    }

    @Test
    fun invalidRangeDoesNotReadReplacementOrMutateState() {
        val buffer = PieceTreeBuffer("abc")
        val revision = buffer.revision
        var replacementRead = false
        val replacement = object : CharSequence {
            override val length: Int get() { replacementRead = true; return Int.MAX_VALUE }
            override fun get(index: Int): Char = error("must not read")
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = error("must not read")
        }

        assertThrows(IllegalArgumentException::class.java) {
            buffer.replace(TextRange(0, 4), replacement)
        }

        assertFalse(replacementRead)
        assertEquals("abc", buffer.snapshot().toString())
        assertEquals(revision, buffer.revision)
        assertFalse(buffer.canUndo())
    }

    @Test
    fun replacementLengthOverflowIsRejectedBeforeMutation() {
        val buffer = PieceTreeBuffer("abc")
        var flattened = false
        val replacement = object : CharSequence {
            override val length: Int get() = Int.MAX_VALUE
            override fun get(index: Int): Char = error("must not read")
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = error("must not read")
            override fun toString(): String { flattened = true; return "" }
        }

        assertThrows(IllegalArgumentException::class.java) {
            buffer.replace(TextRange(0, 0), replacement)
        }

        assertFalse(flattened)
        assertEquals("abc", buffer.snapshot().toString())
        assertEquals(0L, buffer.revision)
        assertFalse(buffer.canUndo())
    }

    @Test
    fun randomizedEditsMatchStringBuilderAndReferenceLineIndex() {
        val random = Random(0x4d443441L)
        val expected = StringBuilder("start\r\n😀\nend")
        val actual = PieceTreeBuffer(expected.toString(), historyLimit = 0)
        val replacements = arrayOf("", "x", "\n", "\r", "\r\n", "😀", "ab\r\ncd")

        repeat(2_500) { iteration ->
            val start = random.nextInt(expected.length + 1)
            val end = start + random.nextInt(expected.length - start + 1)
            val replacement = replacements[random.nextInt(replacements.size)]
            expected.replace(start, end, replacement)
            actual.replace(TextRange(start, end), replacement)

            assertEquals("iteration $iteration", expected.length, actual.length)
            assertEquals("iteration $iteration", expected.toString(), actual.snapshot().toString())
            val starts = referenceLineStarts(expected)
            assertEquals("iteration $iteration", starts.size, actual.lineCount)
            repeat(4) {
                val offset = random.nextInt(expected.length + 1)
                assertEquals(
                    "iteration $iteration, offset $offset",
                    referenceLineForOffset(expected, offset),
                    actual.snapshot().lineForOffset(offset),
                )
            }
            starts.indices.forEach { line ->
                assertEquals("iteration $iteration, line $line", starts[line], actual.snapshot().lineStart(line))
                assertEquals(
                    "iteration $iteration, line end $line",
                    referenceLineEnd(expected, starts, line),
                    actual.snapshot().lineEnd(line),
                )
            }
        }
    }

    @Test
    fun singleCharacterEditsInEightMegabyteDocumentRetainExistingStorage() {
        val line = "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ markdown payload 0123456789abcdef EXTRA-DATA-TO-EXCEED-EIGHT-MIB\r\n"
        val source = buildString(line.length * 82_365) { repeat(82_365) { append(line) } }
        assertTrue(source.length > 8 * 1024 * 1024)
        val buffer = PieceTreeBuffer(source)
        val before = buffer.snapshot()
        assertEquals(82_366, buffer.lineCount)

        val middle = buffer.length / 2
        repeat(200) { buffer.replace(TextRange(middle, middle), "x") }

        assertEquals(source.length + 200, buffer.length)
        assertEquals(0, buffer.lastEditMetrics.existingCodeUnitsCopied)
        assertEquals(1, buffer.lastEditMetrics.insertedCodeUnits)
        val retainedSources = buffer.retainedSources()
        assertTrue(retainedSources.any { it === source })
        assertTrue(retainedSources.filterNot { it === source }.all { it.length == 1 })
        assertEquals(source, before.toString())
        assertEquals(source.substring(0, 128), buffer.snapshot().text(TextRange(0, 128)))
        val tailStart = buffer.length - 128
        assertEquals(source.takeLast(128), buffer.snapshot().text(TextRange(tailStart, buffer.length)))
    }

    private fun referenceLineStarts(text: CharSequence): List<Int> {
        val starts = mutableListOf(0)
        var index = 0
        while (index < text.length) {
            when (text[index]) {
                '\r' -> {
                    index++
                    if (index < text.length && text[index] == '\n') index++
                    starts += index
                }
                '\n' -> {
                    index++
                    starts += index
                }
                else -> index++
            }
        }
        return starts
    }

    private fun referenceLineForOffset(text: CharSequence, offset: Int): Int {
        val starts = referenceLineStarts(text)
        return starts.indexOfLast { it <= offset }
    }

    private fun referenceLineEnd(text: CharSequence, starts: List<Int>, line: Int): Int {
        if (line == starts.lastIndex) return text.length
        var end = starts[line + 1]
        if (end > starts[line] && text[end - 1] == '\n') end--
        if (end > starts[line] && text[end - 1] == '\r') end--
        return end
    }
}
