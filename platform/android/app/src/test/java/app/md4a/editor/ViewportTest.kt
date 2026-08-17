package app.md4a.editor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ViewportTest {
    @Test
    fun readsOnlyViewportAndOverscanLines() {
        assertEquals(9..16, visibleLineRange(1_000_000, 100f, 50, 10f))
    }

    @Test
    fun clampsAtDocumentBoundaries() {
        assertEquals(0..6, visibleLineRange(7, 0f, 100, 20f))
        assertEquals(98..99, visibleLineRange(100, 990f, 30, 10f))
    }

    @Test
    fun emptyOrUnmeasuredViewportHasNoRange() {
        assertNull(visibleLineRange(0, 0f, 100, 10f))
        assertNull(visibleLineRange(10, 0f, 0, 10f))
    }
}
