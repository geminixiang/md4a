cmake_minimum_required(VERSION 3.22.1)
project(md4a_android LANGUAGES C)

set(MD4A_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../..")

add_library(md4a_android SHARED
    md4a_jni.c
    "${MD4A_ROOT}/core/src/md4a.c"
    "${MD4A_ROOT}/third_party/md4c/src/md4c.c"
    "${MD4A_ROOT}/third_party/md4c/src/md4c-html.c"
    "${MD4A_ROOT}/third_party/md4c/src/entity.c"
)

target_include_directories(md4a_android PRIVATE
    "${MD4A_ROOT}/core/include"
    "${MD4A_ROOT}/third_party/md4c/src"
)
target_compile_features(md4a_android PRIVATE c_std_99)
target_compile_options(md4a_android PRIVATE -Wall -Wextra -Wpedantic)
