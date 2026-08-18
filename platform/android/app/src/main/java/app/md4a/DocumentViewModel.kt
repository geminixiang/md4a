package app.md4a

import android.app.Application
import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.md4a.editor.DocumentSession
import app.md4a.editor.DraftMetadata
import app.md4a.editor.DraftStore
import app.md4a.editor.SessionSnapshot
import java.io.File
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DocumentViewModel(application: Application) : AndroidViewModel(application) {
    var session by mutableStateOf(DocumentSession(INITIAL_MARKDOWN))
        private set
    var documentUri by mutableStateOf<Uri?>(null)
        private set
    var title by mutableStateOf("Untitled.md")
        private set
    var isLoading by mutableStateOf(false)
        private set
    var isRestoring by mutableStateOf(true)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var pendingLaunchUri by mutableStateOf<Uri?>(null)
        private set
    var isDirty by mutableStateOf(session.isDirty)
        private set
    var observedRevision by mutableLongStateOf(session.revision)
        private set

    private val draftStore = DraftStore(File(application.filesDir, "recovery"))
    private var sessionToken = newToken()
    private var initialized = false
    private var openJob: Job? = null
    private var draftJob: Job? = null
    private var openGeneration = 0L

    /** Recovery always resolves before launch activation, and a recovered draft wins. */
    fun initialize(resolver: ContentResolver, launchUri: Uri?) {
        if (initialized) return
        initialized = true
        isRestoring = true
        viewModelScope.launch {
            val recovered = try {
                withContext(Dispatchers.IO) {
                    draftStore.recover()?.let { it to DocumentSession(it.text, initiallyDirty = true) }
                }
            } catch (error: IOException) {
                errorMessage = error.message
                null
            }
            if (recovered != null) {
                session = recovered.second
                sessionToken = recovered.first.metadata.token
                documentUri = recovered.first.metadata.originalUri?.let(Uri::parse)
                title = recovered.first.metadata.title
                pendingLaunchUri = launchUri
                syncSessionState()
            } else if (launchUri != null) {
                open(resolver, launchUri, clearDraft = false)
            }
            isRestoring = false
        }
    }

    fun queueLaunchUri(uri: Uri) {
        pendingLaunchUri = uri
    }

    fun newDocument() {
        replaceSession(DocumentSession(""), null, "Untitled.md", clearDraft = true)
        errorMessage = null
    }

    fun open(resolver: ContentResolver, uri: Uri, clearDraft: Boolean = true) {
        if (clearDraft) invalidateAndClearDraft()
        openJob?.cancel()
        val generation = ++openGeneration
        isLoading = true
        errorMessage = null
        openJob = viewModelScope.launch {
            try {
                val (loaded, name) = withContext(Dispatchers.IO) {
                    val text = resolver.openInputStream(uri)?.use { input ->
                        val decoder = StandardCharsets.UTF_8.newDecoder()
                            .onMalformedInput(CodingErrorAction.REPORT)
                            .onUnmappableCharacter(CodingErrorAction.REPORT)
                        InputStreamReader(input, decoder).use { it.readText().removePrefix("\uFEFF") }
                    } ?: throw IOException("Unable to open document")
                    DocumentSession(text) to displayName(resolver, uri, "Document.md")
                }
                if (generation != openGeneration) return@launch
                replaceSession(loaded, uri, name, clearDraft = false)
                errorMessage = null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: IOException) {
                if (generation == openGeneration) errorMessage = error.message ?: "Unable to open document"
            } catch (error: SecurityException) {
                if (generation == openGeneration) errorMessage = error.message ?: "Permission denied"
            } finally {
                if (generation == openGeneration) isLoading = false
            }
        }
    }

    fun save(resolver: ContentResolver, uri: Uri) {
        val savingSession = session
        val savingToken = sessionToken
        val snapshot = savingSession.snapshot()
        isSaving = true
        errorMessage = null
        viewModelScope.launch {
            try {
                val name = withContext(Dispatchers.IO) {
                    resolver.openOutputStream(uri, "wt")?.use { output ->
                        OutputStreamWriter(output, StandardCharsets.UTF_8).buffered().use(snapshot.document::appendTo)
                    } ?: throw IOException("Unable to save document")
                    displayName(resolver, uri, title)
                }
                if (session === savingSession && sessionToken == savingToken &&
                    savingSession.markSavedIfRevision(snapshot.revision)
                ) {
                    documentUri = uri
                    title = name
                    syncSessionState()
                    invalidateAndClearDraft()
                }
            } catch (error: IOException) {
                errorMessage = error.message ?: "Unable to save document"
            } catch (error: SecurityException) {
                errorMessage = error.message ?: "Permission denied"
            } finally {
                isSaving = false
            }
        }
    }

    fun documentEdited() {
        syncSessionState()
        errorMessage = null
        scheduleDraft()
    }

    fun undo(): Boolean = session.undo().also { changed ->
        if (changed) {
            syncSessionState()
            scheduleDraft()
        }
    }

    fun redo(): Boolean = session.redo().also { changed ->
        if (changed) {
            syncSessionState()
            scheduleDraft()
        }
    }

    fun previewSnapshot(): SessionSnapshot = session.snapshot()
    fun consumePendingLaunchUri() { pendingLaunchUri = null }
    fun discardRecoveryDraft() { invalidateAndClearDraft() }
    fun reportError(message: String) { errorMessage = message }
    fun clearError() { errorMessage = null }

    private fun scheduleDraft() {
        draftJob?.cancel()
        if (!session.isDirty) {
            invalidateAndClearDraft()
            return
        }
        val sourceSession = session
        val token = sessionToken
        // Reserve immediately so an older write can no longer publish after this edit.
        val reservation = draftStore.reserve()
        draftJob = viewModelScope.launch {
            delay(DRAFT_DEBOUNCE_MS)
            val snapshot = sourceSession.snapshot()
            val metadata = DraftMetadata(token, snapshot.revision, title, documentUri?.toString())
            try {
                withContext(Dispatchers.IO) {
                    draftStore.write(reservation, metadata, snapshot.document::appendTo)
                }
            } catch (error: IOException) {
                if (session === sourceSession && sessionToken == token) {
                    errorMessage = "Could not preserve recovery draft: ${error.message ?: "storage error"}"
                }
            }
        }
    }

    private fun replaceSession(value: DocumentSession, uri: Uri?, name: String, clearDraft: Boolean) {
        cancelOpen()
        if (clearDraft) invalidateAndClearDraft()
        session = value
        sessionToken = newToken()
        documentUri = uri
        pendingLaunchUri = null
        title = name
        isLoading = false
        syncSessionState()
    }

    private fun syncSessionState() {
        observedRevision = session.revision
        isDirty = session.isDirty
    }

    private fun invalidateAndClearDraft() {
        draftJob?.cancel()
        draftJob = null
        draftStore.clear()
    }

    private fun cancelOpen() {
        openJob?.cancel()
        openJob = null
        openGeneration++
    }

    private fun displayName(resolver: ContentResolver, uri: Uri, fallback: String): String {
        val providerName = try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst() && !cursor.isNull(column)) {
                    cursor.getString(column)?.takeIf(String::isNotBlank)
                } else {
                    null
                }
            }
        } catch (_: RuntimeException) {
            null
        }
        return providerName
            ?: uri.takeUnless { it.scheme == ContentResolver.SCHEME_CONTENT }
                ?.lastPathSegment?.substringAfterLast('/')?.takeIf(String::isNotBlank)
            ?: fallback
    }

    private fun newToken(): String = UUID.randomUUID().toString()

    private companion object {
        const val DRAFT_DEBOUNCE_MS = 750L
        const val INITIAL_MARKDOWN = "# md4a\n\nOpen a Markdown file or start editing."
    }
}
