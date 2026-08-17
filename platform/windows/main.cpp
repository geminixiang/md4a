#include "pch.h"
#include "App.xaml.h"
#include "Startup.h"

#include <windows.h>
#include <shellapi.h>

#include <optional>
#include <string>

#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/base.h>

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
}  // namespace

int __stdcall wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  md4a::startup::Log("process.entry");
  try {
    winrt::Md4a::implementation::App::SetInitialDocumentPath(InitialDocumentPath());
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    md4a::startup::Log("apartment.initialized");
    winrt::Microsoft::UI::Xaml::Application::Start([](auto&&) {
      md4a::startup::Log("application.start.callback");
      winrt::make<winrt::Md4a::implementation::App>();
    });
    md4a::startup::Log("application.stopped");
    return 0;
  } catch (winrt::hresult_error const& error) {
    md4a::startup::LogFailure("process", error.code().value);
  } catch (...) {
    md4a::startup::Log("process failed unknown");
  }
  md4a::startup::ShowFailure();
  return 1;
}
