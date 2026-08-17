#pragma once

#include <string_view>

namespace md4a::startup {

void Log(std::string_view stage) noexcept;
void LogFailure(std::string_view stage, long error) noexcept;
void ShowFailure() noexcept;

}  // namespace md4a::startup
