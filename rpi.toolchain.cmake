# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017, Wang Bin
#
# clang + lld to cross build apps for raspberry pi. can be easily change to other target platforms
#

set(CMAKE_SYSTEM_NAME Linux) # assume host build if not set, host flags will be used, e.g. apple clang flags are added on macOS
#set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR armv6)
set(CMAKE_C_COMPILER clang-5.0)
set(CMAKE_CXX_COMPILER clang++-5.0)
set(USE_LIBCXX TRUE)
set(RPI_FLAGS "-stdlib=libc++ -target arm-rpi-linux-gnueabihf -mfloat-abi=hard -march=armv6zk -mtune=arm1176jzf-s -mfpu=vfp -marm")
# Sysroot.
if(NOT RPI_SYSROOT)
  set(RPI_SYSROOT $ENV{RPI_SYSROOT})
endif()
set(CMAKE_SYSROOT ${RPI_SYSROOT})

# llvm-ar support all kinds of file, including bitcode
# llvm-ranlib is for bitcode. but seems works for others. "llvm-ar -s" should be better
# macOS system ranlib does not work
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-prog-name=llvm-ranlib
    OUTPUT_VARIABLE CMAKE_RANLIB
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
get_filename_component(LLVM_DIR ${CMAKE_RANLIB} DIRECTORY)

set(CMAKE_CROSSCOMPILING TRUE)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# CMake 3.9 tries to use CMAKE_SYSROOT_COMPILE before it gets set from CMAKE_SYSROOT, which leads to using the system's /usr/include. Set this manually.
# https://github.com/android-ndk/ndk/issues/467
set(CMAKE_SYSROOT_COMPILE "${CMAKE_SYSROOT}")

set(RPI_CC_FLAGS "-g")
set(RPI_LD_FLAGS "-Wl,--build-id -s -fuse-ld=lld")
# Debug and release flags.
set(RPI_CC_FLAGS_DEBUG "-O0 -fno-limit-debug-info") #-s strip
set(RPI_CC_FLAGS_RELEASE "-O2 -DNDEBUG")

# Set or retrieve the cached flags. Without these compiler probing may fail!
set(CMAKE_C_FLAGS "" CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_CXX_FLAGS "" CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_ASM_FLAGS "" CACHE STRING "Flags used by the compiler during all build types.")
set(CMAKE_C_FLAGS_DEBUG "" CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_CXX_FLAGS_DEBUG "" CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_ASM_FLAGS_DEBUG "" CACHE STRING "Flags used by the compiler during debug builds.")
set(CMAKE_C_FLAGS_RELEASE "" CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_CXX_FLAGS_RELEASE "" CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_ASM_FLAGS_RELEASE "" CACHE STRING "Flags used by the compiler during release builds.")
set(CMAKE_MODULE_LINKER_FLAGS "" CACHE STRING "Flags used by the linker during the creation of modules.")
set(CMAKE_SHARED_LINKER_FLAGS "" CACHE STRING "Flags used by the linker during the creation of dll's.")
set(CMAKE_EXE_LINKER_FLAGS "" CACHE STRING "Flags used by the linker.")
   
set(CMAKE_C_FLAGS             "${RPI_FLAGS} ${CMAKE_C_FLAGS}")
set(CMAKE_CXX_FLAGS           "${RPI_FLAGS} ${RPI_FLAGS_CXX} ${CMAKE_CXX_FLAGS}")
set(CMAKE_ASM_FLAGS           "${RPI_FLAGS} ${CMAKE_ASM_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG       "${RPI_CC_FLAGS_DEBUG} ${CMAKE_C_FLAGS_DEBUG}")
set(CMAKE_CXX_FLAGS_DEBUG     "${RPI_CC_FLAGS_DEBUG} ${CMAKE_CXX_FLAGS_DEBUG}")
set(CMAKE_ASM_FLAGS_DEBUG     "${RPI_CC_FLAGS_DEBUG} ${CMAKE_ASM_FLAGS_DEBUG}")
set(CMAKE_C_FLAGS_RELEASE     "${RPI_CC_FLAGS_RELEASE} ${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_RELEASE   "${RPI_CC_FLAGS_RELEASE} ${CMAKE_CXX_FLAGS_RELEASE}")
set(CMAKE_ASM_FLAGS_RELEASE   "${RPI_CC_FLAGS_RELEASE} ${CMAKE_ASM_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS "${RPI_LD_FLAGS} ${CMAKE_SHARED_LINKER_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${RPI_LD_FLAGS} ${CMAKE_MODULE_LINKER_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS    "${RPI_LD_FLAGS} ${RPI_LD_FLAGS_EXE} ${CMAKE_EXE_LINKER_FLAGS}")

set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
