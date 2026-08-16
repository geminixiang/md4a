find_package(PkgConfig REQUIRED)

pkg_check_modules(GTK4 REQUIRED IMPORTED_TARGET gtk4>=4.10)
pkg_check_modules(GTKSOURCEVIEW REQUIRED IMPORTED_TARGET gtksourceview-5)
pkg_check_modules(WEBKITGTK REQUIRED IMPORTED_TARGET webkitgtk-6.0)

add_executable(md4a_linux src/main.c)
target_compile_features(md4a_linux PRIVATE c_std_99)
target_link_libraries(md4a_linux PRIVATE
  md4a::core
  PkgConfig::GTK4
  PkgConfig::GTKSOURCEVIEW
  PkgConfig::WEBKITGTK
)

if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(md4a_linux PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS md4a_linux RUNTIME DESTINATION bin)
