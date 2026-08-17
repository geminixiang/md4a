#include "pch.h"
#include "App.xaml.h"

#include "Startup.h"

#include <windows.h>

#include <utility>

namespace winrt::Md4a::implementation {
namespace {
std::optional<std::wstring> g_initialDocumentPath;
}

App::App() {
  md4a::startup::Log("app.constructor.begin");
  InitializeComponent();
  md4a::startup::Log("app.initialize-component.complete");
}

void App::SetInitialDocumentPath(std::optional<std::wstring> path) {
  g_initialDocumentPath = std::move(path);
}

void App::OnLaunched(Microsoft::UI::Xaml::LaunchActivatedEventArgs const&) {
  md4a::startup::Log("app.on-launched.begin");
  m_window = md4a::windows::CreateMainWindow();
  md4a::startup::Log("window.activated");

  if (g_initialDocumentPath) {
    m_window->OpenInitialDocument(*g_initialDocumentPath);
    md4a::startup::Log("document.open-requested");
  }

  wchar_t skipPrompt[2]{};
  if (GetEnvironmentVariableW(L"MD4A_SKIP_DEFAULT_APP_PROMPT", skipPrompt, 2) == 0) {
    m_window->PromptForDefaultApp();
  }
  md4a::startup::Log("startup.complete");
}

}  // namespace winrt::Md4a::implementation
