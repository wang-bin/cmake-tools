# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2022, Wang Bin
#
# llvm-mingw toolchain: https://github.com/mstorsjo/llvm-mingw

option(UWP "build for uwp" OFF)

set(CMAKE_C_COMPILER_FRONTEND_VARIANT GNU)
if(UWP)
  set(CMAKE_SYSTEM_NAME WindowsStore)
  set(WINRT 1)
  set(WINSTORE 1)
  set(_OS_API uwp)
else()
  set(CMAKE_SYSTEM_NAME Windows)
  set(WINRT 0)
  set(WINDOWS_DESKTOP 1)
endif()
# TODO: CMAKE_SYSTEM_VERSION: -D_WIN32_WINNT, --subsystem name:x[.y]

if(NOT LLVM_MINGW)
  set(LLVM_MINGW $ENV{LLVM_MINGW})
endif()

set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
# avoid find_program multiple times
  CMAKE_SYSTEM_NAME
  CMAKE_SYSTEM_PROCESSOR
)

if(NOT CMAKE_SYSTEM_PROCESSOR)
  message("CMAKE_SYSTEM_PROCESSOR for target is not set. Must be aarch64(arm64), armv7(arm), x86(i686), x64(x86_64). Assumeme build for host arch: ${CMAKE_HOST_SYSTEM_PROCESSOR}.")
  set(CMAKE_SYSTEM_PROCESSOR ${CMAKE_HOST_SYSTEM_PROCESSOR})
endif()
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x.*64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL AMD64)
  set(_TRIPLE_ARCH x86_64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "86")
  set(_TRIPLE_ARCH i386)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "a.*64")
  set(_TRIPLE_ARCH aarch64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(_TRIPLE_ARCH armv7)
endif()

set(_LLVM_TRIPPLE ${_TRIPLE_ARCH}-w64-mingw32${_OS_API})
SET(CMAKE_C_COMPILER ${LLVM_MINGW}/bin/${_LLVM_TRIPPLE}-clang)
SET(CMAKE_CXX_COMPILER ${LLVM_MINGW}/bin/${_LLVM_TRIPPLE}-clang++)
SET(CMAKE_RC_COMPILER ${LLVM_MINGW}/bin/${_LLVM_TRIPPLE}-windres)
add_compile_options(-gcodeview)
add_link_options(-Wl,-pdb=)
#add_compile_options($<$<CONFIG:DEBUG>:-gcodeview>)
#add_link_options($<$<CONFIG:DEBUG>:-Wl,-pdb=>)


SET(CMAKE_FIND_ROOT_PATH ${LLVM_MINGW}/generic-w64-mingw32 ${LLVM_MINGW}/${_TRIPLE_ARCH}-w64-mingw32/bin)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)  # host env
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ALWAYS) # target env
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)   # target env