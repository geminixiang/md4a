package app.md4a.benchmark

import app.md4a.editor.EditorDocument
import app.md4a.editor.EditorLocation
import app.md4a.editor.PieceTreeBuffer
import app.md4a.editor.TextRange
import java.io.Writer

internal class BenchmarkDocument(initial: String) : EditorDocument {
    val buffer = PieceTreeBuffer(initial, historyLimit = 1_100)
    override val length: Long get() = buffer.length.toLong()
    override val lineCount: Int get() = buffer.lineCount

    override fun line(index: Int): CharSequence {
        val snapshot = buffer.snapshot()
        return snapshot.text(TextRange(snapshot.lineStart(index), snapshot.lineEnd(index)))
    }

    override fun positionAt(line: Int, column: Int): Long =
        (buffer.snapshot().lineStart(line) + column).toLong()

    override fun locationAt(position: Long): EditorLocation {
        val snapshot = buffer.snapshot()
        val offset = position.toInt()
        val line = snapshot.lineForOffset(offset)
        return EditorLocation(line, offset - snapshot.lineStart(line))
    }

    override fun text(start: Long, endExclusive: Long): CharSequence =
        buffer.snapshot().text(TextRange(start.toInt(), endExclusive.toInt()))

    override fun replace(start: Long, endExclusive: Long, text: CharSequence): Long {
        buffer.replace(TextRange(start.toInt(), endExclusive.toInt()), text)
        return start + text.length
    }

    fun streamTo(writer: Writer) = buffer.snapshot().appendTo(writer)
}
