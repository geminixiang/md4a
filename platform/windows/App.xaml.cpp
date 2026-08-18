#include "pch.h"
#include "App.xaml.h"

#include "Startup.h"

#include <windows.h>

#include <shellapi.h>
#include <utility>

namespace winrt::Md4a::implementation {
namespace {
std::optional<std::wstring> InitialDocumentPath() {
  int argumentCount{};
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &argumentCount);
  if (!arguments) return std::nullopt;

  std::optional<std::wstring> path;
  if (argumentCount > 1 && arguments[1][0] != L'-' && arguments[1][0] != L'/') {
    DWORD required = GetFullPathNameW(arguments[1], 0, nullptr, nullptr);
    if (required > 0) {
      std::wstring fullPath(required, L'\0');
      DWORD written = GetFullPathNameW(arguments[1], required, fullPath.data(), nullptr);
      if (written > 0 && written < required) {
        fullPath.resize(written);
        path = std::move(fullPath);
      }
    }
  }
  LocalFree(arguments);
  return path;
}
}

App::App() {
  md4a::startup::Log("app.constructor.begin");
  InitializeComponent();
  md4a::startup::Log("app.initialize-component.complete");
}

void App::OnLaunched(Microsoft::UI::Xaml::LaunchActivatedEventArgs const&) {
  md4a::startup::Log("app.on-launched.begin");
  m_window = md4a::windows::CreateMainWindow();
  md4a::startup::Log("window.activated");

  if (auto initialDocumentPath = InitialDocumentPath()) {
    m_window->OpenInitialDocument(*initialDocumentPath);
    md4a::startup::Log("document.open-requested");
  }

  md4a::startup::Log("startup.complete");
  wchar_t skipPrompt[2]{};
  if (GetEnvironmentVariableW(L"MD4A_SKIP_DEFAULT_APP_PROMPT", skipPrompt, 2) == 0) {
    m_window->PromptForDefaultApp();
  }
}

}  // namespace winrt::Md4a::implementation
