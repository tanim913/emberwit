# Builds llama.cpp as shared libraries for the Dart FFI bindings in lib/.
#
# Used by Android (android/build.gradle), Linux desktop (linux/CMakeLists.txt)
# and host test builds (tool/build_host.sh). iOS uses the prebuilt official
# xcframework instead, see ios/.
#
# Output libraries: libllama, libggml, libggml-base and one or more CPU
# backends (libggml-cpu*.so). The CPU backend is loaded at runtime with
# ggml_backend_load_all_from_path(), which picks the best variant for the
# device's CPU features (dotprod, i8mm, SVE, ...).
cmake_minimum_required(VERSION 3.14)

project(llama_ffi_native LANGUAGES C CXX)

set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/llama.cpp")
if (NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
  message(FATAL_ERROR
    "llama.cpp sources missing. Run: git submodule update --init --recursive")
endif()

if (NOT CMAKE_BUILD_TYPE)
  # Inference is unusably slow without optimisation, even in debug app builds.
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Library only: no tools, examples, tests, server or network code.
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)

# Portable binaries: never tune for the build machine.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
# CPU backends are separate modules chosen at runtime.
set(GGML_BACKEND_DL ON CACHE BOOL "" FORCE)
# KleidiAI is fetched from the network at configure time; keep builds offline
# and reproducible.
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

if (ANDROID)
  if (ANDROID_ABI STREQUAL "arm64-v8a")
    # One CPU backend per ARM feature level; the best one is picked on device.
    set(GGML_CPU_ALL_VARIANTS ON CACHE BOOL "" FORCE)
    set(GGML_OPENMP ON CACHE BOOL "" FORCE)
  else()
    # x86_64 is only used on emulators: a single baseline backend is enough
    # and keeps build times reasonable.
    set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
  endif()
  # Vulkan stays off until it is stable across Android GPU drivers.
  set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
elseif (LLAMA_FFI_ALL_VARIANTS)
  set(GGML_CPU_ALL_VARIANTS ON CACHE BOOL "" FORCE)
endif()

# Builds libllama, libggml, libggml-base and the CPU backend module(s). With
# the tools, examples and tests switched off above, nothing else is built.
add_subdirectory("${LLAMA_CPP_DIR}" llama.cpp)

if (ANDROID)
  # Android 15+ devices may use 16 KB memory pages.
  foreach (lib llama ggml ggml-base)
    target_link_options(${lib} PRIVATE "-Wl,-z,max-page-size=16384")
  endforeach()
endif()
