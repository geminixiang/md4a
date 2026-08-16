package app.md4a

import android.content.ContentResolver
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import java.io.IOException

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

    fun edit(value: String) {
        markdown = value
        isDirty = true
        errorMessage = null
    }

    fun open(resolver: ContentResolver, uri: Uri) {
        try {
            markdown = resolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: throw IOException("Unable to open document")
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

    fun save(resolver: ContentResolver, uri: Uri): Boolean {
        return try {
            resolver.openOutputStream(uri, "wt")?.bufferedWriter()?.use { it.write(markdown) }
                ?: throw IOException("Unable to save document")
            documentUri = uri
            title = uri.lastPathSegment?.substringAfterLast('/') ?: title
            isDirty = false
            errorMessage = null
            true
        } catch (error: IOException) {
            errorMessage = error.message ?: "Unable to save document"
            false
        } catch (error: SecurityException) {
            errorMessage = error.message ?: "Permission denied"
            false
        }
    }

    fun reportError(message: String) {
        errorMessage = message
    }

    fun clearError() {
        errorMessage = null
    }
}
