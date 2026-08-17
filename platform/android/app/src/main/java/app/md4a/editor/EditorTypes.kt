package app.md4a.editor

/** A half-open UTF-16 range. Offsets never split or reinterpret surrogate pairs. */
data class TextRange(val start: Int, val end: Int) {
    init {
        require(start >= 0 && end >= start) { "Invalid range [$start, $end)" }
    }

    val length: Int get() = end - start
}

/** Selection offsets are UTF-16 offsets; anchor and caret preserve selection direction. */
data class EditorSelection(val anchor: Int, val caret: Int) {
    val range: TextRange get() = TextRange(minOf(anchor, caret), maxOf(anchor, caret))
    val isCollapsed: Boolean get() = anchor == caret

    companion object {
        val Zero = EditorSelection(0, 0)
    }
}

data class EditMetrics(
    val previousLength: Int,
    val newLength: Int,
    /** Existing UTF-16 code units copied while constructing the new tree. Always zero. */
    val existingCodeUnitsCopied: Int,
    /** New UTF-16 code units retained for this edit. */
    val insertedCodeUnits: Int,
)
