#pragma once

#include "App.xaml.g.h"

#include <memory>
#include <optional>
#include <string>

#include "MainWindow.h"

namespace winrt::Md4a::implementation {

struct App : AppT<App> {
  App();
  void OnLaunched(Microsoft::UI::Xaml::LaunchActivatedEventArgs const& args);

 private:
  std::unique_ptr<md4a::windows::MainWindow> m_window;
};

}  // namespace winrt::Md4a::implementation
