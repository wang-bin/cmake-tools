# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2018, Wang Bin
#
# clang + lld to cross build apps for raspberry pi. can be easily change to other target platforms
#
# Options:
# - RPI_SYSROOT or env var RPI_SYSROOT
# - USE_LIBCXX
# TODO: xlocale.h: https://stackoverflow.com/questions/24738059/c-error-locale-t-has-not-been-declared, https://sourceware.org/bugzilla/show_bug.cgi?id=10456
# FIXME: g++8 libm lgammaf32_r@GLIBC_2.27 is missing on stretch(libavcodec/libavformat)
# mini sysroot: https://sourceforge.net/projects/avbuild/files/raspberry-pi/rpi-sysroot.tar.xz/download

set(CMAKE_SYSTEM_PROCESSOR armv6)
set(RPI 1)
set(OS rpi)

if(NOT LINUX_SYSROOT OR NOT EXISTS "${LINUX_SYSROOT}")
  set(LINUX_SYSROOT "${RPI_SYSROOT}")
  if(NOT LINUX_SYSROOT OR NOT EXISTS "${LINUX_SYSROOT}")
    set(LINUX_SYSROOT "$ENV{RPI_SYSROOT}")
  endif()
endif()

# flags for both compiler and linker
set(LINUX_FLAGS "--target=arm-rpi-linux-gnueabihf -mfloat-abi=hard -march=armv6zk -mtune=arm1176jzf-s -mfpu=vfp -marm")
add_definitions(-DOS_RPI)

if(EXISTS /dev/vchiq)
  set(CMAKE_CROSSCOMPILING OFF)
else()
  set(CMAKE_CROSSCOMPILING ON)
endif()

# set options in linux.clang.cmake
set(USE_LIBCXX ON)
include(${CMAKE_CURRENT_LIST_DIR}/linux.clang.cmake)
