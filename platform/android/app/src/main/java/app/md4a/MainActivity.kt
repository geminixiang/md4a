package app.md4a

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import app.md4a.editor.EditListener
import app.md4a.editor.HistoryRequestListener
import app.md4a.editor.LargeDocumentView
import app.md4a.editor.SessionSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    internal val document: DocumentViewModel by viewModels()
    internal var showingPreview by mutableStateOf(false)
        private set

    internal fun showPreviewForTest(value: Boolean) {
        showingPreview = value
    }

    internal fun openDefaultHandlerSettings() {
        val openByDefault = Intent(
            Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS,
            Uri.parse("package:$packageName"),
        )
        val destination = DefaultHandlerOnboarding.destination(
            canOpenDefaultSettings = openByDefault.resolveActivity(packageManager) != null,
        )
        val settingsIntent = when (destination) {
            DefaultHandlerDestination.OpenByDefaultSettings -> openByDefault
            DefaultHandlerDestination.ApplicationDetailsSettings -> Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        startActivity(settingsIntent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        document.initialize(contentResolver, intent.data)
        setContent { MaterialTheme { MarkdownScreen(document) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = intent.data ?: return
        if (document.isRestoring) {
            document.queueLaunchUri(uri)
        } else if (document.isDirty) {
            document.reportError("Save or discard the current edits before opening another document")
        } else {
            document.open(contentResolver, uri)
        }
    }
}

private sealed interface PendingReplacement {
    data object New : PendingReplacement
    data object Exit : PendingReplacement
    data class Open(val uri: android.net.Uri) : PendingReplacement
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MarkdownScreen(document: DocumentViewModel = viewModel()) {
    val context = LocalContext.current
    val activity = context as? MainActivity
    var pendingReplacement by remember { mutableStateOf<PendingReplacement?>(null) }
    var showDefaultHandlerPrompt by remember { mutableStateOf(false) }
    val defaultHandlerPreferences = remember {
        context.getSharedPreferences(
            DefaultHandlerOnboarding.preferencesName,
            Context.MODE_PRIVATE,
        )
    }
    val preview = activity?.showingPreview ?: false
    val snackbar = remember { SnackbarHostState() }
    val openDocument = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let {
            try {
                context.contentResolver.takePersistableUriPermission(
                    it,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // Some providers grant access only for this app session.
            }
            if (document.isDirty) pendingReplacement = PendingReplacement.Open(it)
            else document.open(context.contentResolver, it)
        }
    }
    val createDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/markdown"),
    ) { uri -> uri?.let { document.save(context.contentResolver, it) } }

    LaunchedEffect(Unit) {
        val hasAsked = defaultHandlerPreferences.getBoolean(
            DefaultHandlerOnboarding.askedKey,
            false,
        )
        if (DefaultHandlerOnboarding.shouldAsk(hasAsked)) {
            defaultHandlerPreferences.edit()
                .putBoolean(DefaultHandlerOnboarding.askedKey, true)
                .apply()
            showDefaultHandlerPrompt = true
        }
    }

    LaunchedEffect(document.pendingLaunchUri, document.isRestoring) {
        val uri = document.pendingLaunchUri
        if (!document.isRestoring && uri != null) pendingReplacement = PendingReplacement.Open(uri)
    }

    BackHandler(enabled = document.isDirty) {
        pendingReplacement = PendingReplacement.Exit
    }

    LaunchedEffect(pendingReplacement, document.isDirty, document.isSaving) {
        if (pendingReplacement == PendingReplacement.Exit && !document.isDirty && !document.isSaving) {
            pendingReplacement = null
            activity?.finish()
        }
    }

    LaunchedEffect(document.errorMessage) {
        document.errorMessage?.let {
            snackbar.showSnackbar(it)
            document.clearError()
        }
    }

    if (showDefaultHandlerPrompt) {
        AlertDialog(
            onDismissRequest = { showDefaultHandlerPrompt = false },
            title = { Text("Open Markdown with md4a?") },
            text = {
                Text(
                    "Android does not let apps change this automatically. " +
                        "When you next open a Markdown file, choose md4a and tap Always. " +
                        "You can review md4a's Open by default settings now.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDefaultHandlerPrompt = false
                    activity?.openDefaultHandlerSettings()
                }) { Text("Open settings") }
            },
            dismissButton = {
                TextButton(onClick = { showDefaultHandlerPrompt = false }) { Text("Not now") }
            },
        )
    }

    pendingReplacement?.let { pending ->
        AlertDialog(
            onDismissRequest = { pendingReplacement = null },
            title = { Text("Discard unsaved changes?") },
            text = { Text(if (pending == PendingReplacement.Exit) "Save the document or discard your edits before leaving." else "This will replace the current edits.") },
            confirmButton = {
                Row {
                    if (pending == PendingReplacement.Exit && document.documentUri != null) {
                        TextButton(
                            enabled = !document.isSaving,
                            onClick = { document.save(context.contentResolver, document.documentUri!!) },
                        ) { Text("Save") }
                    }
                    TextButton(onClick = {
                        when (pending) {
                            PendingReplacement.New -> document.newDocument()
                            PendingReplacement.Exit -> {
                                document.discardRecoveryDraft()
                                activity?.finish()
                            }
                            is PendingReplacement.Open -> document.open(context.contentResolver, pending.uri)
                        }
                        document.consumePendingLaunchUri()
                        activity?.showPreviewForTest(false)
                        pendingReplacement = null
                    }) { Text("Discard") }
                }
            },
            dismissButton = { TextButton(onClick = {
                document.consumePendingLaunchUri()
                pendingReplacement = null
            }) { Text("Cancel") } },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { Text((if (document.isDirty) "• " else "") + document.title) },
                actions = {
                    TextButton(
                        onClick = { activity?.openDefaultHandlerSettings() },
                    ) { Text("Defaults") }
                    TextButton(
                        onClick = {
                            if (document.isDirty) pendingReplacement = PendingReplacement.New
                            else { document.newDocument(); activity?.showPreviewForTest(false) }
                        },
                        enabled = !document.isLoading && !document.isSaving,
                    ) { Text("New") }
                    TextButton(
                        onClick = { openDocument.launch(arrayOf("text/markdown", "text/plain")) },
                        enabled = !document.isLoading && !document.isSaving,
                    ) { Text("Open") }
                    TextButton(
                        onClick = {
                            document.documentUri?.let { document.save(context.contentResolver, it) }
                                ?: createDocument.launch(document.title)
                        },
                        enabled = !document.isLoading && !document.isSaving,
                    ) { Text(if (document.isSaving) "Saving…" else "Save") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(onClick = { activity?.showPreviewForTest(false) }, enabled = preview && !document.isLoading) { Text("Edit") }
                Button(onClick = { activity?.showPreviewForTest(true) }, enabled = !preview && !document.isLoading) { Text("Preview") }
            }
            Box(Modifier.fillMaxSize().padding(12.dp)) {
                when {
                    document.isRestoring -> LoadingMessage("Recovering unsaved document…")
                    document.isLoading -> LoadingMessage("Opening document…")
                    preview -> {
                        val revision = document.observedRevision
                        val snapshot = remember(document.session, revision) { document.previewSnapshot() }
                        Preview(snapshot)
                    }
                    else -> Editor(document)
                }
            }
        }
    }
}

@Composable
private fun Editor(document: DocumentViewModel) {
    // Read this small revision state so the title/dirty state and history redraw stay observable.
    document.observedRevision
    val textColor = MaterialTheme.colorScheme.onBackground.toArgb()
    val accentColor = MaterialTheme.colorScheme.primary.toArgb()
    val selectionColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.35f).toArgb()
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context -> LargeDocumentView(context) },
        update = { view ->
            view.setDocument(document.session)
            view.onEdit = EditListener { _, _, _ -> document.documentEdited() }
            view.onUndo = HistoryRequestListener { document.undo() }
            view.onRedo = HistoryRequestListener { document.redo() }
            view.updateColors(textColor, accentColor, selectionColor)
        },
        onRelease = { it.clearDocument() },
    )
}

