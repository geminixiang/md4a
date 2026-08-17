package app.md4a

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultHandlerOnboardingTest {
    @Test
    fun asksOnlyBeforeChoiceHasBeenRecorded() {
        assertTrue(DefaultHandlerOnboarding.shouldAsk(hasAsked = false))
        assertFalse(DefaultHandlerOnboarding.shouldAsk(hasAsked = true))
    }

    @Test
    fun prefersOpenByDefaultSettingsAndFallsBackToAppDetails() {
        assertEquals(
            DefaultHandlerDestination.OpenByDefaultSettings,
            DefaultHandlerOnboarding.destination(canOpenDefaultSettings = true),
        )
        assertEquals(
            DefaultHandlerDestination.ApplicationDetailsSettings,
            DefaultHandlerOnboarding.destination(canOpenDefaultSettings = false),
        )
    }
}
