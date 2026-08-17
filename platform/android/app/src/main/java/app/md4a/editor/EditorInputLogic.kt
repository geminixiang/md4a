package app.md4a.editor

/** UTF-16/code-point boundary operations shared by the View and JVM tests. */
internal object UnicodeOffsets {
    fun normalizeBackward(text: CharSequence, offset: Int): Int {
        val clamped = offset.coerceIn(0, text.length)
        return if (clamped in 1 until text.length &&
            Character.isHighSurrogate(text[clamped - 1]) && Character.isLowSurrogate(text[clamped])
        ) clamped - 1 else clamped
    }

    fun normalizeForward(text: CharSequence, offset: Int): Int {
        val clamped = offset.coerceIn(0, text.length)
        return if (clamped in 1 until text.length &&
            Character.isHighSurrogate(text[clamped - 1]) && Character.isLowSurrogate(text[clamped])
        ) clamped + 1 else clamped
    }

    data class Window(val start: Int, val end: Int)

    fun window(text: CharSequence, start: Int, end: Int): Window = Window(
        normalizeBackward(text, start),
        normalizeForward(text, end),
    )

    fun previous(text: CharSequence, offset: Int): Int {
        val end = normalizeBackward(text, offset)
        if (end == 0) return 0
        return if (end >= 2 && Character.isHighSurrogate(text[end - 2]) && Character.isLowSurrogate(text[end - 1])) end - 2 else end - 1
    }

    fun next(text: CharSequence, offset: Int): Int {
        val start = normalizeForward(text, offset)
        if (start == text.length) return start
        return if (start + 1 < text.length && Character.isHighSurrogate(text[start]) && Character.isLowSurrogate(text[start + 1])) start + 2 else start + 1
    }

    fun moveCodePoints(text: CharSequence, offset: Int, count: Int): Int {
        var result = if (count < 0) normalizeBackward(text, offset) else normalizeForward(text, offset)
        repeat(kotlin.math.abs(count)) { result = if (count < 0) previous(text, result) else next(text, result) }
        return result
    }
}

internal data class InputEdit(
    val replaceStart: Long,
    val replaceEnd: Long,
    val selection: Long,
    val composingStart: Long = -1,
    val composingEnd: Long = -1,
)

/** Pure InputConnection range/cursor semantics, independent of Android framework state. */
internal object InputEdits {
    fun replacement(
        selectionStart: Long,
        selectionEnd: Long,
        composingStart: Long,
        composingEnd: Long,
        insertedLength: Int,
        newCursorPosition: Int,
        keepComposing: Boolean,
        documentLength: Long,
    ): InputEdit {
        val hasComposition = composingStart >= 0 && composingEnd >= composingStart
        val start = if (hasComposition) composingStart else selectionStart
        val end = if (hasComposition) composingEnd else selectionEnd
        val insertedEnd = start + insertedLength
        val resultingLength = documentLength - (end - start) + insertedLength
        val cursor = if (newCursorPosition > 0) insertedEnd + newCursorPosition - 1L
        else start + newCursorPosition.toLong()
        return InputEdit(
            start,
            end,
            cursor.coerceIn(0, resultingLength),
            if (keepComposing) start else -1,
            if (keepComposing) insertedEnd else -1,
        )
    }
}
