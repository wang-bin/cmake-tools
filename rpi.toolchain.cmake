# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2018, Wang Bin
#
# clang + lld to cross build apps for raspberry pi. can be easily change to other target platforms
#
option(CLANG_AS_LINKER "use clang as linker to invoke lld. MUST ON for now" ON)
option(USE_LIBCXX "use libc++ instead of libstdc++" ON)
# "/usr/local/opt/llvm/bin/ld.lld" --sysroot=/Users/wangbin/dev/rpi/sysroot -pie -X --eh-frame-hdr -m armelf_linux_eabi -dynamic-linker /lib/ld-linux-armhf.so.3 -o test/audiodec /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/Scrt1.o /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/crti.o /Users/wangbin/dev/rpi/sysroot/lib/../lib/crtbeginS.o -L/Users/wangbin/dev/rpi/sysroot/lib/../lib -L/Users/wangbin/dev/rpi/sysroot/usr/lib/../lib -L/Users/wangbin/dev/rpi/sysroot/lib -L/Users/wangbin/dev/rpi/sysroot/usr/lib --build-id --as-needed --gc-sections --enable-new-dtags -z origin "-rpath=\$ORIGIN" "-rpath=\$ORIGIN/lib" -rpath-link /Users/wangbin/dev/multimedia/mdk/external/lib/rpi/armv6 test/CMakeFiles/audiodec.dir/audiodec.cpp.o libmdk.so.0.1.0 -lc++ -lm -lgcc_s -lgcc -lc -lgcc_s -lgcc /Users/wangbin/dev/rpi/sysroot/lib/../lib/crtendS.o /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/crtn.o

if(EXISTS /dev/vchiq)
  set(CMAKE_CROSSCOMPILING OFF)
else()
  set(CMAKE_CROSSCOMPILING ON)
endif()

set(CMAKE_SYSTEM_NAME Linux) # assume host build if not set, host flags will be used, e.g. apple clang flags are added on macOS
#set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR armv6)
if(CMAKE_CROSSCOMPILING)
  set(CMAKE_C_COMPILER clang-5.0)
  set(CMAKE_CXX_COMPILER clang++-5.0)
else()
  set(CMAKE_C_COMPILER clang)
  set(CMAKE_CXX_COMPILER clang++)
endif()

set(USE_STD_TLS ON)

# flags for both compiler and linker
set(RPI_FLAGS "--target=arm-rpi-linux-gnueabihf -mfloat-abi=hard -march=armv6zk -mtune=arm1176jzf-s -mfpu=vfp -marm")
set(RPI_FLAGS_CXX)

# Sysroot.
if(NOT RPI_SYSROOT)
  set(RPI_SYSROOT $ENV{RPI_SYSROOT})
endif()
set(CMAKE_SYSROOT ${RPI_SYSROOT})

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

set(RPI_CC_FLAGS "-g")
# Debug and release flags.
set(RPI_CC_FLAGS_DEBUG "-O0 -fno-limit-debug-info")
set(RPI_CC_FLAGS_RELEASE "-O2 -DNDEBUG")

if(USE_LIBCXX)
  if(CMAKE_CROSSCOMPILING)
    # clang always search libc++ in host toolchain and results in conflict(include_next)
    add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-nostdinc++>)
    add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-iwithsysroot;/usr/include/c++/v1>)
    # -stdlib=libc++ is not required if -nostdinc++ is set(otherwise warnings)
    link_libraries(-stdlib=libc++) #unlike RPI_LD_FLAGS, it will append flags to last
  else()
    set(RPI_FLAGS_CXX "-stdlib=libc++")
  endif()
  # clang generates __cxa_thread_atexit for thread_local, but armhf libc++abi is too old. linking to supc++, libstdc++ results in duplicated symbols when linking static libc++. so never link to supc++. rename to glibc has __cxa_thread_atexit_impl!
# link to libc++abi?
  link_libraries(-Wl,-defsym,__cxa_thread_atexit=__cxa_thread_atexit_impl)
  #link_libraries(-lsupc++)
else()
  if(CMAKE_CROSSCOMPILING) # FIXME: math.h declaration conflicts with target of using declaration already in scope. try g++4.9
    add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-iwithsysroot;/usr/include/arm-linux-gnueabihf/c++/7;-iwithsysroot;/usr/include/c++/7>)
  endif()
endif()

macro(rpi_cc_clang lang)
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
  set(CMAKE_LINKER lld)
  set(RPI_LD_FLAGS "${RPI_LD_FLAGS} --build-id --sysroot=${CMAKE_SYSROOT}") # -s: strip
  rpi_cc_clang(C)
  rpi_cc_clang(CXX)
endif()
#53472, 5702912
# Set or retrieve the cached flags. Without these compiler probing may fail!

set(CMAKE_LINER      "lld")
set(CMAKE_AR         "${CMAKE_LLVM_AR}" CACHE INTERNAL "rpi ar" FORCE)
set(CMAKE_C_FLAGS    "${RPI_FLAGS}" CACHE INTERNAL "rpi c compiler flags" FORCE)
set(CMAKE_CXX_FLAGS  "${RPI_FLAGS} ${RPI_FLAGS_CXX}"  CACHE INTERNAL "rpi c++ compiler flags" FORCE)
set(CMAKE_ASM_FLAGS  "${RPI_FLAGS}"  CACHE INTERNAL "rpi asm compiler flags" FORCE)

set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)