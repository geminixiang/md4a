package app.md4a

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.lifecycle.viewmodel.compose.viewModel

class MainActivity : ComponentActivity() {
    private val document: DocumentViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            intent.data?.let { document.open(contentResolver, it) }
        }
        setContent {
            MaterialTheme {
                MarkdownScreen(document)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (document.isDirty) {
            document.reportError("Save or discard the current edits before opening another document")
        } else {
            intent.data?.let { document.open(contentResolver, it) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MarkdownScreen(document: DocumentViewModel = viewModel()) {
    val context = LocalContext.current
    var preview by remember { mutableStateOf(false) }
    var pendingOpenUri by remember { mutableStateOf<android.net.Uri?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val openDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        uri?.let {
            try {
                context.contentResolver.takePersistableUriPermission(
                    it,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // Some document providers grant access only for this app session.
            }
            if (document.isDirty) {
                pendingOpenUri = it
                confirmDiscard = true
            } else {
                document.open(context.contentResolver, it)
            }
        }
    }
    val createDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/markdown"),
    ) { uri -> uri?.let { document.save(context.contentResolver, it) } }

    LaunchedEffect(document.errorMessage) {
        document.errorMessage?.let {
            snackbar.showSnackbar(it)
            document.clearError()
        }
    }

    if (confirmDiscard) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = {
                confirmDiscard = false
                pendingOpenUri = null
            },
            title = { Text("Discard unsaved changes?") },
            text = { Text("Opening another document will replace the current edits.") },
            confirmButton = {
                TextButton(onClick = {
                    pendingOpenUri?.let { document.open(context.contentResolver, it) }
                    pendingOpenUri = null
                    confirmDiscard = false
                }) { Text("Discard and Open") }
            },
            dismissButton = {
                TextButton(onClick = {
                    pendingOpenUri = null
                    confirmDiscard = false
                }) { Text("Cancel") }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { Text((if (document.isDirty) "• " else "") + document.title) },
                actions = {
                    TextButton(onClick = { openDocument.launch(arrayOf("text/markdown", "text/plain")) }) { Text("Open") }
                    TextButton(onClick = {
                        document.documentUri?.let { document.save(context.contentResolver, it) }
                            ?: createDocument.launch(document.title)
                    }) { Text("Save") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { preview = !preview }, enabled = preview) { Text("Edit") }
                Button(onClick = { preview = !preview }, enabled = !preview) { Text("Preview") }
            }
            Box(Modifier.fillMaxSize().padding(12.dp)) {
                if (preview) {
                    Preview(document.markdown)
                } else {
                    BasicTextField(
                        value = document.markdown,
                        onValueChange = document::edit,
                        modifier = Modifier.fillMaxSize(),
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onBackground),
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    )
                }
            }
        }
    }
}

@Composable
private fun Preview(markdown: String) {
    val html = remember(markdown) {
        runCatching { previewDocument(NativeRenderer.render(markdown)) }
            .getOrElse { previewDocument("<p>Preview failed: ${it.message ?: "unknown error"}</p>") }
    }
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = false
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean = true
                }
            }
        },
        update = { webView -> webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null) },
    )
}
