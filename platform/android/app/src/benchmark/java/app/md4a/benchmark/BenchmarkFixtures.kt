package app.md4a.benchmark

import java.io.File

internal const val TARGET_BYTES = 8_841_392

internal data class BenchmarkFixture(val name: String, val text: String, val source: String)

internal object BenchmarkFixtures {
    fun primary(exactPath: String?): BenchmarkFixture {
        val file = exactPath?.let(::File)
        return if (file?.isFile == true) {
            val text = file.inputStream().buffered().reader(Charsets.UTF_8).use { it.readText() }
            BenchmarkFixture("8mb-md", text, file.absolutePath)
        } else {
            synthetic("synthetic-8mb", "Paragraph **bold** [link](https://example.invalid) payload 0123456789\n")
        }
    }

    fun matrix(exactPath: String?): List<BenchmarkFixture> = listOf(
        primary(exactPath),
        synthetic("long-line", "x".repeat(65_536) + "\n"),
        synthetic("crlf", "alpha beta gamma\r\n"),
        synthetic("unicode", "中文 😀 café हिन्दी العربية 日本語 한글\n"),
        synthetic("markup-heavy", "# Heading\n- [x] **bold** and `code` [link](https://example.invalid)\n> quote\n```kotlin\nval x = 1\n```\n"),
    )

    private fun synthetic(name: String, unit: String): BenchmarkFixture {
        val bytes = unit.toByteArray(Charsets.UTF_8)
        val output = java.io.ByteArrayOutputStream(TARGET_BYTES)
        while (output.size() + bytes.size <= TARGET_BYTES) output.write(bytes)
        val remaining = TARGET_BYTES - output.size()
        if (remaining > 0) output.write("x".repeat(remaining).toByteArray(Charsets.UTF_8))
        return BenchmarkFixture(name, output.toString(Charsets.UTF_8.name()), "deterministic-generated")
    }
}
