#include <gtk/gtk.h>
#include <gtksourceview/gtksource.h>
#include <webkit/webkit.h>

#include <stdint.h>
#include <string.h>

#include "default_handler.h"
#include "md4a/md4a.h"

typedef struct {
  GtkWindow *window;
  GtkSourceBuffer *buffer;
  WebKitWebView *preview;
  GFile *file;
  guint preview_source;
  guint64 revision;
} Editor;

typedef struct {
  Editor *editor;
  char *contents;
  uint64_t revision;
} SaveOperation;

static const char *PAGE_PREFIX =
    "<!doctype html><html><head><meta charset=\"utf-8\"><meta "
    "http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; "
    "img-src data:; style-src 'unsafe-inline'\"><meta "
    "name=\"color-scheme\" content=\"light dark\"><style>body{font-family:system-ui,"
    "sans-serif;line-height:1.55;max-width:52rem;margin:0 auto;padding:2rem;}"
    "pre{overflow:auto;padding:1rem;background:color-mix(in srgb,currentColor 8%,"
    "transparent);}code{font-family:monospace;}img{max-width:100%;}table{border-"
    "collapse:collapse;}th,td{border:1px solid #888;padding:.35rem .6rem;}</style>"
    "</head><body>";
static const char *PAGE_SUFFIX = "</body></html>";
static const char *PREFERENCES_GROUP = "onboarding";
static const char *DEFAULT_HANDLER_ASKED_KEY = "default-handler-asked";

static char *preferences_path(void) {
  return g_build_filename(g_get_user_config_dir(), "md4a", "preferences.ini",
                          NULL);
}

static gboolean default_handler_was_asked(void) {
  GKeyFile *preferences = g_key_file_new();
  char *path = preferences_path();
  gboolean asked = g_key_file_load_from_file(preferences, path, G_KEY_FILE_NONE,
                                              NULL) &&
                   g_key_file_get_boolean(preferences, PREFERENCES_GROUP,
                                          DEFAULT_HANDLER_ASKED_KEY, NULL);
  g_free(path);
  g_key_file_unref(preferences);
  return asked;
}

static void remember_default_handler_was_asked(void) {
  GKeyFile *preferences = g_key_file_new();
  char *path = preferences_path();
  char *directory = g_path_get_dirname(path);
  GError *error = NULL;

  g_key_file_load_from_file(preferences, path, G_KEY_FILE_NONE, NULL);
  g_key_file_set_boolean(preferences, PREFERENCES_GROUP,
                         DEFAULT_HANDLER_ASKED_KEY, TRUE);
  if (g_mkdir_with_parents(directory, 0700) != 0 ||
      !g_key_file_save_to_file(preferences, path, &error)) {
    g_warning("Could not save onboarding preference: %s",
              error == NULL ? "could not create the configuration directory"
                            : error->message);
  }
  g_clear_error(&error);
  g_free(directory);
  g_free(path);
  g_key_file_unref(preferences);
}

static gboolean run_xdg_mime(const char *operation, const char *argument,
                             const char *mime_type, char **stdout_text,
                             GError **error) {
  const char *argv[] = {"xdg-mime", operation, argument, mime_type, NULL};
  int exit_status = 0;

  if (!g_spawn_sync(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL,
                    stdout_text, NULL, &exit_status, error)) {
    return FALSE;
  }
  return g_spawn_check_wait_status(exit_status, error);
}

static gboolean markdown_handler_is_default(const char *mime_type,
                                             GError **error) {
  char *output = NULL;
  gboolean succeeded = run_xdg_mime("query", "default", mime_type, &output,
                                    error);
  gboolean matches = succeeded && md4a_handler_output_matches(output);
  g_free(output);
  return matches;
}

static void show_error(Editor *editor, const char *heading, const char *detail) {
  GtkAlertDialog *dialog = gtk_alert_dialog_new("%s", heading);
  gtk_alert_dialog_set_detail(dialog, detail);
  gtk_alert_dialog_show(dialog, editor->window);
  g_object_unref(dialog);
}

