# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2018, Wang Bin
#
# clang-cl + lld to cross build apps for windows. can be easily change to other target platforms
# can not use clang --target=${ARCH}-none-windows-msvc19.0 because cmake will test msvc flags
# ref: https://github.com/llvm-mirror/llvm/blob/master/cmake/platforms/WinMsvc.cmake

# vars:
# WINSDK_DIR, WINSDK_VER, MSVC_DIR. If not set, environment vars WindowsSdkDir, WindowsSDKVersion, VCDIR are used
# CMAKE_SYSTEM_PROCESSOR: target arch, host arch is used if not set
# CMAKE_C_COMPILER: clang-cl path (optional)

# when cross building on a case sensitive filesystem, symbolic links for libs and vfs overlay for headers are required.
# You can download winsdk containing scripts to generate links and vfs overlay from: https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download
# msvc sdk: https://sourceforge.net/projects/avbuild/files/dep/msvcrt-dev.7z/download

# /bin/link will be selected by cmake
# non-windows host: clang-cl invokes link.exe by default, use -fuse-ld=lld works. but -Wl, /link, -Xlinker does not work
option(CLANG_AS_LINKER "use clang as linker to invoke lld. MUST ON for now" OFF) # MUST use lld-link as CMAKE_LINKER on windows host, otherwise ms link.exe is used
option(USE_CLANG_CL "use clang-cl" ON)
option(USE_LIBCXX "use libc++ instead of libstdc++" OFF)
option(UWP "build for uwp" OFF)
option(PHONE "build for phone" OFF)
option(ONECORE "build with oncore" OFF)

set(CMAKE_CROSSCOMPILING ON) # turned on by setting CMAKE_SYSTEM_NAME?
# FIXME: msvcrtd.lib is required
set(CMAKE_SYSTEM_NAME Windows) # phone, store?
#set(CMAKE_SYSTEM_VERSION 10.0)

if(NOT CMAKE_C_COMPILER)
  set(CMAKE_C_COMPILER clang-cl CACHE FILEPATH "")
  set(CMAKE_CXX_COMPILER clang-cl CACHE FILEPATH "")
  set(CMAKE_LINKER lld-link CACHE FILEPATH "")
# llvm-ar is not required to create static lib: lld-link /lib /machine:${WINSDK_ARCH}
endif()

if(NOT CMAKE_SYSTEM_PROCESSOR)
  message("CMAKE_SYSTEM_PROCESSOR for target is not set. Must be aarch64(arm64), armv7(arm), x86(i686), x64(x86_64). Assumeme build for host arch: ${CMAKE_HOST_SYSTEM_PROCESSOR}.")
  set(CMAKE_SYSTEM_PROCESSOR ${CMAKE_HOST_SYSTEM_PROCESSOR})
endif()
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x.*64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL AMD64)
  set(TRIPLE_ARCH x86_64)
  set(WINSDK_ARCH x64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "86")
  set(TRIPLE_ARCH i386)
  set(WINSDK_ARCH x86)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "a.*64")
  set(TRIPLE_ARCH aarch64)
  set(WINSDK_ARCH arm64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(TRIPLE_ARCH armv7)
  set(WINSDK_ARCH arm)
endif()

# fetch env vars set by vcvarsall.bat if required vars are not set
if(NOT WINSDK_DIR)
  set(WINSDK_DIR $ENV{WindowsSdkDir})
endif()
if(NOT WINSDK_VER)
  set(WINSDK_VER $ENV{WindowsSDKVersion})
endif()
if(NOT MSVC_DIR)
  set(MSVC_DIR $ENV{VCDIR})
endif()
# Export configurable variables for the try_compile() command. Or set env var like llvm
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  CMAKE_SYSTEM_PROCESSOR
  MSVC_DIR
  WINSDK_DIR
  WINSDK_VER
)

set(MSVC_INCLUDE "${MSVC_DIR}/include")
set(MSVC_LIB "${MSVC_DIR}/lib")
set(WINSDK_INCLUDE "${WINSDK_DIR}/Include/${WINSDK_VER}")
set(WINSDK_LIB "${WINSDK_DIR}/Lib/${WINSDK_VER}")

if(NOT EXISTS "${WINSDK_INCLUDE}/um/Windows.h")
  message(SEND_ERROR "Cannot find Windows.h")
endif()

set(COMPILE_FLAGS
    -D_CRT_SECURE_NO_WARNINGS
    --target=${TRIPLE_ARCH}-windows-msvc
    -fms-compatibility-version=19.14)

if(NOT CMAKE_HOST_WIN32) # assume CMAKE_HOST_WIN32 means in VS env, vs tools like rc and mt exists
  if(NOT EXISTS "${WINSDK_INCLUDE}/um/WINDOWS.H")
    set(case_sensitive_fs TRUE)
  endif()
  if(case_sensitive_fs)
    if(NOT EXISTS "${WINSDK_DIR}/vfs.yaml")
      message(SEND_ERROR "can not find vfs.yaml. you can use winsdk from https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download")
    endif()
    list(APPEND COMPILE_FLAGS -Xclang -ivfsoverlay -Xclang "${WINSDK_DIR}/vfs.yaml")
  endif()
  list(APPEND COMPILE_FLAGS
    -imsvc "${MSVC_INCLUDE}"
    -imsvc "${WINSDK_INCLUDE}/ucrt"
    -imsvc "${WINSDK_INCLUDE}/shared"
    -imsvc "${WINSDK_INCLUDE}/um"
    -imsvc "${WINSDK_INCLUDE}/winrt")

  list(APPEND LINK_FLAGS
    # Prevent CMake from attempting to invoke mt.exe. It only recognizes the slashed form and not the dashed form.
    /manifest:no # why -manifest:no results in rc error?  TODO: check mt and rc?
    -libpath:"${MSVC_LIB}/${WINSDK_ARCH}"
    -libpath:"${WINSDK_LIB}/ucrt/${WINSDK_ARCH}"
    -libpath:"${WINSDK_LIB}/um/${WINSDK_ARCH}")
endif()

string(REPLACE ";" " " COMPILE_FLAGS "${COMPILE_FLAGS}")
set(CMAKE_C_FLAGS "${COMPILE_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${COMPILE_FLAGS}" CACHE STRING "" FORCE)

string(REPLACE ";" " " LINK_FLAGS "${LINK_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS "${LINK_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "${LINK_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "${LINK_FLAGS}" CACHE STRING "" FORCE)

# CMake populates these with a bunch of unnecessary libraries, which requires
# extra case-correcting symlinks and what not. Instead, let projects explicitly
# control which libraries they require.
set(CMAKE_C_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)

set(CMAKE_RC_COMPILER_INIT llvm-rc CACHE INTERNAL "windows llvm rc" FORCE)
set(CMAKE_RC_COMPLIER llvm-rc CACHE INTERNAL "windows llvm rc" FORCE)
set(CMAKE_GENERATOR_RC llvm-rc CACHE INTERNAL "windows llvm rc" FORCE)
# Allow clang-cl to work with macOS paths.
set(CMAKE_USER_MAKE_RULES_OVERRIDE "${CMAKE_CURRENT_LIST_DIR}/override.windows.clang.cmake")