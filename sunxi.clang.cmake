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
# - SUNXI_SYSROOT or env var SUNXI_SYSROOT
# - USE_LIBCXX
# mini sysroot(with libc++ 6.0): https://sourceforge.net/projects/avbuild/files/sunxi/sunxi-sysroot.tar.xz/download

option(CLANG_AS_LINKER "use clang as linker to invoke lld. MUST ON for now" ON)
option(USE_LIBCXX "use libc++ instead of libstdc++" ON)
option(USE_STD_TLS "use std c++11 thread_local" OFF) # libc does not have __cxa_thread_atexit_impl
# "/usr/local/opt/llvm/bin/ld.lld" --sysroot=/Users/wangbin/dev/rpi/sysroot -pie -X --eh-frame-hdr -m armelf_linux_eabi -dynamic-linker /lib/ld-linux-armhf.so.3 -o test/audiodec /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/Scrt1.o /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/crti.o /Users/wangbin/dev/rpi/sysroot/lib/../lib/crtbeginS.o -L/Users/wangbin/dev/rpi/sysroot/lib/../lib -L/Users/wangbin/dev/rpi/sysroot/usr/lib/../lib -L/Users/wangbin/dev/rpi/sysroot/lib -L/Users/wangbin/dev/rpi/sysroot/usr/lib --build-id --as-needed --gc-sections --enable-new-dtags -z origin "-rpath=\$ORIGIN" "-rpath=\$ORIGIN/lib" -rpath-link /Users/wangbin/dev/multimedia/mdk/external/lib/rpi/armv6 test/CMakeFiles/audiodec.dir/audiodec.cpp.o libmdk.so.0.1.0 -lc++ -lm -lgcc_s -lgcc -lc -lgcc_s -lgcc /Users/wangbin/dev/rpi/sysroot/lib/../lib/crtendS.o /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/crtn.o
set(SUNXI 1)
set(OS sunxi)
if(EXISTS /dev/cedar_dev)
  set(CMAKE_CROSSCOMPILING OFF)
else()
  set(CMAKE_CROSSCOMPILING ON)
endif()

set(CMAKE_SYSTEM_NAME Linux) # assume host build if not set, host flags will be used, e.g. apple clang flags are added on macOS
#set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR armv7)
if(CMAKE_CROSSCOMPILING)
  set(CMAKE_C_COMPILER clang-6.0)
  set(CMAKE_CXX_COMPILER clang++-6.0)
else()
  set(CMAKE_C_COMPILER clang)
  set(CMAKE_CXX_COMPILER clang++)
endif()

# flags for both compiler and linker
# https://wiki.openwrt.org/doc/hardware/soc/soc.allwinner.sunxi
set(SUNXI_FLAGS "--target=arm-sunxi-linux-gnueabihf -mfloat-abi=hard -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mthumb") #-mfpu=vfpv3-d16
set(SUNXI_FLAGS_CXX)

# Sysroot.
set(SUNXI_SYSROOT /Users/wangbin/dev/sunxi/sysroot)
if(NOT SUNXI_SYSROOT)
  set(SUNXI_SYSROOT $ENV{SUNXI_SYSROOT})
endif()
set(CMAKE_SYSROOT ${SUNXI_SYSROOT})
if(CMAKE_CROSSCOMPILING)
  set(ENV{PKG_CONFIG_PATH} "${CMAKE_SYSROOT}/usr/lib/pkgconfig:${CMAKE_SYSROOT}/usr/lib/arm-linux-gnueabihf/pkgconfig:${CMAKE_SYSROOT}/usr/share/pkgconfig")
endif()

