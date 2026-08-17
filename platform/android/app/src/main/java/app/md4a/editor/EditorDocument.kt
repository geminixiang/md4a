package app.md4a.editor

/** A storage seam for [LargeDocumentView]. Implementations own persistence and undo history. */
interface EditorDocument {
    val length: Long
    val lineCount: Int

    /** Returns one logical line without its trailing line break. */
    fun line(index: Int): CharSequence

    fun positionAt(line: Int, column: Int): Long
    fun locationAt(position: Long): EditorLocation

    /** Intended for small, bounded IME/clipboard reads, not full-document snapshots. */
    fun text(start: Long, endExclusive: Long): CharSequence

    /** Replaces a range and returns the cursor position after the inserted text. */
    fun replace(start: Long, endExclusive: Long, text: CharSequence): Long

    /** Keeps document history selection synchronized without changing text. */
    fun setSelection(anchor: Long, caret: Long) = Unit

    fun selection(): EditorSelection = EditorSelection.Zero
}

data class EditorLocation(val line: Int, val column: Int)

fun interface EditListener {
    fun onEdit(start: Long, oldEndExclusive: Long, newEndExclusive: Long)
}

fun interface HistoryRequestListener {
    fun onHistoryRequest(): Boolean
}
