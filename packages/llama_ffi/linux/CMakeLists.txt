# Linux desktop: builds llama.cpp with src/CMakeLists.txt and bundles the
# shared libraries next to the app. The CPU backend module is discovered at
# runtime in the same directory as libllama.so.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "llama_ffi")
project(${PROJECT_NAME} LANGUAGES C CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(llama_ffi_bundled_libraries
  $<TARGET_FILE:llama>
  $<TARGET_FILE:ggml>
  $<TARGET_FILE:ggml-base>
  $<TARGET_FILE:ggml-cpu>
  PARENT_SCOPE
)