static void update_title(Editor *editor) {
  char *name = editor->file == NULL ? g_strdup("Untitled.md")
                                    : g_file_get_basename(editor->file);
  char *title = g_strdup_printf("%s%s — md4a",
                                gtk_text_buffer_get_modified(
                                    GTK_TEXT_BUFFER(editor->buffer))
                                    ? "• "
                                    : "",
                                name);
  gtk_window_set_title(editor->window, title);
  g_free(title);
  g_free(name);
}

static void set_file(Editor *editor, GFile *file) {
  g_set_object(&editor->file, file);
  update_title(editor);
}

static gboolean render_preview(gpointer data) {
  Editor *editor = data;
  GtkTextIter start;
  GtkTextIter end;
  char *markdown;
  char *page;
  md4a_result result;

  editor->preview_source = 0;
  gtk_text_buffer_get_bounds(GTK_TEXT_BUFFER(editor->buffer), &start, &end);
  markdown = gtk_text_buffer_get_text(GTK_TEXT_BUFFER(editor->buffer), &start,
                                      &end, FALSE);
  result = md4a_render(markdown, strlen(markdown), NULL);
  g_free(markdown);

  if (result.status != MD4A_STATUS_OK) {
    show_error(editor, "Preview could not be rendered", result.error);
    md4a_result_free(&result);
    return G_SOURCE_REMOVE;
  }

  page = g_strconcat(PAGE_PREFIX, result.html, PAGE_SUFFIX, NULL);
  webkit_web_view_load_html(editor->preview, page, NULL);
  g_free(page);
  md4a_result_free(&result);
  return G_SOURCE_REMOVE;
}

static void buffer_changed(GtkTextBuffer *buffer, gpointer data) {
  Editor *editor = data;
  (void)buffer;
  editor->revision++;
  if (editor->preview_source != 0) {
    g_source_remove(editor->preview_source);
  }
  editor->preview_source = g_timeout_add(120, render_preview, editor);
  update_title(editor);
}

static void load_finished(GObject *source, GAsyncResult *result, gpointer data) {
  Editor *editor = data;
  char *contents = NULL;
  gsize length = 0;
  GError *error = NULL;

  if (!g_file_load_contents_finish(G_FILE(source), result, &contents, &length,
                                   NULL, &error)) {
    show_error(editor, "File could not be opened", error->message);
    g_error_free(error);
    return;
  }

  if (!g_utf8_validate(contents, length, NULL)) {
    show_error(editor, "File could not be opened", "The file is not UTF-8 text.");
    g_free(contents);
    return;
  }
  if (length > G_MAXINT) {
    show_error(editor, "File could not be opened",
               "The file is too large to edit.");
    g_free(contents);
    return;
  }

  gtk_text_buffer_set_text(GTK_TEXT_BUFFER(editor->buffer), contents,
                           (gint)length);
  gtk_text_buffer_set_modified(GTK_TEXT_BUFFER(editor->buffer), FALSE);
  set_file(editor, G_FILE(source));
  g_free(contents);
}

static void open_selected(GObject *source, GAsyncResult *result, gpointer data) {
  Editor *editor = data;
  GError *error = NULL;
  GFile *file = gtk_file_dialog_open_finish(GTK_FILE_DIALOG(source), result,
                                            &error);
  if (file == NULL) {
    if (!g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
      show_error(editor, "File could not be opened", error->message);
    }
    g_clear_error(&error);
    return;
  }
  g_file_load_contents_async(file, NULL, load_finished, editor);
  g_object_unref(file);
}

