add_executable(md4a_core_test md4a_test.c)
target_link_libraries(md4a_core_test PRIVATE md4a::core)
add_test(NAME md4a_core COMMAND md4a_core_test)
