#include "MainWindow.h"

#include <windows.h>
#include <shobjidl_core.h>
#include <microsoft.ui.xaml.window.h>

#include <memory>
#include <string>
#include <string_view>

#include <winrt/base.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.System.h>

#include "md4a/md4a.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;
using namespace Microsoft::UI::Xaml::Controls;
using namespace Microsoft::UI::Xaml::Input;
using namespace Windows::Foundation;
using namespace Windows::Storage;
using namespace Windows::Storage::Pickers;
using namespace Windows::System;

namespace {
constexpr std::string_view kDocumentPrefix = R"(<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:16px system-ui;margin:2rem;line-height:1.55;color:#202020}pre{padding:1rem;overflow:auto;background:#f5f5f5}code{font-family:ui-monospace,monospace}img{max-width:100%}@media(prefers-color-scheme:dark){body{color:#eee;background:#202020}pre{background:#303030}a{color:#75bfff}}</style></head><body>)";
constexpr std::string_view kDocumentSuffix = "</body></html>";

constexpr wchar_t kPreferencesKey[] = L"Software\\md4a";
constexpr wchar_t kDefaultAppsUri[] = L"ms-settings:defaultapps?registeredAppUser=md4a";

bool HasAskedAboutDefaults() {
  DWORD value{};
  DWORD size = sizeof(value);
  return RegGetValueW(HKEY_CURRENT_USER, kPreferencesKey, L"AskedAboutDefaults",
                      RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS && value != 0;
}

void RecordDefaultsPrompt() {
  DWORD value = 1;
  RegSetKeyValueW(HKEY_CURRENT_USER, kPreferencesKey, L"AskedAboutDefaults",
                  REG_DWORD, &value, sizeof(value));
}

fire_and_forget OpenDefaultAppsSettings() {
  bool opened = false;
  try {
    opened = co_await Launcher::LaunchUriAsync(Uri(kDefaultAppsUri));
  } catch (...) {
  }
  if (!opened) {
    co_await Launcher::LaunchUriAsync(Uri(L"ms-settings:defaultapps"));
  }
}

void InitializePickerWithWindow(IInspectable const& picker, Window const& window) {
  HWND hwnd{};
  check_hresult(window.as<::IWindowNative>()->get_WindowHandle(&hwnd));
  check_hresult(picker.as<::IInitializeWithWindow>()->Initialize(hwnd));
}

class MainWindowImpl final : public md4a::windows::MainWindow {
 public:
  MainWindowImpl() {
    m_window.Title(L"md4a — Untitled");
    BuildUi();
    m_editor.Text(L"# Untitled\r\n\r\n");
    m_dirty = false;
    RenderPreview();
    m_window.Activate();
  }

 private:
  void BuildUi() {
    Grid root;
    RowDefinition menuRow;
    menuRow.Height(GridLengthHelper::Auto());
    root.RowDefinitions().Append(menuRow);
    root.RowDefinitions().Append(RowDefinition());

    MenuBar menu;
    MenuBarItem fileMenu;
    fileMenu.Title(L"File");
    AddMenuItem(fileMenu, L"New", VirtualKey::N, [this] { NewDocument(); });
    AddMenuItem(fileMenu, L"Open…", VirtualKey::O, [this] { OpenDocument(); });
    AddMenuItem(fileMenu, L"Save", VirtualKey::S, [this] { SaveDocument(false); });
    AddMenuItem(fileMenu, L"Save As…", VirtualKey::S,
                [this] { SaveDocument(true); }, VirtualKeyModifiers::Control | VirtualKeyModifiers::Shift);
    menu.Items().Append(fileMenu);

    MenuBarItem settingsMenu;
    settingsMenu.Title(L"Settings");
    AddMenuItem(settingsMenu, L"Default apps…", VirtualKey::None,
                [] { OpenDefaultAppsSettings(); }, VirtualKeyModifiers::None);
    menu.Items().Append(settingsMenu);
    root.Children().Append(menu);

    Grid workspace;
    workspace.ColumnDefinitions().Append(ColumnDefinition());
    workspace.ColumnDefinitions().Append(ColumnDefinition());
    Grid::SetRow(workspace, 1);

    m_editor.AcceptsReturn(true);
    m_editor.TextWrapping(TextWrapping::NoWrap);
    m_editor.FontFamily(Microsoft::UI::Xaml::Media::FontFamily(L"Consolas"));
    m_editor.Padding(ThicknessHelper::FromUniformLength(16));
    m_editor.TextChanged([this](IInspectable const&, TextChangedEventArgs const&) {
      m_dirty = true;
      ++m_revision;
      UpdateTitle();
      RenderPreview();
    });
    workspace.Children().Append(m_editor);

    Grid::SetColumn(m_preview, 1);
    workspace.Children().Append(m_preview);
    root.Children().Append(workspace);
    m_window.Content(root);
  }

  template <typename Action>
  void AddMenuItem(MenuBarItem const& menu, wchar_t const* label, VirtualKey key,
                   Action action, VirtualKeyModifiers modifiers = VirtualKeyModifiers::Control) {
    MenuFlyoutItem item;
    item.Text(label);
    if (key != VirtualKey::None) {
      KeyboardAccelerator accelerator;
      accelerator.Key(key);
      accelerator.Modifiers(modifiers);
      item.KeyboardAccelerators().Append(accelerator);
    }
    item.Click([action = std::move(action)](IInspectable const&, RoutedEventArgs const&) { action(); });
    menu.Items().Append(item);
  }

  void NewDocument() {
    if (m_dirty) {
      ShowError(L"Save the current document first",
                L"Creating a new document would discard unsaved changes.");
      return;
    }
    m_file = nullptr;
    m_editor.Text(L"");
    m_dirty = false;
    UpdateTitle();
  }

  fire_and_forget OpenPath(std::wstring path) {
    try {
      auto file = co_await StorageFile::GetFileFromPathAsync(path);
      co_await LoadFile(file);
    } catch (hresult_error const& error) {
      ShowError(L"Could not open the document", error.message());
    }
  }

  IAsyncAction LoadFile(StorageFile const& file) {
    auto text = co_await FileIO::ReadTextAsync(file, Streams::UnicodeEncoding::Utf8);
    m_file = file;
    m_editor.Text(text);
    m_dirty = false;
    UpdateTitle();
  }

 public:
  void OpenInitialDocument(std::wstring const& path) override { OpenPath(path); }

  void PromptForDefaultApp() override { PromptForDefaultAppAsync(); }

 private:
  fire_and_forget PromptForDefaultAppAsync() {
    if (HasAskedAboutDefaults()) co_return;
    RecordDefaultsPrompt();

    ContentDialog dialog;
    dialog.XamlRoot(m_window.Content().XamlRoot());
    dialog.Title(box_value(L"Open Markdown files with md4a?"));
    dialog.Content(box_value(L"Windows controls default apps. Open Settings to choose md4a for .md and .markdown files?"));
    dialog.PrimaryButtonText(L"Open Settings");
    dialog.CloseButtonText(L"Not now");
    if (co_await dialog.ShowAsync() == ContentDialogResult::Primary) {
      OpenDefaultAppsSettings();
    }
  }

 private:
  fire_and_forget OpenDocument() {
    if (m_dirty) {
      ShowError(L"Save the current document first",
                L"Opening another document would discard unsaved changes.");
      co_return;
    }
    FileOpenPicker picker;
    InitializePickerWithWindow(picker, m_window);
    picker.FileTypeFilter().Append(L".md");
    picker.FileTypeFilter().Append(L".markdown");
    auto file = co_await picker.PickSingleFileAsync();
    if (!file) co_return;

    try {
      co_await LoadFile(file);
    } catch (hresult_error const& error) {
      ShowError(L"Could not open the document", error.message());
    }
  }

  fire_and_forget SaveDocument(bool saveAs) {
    StorageFile file = m_file;
    if (!file || saveAs) {
      FileSavePicker picker;
      InitializePickerWithWindow(picker, m_window);
      picker.SuggestedFileName(file ? file.DisplayName() : L"Untitled");
      picker.FileTypeChoices().Insert(L"Markdown document", single_threaded_vector<hstring>({L".md"}));
      file = co_await picker.PickSaveFileAsync();
      if (!file) co_return;
    }

    try {
      hstring text = m_editor.Text();
      uint64_t revision = m_revision;
      co_await FileIO::WriteTextAsync(file, text, Streams::UnicodeEncoding::Utf8);
      m_file = file;
      if (m_revision == revision) {
        m_dirty = false;
      }
      UpdateTitle();
    } catch (hresult_error const& error) {
      ShowError(L"Could not save the document", error.message());
    }
  }

  void RenderPreview() {
    std::string markdown = to_string(m_editor.Text());
    md4a_render_options options{};
    md4a_result result = md4a_render(markdown.data(), markdown.size(), &options);
    if (result.status != MD4A_STATUS_OK) {
      m_preview.NavigateToString(L"<html><body><p>Preview could not be rendered.</p></body></html>");
      md4a_result_free(&result);
      return;
    }

    std::string page;
    page.reserve(kDocumentPrefix.size() + result.html_size + kDocumentSuffix.size());
    page.append(kDocumentPrefix);
    page.append(result.html, result.html_size);
    page.append(kDocumentSuffix);
    md4a_result_free(&result);
    m_preview.NavigateToString(to_hstring(page));
  }

  fire_and_forget ShowError(hstring const& title, hstring const& message) {
    ContentDialog dialog;
    dialog.XamlRoot(m_window.Content().XamlRoot());
    dialog.Title(box_value(title));
    dialog.Content(box_value(message));
    dialog.CloseButtonText(L"OK");
    co_await dialog.ShowAsync();
  }

  void UpdateTitle() {
    hstring name = m_file ? m_file.Name() : L"Untitled";
    std::wstring title = L"md4a — ";
    title.append(name);
    if (m_dirty) title.append(L" *");
    m_window.Title(title);
  }

  Window m_window;
  TextBox m_editor;
  WebView2 m_preview;
  StorageFile m_file{nullptr};
  bool m_dirty{false};
  uint64_t m_revision{0};
};
}  // namespace

namespace md4a::windows {

std::unique_ptr<MainWindow> CreateMainWindow() {
  return std::make_unique<MainWindowImpl>();
}

}  // namespace md4a::windows