static void open_document(GSimpleAction *action, GVariant *parameter,
                          gpointer data) {
  Editor *editor = data;
  GtkFileDialog *dialog;
  GtkFileFilter *filter;
  GListStore *filters;
  (void)action;
  (void)parameter;

  if (gtk_text_buffer_get_modified(GTK_TEXT_BUFFER(editor->buffer))) {
    show_error(editor, "Save the current document first",
               "Opening another document would discard unsaved changes.");
    return;
  }

  dialog = gtk_file_dialog_new();
  filter = gtk_file_filter_new();
  filters = g_list_store_new(GTK_TYPE_FILE_FILTER);

  gtk_file_dialog_set_title(dialog, "Open Markdown Document");
  gtk_file_filter_set_name(filter, "Markdown documents");
  gtk_file_filter_add_mime_type(filter, "text/markdown");
  gtk_file_filter_add_pattern(filter, "*.md");
  gtk_file_filter_add_pattern(filter, "*.markdown");
  g_list_store_append(filters, filter);
  gtk_file_dialog_set_filters(dialog, G_LIST_MODEL(filters));
  gtk_file_dialog_set_default_filter(dialog, filter);
  gtk_file_dialog_open(dialog, editor->window, NULL, open_selected, editor);
  g_object_unref(filters);
  g_object_unref(filter);
  g_object_unref(dialog);
}

static char *buffer_text(Editor *editor, gsize *length) {
  GtkTextIter start;
  GtkTextIter end;
  char *text;
  gtk_text_buffer_get_bounds(GTK_TEXT_BUFFER(editor->buffer), &start, &end);
  text = gtk_text_buffer_get_text(GTK_TEXT_BUFFER(editor->buffer), &start, &end,
                                  FALSE);
  *length = strlen(text);
  return text;
}

static void save_finished(GObject *source, GAsyncResult *result, gpointer data) {
  SaveOperation *operation = data;
  Editor *editor = operation->editor;
  GError *error = NULL;
  if (!g_file_replace_contents_finish(G_FILE(source), result, NULL, &error)) {
    show_error(editor, "Document could not be saved", error->message);
    g_error_free(error);
  } else {
    set_file(editor, G_FILE(source));
    if (editor->revision == operation->revision) {
      gtk_text_buffer_set_modified(GTK_TEXT_BUFFER(editor->buffer), FALSE);
      update_title(editor);
    }
  }
  g_free(operation->contents);
  g_free(operation);
}

static void save_to(Editor *editor, GFile *file) {
  gsize length;
  SaveOperation *operation = g_new0(SaveOperation, 1);
  operation->editor = editor;
  operation->contents = buffer_text(editor, &length);
  operation->revision = editor->revision;
  g_file_replace_contents_async(file, operation->contents, length, NULL, FALSE,
                                G_FILE_CREATE_REPLACE_DESTINATION, NULL,
                                save_finished, operation);
}

static void save_selected(GObject *source, GAsyncResult *result, gpointer data) {
  Editor *editor = data;
  GError *error = NULL;
  GFile *file = gtk_file_dialog_save_finish(GTK_FILE_DIALOG(source), result,
                                            &error);
  if (file == NULL) {
    if (!g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
      show_error(editor, "Document could not be saved", error->message);
    }
    g_clear_error(&error);
    return;
  }
  save_to(editor, file);
  g_object_unref(file);
}

static void save_as(Editor *editor) {
  GtkFileDialog *dialog = gtk_file_dialog_new();
  gtk_file_dialog_set_title(dialog, "Save Markdown Document");
  gtk_file_dialog_set_initial_name(dialog, "Untitled.md");
  gtk_file_dialog_save(dialog, editor->window, NULL, save_selected, editor);
  g_object_unref(dialog);
}

static void save_document(GSimpleAction *action, GVariant *parameter,
                          gpointer data) {
  Editor *editor = data;
  (void)action;
  (void)parameter;
  if (editor->file == NULL) {
    save_as(editor);
  } else {
    save_to(editor, editor->file);
  }
}

static void save_document_as(GSimpleAction *action, GVariant *parameter,
                             gpointer data) {
  (void)action;
  (void)parameter;
  save_as(data);
}

static gboolean close_requested(GtkWindow *window, gpointer data) {
  Editor *editor = data;
  (void)window;
  if (!gtk_text_buffer_get_modified(GTK_TEXT_BUFFER(editor->buffer))) {
    return FALSE;
  }
  show_error(editor, "Save the document before closing",
             "The document has unsaved changes.");
  return TRUE;
}

