#pragma once

#include <memory>
#include <string>

namespace md4a::windows {

class MainWindow {
 public:
  virtual ~MainWindow() = default;
  virtual void OpenInitialDocument(std::wstring const& path) = 0;
  virtual void PromptForDefaultApp() = 0;
};

std::unique_ptr<MainWindow> CreateMainWindow();

}  // namespace md4a::windows
