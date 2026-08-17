package app.md4a.editor

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Properties

/** Metadata identifying the exact editor revision captured by a recoverable draft. */
data class DraftMetadata(
    val token: String,
    val revision: Long,
    val title: String,
    val originalUri: String?,
)

data class RecoveredDraft(val metadata: DraftMetadata, val text: String)
class DraftReservation internal constructor(val generation: Long)

/**
 * Atomic app-private draft persistence. Reservations make delayed/older writers harmless after a
 * newer edit or clear. The manifest is published last and is the only recovery commit point.
 */
class DraftStore(private val directory: File) {
    private val lock = Any()
    private var generation = 0L

    fun reserve(): DraftReservation = synchronized(lock) { DraftReservation(++generation) }

    @Throws(IOException::class)
    fun write(reservation: DraftReservation, metadata: DraftMetadata, writeText: (Appendable) -> Unit): Boolean {
        directory.mkdirs()
        val textName = "draft-${reservation.generation}.txt"
        val textTemp = File(directory, "$textName.tmp")
        val metadataTemp = File(directory, "draft-${reservation.generation}.properties.tmp")
        try {
            Files.newBufferedWriter(textTemp.toPath(), StandardCharsets.UTF_8).use(writeText)
            Properties().apply {
                setProperty("token", metadata.token)
                setProperty("revision", metadata.revision.toString())
                setProperty("title", metadata.title)
                metadata.originalUri?.let { setProperty("uri", it) }
                setProperty("text", textName)
            }.storeUtf8(metadataTemp)
            synchronized(lock) {
                if (reservation.generation != generation) return false
                atomicMove(textTemp, File(directory, textName))
                atomicMove(metadataTemp, File(directory, MANIFEST_FILE))
                deleteObsoleteFiles()
                return true
            }
        } finally {
            textTemp.delete()
            metadataTemp.delete()
        }
    }

    /** Invalidates in-flight writers before removing the recovery commit point. */
    fun clear() {
        synchronized(lock) {
            generation++
            directory.listFiles()?.filter { it.name == MANIFEST_FILE || it.name.startsWith("draft-") }
                ?.forEach(File::delete)
            deleteObsoleteFiles()
        }
    }

    @Throws(IOException::class)
    fun recover(): RecoveredDraft? = synchronized(lock) {
        val manifest = File(directory, MANIFEST_FILE)
        if (!manifest.exists()) return null
        try {
            val properties = Files.newBufferedReader(manifest.toPath(), StandardCharsets.UTF_8).use { reader ->
                Properties().apply { load(reader) }
            }
            val metadata = DraftMetadata(
                token = properties.required("token"),
                revision = properties.required("revision").toLong(),
                title = properties.required("title"),
                originalUri = properties.getProperty("uri"),
            )
            val textName = properties.required("text")
            if (!textName.matches(Regex("draft-[0-9]+\\.txt"))) throw IOException("Invalid draft text path")
            val textFile = File(directory, textName)
            if (!textFile.isFile) throw IOException("Draft text is missing")
            RecoveredDraft(metadata, Files.newBufferedReader(textFile.toPath(), StandardCharsets.UTF_8).use(BufferedReader::readText))
        } catch (error: Exception) {
            quarantine()
            throw IOException("The recovered draft was corrupt and has been quarantined", error)
        }
    }

    private fun quarantine() {
        val suffix = System.currentTimeMillis().toString()
        val manifest = File(directory, MANIFEST_FILE)
        val textName = runCatching {
            Files.newBufferedReader(manifest.toPath(), StandardCharsets.UTF_8).use { reader ->
                Properties().apply { load(reader) }.getProperty("text")
            }
        }.getOrNull()
        manifest.takeIf(File::exists)?.renameTo(File(directory, "corrupt-$suffix.properties"))
        textName?.takeIf { it.matches(Regex("draft-[0-9]+\\.txt")) }
            ?.let { File(directory, it) }
            ?.takeIf(File::exists)
            ?.renameTo(File(directory, "corrupt-$suffix.txt"))
    }

    private fun deleteObsoleteFiles() {
        val currentText = runCatching {
            Files.newBufferedReader(File(directory, MANIFEST_FILE).toPath(), StandardCharsets.UTF_8).use { reader ->
                Properties().apply { load(reader) }.getProperty("text")
            }
        }.getOrNull()
        directory.listFiles()?.filter {
            it.name.endsWith(".tmp") ||
                (it.name.startsWith("draft-") && it.name.endsWith(".txt") && it.name != currentText)
        }?.forEach(File::delete)
    }

    private fun Properties.required(key: String): String =
        getProperty(key)?.takeIf(String::isNotEmpty) ?: throw IOException("Draft metadata is missing $key")

    private fun Properties.storeUtf8(file: File) {
        Files.newBufferedWriter(file.toPath(), StandardCharsets.UTF_8).use { writer: BufferedWriter -> store(writer, null) }
    }

    private fun atomicMove(source: File, destination: File) {
        try {
            Files.move(source.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private companion object {
        const val MANIFEST_FILE = "draft.properties"
    }
}
