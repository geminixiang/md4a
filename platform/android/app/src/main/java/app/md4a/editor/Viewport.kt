package app.md4a.editor

internal fun visibleLineRange(
    lineCount: Int,
    scrollY: Float,
    viewportHeight: Int,
    lineHeight: Float,
    overscan: Int = 1,
): IntRange? {
    if (lineCount <= 0 || viewportHeight <= 0 || lineHeight <= 0f) return null
    val firstVisible = kotlin.math.floor(scrollY.coerceAtLeast(0f) / lineHeight).toInt()
    val visibleCount = kotlin.math.ceil(viewportHeight / lineHeight).toInt()
    val first = (firstVisible - overscan).coerceAtLeast(0)
    val last = (firstVisible + visibleCount + overscan).coerceAtMost(lineCount - 1)
    return first..last
}
