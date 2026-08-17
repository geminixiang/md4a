package app.md4a

internal enum class DefaultHandlerDestination {
    OpenByDefaultSettings,
    ApplicationDetailsSettings,
}

internal object DefaultHandlerOnboarding {
    const val preferencesName = "default_handler_onboarding"
    const val askedKey = "asked"

    fun shouldAsk(hasAsked: Boolean): Boolean = !hasAsked

    fun destination(canOpenDefaultSettings: Boolean): DefaultHandlerDestination =
        if (canOpenDefaultSettings) DefaultHandlerDestination.OpenByDefaultSettings
        else DefaultHandlerDestination.ApplicationDetailsSettings
}
