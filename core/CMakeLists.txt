add_library(md4a_core STATIC src/md4a.c)
add_library(md4a::core ALIAS md4a_core)

target_include_directories(md4a_core
  PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
)
target_link_libraries(md4a_core PRIVATE md4c-html)
target_compile_features(md4a_core PRIVATE c_std_99)

if(MSVC)
  target_compile_options(md4a_core PRIVATE /W4)
else()
  target_compile_options(md4a_core PRIVATE -Wall -Wextra -Wpedantic)
endif()
