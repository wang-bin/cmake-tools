# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2020, Wang Bin
#
# clang + lld to cross build apps for linux sunxi. can be easily change to other target platforms
#
# Options:
# - SUNXI_SYSROOT or env var SUNXI_SYSROOT
# - USE_LIBCXX
# mini sysroot(with libc++ 6.0): https://sourceforge.net/projects/avbuild/files/sunxi/sunxi-sysroot.tar.xz/download

set(CMAKE_SYSTEM_PROCESSOR armv7)
set(SUNXI 1)
set(OS sunxi)

if(NOT LINUX_SYSROOT OR NOT EXISTS "${LINUX_SYSROOT}")
  set(LINUX_SYSROOT "${SUNXI_SYSROOT}")
  if(NOT LINUX_SYSROOT OR NOT EXISTS "${LINUX_SYSROOT}")
    set(LINUX_SYSROOT "$ENV{SUNXI_SYSROOT}")
  endif()
endif()

# flags for both compiler and linker
# https://wiki.openwrt.org/doc/hardware/soc/soc.allwinner.sunxi
set(LINUX_FLAGS "-mfloat-abi=hard -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mthumb") #-mfpu=vfpv3-d16
add_definitions(-DOS_SUNXI)

if(EXISTS /dev/cedar_dev)
  set(CMAKE_CROSSCOMPILING OFF)
else()
  set(CMAKE_CROSSCOMPILING ON)
endif()

# set options in linux.clang.cmake
if(NOT DEFINED USE_LIBCXX)
  set(USE_LIBCXX ON CACHE INTERNAL "use libc++" FORCE) # cache is required by cmake3.13 option() (CMP0077)
endif()
include(${CMAKE_CURRENT_LIST_DIR}/linux.clang.cmake)
