# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2024, Wang Bin
#
#cross build apps for linux
#
# LINUX_FLAGS: flags for both compiler and linker, e.g. --target=arm-rpi-linux-gnueabihf ...
# CMAKE_SYSTEM_PROCESSOR: REQUIRED
# vars: CXXCONFIG_H_DIR, LIBSTDCXX_SO

option(USE_STDCXX "libstdc++ version to use, MUST >= 4.8. default is 0, selected by compiler" 0)


if(NOT OS)
  set(OS Linux)
endif()
set(CMAKE_SYSTEM_NAME Linux) # assume host build if not set, host flags will be used, e.g. apple clang flags are added on macOS
if(NOT CMAKE_SYSTEM_PROCESSOR)
  message("CMAKE_SYSTEM_PROCESSOR for target is not set. Must be aarch64(arm64), armv7(arm), x86(i386,i686), x64(x86_64). Assumeme build for host arch: ${CMAKE_HOST_SYSTEM_PROCESSOR}.")
  set(CMAKE_SYSTEM_PROCESSOR ${CMAKE_HOST_SYSTEM_PROCESSOR})
endif()
if(CMAKE_SYSTEM_PROCESSOR MATCHES "[aA].*[rR].*64") # arm64, aarch64
  set(TRIPLE_ARCH aarch64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm.*hf") # armhf, armv7hf, armv6kzhf
  string(REPLACE "hf" "" __MARCH "${CMAKE_SYSTEM_PROCESSOR}")
  if(NOT ${__MARCH} STREQUAL "arm")
    add_compile_options(-march=${__MARCH})
  endif()
  set(TRIPLE_ARCH arm) # will affect lib dir search, e.g. /lib/${TRIPLE_ARCH}-linux-gnueabihf
  set(TRIPLE_ABI eabihf) # armhf: -mfloat-abi=hard
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(TRIPLE_ARCH arm) # will affect lib dir search, e.g. /lib/${TRIPLE_ARCH}-linux-gnueabihf
  set(TRIPLE_ABI eabi) # armel: -mfloat-abi=soft -mfloat-abi=softfp
  if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "arm" AND NOT LINUX_FLAGS MATCHES "-march=")
    add_compile_options(-march=${CMAKE_SYSTEM_PROCESSOR})
  endif()
  if(LINUX_FLAGS MATCHES "-mfloat-abi=hard")
    set(TRIPLE_ABI eabihf) # TARGET_TRIPPLE will affect lib dir search
  endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "64")
  set(TRIPLE_ARCH x86_64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "86")
  set(TRIPLE_ARCH i386)
endif()
if(NOT DEFINED USE_CRT) # can be gnu, musl
  set(USE_CRT gnu)
endif()
if(NOT "${USE_CRT}" STREQUAL "")
  set(TARGET_ABI "-${USE_CRT}${TRIPLE_ABI}")
endif()
# arch[sub][-vendor]-sys[-abi]
set(TARGET_TRIPPLE ${TRIPLE_ARCH}${TARGET_VENDOR}-linux${TARGET_ABI})
set(CMAKE_LIBRARY_ARCHITECTURE ${TARGET_TRIPPLE}) # FIND_LIBRARY search subdir

# Export configurable variables for the try_compile() command. Or set env var like llvm
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  CMAKE_SYSTEM_PROCESSOR
  CMAKE_C_COMPILER # find_program only once
  LINUX_FLAGS
  #LINUX_SYSROOT
)

# Sysroot.
#message("CMAKE_SYSROOT_COMPILE: ${CMAKE_SYSROOT_COMPILE}, ${CMAKE_CROSSCOMPILING}")
if(EXISTS "${LINUX_SYSROOT}")
  set(CMAKE_SYSROOT ${LINUX_SYSROOT})
# CMake 3.9 tries to use CMAKE_SYSROOT_COMPILE before it gets set from CMAKE_SYSROOT, which leads to using the system's /usr/include. Set this manually.
# https://github.com/android-ndk/ndk/issues/467
  set(CMAKE_SYSROOT_COMPILE "${CMAKE_SYSROOT}")
endif()
if(CMAKE_CROSSCOMPILING) # default is true
  set(ENV{PKG_CONFIG_PATH} "${CMAKE_SYSROOT}/usr/share/pkgconfig:${CMAKE_SYSROOT}/usr/lib/${TARGET_TRIPPLE}/pkgconfig")
endif()
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

file(GLOB_RECURSE _LIBSTDCXX_SOS LIST_DIRECTORIES false "${CMAKE_SYSROOT}/usr/lib/gcc/${TARGET_TRIPPLE}/*/libstdc++.so")
if(_LIBSTDCXX_SOS)
  list(GET _LIBSTDCXX_SOS -1 LIBSTDCXX_SO)
endif()

set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)

if(NOT USE_STDCXX VERSION_LESS 4.8)
  set(CXXCONFIG_H_DIR ${CMAKE_SYSROOT}/usr/include/${TARGET_TRIPPLE}/c++/${USE_STDCXX}) # c++config.h dir
  if(NOT EXISTS ${CXXCONFIG_H_DIR}/bits/c++config.h)
  # redhat
    set(CXXCONFIG_H_DIR ${CMAKE_SYSROOT}/usr/include/c++/${USE_STDCXX}/${TARGET_TRIPPLE})
  endif()
endif()

# CentOS

if(NOT RHEL_MAJOR)
  file(STRINGS "${CMAKE_SYSROOT}/usr/include/linux/version.h" centos_ver_str REGEX "^#[\t ]*define[\t ]+RHEL_M[A-Z]*[\t ]+[0-9]+$")
  foreach(VLINE ${centos_ver_str})
    if(VLINE MATCHES "^#[\t ]*define[\t ]+RHEL_MAJOR[\t ]+([0-9]+)$")
      set(RHEL_MAJOR "${CMAKE_MATCH_1}")
    endif()
    if(VLINE MATCHES "^#[\t ]*define[\t ]+RHEL_MINOR[\t ]+([0-9]+)$")
      set(RHEL_MINOR "${CMAKE_MATCH_1}")
    endif()
  endforeach()
  if(NOT RHEL_MAJOR GREATER 0)
    set(RHEL_MAJOR 7)
    set(RHEL_MINOR 0)
  endif()
endif()
