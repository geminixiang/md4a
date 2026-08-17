package app.md4a.editor

/** A production editor session owning one mutable document and its persistent history. */
class DocumentSession(
    initialText: String,
    historyLimit: Int = 100,
    initiallyDirty: Boolean = false,
) : EditorDocument {
    private val buffer = PieceTreeBuffer(initialText, historyLimit, initiallyDirty)

    override val length: Long get() = buffer.length.toLong()
    override val lineCount: Int get() = buffer.lineCount
    val revision: Long get() = buffer.revision
    val isDirty: Boolean get() = buffer.isDirty

    override fun line(index: Int): CharSequence {
        val snapshot = buffer.snapshot()
        return snapshot.subSequence(snapshot.lineStart(index), snapshot.lineEnd(index))
    }

    override fun positionAt(line: Int, column: Int): Long {
        val snapshot = buffer.snapshot()
        val start = snapshot.lineStart(line)
        return (start + column.coerceIn(0, snapshot.lineEnd(line) - start)).toLong()
    }

    override fun locationAt(position: Long): EditorLocation {
        val snapshot = buffer.snapshot()
        val offset = position.toInt().coerceIn(0, snapshot.length)
        val line = snapshot.lineForOffset(offset)
        return EditorLocation(line, offset - snapshot.lineStart(line))
    }

    override fun text(start: Long, endExclusive: Long): CharSequence =
        buffer.snapshot().text(TextRange(start.toInt(), endExclusive.toInt()))

    override fun replace(start: Long, endExclusive: Long, text: CharSequence): Long {
        val caret = start.toInt() + text.length
        buffer.replace(
            TextRange(start.toInt(), endExclusive.toInt()),
            text,
            EditorSelection(caret, caret),
        )
        return caret.toLong()
    }

    override fun setSelection(anchor: Long, caret: Long) {
        buffer.setSelection(EditorSelection(anchor.toInt(), caret.toInt()))
    }

    override fun selection(): EditorSelection = buffer.selection

    fun undo(): Boolean = buffer.undo()
    fun redo(): Boolean = buffer.redo()

    /** Capturing this handle is O(1); flattening is left to an explicit consumer. */
    fun snapshot(): SessionSnapshot = SessionSnapshot(buffer.revision, buffer.snapshot())

    /** A completed write is current only if no edit or history operation occurred meanwhile. */
    fun markSavedIfRevision(writtenRevision: Long): Boolean {
        if (buffer.revision != writtenRevision) return false
        buffer.markSaved()
        return true
    }
}

data class SessionSnapshot(
    val revision: Long,
    val document: DocumentSnapshot,
)
