package app.md4a

import android.content.ContentResolver
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DocumentViewModel : ViewModel() {
    var markdown by mutableStateOf("# md4a\n\nOpen a Markdown file or start editing.")
        private set
    var documentUri by mutableStateOf<Uri?>(null)
        private set
    var title by mutableStateOf("Untitled.md")
        private set
    var isDirty by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set

    // Compose's text field lays out the whole string; past this size that
    // freezes or exhausts memory, so large documents stay preview-only.
    val isEditable: Boolean get() = markdown.length <= MAX_EDITABLE_CHARS

    fun edit(value: String) {
        markdown = value
        isDirty = true
        errorMessage = null
    }

    fun open(resolver: ContentResolver, uri: Uri) {
        viewModelScope.launch {
            try {
                val text = withContext(Dispatchers.IO) {
                    resolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                        ?: throw IOException("Unable to open document")
                }
                markdown = text
                documentUri = uri
                title = uri.lastPathSegment?.substringAfterLast('/') ?: "Document.md"
                isDirty = false
                errorMessage = null
            } catch (error: IOException) {
                errorMessage = error.message ?: "Unable to open document"
            } catch (error: SecurityException) {
                errorMessage = error.message ?: "Permission denied"
            }
        }
    }

    fun save(resolver: ContentResolver, uri: Uri) {
        viewModelScope.launch {
            try {
                val text = markdown
                withContext(Dispatchers.IO) {
                    resolver.openOutputStream(uri, "wt")?.bufferedWriter()?.use { it.write(text) }
                        ?: throw IOException("Unable to save document")
                }
                documentUri = uri
                title = uri.lastPathSegment?.substringAfterLast('/') ?: title
                isDirty = false
                errorMessage = null
            } catch (error: IOException) {
                errorMessage = error.message ?: "Unable to save document"
            } catch (error: SecurityException) {
                errorMessage = error.message ?: "Permission denied"
            }
        }
    }

    fun reportError(message: String) {
        errorMessage = message
    }

    fun clearError() {
        errorMessage = null
    }

    private companion object {
        const val MAX_EDITABLE_CHARS = 512 * 1024
    }
}
