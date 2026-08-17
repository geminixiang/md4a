package app.md4a.benchmark

/** Dependency-free JVM entry point used by the Gradle `largeDocumentBenchmark` task. */
object BenchmarkCli {
    @JvmStatic
    fun main(args: Array<String>) {
        val arguments = args.mapNotNull { value -> value.substringBefore('=', "").takeIf { value.startsWith("--") }?.let { it to value.substringAfter('=', "") } }.toMap()
        val exact = arguments["--fixture"]?.takeIf(String::isNotBlank)
        val warmups = arguments["--warmups"]?.toIntOrNull() ?: 1
        val repetitions = arguments["--repetitions"]?.toIntOrNull() ?: 5
        val environment = mapOf(
            "runtime" to "jvm",
            "java_vm" to System.getProperty("java.vm.name"),
            "java_version" to System.getProperty("java.version"),
            "os" to "${System.getProperty("os.name")} ${System.getProperty("os.version")} ${System.getProperty("os.arch")}",
            "warmups" to warmups.toString(),
            "repetitions" to repetitions.toString(),
        )
        BenchmarkFixtures.matrix(exact).forEach { fixture ->
            println("MD4A_BENCHMARK ${BufferBenchmark(warmups, repetitions).run(fixture).toJson(environment)}")
        }
    }
}