static void editor_destroy(gpointer data) {
  Editor *editor = data;
  if (editor->preview_source != 0) {
    g_source_remove(editor->preview_source);
  }
  g_clear_object(&editor->file);
  g_clear_object(&editor->buffer);
  g_free(editor);
}

static GtkWidget *create_editor_view(Editor *editor) {
  GtkSourceView *view = GTK_SOURCE_VIEW(gtk_source_view_new_with_buffer(
      GTK_SOURCE_BUFFER(editor->buffer)));
  GtkSourceLanguageManager *manager = gtk_source_language_manager_get_default();
  GtkSourceLanguage *language =
      gtk_source_language_manager_get_language(manager, "markdown");
  gtk_source_buffer_set_language(editor->buffer, language);
  gtk_source_view_set_show_line_numbers(view, TRUE);
  gtk_source_view_set_highlight_current_line(view, TRUE);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(view), TRUE);
  return GTK_WIDGET(view);
}

static void default_handler_chosen(GObject *source, GAsyncResult *result,
                                   gpointer data) {
  Editor *editor = data;
  GError *error = NULL;
  int choice = gtk_alert_dialog_choose_finish(GTK_ALERT_DIALOG(source), result,
                                               &error);
  remember_default_handler_was_asked();

  if (error != NULL) {
    if (!g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
      show_error(editor, "Default app preference could not be changed",
                 error->message);
    }
    g_error_free(error);
    return;
  }
  if (choice != 1) {
    return;
  }

  if (!run_xdg_mime("default", MD4A_DESKTOP_ID, "text/markdown", NULL,
                    &error) ||
      !run_xdg_mime("default", MD4A_DESKTOP_ID, "text/x-markdown", NULL,
                    &error)) {
    char *detail = g_strdup_printf(
        "%s\n\nEnsure xdg-utils is installed, then choose md4a in your "
        "desktop environment's Default Applications or file Properties panel.",
        error == NULL ? "xdg-mime did not complete successfully."
                      : error->message);
    show_error(editor, "md4a could not be made the default", detail);
    g_free(detail);
    g_clear_error(&error);
    return;
  }

  if (!markdown_handler_is_default("text/markdown", &error) ||
      !markdown_handler_is_default("text/x-markdown", &error)) {
    char *detail = g_strdup_printf(
        "%s\n\nYour desktop may manage defaults itself. Open Default "
        "Applications or a Markdown file's Properties panel and select md4a.",
        error == NULL ? "The desktop did not report md4a as the default for all "
                        "Markdown MIME types."
                      : error->message);
    show_error(editor, "Default app setting needs confirmation", detail);
    g_free(detail);
    g_clear_error(&error);
  }
}

static void ask_default_handler(Editor *editor) {
  const char *buttons[] = {"Not Now", "Make Default", NULL};
  GtkAlertDialog *dialog = gtk_alert_dialog_new(
      "Make md4a your default app for Markdown files?");
  gtk_alert_dialog_set_detail(
      dialog, "This changes only Markdown file associations. Plain text files "
              "will keep their current default app.");
  gtk_alert_dialog_set_buttons(dialog, buttons);
  gtk_alert_dialog_set_cancel_button(dialog, 0);
  gtk_alert_dialog_set_default_button(dialog, 1);
  gtk_alert_dialog_choose(dialog, editor->window, NULL, default_handler_chosen,
                          editor);
  g_object_unref(dialog);
}

static void choose_default_handler(GSimpleAction *action, GVariant *parameter,
                                   gpointer data) {
  (void)action;
  (void)parameter;
  ask_default_handler(data);
}

static void add_actions(Editor *editor) {
  static const GActionEntry entries[] = {
      {"open", open_document, NULL, NULL, NULL},
      {"save", save_document, NULL, NULL, NULL},
      {"save-as", save_document_as, NULL, NULL, NULL},
      {"make-default", choose_default_handler, NULL, NULL, NULL},
  };
  g_action_map_add_action_entries(G_ACTION_MAP(editor->window), entries,
                                  G_N_ELEMENTS(entries), editor);
}

