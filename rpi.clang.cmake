# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2020, Wang Bin
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
# pi4: -mcpu=arm1176jzf-s -mtune=arm1176jzf-s, -mcpu=cortex-a7/a53/a72 (-march=armv8-a -mtune) -mfloat-abi=hard -mfpu=neon-fp-armv8 -mvectorize-with-neon-quad
# pi1: -mcpu=arm1176jzf-s -mtune=arm1176jzf-s -mfloat-abi=hard -mfpu=vfp
# pi2: -mcpu=cortex-a7 -mfloat-abi=hard -mfpu=neon-vfpv4 -mvectorize-with-neon-quad (-march=armv7-a -mtune=cortex-a7. -marm -mthumb-interwork -mabi=aapcs-linux)
# pi3/4: -mcpu=cortex-a53/72 -mfloat-abi=hard -mfpu=neon-fp-armv8 -mvectorize-with-neon-quad
# -march=armv8-a -mtune=cortex-... <=> -mcpu=cortex-
set(LINUX_FLAGS "-mfloat-abi=hard -march=armv6zk -mtune=arm1176jzf-s -mfpu=vfp -marm")
add_definitions(-DOS_RPI=1)

if(EXISTS /dev/vchiq)
  set(CMAKE_CROSSCOMPILING OFF)
else()
  set(CMAKE_CROSSCOMPILING ON)
endif()

# set options in linux.clang.cmake
if(NOT DEFINED USE_LIBCXX)
  set(USE_LIBCXX ON CACHE INTERNAL "use libc++" FORCE) # cache is required by cmake3.13 option() (CMP0077)
endif()
set(LINUX_FLAGS "${LINUX_FLAGS} -iwithsysroot /opt/vc/include") # check_include_files() requires CMAKE_C_FLAGS
include(${CMAKE_CURRENT_LIST_DIR}/linux.clang.cmake)
#include_directories(SYSTEM ${LINUX_SYSROOT}/opt/vc/include)
#link_directories(${LINUX_SYSROOT}/opt/vc/lib) # no effect
link_libraries(-L${LINUX_SYSROOT}/opt/vc/lib)
