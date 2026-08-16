cmake_minimum_required(VERSION 3.20)

project(md4a VERSION 0.1.0 LANGUAGES C)

option(MD4A_BUILD_TESTS "Build the shared-core tests" ON)
option(MD4A_BUILD_LINUX_APP "Build the native GTK Linux application" OFF)

set(BUILD_MD2HTML_EXECUTABLE OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/md4c EXCLUDE_FROM_ALL)
add_subdirectory(core)

if(MD4A_BUILD_LINUX_APP)
  if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR "MD4A_BUILD_LINUX_APP requires Linux")
  endif()
  add_subdirectory(platform/linux)
endif()

if(MD4A_BUILD_TESTS)
  enable_testing()
  add_subdirectory(core/tests)
endif()
