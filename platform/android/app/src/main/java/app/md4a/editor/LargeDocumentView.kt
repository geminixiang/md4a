package app.md4a.editor

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.os.Bundle
import android.text.InputType
import android.util.AttributeSet
import android.view.ActionMode
import android.view.GestureDetector
import android.view.KeyEvent
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedText
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.widget.OverScroller
import kotlin.math.floor
import kotlin.math.max

/**
 * A virtualized plain-text editor. It deliberately asks [EditorDocument] only for lines intersecting
 * the viewport (plus one overscan line); word wrapping is not performed.
 */
class LargeDocumentView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {
    private val density = resources.displayMetrics.density
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xff202124.toInt()
        textSize = 16f * resources.displayMetrics.density * resources.configuration.fontScale
        typeface = android.graphics.Typeface.MONOSPACE
    }
    private val selectionPaint = Paint().apply { color = 0x663f51b5 }
    private val cursorPaint = Paint().apply {
        color = 0xff3f51b5.toInt()
        strokeWidth = max(2f, density)
    }
    private val scroller = OverScroller(context)
    private val gestureDetector = GestureDetector(context, GestureListener())
    private var actionMode: ActionMode? = null
    private var document: EditorDocument? = null
    private var cursor = 0L
    private var anchor = 0L
    private var preferredColumn: Int? = null
    private var composingStart = -1L
    private var composingEnd = -1L
    private var scrollXFloat = 0f
    private var scrollYFloat = 0f
    private var maximumObservedLineWidth = 0f

    var onEdit: EditListener? = null
    var onUndo: HistoryRequestListener? = null
    var onRedo: HistoryRequestListener? = null

    private val fontMetrics get() = textPaint.fontMetrics
    private val lineHeight get() = fontMetrics.descent - fontMetrics.ascent
    private val contentWidth get() = max(0, width - paddingLeft - paddingRight)
    private val contentHeight get() = max(0, height - paddingTop - paddingBottom)

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        isClickable = true
        isLongClickable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = "Document editor"
        setOnLongClickListener {
            startSelectionActionMode()
            true
        }
    }

    fun setDocument(value: EditorDocument?) {
        if (document === value) return
        finishComposingText()
        document = value
        val restored = value?.selection() ?: EditorSelection.Zero
        cursor = restored.caret.toLong()
        anchor = restored.anchor.toLong()
        scrollXFloat = 0f
        scrollYFloat = 0f
        maximumObservedLineWidth = 0f
        scroller.abortAnimation()
        invalidate()
        sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
    }

    fun clearDocument() {
        setDocument(null)
        onEdit = null
        onUndo = null
        onRedo = null
    }

    fun updateColors(textColor: Int, accentColor: Int, selectionColor: Int) {
        textPaint.color = textColor
        cursorPaint.color = accentColor
        selectionPaint.color = selectionColor
        invalidate()
    }

    fun selectionStart(): Long = minOf(anchor, cursor)
    fun selectionEnd(): Long = maxOf(anchor, cursor)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val value = document ?: return
        if (value.lineCount == 0 || contentHeight == 0) return
        val range = visibleLineRange(value.lineCount, scrollYFloat, contentHeight, lineHeight) ?: return
        val first = range.first
        val last = range.last
        canvas.save()
        canvas.clipRect(paddingLeft, paddingTop, width - paddingRight, height - paddingBottom)
        val selectedStart = selectionStart()
        val selectedEnd = selectionEnd()
        for (lineIndex in first..last) {
            val text = value.line(lineIndex)
            val lineStart = value.positionAt(lineIndex, 0)
            val lineEnd = lineStart + text.length
            val x = paddingLeft - scrollXFloat
            val baseline = paddingTop - scrollYFloat - fontMetrics.ascent + lineIndex * lineHeight
            val width = textPaint.measureText(text, 0, text.length)
            maximumObservedLineWidth = max(maximumObservedLineWidth, width)
            if (selectedStart != selectedEnd && selectedEnd >= lineStart && selectedStart <= lineEnd) {
                val from = (selectedStart - lineStart).coerceIn(0, text.length.toLong()).toInt()
                val to = (selectedEnd - lineStart).coerceIn(0, text.length.toLong()).toInt()
                canvas.drawRect(
                    x + measuredPrefix(text, from), baseline + fontMetrics.ascent,
                    x + measuredPrefix(text, to), baseline + fontMetrics.descent, selectionPaint,
                )
            }
            canvas.drawText(text, 0, text.length, x, baseline, textPaint)
            if (cursor in lineStart..lineEnd) {
                val column = (cursor - lineStart).toInt()
                val cursorX = x + measuredPrefix(text, column)
                canvas.drawLine(cursorX, baseline + fontMetrics.ascent, cursorX, baseline + fontMetrics.descent, cursorPaint)
            }
        }
        canvas.restore()
    }

    private fun measuredPrefix(text: CharSequence, end: Int): Float =
        if (end == 0) 0f else textPaint.measureText(text, 0, end)

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val handled = gestureDetector.onTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
            parent?.requestDisallowInterceptTouchEvent(false)
        } else {
            parent?.requestDisallowInterceptTouchEvent(true)
        }
        return handled || super.onTouchEvent(event)
    }

    private inner class GestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent): Boolean {
            scroller.forceFinished(true)
            return true
        }

        override fun onSingleTapUp(event: MotionEvent): Boolean {
            requestFocus()
            moveCursor(positionForPoint(event.x, event.y), extend = false)
            context.getSystemService(InputMethodManager::class.java)?.showSoftInput(this@LargeDocumentView, InputMethodManager.SHOW_IMPLICIT)
            performClick()
            return true
        }

        override fun onScroll(first: MotionEvent?, second: MotionEvent, dx: Float, dy: Float): Boolean {
            setScroll(scrollXFloat + dx, scrollYFloat + dy)
            return true
        }

        override fun onFling(first: MotionEvent?, second: MotionEvent, velocityX: Float, velocityY: Float): Boolean {
            val maxX = maxHorizontalScroll().toInt()
            val maxY = maxVerticalScroll().toInt()
            scroller.fling(scrollXFloat.toInt(), scrollYFloat.toInt(), -velocityX.toInt(), -velocityY.toInt(), 0, maxX, 0, maxY)
            postInvalidateOnAnimation()
            return true
        }
    }

    override fun performClick(): Boolean = super.performClick()

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            setScroll(scroller.currX.toFloat(), scroller.currY.toFloat())
            postInvalidateOnAnimation()
        }
    }

    private fun setScroll(x: Float, y: Float) {
        scrollXFloat = x.coerceIn(0f, maxHorizontalScroll())
        scrollYFloat = y.coerceIn(0f, maxVerticalScroll())
        invalidate()
    }

    private fun maxVerticalScroll(): Float = max(0f, (document?.lineCount ?: 0) * lineHeight - contentHeight)
    private fun maxHorizontalScroll(): Float = max(0f, maximumObservedLineWidth - contentWidth)

    private fun positionForPoint(x: Float, y: Float): Long {
        val value = document ?: return 0
        if (value.lineCount == 0) return 0
        val lineIndex = floor((y - paddingTop + scrollYFloat) / lineHeight).toInt().coerceIn(0, value.lineCount - 1)
        val text = value.line(lineIndex)
        val target = x - paddingLeft + scrollXFloat
        var low = 0
        var high = text.length
        while (low < high) {
            val middle = (low + high + 1) / 2
            if (measuredPrefix(text, middle) <= target) low = middle else high = middle - 1
        }
        val column = if (low < text.length && target - measuredPrefix(text, low) >
            (measuredPrefix(text, low + 1) - measuredPrefix(text, low)) / 2f) low + 1 else low
        return value.positionAt(lineIndex, column)
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
            InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN
        outAttrs.initialSelStart = cursor.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        outAttrs.initialSelEnd = outAttrs.initialSelStart
        return DocumentInputConnection()
    }

    private inner class DocumentInputConnection : BaseInputConnection(this@LargeDocumentView, false) {
        override fun commitText(text: CharSequence, newCursorPosition: Int): Boolean =
            applyInputEdit(text, newCursorPosition, keepComposing = false)

        override fun setComposingText(text: CharSequence, newCursorPosition: Int): Boolean =
            applyInputEdit(text, newCursorPosition, keepComposing = true)

        override fun finishComposingText(): Boolean {
            clearComposing()
            return true
        }

        override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean =
            deleteSurrounding(beforeLength, afterLength, lengthsAreCodePoints = false)

        override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean =
            deleteSurrounding(beforeLength, afterLength, lengthsAreCodePoints = true)

        override fun setSelection(start: Int, end: Int): Boolean {
            val length = document?.length ?: return false
            clearComposing()
            if (start == end) {
                cursor = normalizeBoundary(start.toLong().coerceIn(0, length), forward = true)
                anchor = cursor
            } else {
                val low = normalizeBoundary(minOf(start, end).toLong().coerceIn(0, length), forward = false)
                val high = normalizeBoundary(maxOf(start, end).toLong().coerceIn(0, length), forward = true)
                if (start < end) {
                    anchor = low
                    cursor = high
                } else {
                    anchor = high
                    cursor = low
                }
            }
            selectionChanged()
            return true
        }

        override fun getTextBeforeCursor(length: Int, flags: Int): CharSequence = boundedAroundCursor(length, before = true)
        override fun getTextAfterCursor(length: Int, flags: Int): CharSequence = boundedAroundCursor(length, before = false)
        override fun getSelectedText(flags: Int): CharSequence? {
            val value = document ?: return null
            val start = selectionStart()
            val end = selectionEnd()
            if (start == end) return null
            val boundedEnd = normalizeBoundary(minOf(end, start + MAX_SURROUNDING_TEXT), forward = true)
            return value.text(normalizeBoundary(start, forward = false), boundedEnd)
        }

        override fun getExtractedText(request: ExtractedTextRequest, flags: Int): ExtractedText {
            val value = document
            val approximateStart = (cursor - MAX_SURROUNDING_TEXT / 2).coerceAtLeast(0)
            val start = normalizeBoundary(approximateStart, forward = false)
            val end = normalizeBoundary(minOf(value?.length ?: 0, start + MAX_SURROUNDING_TEXT), forward = true)
            return ExtractedText().apply {
                text = value?.text(start, end) ?: ""
                startOffset = start.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                selectionStart = (cursor - start).coerceAtLeast(0).toInt()
                selectionEnd = selectionStart
                partialStartOffset = -1
                partialEndOffset = -1
            }
        }

        override fun performContextMenuAction(id: Int): Boolean = performEditorAction(id)
    }

    private fun boundedAroundCursor(requestedLength: Int, before: Boolean): CharSequence {
        val value = document ?: return ""
        val count = requestedLength.coerceIn(0, MAX_SURROUNDING_TEXT)
        val approximateStart = if (before) (cursor - count).coerceAtLeast(0) else cursor
        val approximateEnd = if (before) cursor else (cursor + count).coerceAtMost(value.length)
        val start = normalizeBoundary(approximateStart, forward = false)
        val end = normalizeBoundary(approximateEnd, forward = true)
        return value.text(start, end)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val ctrl = event.isCtrlPressed
        if (ctrl) when (keyCode) {
            KeyEvent.KEYCODE_A -> { selectAll(); return true }
            KeyEvent.KEYCODE_C -> return copySelection(cut = false)
            KeyEvent.KEYCODE_X -> return copySelection(cut = true)
            KeyEvent.KEYCODE_V -> return paste()
            KeyEvent.KEYCODE_Z -> return if (event.isShiftPressed) requestRedo() else requestUndo()
            KeyEvent.KEYCODE_Y -> return requestRedo()
        }
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT -> moveHorizontal(-1, event.isShiftPressed)
            KeyEvent.KEYCODE_DPAD_RIGHT -> moveHorizontal(1, event.isShiftPressed)
            KeyEvent.KEYCODE_DPAD_UP -> moveVertical(-1, event.isShiftPressed)
            KeyEvent.KEYCODE_DPAD_DOWN -> moveVertical(1, event.isShiftPressed)
            KeyEvent.KEYCODE_MOVE_HOME -> moveToLineBoundary(false, event.isShiftPressed)
            KeyEvent.KEYCODE_MOVE_END -> moveToLineBoundary(true, event.isShiftPressed)
            KeyEvent.KEYCODE_DEL -> deleteBackward()
            KeyEvent.KEYCODE_FORWARD_DEL -> deleteForward()
            KeyEvent.KEYCODE_ENTER -> replaceSelection("\n")
            KeyEvent.KEYCODE_TAB -> replaceSelection("\t")
            else -> {
                val unicode = event.unicodeChar
                if (unicode != 0 && !ctrl && !event.isAltPressed) replaceSelection(String(Character.toChars(unicode))) else return super.onKeyDown(keyCode, event)
            }
        }
        return true
    }

    private fun moveHorizontal(delta: Int, extend: Boolean) {
        val value = document ?: return
        val target = if (delta < 0) previousCodePoint(cursor) else nextCodePoint(cursor)
        moveCursor(target.coerceIn(0, value.length), extend)
    }

    private fun moveVertical(delta: Int, extend: Boolean) {
        val value = document ?: return
        val location = value.locationAt(cursor)
        val column = preferredColumn ?: location.column
        val line = (location.line + delta).coerceIn(0, max(0, value.lineCount - 1))
        val target = value.positionAt(line, minOf(column, value.line(line).length))
        moveCursor(target, extend, preservePreferredColumn = true)
        preferredColumn = column
    }

    private fun moveToLineBoundary(end: Boolean, extend: Boolean) {
        val value = document ?: return
        val location = value.locationAt(cursor)
        moveCursor(value.positionAt(location.line, if (end) value.line(location.line).length else 0), extend)
    }

    private fun moveCursor(position: Long, extend: Boolean, preservePreferredColumn: Boolean = false) {
        val normalized = normalizeBoundary(position.coerceIn(0, document?.length ?: 0), forward = position >= cursor)
        cursor = normalized
        if (!extend) anchor = cursor
        if (!preservePreferredColumn) preferredColumn = null
        clearComposing()
        ensureCursorVisible()
        selectionChanged()
    }

    private fun ensureCursorVisible() {
        val value = document ?: return
        if (value.lineCount == 0) return
        val location = value.locationAt(cursor)
        val text = value.line(location.line)
        val x = measuredPrefix(text, location.column)
        val top = location.line * lineHeight
        var nextX = scrollXFloat
        var nextY = scrollYFloat
        if (x < nextX) nextX = x else if (x > nextX + contentWidth) nextX = x - contentWidth + density * 8
        if (top < nextY) nextY = top else if (top + lineHeight > nextY + contentHeight) nextY = top + lineHeight - contentHeight
        maximumObservedLineWidth = max(maximumObservedLineWidth, textPaint.measureText(text, 0, text.length))
        setScroll(nextX, nextY)
    }

    private fun applyInputEdit(text: CharSequence, newCursorPosition: Int, keepComposing: Boolean): Boolean {
        val value = document ?: return false
        val edit = InputEdits.replacement(
            selectionStart(), selectionEnd(), composingStart, composingEnd,
            text.length, newCursorPosition, keepComposing, value.length,
        )
        value.replace(edit.replaceStart, edit.replaceEnd, text)
        anchor = normalizeBoundary(edit.selection, forward = true)
        cursor = anchor
        composingStart = edit.composingStart
        composingEnd = edit.composingEnd
        preferredColumn = null
        onEdit?.onEdit(edit.replaceStart, edit.replaceEnd, edit.replaceStart + text.length)
        ensureCursorVisible()
        selectionChanged(textChanged = true)
        return true
    }

    private fun deleteSurrounding(beforeLength: Int, afterLength: Int, lengthsAreCodePoints: Boolean): Boolean {
        if (document == null) return false
        clearComposing()
        if (selectionStart() != selectionEnd()) return replaceSelection("")
        val before = beforeLength.coerceAtLeast(0)
        val after = afterLength.coerceAtLeast(0)
        val start = if (lengthsAreCodePoints) moveByCodePoints(cursor, -before)
        else normalizeBoundary((cursor - before).coerceAtLeast(0), forward = false)
        val end = if (lengthsAreCodePoints) moveByCodePoints(cursor, after)
        else normalizeBoundary((cursor + after).coerceAtMost(document?.length ?: 0), forward = true)
        replaceRange(start, end, "")
        return true
    }

    private fun replaceSelection(text: CharSequence): Boolean {
        if (document == null) return false
        clearComposing()
        replaceRange(selectionStart(), selectionEnd(), text)
        return true
    }

    private fun replaceRange(start: Long, end: Long, text: CharSequence): Long {
        val value = document ?: return cursor
        val newCursor = value.replace(start, end, text).coerceIn(0, value.length)
        anchor = newCursor
        cursor = newCursor
        preferredColumn = null
        onEdit?.onEdit(start, end, newCursor)
        ensureCursorVisible()
        selectionChanged(textChanged = true)
        return newCursor
    }

    private fun deleteBackward() {
        clearComposing()
        if (selectionStart() != selectionEnd()) replaceSelection("")
        else if (cursor > 0) replaceRange(previousCodePoint(cursor), cursor, "")
    }

    private fun deleteForward() {
        clearComposing()
        val length = document?.length ?: return
        if (selectionStart() != selectionEnd()) replaceSelection("")
        else if (cursor < length) replaceRange(cursor, nextCodePoint(cursor), "")
    }

    private fun normalizeBoundary(offset: Long, forward: Boolean): Long {
        val value = document ?: return 0
        val clamped = offset.coerceIn(0, value.length)
        if (clamped == 0L || clamped == value.length) return clamped
        val pair = value.text(clamped - 1, clamped + 1)
        if (pair.length == 2 && Character.isHighSurrogate(pair[0]) && Character.isLowSurrogate(pair[1])) {
            return clamped + if (forward) 1 else -1
        }
        return clamped
    }

    private fun previousCodePoint(offset: Long): Long {
        val value = document ?: return 0
        val end = normalizeBoundary(offset, forward = false)
        val start = (end - 2).coerceAtLeast(0)
        val text = value.text(start, end)
        return start + UnicodeOffsets.previous(text, text.length)
    }

    private fun nextCodePoint(offset: Long): Long {
        val value = document ?: return 0
        val start = normalizeBoundary(offset, forward = true)
        val end = (start + 2).coerceAtMost(value.length)
        val text = value.text(start, end)
        return start + UnicodeOffsets.next(text, 0)
    }

    private fun moveByCodePoints(offset: Long, count: Int): Long {
        var result = offset
        repeat(kotlin.math.abs(count)) {
            result = if (count < 0) previousCodePoint(result) else nextCodePoint(result)
        }
        return result
    }

    private fun selectAll() {
        clearComposing()
        anchor = 0
        cursor = document?.length ?: 0
        selectionChanged()
    }

    private fun clipboard(): ClipboardManager = context.getSystemService(ClipboardManager::class.java)

    private fun copySelection(cut: Boolean): Boolean {
        val value = document ?: return false
        val start = selectionStart()
        val end = selectionEnd()
        if (start == end) return false
        clipboard().setPrimaryClip(ClipData.newPlainText("Markdown", value.text(start, end)))
        if (cut) replaceSelection("")
        return true
    }

    private fun paste(): Boolean {
        val clip = clipboard().primaryClip ?: return false
        val text = clip.getItemAt(0).coerceToText(context) ?: return false
        return replaceSelection(text)
    }

    private fun requestUndo(): Boolean = onUndo?.onHistoryRequest()?.also { if (it) historyChanged() } ?: false
    private fun requestRedo(): Boolean = onRedo?.onHistoryRequest()?.also { if (it) historyChanged() } ?: false

    private fun historyChanged() {
        clearComposing()
        val value = document
        val length = value?.length ?: 0
        val restored = value?.selection()
        cursor = restored?.caret?.toLong()?.coerceAtMost(length) ?: cursor.coerceAtMost(length)
        anchor = restored?.anchor?.toLong()?.coerceAtMost(length) ?: anchor.coerceAtMost(length)
        ensureCursorVisible()
        invalidate()
        restartInput()
    }

    private fun performEditorAction(id: Int): Boolean = when (id) {
        android.R.id.selectAll -> { selectAll(); true }
        android.R.id.copy -> copySelection(false)
        android.R.id.cut -> copySelection(true)
        android.R.id.paste -> paste()
        android.R.id.undo -> requestUndo()
        android.R.id.redo -> requestRedo()
        else -> false
    }

    private fun startSelectionActionMode() {
        actionMode?.finish()
        actionMode = startActionMode(object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                menu.add(0, android.R.id.cut, 0, "Cut")
                menu.add(0, android.R.id.copy, 1, "Copy")
                menu.add(0, android.R.id.paste, 2, "Paste")
                menu.add(0, android.R.id.selectAll, 3, "Select all")
                return true
            }
            override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false
            override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean =
                performEditorAction(item.itemId).also { if (it) mode.finish() }
            override fun onDestroyActionMode(mode: ActionMode) { actionMode = null }
        }, ActionMode.TYPE_FLOATING)
    }

    private fun selectionChanged(textChanged: Boolean = false) {
        document?.setSelection(anchor, cursor)
        invalidate()
        actionMode?.invalidate()
        context.getSystemService(InputMethodManager::class.java)?.updateSelection(
            this,
            anchor.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            cursor.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            composingStart.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            composingEnd.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
        )
        sendAccessibilityEvent(if (textChanged) AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED else AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED)
    }

    private fun restartInput() {
        context.getSystemService(InputMethodManager::class.java)?.restartInput(this)
    }

    private fun clearComposing() {
        composingStart = -1
        composingEnd = -1
    }

    private fun finishComposingText() {
        clearComposing()
        context.getSystemService(InputMethodManager::class.java)?.restartInput(this)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.EditText"
        info.isEditable = true
        info.isMultiLine = true
        info.isFocusable = true
        info.isFocused = isFocused
        info.isScrollable = maxVerticalScroll() > 0 || maxHorizontalScroll() > 0
        val value = document
        if (value != null) {
            val location = value.locationAt(cursor)
            info.text = value.line(location.line).take(MAX_ACCESSIBILITY_TEXT)
        }
        info.setTextSelection(
            selectionStart().coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            selectionEnd().coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
        )
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_SELECTION)
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_TEXT)
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_COPY)
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CUT)
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_PASTE)
    }

    override fun performAccessibilityAction(action: Int, arguments: Bundle?): Boolean {
        when (action) {
            AccessibilityNodeInfo.ACTION_SET_SELECTION -> {
                val start = arguments?.getInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, cursor.toInt()) ?: return false
                val end = arguments.getInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, start)
                return DocumentInputConnection().setSelection(start, end)
            }
            AccessibilityNodeInfo.ACTION_SET_TEXT -> {
                val text = arguments?.getCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE) ?: return false
                selectAll()
                return replaceSelection(text)
            }
            AccessibilityNodeInfo.ACTION_COPY -> return copySelection(false)
            AccessibilityNodeInfo.ACTION_CUT -> return copySelection(true)
            AccessibilityNodeInfo.ACTION_PASTE -> return paste()
        }
        return super.performAccessibilityAction(action, arguments)
    }

    override fun onDetachedFromWindow() {
        actionMode?.finish()
        scroller.abortAnimation()
        finishComposingText()
        // A View may detach temporarily during Compose/layout transitions. The owning production
        // lifecycle releases the session explicitly through clearDocument().
        super.onDetachedFromWindow()
    }

    private companion object {
        const val MAX_SURROUNDING_TEXT = 8 * 1024
        const val MAX_ACCESSIBILITY_TEXT = 4 * 1024
    }
}