static Editor *create_editor(GtkApplication *application) {
  Editor *editor = g_new0(Editor, 1);
  GtkWidget *paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  GtkWidget *editor_scroll = gtk_scrolled_window_new();
  GtkWidget *preview_scroll = gtk_scrolled_window_new();
  GtkWidget *editor_view;

  editor->window = GTK_WINDOW(gtk_application_window_new(application));
  g_object_set_data_full(G_OBJECT(editor->window), "md4a-editor", editor,
                         editor_destroy);
  editor->buffer = gtk_source_buffer_new(NULL);
  editor->preview = WEBKIT_WEB_VIEW(webkit_web_view_new());
  webkit_settings_set_enable_javascript(
      webkit_web_view_get_settings(editor->preview), FALSE);
  editor_view = create_editor_view(editor);

  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(editor_scroll), editor_view);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(preview_scroll),
                                GTK_WIDGET(editor->preview));
  gtk_paned_set_start_child(GTK_PANED(paned), editor_scroll);
  gtk_paned_set_end_child(GTK_PANED(paned), preview_scroll);
  gtk_paned_set_resize_start_child(GTK_PANED(paned), TRUE);
  gtk_paned_set_resize_end_child(GTK_PANED(paned), TRUE);
  gtk_window_set_default_size(editor->window, 1100, 720);
  gtk_window_set_child(editor->window, paned);

  add_actions(editor);
  g_signal_connect(editor->buffer, "changed", G_CALLBACK(buffer_changed), editor);
  g_signal_connect(editor->window, "close-request",
                   G_CALLBACK(close_requested), editor);
  gtk_text_buffer_set_text(GTK_TEXT_BUFFER(editor->buffer),
                           "# Untitled\n\nStart writing Markdown.\n", -1);
  gtk_text_buffer_set_modified(GTK_TEXT_BUFFER(editor->buffer), FALSE);
  update_title(editor);
  render_preview(editor);
  gtk_window_present(editor->window);
  return editor;
}

static void activate(GtkApplication *application, gpointer data) {
  Editor *editor;
  (void)data;
  editor = create_editor(application);
  if (!default_handler_was_asked()) {
    ask_default_handler(editor);
  }
}

static void open_files(GApplication *application, GFile **files, gint file_count,
                       const char *hint, gpointer data) {
  gint index;
  (void)hint;
  (void)data;

  for (index = 0; index < file_count; index++) {
    Editor *editor = create_editor(GTK_APPLICATION(application));
    g_file_load_contents_async(files[index], NULL, load_finished, editor);
    if (index == 0 && !default_handler_was_asked()) {
      ask_default_handler(editor);
    }
  }
}

static void startup(GtkApplication *application, gpointer data) {
  GMenu *menu = g_menu_new();
  GMenu *file = g_menu_new();
  (void)data;
  g_menu_append(file, "Open…", "win.open");
  g_menu_append(file, "Save", "win.save");
  g_menu_append(file, "Save As…", "win.save-as");
  g_menu_append(file, "Make Default for Markdown…", "win.make-default");
  g_menu_append_submenu(menu, "File", G_MENU_MODEL(file));
  gtk_application_set_menubar(application, G_MENU_MODEL(menu));
  gtk_application_set_accels_for_action(application, "win.open",
                                        (const char *[]) {"<Primary>o", NULL});
  gtk_application_set_accels_for_action(application, "win.save",
                                        (const char *[]) {"<Primary>s", NULL});
  gtk_application_set_accels_for_action(
      application, "win.save-as",
      (const char *[]) {"<Primary><Shift>s", NULL});
  g_object_unref(file);
  g_object_unref(menu);
}

int main(int argc, char **argv) {
  GtkApplication *application = gtk_application_new(
      "app.md4a.Md4a", G_APPLICATION_HANDLES_OPEN);
  int status;
  g_signal_connect(application, "startup", G_CALLBACK(startup), NULL);
  g_signal_connect(application, "activate", G_CALLBACK(activate), NULL);
  g_signal_connect(application, "open", G_CALLBACK(open_files), NULL);
  status = g_application_run(G_APPLICATION(application), argc, argv);
  g_object_unref(application);
  return status;
}