# llvm-ranlib is for bitcode. but seems works for others. "llvm-ar -s" should be better
# macOS system ranlib does not work
execute_process(
  COMMAND ${CMAKE_C_COMPILER} -print-prog-name=llvm-ranlib
  OUTPUT_VARIABLE CMAKE_RANLIB
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
# llvm-ar for all host platforms. support all kinds of file, including bitcode
execute_process(
  COMMAND ${CMAKE_C_COMPILER} -print-prog-name=llvm-ar
  OUTPUT_VARIABLE CMAKE_LLVM_AR
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
get_filename_component(LLVM_DIR ${CMAKE_RANLIB} DIRECTORY)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# CMake 3.9 tries to use CMAKE_SYSROOT_COMPILE before it gets set from CMAKE_SYSROOT, which leads to using the system's /usr/include. Set this manually.
# https://github.com/android-ndk/ndk/issues/467
set(CMAKE_SYSROOT_COMPILE "${CMAKE_SYSROOT}")

set(SUNXI_CC_FLAGS "-g")
# Debug and release flags.
set(SUNXI_CC_FLAGS_DEBUG "-O0 -fno-limit-debug-info")
set(SUNXI_CC_FLAGS_RELEASE "-O2 -DNDEBUG")

if(USE_LIBCXX)
  if(CMAKE_CROSSCOMPILING AND USE_TARGET_LIBCXX) # assume libc++ abi is stable, then USE_TARGET_LIBCXX=0 is ok, i.e. build with host libc++, but run with a different target libc++ version
  # headers in clang builtin include dir(stddef.h etc.). -nobuiltininc makes cross build harder if a header is not found in sysroot(include_next stddef.h in /usr/include/linux/)
    # -nostdinc++: clang always search libc++(-stdlib=libc++) in host toolchain, may mismatch with target libc++ version, and results in conflict(include_next)
    if(CMAKE_VERSION VERSION_LESS 3.3)
      set(SUNXI_FLAGS_CXX "${SUNXI_FLAGS_CXX} -nostdinc++ -iwithsysroot /usr/include/c++/v1")
    else()
      #add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-stdlib=libc++>")
      add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-nostdinc++;-iwithsysroot;/usr/include/c++/v1>")
    endif()
    # -stdlib=libc++ is not required if -nostdinc++ is set(otherwise warnings)
    link_libraries(-stdlib=libc++) #unlike SUNXI_LD_FLAGS, it will append flags to last
  else()
    set(SUNXI_FLAGS_CXX "${SUNXI_FLAGS_CXX} -stdlib=libc++") # for both compiler & linker
  endif()
  link_libraries(-lc++abi)
  # clang generates __cxa_thread_atexit for thread_local, but armhf libc++abi is too old. linking to supc++, libstdc++ results in duplicated symbols when linking static libc++. so never link to supc++. rename to glibc has __cxa_thread_atexit_impl!
# link to libc++abi?
  if(USE_STD_TLS)
    link_libraries(-Wl,-defsym,__cxa_thread_atexit=__cxa_thread_atexit_impl)
  endif()
  #link_libraries(-lsupc++)
else() # gcc files can be found by clang
endif()

macro(set_cc_clang lang)
  set(CMAKE_${lang}_LINK_EXECUTABLE
    "<CMAKE_LINKER> -flavor gnu <CMAKE_${lang}_LINK_FLAGS> <LINK_FLAGS> <LINK_LIBRARIES> <OBJECTS> -o <TARGET>")                
  set(CMAKE_${lang}_CREATE_SHARED_LIBRARY
    "<CMAKE_LINKER> -flavor gnu <CMAKE_${lang}_LINK_FLAGS> <CMAKE_SHARED_LIBRARY_${lang}_FLAGS> <LINK_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_${lang}_FLAGS> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
  set(CMAKE_${lang}_CREATE_SHARED_MODULE
    "<CMAKE_LINKER> -flavor gnu <CMAKE_${lang}_LINK_FLAGS> <CMAKE_SHARED_MODULE_${lang}_FLAGS> <LINK_FLAGS> <CMAKE_SHARED_MODULE_CREATE_${lang}_FLAGS> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
endmacro()

if(CLANG_AS_LINKER)
  link_libraries(-Wl,--build-id -fuse-ld=lld) # -s: strip
else()
  #set(CMAKE_LINER      "lld" CACHE INTERNAL "linker" FORCE)
  set(SUNXI_LD_FLAGS "${SUNXI_LD_FLAGS} --build-id --sysroot=${CMAKE_SYSROOT}") # -s: strip
  set_cc_clang(C)
  set_cc_clang(CXX)
endif()
#53472, 5702912
# Set or retrieve the cached flags. Without these compiler probing may fail!

set(CMAKE_AR         "${CMAKE_LLVM_AR}" CACHE INTERNAL "cross ar" FORCE)
set(CMAKE_C_FLAGS    "${SUNXI_FLAGS}" CACHE INTERNAL "cross c compiler flags" FORCE)
set(CMAKE_CXX_FLAGS  "${SUNXI_FLAGS} ${SUNXI_FLAGS_CXX}"  CACHE INTERNAL "cross c++ compiler/linker flags" FORCE)
set(CMAKE_ASM_FLAGS  "${SUNXI_FLAGS}"  CACHE INTERNAL "cross asm compiler flags" FORCE)

set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)