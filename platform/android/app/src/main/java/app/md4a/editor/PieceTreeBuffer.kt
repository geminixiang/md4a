package app.md4a.editor

/** Immutable view of a document revision. Safe to retain while the buffer is edited. */
class DocumentSnapshot internal constructor(private val root: PieceNode?) : CharSequence {
    override val length: Int get() = root.nodeLength
    val lineCount: Int get() = root.summary.breaks + 1

    override fun get(index: Int): Char {
        require(index in 0 until length) { "Offset $index outside 0 until $length" }
        return charAt(root, index)
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        text(TextRange(startIndex, endIndex))

    fun text(range: TextRange): String = buildString(range.length) { appendTo(this, range) }

    fun appendTo(destination: Appendable, range: TextRange = TextRange(0, length)) {
        requireRange(range, length)
        appendRange(root, 0, range.start, range.end, destination)
    }

    fun lineForOffset(offset: Int): Int {
        require(offset in 0..length) { "Offset $offset outside 0..$length" }
        val breaks = breakCountBefore(root, offset)
        // A CRLF break completes after LF, so its intermediate caret remains on the prior line.
        return breaks - if (offset in 1 until length && this[offset - 1] == '\r' && this[offset] == '\n') 1 else 0
    }

    fun lineStart(line: Int): Int {
        require(line in 0 until lineCount) { "Line $line outside 0 until $lineCount" }
        if (line == 0) return 0
        return offsetAfterBreak(root, line)
    }

    /** Excludes the line terminator (both code units for CRLF). */
    fun lineEnd(line: Int): Int {
        val start = lineStart(line)
        if (line == lineCount - 1) return length
        var end = lineStart(line + 1)
        if (end > start && this[end - 1] == '\n') end--
        if (end > start && this[end - 1] == '\r') end--
        return end
    }

    override fun toString(): String = text(TextRange(0, length))
}

/**
 * Persistent piece-tree text buffer. Tree edits copy O(log pieces) nodes and retain source strings;
 * existing document characters are never copied by [replace].
 */
class PieceTreeBuffer(
    initialText: String = "",
    historyLimit: Int = DEFAULT_HISTORY_LIMIT,
    initiallyDirty: Boolean = false,
) {
    init {
        require(historyLimit >= 0) { "historyLimit must not be negative" }
    }

    private val historyLimit = historyLimit
    private var nextPieceId = 1L
    private var nextRevision = 1L
    private var root: PieceNode? = buildInitial(initialText)
    private val undoStack = ArrayDeque<State>()
    private val redoStack = ArrayDeque<State>()

    var selection: EditorSelection = EditorSelection.Zero
        private set
    var revision: Long = 0L
        private set
    private var savedRevision: Long = if (initiallyDirty) -1L else revision

    val length: Int get() = root.nodeLength
    val lineCount: Int get() = root.summary.breaks + 1
    val isDirty: Boolean get() = revision != savedRevision
    var lastEditMetrics: EditMetrics = EditMetrics(length, length, 0, 0)
        private set

    fun snapshot(): DocumentSnapshot = DocumentSnapshot(root)

    internal fun retainedSources(): List<String> = buildList { collectSources(root, this) }

    fun setSelection(value: EditorSelection) {
        require(value.anchor in 0..length && value.caret in 0..length) {
            "Selection (${value.anchor}, ${value.caret}) outside document length $length"
        }
        selection = value
    }

    fun markSaved() {
        savedRevision = revision
    }

    fun replace(
        range: TextRange,
        replacement: CharSequence,
        selectionAfter: EditorSelection? = null,
    ) {
        val currentLength = length
        requireRange(range, currentLength)
        val replacementLength = replacement.length
        require(replacementLength >= 0) { "Replacement length must not be negative" }
        val resultingLength = currentLength.toLong() - range.length + replacementLength.toLong()
        require(resultingLength <= Int.MAX_VALUE) { "Replacement would exceed maximum document length" }
        val defaultCaret = range.start.toLong() + replacementLength
        require(defaultCaret <= resultingLength) { "Replacement cursor overflow" }
        val validatedSelection = selectionAfter ?: EditorSelection(defaultCaret.toInt(), defaultCaret.toInt())
        require(
            validatedSelection.anchor in 0..resultingLength.toInt() &&
                validatedSelection.caret in 0..resultingLength.toInt()
        ) { "Selection (${validatedSelection.anchor}, ${validatedSelection.caret}) outside resulting document length $resultingLength" }
        val inserted = replacement.toString()
        require(inserted.length == replacementLength) { "Replacement length changed while being read" }

        val previousLength = currentLength
        pushBounded(undoStack, State(root, selection, revision))
        redoStack.clear()

        val (before, remainder) = split(root, range.start)
        val (_, after) = split(remainder, range.length)
        val middle = if (inserted.isEmpty()) null else leaf(Piece(inserted, 0, inserted.length, nextId()))
        root = merge(merge(before, middle), after)
        revision = nextRevision++
        selection = validatedSelection
        lastEditMetrics = EditMetrics(previousLength, length, 0, inserted.length)
    }

    fun canUndo(): Boolean = undoStack.isNotEmpty()
    fun canRedo(): Boolean = redoStack.isNotEmpty()

    fun undo(): Boolean {
        if (undoStack.isEmpty()) return false
        pushBounded(redoStack, State(root, selection, revision))
        restore(undoStack.removeLast())
        return true
    }

    fun redo(): Boolean {
        if (redoStack.isEmpty()) return false
        pushBounded(undoStack, State(root, selection, revision))
        restore(redoStack.removeLast())
        return true
    }

    private fun restore(state: State) {
        root = state.root
        selection = state.selection
        revision = state.revision
        lastEditMetrics = EditMetrics(length, length, 0, 0)
    }

    private fun pushBounded(stack: ArrayDeque<State>, state: State) {
        if (historyLimit == 0) return
        if (stack.size == historyLimit) stack.removeFirst()
        stack.addLast(state)
    }

    private fun buildInitial(text: String): PieceNode? {
        var result: PieceNode? = null
        var start = 0
        while (start < text.length) {
            val end = minOf(start + INITIAL_CHUNK_SIZE, text.length)
            result = merge(result, leaf(Piece(text, start, end - start, nextId())))
            start = end
        }
        return result
    }

    private fun nextId(): Long = nextPieceId++

    private fun split(node: PieceNode?, offset: Int): Pair<PieceNode?, PieceNode?> {
        if (node == null) return null to null
        val leftLength = node.left.nodeLength
        return when {
            offset < leftLength -> {
                val (first, second) = split(node.left, offset)
                first to merge(second, merge(leaf(node.piece), node.right))
            }
            offset > leftLength + node.piece.length -> {
                val (first, second) = split(node.right, offset - leftLength - node.piece.length)
                merge(merge(node.left, leaf(node.piece)), first) to second
            }
            else -> {
                val local = offset - leftLength
                val leftPiece = if (local == 0) null else leaf(node.piece.slice(0, local, nextId()))
                val rightPiece = if (local == node.piece.length) null else
                    leaf(node.piece.slice(local, node.piece.length, nextId()))
                merge(node.left, leftPiece) to merge(rightPiece, node.right)
            }
        }
    }

    private fun merge(left: PieceNode?, right: PieceNode?): PieceNode? = when {
        left == null -> right
        right == null -> left
        left.priority <= right.priority -> rebuild(left, right = merge(left.right, right))
        else -> rebuild(right, left = merge(left, right.left))
    }

    private fun leaf(piece: Piece) = PieceNode(piece, null, null)
    private fun rebuild(node: PieceNode, left: PieceNode? = node.left, right: PieceNode? = node.right) =
        PieceNode(node.piece, left, right)

    private data class State(val root: PieceNode?, val selection: EditorSelection, val revision: Long)

    private companion object {
        const val INITIAL_CHUNK_SIZE = 16 * 1024
        const val DEFAULT_HISTORY_LIMIT = 100
    }
}

internal class Piece private constructor(
    val source: String,
    val start: Int,
    val length: Int,
    val id: Long,
    /** Local offsets of CR characters and LF characters not preceded by CR. */
    val breakOffsets: IntArray,
) {
    val summary = NewlineSummary(
        length = length,
        breaks = breakOffsets.size,
        startsWithLf = length > 0 && source[start] == '\n',
        endsWithCr = length > 0 && source[start + length - 1] == '\r',
    )

    fun slice(from: Int, to: Int, newId: Long): Piece {
        val firstBreak = breakOffsets.lowerBound(from)
        val lastBreak = breakOffsets.lowerBound(to)
        val slicedBreaks = IntArray(lastBreak - firstBreak) { breakOffsets[firstBreak + it] - from }
        // LF at the start of a slice is a candidate break even when preceded by CR in the source;
        // the tree aggregate will suppress it when the preceding piece still ends in CR.
        val sliceStart = start + from
        val needsLeadingLf = from < to && source[sliceStart] == '\n' &&
            (slicedBreaks.isEmpty() || slicedBreaks[0] != 0)
        val indexedBreaks = if (needsLeadingLf) intArrayOf(0, *slicedBreaks) else slicedBreaks
        return Piece(source, sliceStart, to - from, newId, indexedBreaks)
    }

    companion object {
        operator fun invoke(source: String, start: Int, length: Int, id: Long): Piece {
            val end = start + length
            var breakCount = 0
            for (index in start until end) {
                val character = source[index]
                if (character == '\r' || (character == '\n' && (index == start || source[index - 1] != '\r'))) {
                    breakCount++
                }
            }
            val offsets = IntArray(breakCount)
            var destination = 0
            for (index in start until end) {
                val character = source[index]
                if (character == '\r' || (character == '\n' && (index == start || source[index - 1] != '\r'))) {
                    offsets[destination++] = index - start
                }
            }
            return Piece(source, start, length, id, offsets)
        }
    }
}

internal class PieceNode(val piece: Piece, val left: PieceNode?, val right: PieceNode?) {
    val priority: Long = mix(piece.id)
    val nodeLength: Int = left.nodeLength + piece.length + right.nodeLength
    val summary: NewlineSummary = left.summary + piece.summary + right.summary
}

internal data class NewlineSummary(
    val length: Int,
    val breaks: Int,
    val startsWithLf: Boolean,
    val endsWithCr: Boolean,
) {
    operator fun plus(other: NewlineSummary): NewlineSummary {
        if (length == 0) return other
        if (other.length == 0) return this
        return NewlineSummary(
            length + other.length,
            breaks + other.breaks - if (endsWithCr && other.startsWithLf) 1 else 0,
            startsWithLf,
            other.endsWithCr,
        )
    }

    companion object {
        val Empty = NewlineSummary(0, 0, false, false)
    }
}

private val PieceNode?.nodeLength: Int get() = this?.nodeLength ?: 0
private val PieceNode?.summary: NewlineSummary get() = this?.summary ?: NewlineSummary.Empty

private fun collectSources(node: PieceNode?, destination: MutableList<String>) {
    if (node == null) return
    collectSources(node.left, destination)
    destination += node.piece.source
    collectSources(node.right, destination)
}

private fun charAt(node: PieceNode?, offset: Int): Char {
    checkNotNull(node)
    val leftLength = node.left.nodeLength
    return when {
        offset < leftLength -> charAt(node.left, offset)
        offset < leftLength + node.piece.length -> node.piece.source[node.piece.start + offset - leftLength]
        else -> charAt(node.right, offset - leftLength - node.piece.length)
    }
}

private fun appendRange(
    node: PieceNode?,
    nodeStart: Int,
    rangeStart: Int,
    rangeEnd: Int,
    destination: Appendable,
) {
    if (node == null || rangeStart >= rangeEnd || nodeStart >= rangeEnd || nodeStart + node.nodeLength <= rangeStart) return
    appendRange(node.left, nodeStart, rangeStart, rangeEnd, destination)
    val pieceStart = nodeStart + node.left.nodeLength
    val from = maxOf(rangeStart, pieceStart) - pieceStart
    val to = minOf(rangeEnd, pieceStart + node.piece.length) - pieceStart
    if (from < to) destination.append(node.piece.source, node.piece.start + from, node.piece.start + to)
    appendRange(node.right, pieceStart + node.piece.length, rangeStart, rangeEnd, destination)
}

private fun effectiveBreaks(summary: NewlineSummary, precedingCr: Boolean): Int =
    summary.breaks - if (precedingCr && summary.startsWithLf && summary.length > 0) 1 else 0

/** Counts logical newline starts in [0, length) in O(tree height + log local breaks). */
private fun breakCountBefore(root: PieceNode?, length: Int): Int {
    var node = root
    var remaining = length
    var breaks = 0
    var precedingCr = false
    while (node != null && remaining > 0) {
        val leftLength = node.left.nodeLength
        if (remaining <= leftLength) {
            node = node.left
            continue
        }

        val leftSummary = node.left.summary
        breaks += effectiveBreaks(leftSummary, precedingCr)
        if (leftSummary.length > 0) precedingCr = leftSummary.endsWithCr
        remaining -= leftLength

        val pieceLength = minOf(remaining, node.piece.length)
        if (pieceLength > 0) {
            val localBreaks = node.piece.breakOffsets.lowerBound(pieceLength)
            breaks += localBreaks - if (precedingCr && node.piece.summary.startsWithLf) 1 else 0
            precedingCr = node.piece.source[node.piece.start + pieceLength - 1] == '\r'
            remaining -= pieceLength
        }
        if (remaining == 0) break
        node = node.right
    }
    return breaks
}

/** Locates the end of the nth logical terminator in O(tree height + log local breaks). */
private fun offsetAfterBreak(root: PieceNode?, breakNumber: Int): Int {
    var node = root
    var wanted = breakNumber
    var precedingCr = false
    var nodeStart = 0
    while (node != null) {
        val leftSummary = node.left.summary
        val leftBreaks = effectiveBreaks(leftSummary, precedingCr)
        if (wanted <= leftBreaks) {
            node = node.left
            continue
        }

        wanted -= leftBreaks
        if (leftSummary.length > 0) precedingCr = leftSummary.endsWithCr
        val pieceStart = nodeStart + node.left.nodeLength
        val skipLeadingLf = precedingCr && node.piece.summary.startsWithLf
        val pieceBreaks = node.piece.breakOffsets.size - if (skipLeadingLf) 1 else 0
        if (wanted <= pieceBreaks) {
            val localIndex = wanted - 1 + if (skipLeadingLf) 1 else 0
            val breakOffset = pieceStart + node.piece.breakOffsets[localIndex]
            return if (charAt(root, breakOffset) == '\r' && breakOffset + 1 < root.nodeLength &&
                charAt(root, breakOffset + 1) == '\n') breakOffset + 2 else breakOffset + 1
        }

        wanted -= pieceBreaks
        if (node.piece.length > 0) precedingCr = node.piece.summary.endsWithCr
        nodeStart = pieceStart + node.piece.length
        node = node.right
    }
    error("Break $breakNumber outside document")
}

private fun IntArray.lowerBound(value: Int): Int {
    var low = 0
    var high = size
    while (low < high) {
        val middle = (low + high) ushr 1
        if (this[middle] < value) low = middle + 1 else high = middle
    }
    return low
}

private fun requireRange(range: TextRange, length: Int) {
    require(range.end <= length) { "Range $range outside document length $length" }
}

private fun mix(value: Long): Long {
    var result = value + -7046029254386353131L
    result = (result xor (result ushr 30)) * -4658895280553007687L
    result = (result xor (result ushr 27)) * -7723592293110705685L
    return result xor (result ushr 31)
}
