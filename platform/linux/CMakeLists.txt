include(GNUInstallDirs)

find_package(PkgConfig REQUIRED)

pkg_check_modules(GTK4 REQUIRED IMPORTED_TARGET gtk4>=4.10)
pkg_check_modules(GTKSOURCEVIEW REQUIRED IMPORTED_TARGET gtksourceview-5)
pkg_check_modules(WEBKITGTK REQUIRED IMPORTED_TARGET webkitgtk-6.0)

add_executable(md4a_linux src/main.c src/default_handler.c)
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

if(MD4A_BUILD_TESTS)
  add_executable(md4a_linux_default_handler_test
    tests/default_handler_test.c
    src/default_handler.c
  )
  target_include_directories(md4a_linux_default_handler_test PRIVATE src)
  target_link_libraries(md4a_linux_default_handler_test PRIVATE PkgConfig::GTK4)
  add_test(NAME md4a_linux_default_handler
           COMMAND md4a_linux_default_handler_test)
endif()

install(TARGETS md4a_linux RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES app.md4a.Md4a.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
foreach(size 16 24 32 48 64 128 256 512)
  install(
    FILES icons/hicolor/${size}x${size}/apps/app.md4a.Md4a.png
    DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${size}x${size}/apps
  )
endforeach()
