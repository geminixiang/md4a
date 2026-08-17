#include "pch.h"
#include "Startup.h"

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <cstdio>
#include <mutex>
#include <string>

namespace md4a::startup {
namespace {
std::mutex g_logMutex;

std::filesystem::path LogPath() {
  wchar_t localAppData[MAX_PATH]{};
  DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return {};
  return std::filesystem::path(localAppData) / L"md4a" / L"startup.log";
}

void Append(std::string_view message) noexcept {
  try {
    std::scoped_lock lock(g_logMutex);
    auto path = LogPath();
    if (path.empty()) return;
    std::filesystem::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::app);
    SYSTEMTIME time{};
    GetSystemTime(&time);
    output << time.wYear << '-' << time.wMonth << '-' << time.wDay << 'T'
           << time.wHour << ':' << time.wMinute << ':' << time.wSecond << "Z "
           << message << '\n';
  } catch (...) {
  }
}
}  // namespace

void Log(std::string_view stage) noexcept { Append(stage); }

void LogFailure(std::string_view stage, long error) noexcept {
  try {
    std::string message(stage);
    message.append(" failed HRESULT=");
    char value[16]{};
    snprintf(value, sizeof(value), "%08lX", static_cast<unsigned long>(error));
    message.append(value);
    Append(message);
  } catch (...) {
  }
}

void ShowFailure() noexcept {
  MessageBoxW(nullptr,
              L"md4a could not start. Restart the app after verifying that Windows App Runtime and WebView2 are installed.\n\nDiagnostic details were written to %LOCALAPPDATA%\\md4a\\startup.log.",
              L"md4a startup error", MB_OK | MB_ICONERROR | MB_TASKMODAL);
}

}  // namespace md4a::startup