@Composable
private fun Preview(snapshot: SessionSnapshot) {
    var html by remember(snapshot.revision, snapshot.document) { mutableStateOf<String?>(null) }
    var renderError by remember(snapshot.revision, snapshot.document) { mutableStateOf<String?>(null) }

    LaunchedEffect(snapshot.revision, snapshot.document) {
        html = null
        renderError = null
        val result = withContext(Dispatchers.Default) {
            runCatching {
                // JNI currently accepts String; this is the one explicit full-document render seam.
                previewDocument(NativeRenderer.render(snapshot.document.toString()))
            }
        }
        result.fold(
            onSuccess = { html = it },
            onFailure = { renderError = it.message ?: "Unknown error" },
        )
    }

    val rendered = html
    if (rendered == null) {
        LoadingMessage(renderError?.let { "Preview failed: $it" } ?: "Rendering preview…", renderError == null)
        return
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
        update = { webView ->
            if (webView.tag != snapshot.revision) {
                webView.tag = snapshot.revision
                webView.loadDataWithBaseURL(null, rendered, "text/html", "UTF-8", null)
            }
        },
        onRelease = { webView ->
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.removeAllViews()
            webView.destroy()
        },
    )
}

@Composable
private fun LoadingMessage(message: String, spinning: Boolean = true) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (spinning) CircularProgressIndicator()
            Text(message)
        }
    }
}
