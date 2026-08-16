package app.md4a

object NativeRenderer {
    init {
        System.loadLibrary("md4a_android")
    }

    fun render(markdown: String): String = renderUtf8(markdown.toByteArray(Charsets.UTF_8)).toString(Charsets.UTF_8)

    private external fun renderUtf8(markdown: ByteArray): ByteArray
}
