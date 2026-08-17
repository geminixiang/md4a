package app.md4a.benchmark

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

/** App-private instrumentation provider exercising production ContentResolver open/save paths. */
class BenchmarkDocumentProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val name = uri.lastPathSegment?.takeIf { it.matches(Regex("[A-Za-z0-9._-]+")) }
            ?: throw IllegalArgumentException("Invalid test document name")
        val file = File(requireNotNull(context).filesDir, name)
        val flags = if (mode.contains('w')) {
            file.parentFile?.mkdirs()
            ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE or ParcelFileDescriptor.MODE_READ_WRITE
        } else ParcelFileDescriptor.MODE_READ_ONLY
        return ParcelFileDescriptor.open(file, flags)
    }

    override fun getType(uri: Uri): String = "text/markdown"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val file = File(requireNotNull(context).filesDir, requireNotNull(uri.lastPathSegment))
        return MatrixCursor(columns).apply { addRow(columns.map { if (it == OpenableColumns.SIZE) file.length() else file.name }) }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
