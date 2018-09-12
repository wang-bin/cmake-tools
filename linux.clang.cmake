# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2018, Wang Bin
#
# clang + lld to cross build apps for linux
#

option(CLANG_AS_LINKER "use clang as linker to invoke lld. MUST ON for now" ON)
option(USE_LIBCXX "use libc++ instead of libstdc++" OFF)
option(USE_CXXABI "can be c++abi, stdc++ and supc++. Only required if libc++ is built with none abi" "")
option(USE_TARGET_LIBCXX "libc++ headers bundled with clang are searched and used by default. usually safe if abi is stable. set to true to use target libc++ if version is different" OFF)
option(USE_COMPILER_RT "use compiler-rt instead of libgcc as compiler runtime library" OFF)
option(USE_STD_TLS "use std c++11 thread_local. Only libc++abi 4.0+ is safe for any libc runtime. Turned off internally when necessary" ON) # sunxi ubuntu12.04(glibc-2.15)/rpi(glibc2.13) libc is too old to have __cxa_thread_atexit_impl(requires glibc2.18)
option(LINUX_FLAGS "flags for both compiler and linker, e.g. --target=arm-rpi-linux-gnueabihf ..." "")
option(USE_STDCXX "libstdc++ version to use, MUST be >= 4.8. default is 0, selected by compiler" 0)

set(CMAKE_SYSTEM_NAME Linux) # assume host build if not set, host flags will be used, e.g. apple clang flags are added on macOS
# "/usr/local/opt/llvm/bin/ld.lld" --sysroot=/Users/wangbin/dev/rpi/sysroot -pie -X --eh-frame-hdr -m armelf_linux_eabi -dynamic-linker /lib/ld-linux-armhf.so.3 -o test/audiodec /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/Scrt1.o /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/crti.o /Users/wangbin/dev/rpi/sysroot/lib/../lib/crtbeginS.o -L/Users/wangbin/dev/rpi/sysroot/lib/../lib -L/Users/wangbin/dev/rpi/sysroot/usr/lib/../lib -L/Users/wangbin/dev/rpi/sysroot/lib -L/Users/wangbin/dev/rpi/sysroot/usr/lib --build-id --as-needed --gc-sections --enable-new-dtags -z origin "-rpath=\$ORIGIN" "-rpath=\$ORIGIN/lib" -rpath-link /Users/wangbin/dev/multimedia/mdk/external/lib/rpi/armv6 test/CMakeFiles/audiodec.dir/audiodec.cpp.o libmdk.so.0.1.0 -lc++ -lm -lgcc_s -lgcc -lc -lgcc_s -lgcc /Users/wangbin/dev/rpi/sysroot/lib/../lib/crtendS.o /Users/wangbin/dev/rpi/sysroot/usr/lib/../lib/crtn.o

# Export configurable variables for the try_compile() command. Or set env var like llvm
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  CMAKE_SYSTEM_PROCESSOR
  CMAKE_C_COMPILER # find_program only once
)

if(NOT CMAKE_C_COMPILER)
  find_program(CMAKE_C_COMPILER clang-8 clang-8.0 clang-7.0 clang-6.0 clang-5.0 clang-4.0 clang
    HINTS /usr/local/opt/llvm/bin
    CMAKE_FIND_ROOT_PATH_BOTH
  )
  if(CMAKE_C_COMPILER)
    string(REGEX REPLACE "clang(|-[0-9]+[\\.0]*)$" "clang++\\1" CMAKE_CXX_COMPILER "${CMAKE_C_COMPILER}")
    if(NOT EXISTS "${CMAKE_CXX_COMPILER}") # homebrew, clang-6.0 but clang++ has no suffix
      string(REGEX REPLACE "clang(|-[0-9]+[\\.0]*)$" "clang++" CMAKE_CXX_COMPILER "${CMAKE_C_COMPILER}")
    endif()
  else()
    set(CMAKE_C_COMPILER clang)
    set(CMAKE_CXX_COMPILER clang++)
  endif()
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
execute_process(
  COMMAND ${CMAKE_C_COMPILER} -print-prog-name=llvm-readelf
  OUTPUT_VARIABLE READELF
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
  COMMAND ${CMAKE_C_COMPILER} -print-prog-name=llvm-objcopy
  OUTPUT_VARIABLE CMAKE_LLVM_OBJCOPY
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
get_filename_component(LLVM_DIR ${CMAKE_RANLIB} DIRECTORY)

# Sysroot.
set(CMAKE_SYSROOT ${LINUX_SYSROOT})
file(GLOB_RECURSE PKGCONFIG_DIRS LIST_DIRECTORIES true "${CMAKE_SYSROOT}/usr/lib/*pkgconfig*") # pkgconfig is dir, so LIST_DIRECTORIES must be true (false by default for GLOB_RECURSE)
list(FILTER PKGCONFIG_DIRS INCLUDE REGEX "/pkgconfig")
string(REPLACE ";" ":" PKGCONFIG_DIRS "${PKGCONFIG_DIRS}")
if(CMAKE_CROSSCOMPILING)
  set(ENV{PKG_CONFIG_PATH} "${CMAKE_SYSROOT}/usr/share/pkgconfig:${PKGCONFIG_DIRS}")
endif()
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# CMake 3.9 tries to use CMAKE_SYSROOT_COMPILE before it gets set from CMAKE_SYSROOT, which leads to using the system's /usr/include. Set this manually.
# https://github.com/android-ndk/ndk/issues/467
set(CMAKE_SYSROOT_COMPILE "${CMAKE_SYSROOT}")

set(LINUX_CC_FLAGS "-g")
# Debug and release flags.
set(LINUX_CC_FLAGS_DEBUG "-O0 -fno-limit-debug-info")
set(LINUX_CC_FLAGS_RELEASE "-O2 -DNDEBUG")

if(USE_LIBCXX)
  if(CMAKE_CROSSCOMPILING AND USE_TARGET_LIBCXX) # assume libc++ abi is stable, then USE_TARGET_LIBCXX=0 is ok, i.e. build with host libc++, but run with a different target libc++ version
  # headers in clang builtin include dir(stddef.h etc.). -nobuiltininc makes cross build harder if a header is not found in sysroot(include_next stddef.h in /usr/include/linux/)
    # -nostdinc++: clang always search libc++(-stdlib=libc++) in host toolchain, may mismatch with target libc++ version, and results in conflict(include_next)
    if(CMAKE_VERSION VERSION_LESS 3.3)
      set(LINUX_FLAGS_CXX "${LINUX_FLAGS_CXX} -nostdinc++ -iwithsysroot /usr/include/c++/v1")
    else()
      #add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-stdlib=libc++>")
      add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-nostdinc++;-iwithsysroot;/usr/include/c++/v1>")
    endif()
    # -stdlib=libc++ is not required if -nostdinc++ is set(otherwise warnings)
    link_libraries(-stdlib=libc++) #unlike SUNXI_LD_FLAGS, it will append flags to last
  else()
    set(LINUX_FLAGS_CXX "${LINUX_FLAGS_CXX} -stdlib=libc++") # for both compiler & linker
  endif()
  if(USE_CXXABI)
    link_libraries(-l${USE_CXXABI}) # required if libc++ is built with none abi. otherwise libc++.so is a ld script contains an abi library, e.g. -lc++abi/-lstdc++/-lsupc++
  endif()
  #check_library_exists:  compiler must be detected
  # old libc + old libc++abi: DO NOT use thread_local
  # new/old libc + new libc++abi: use libc++abi tls/fallback
  # new libc + old libc++abi: can not ensure libc runtime thread_local support
  # old libc + stdc++ abi: disable thread_local, stdc++(g++8.0) does not use __cxa_thread_atexit_impl as weak symbol, so can not run on old glibc runtime
  file(GLOB_RECURSE LIBCXX_SO "${CMAKE_SYSROOT}/usr/lib/*libc++.so.1")
  if(LIBCXX_SO)
    execute_process(
      COMMAND ${READELF} -needed-libs ${LIBCXX_SO}
      OUTPUT_VARIABLE LIBCXX_NEEDED
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    string(FIND "${LIBCXX_NEEDED}" libc++abi.so.1 LIBCXX_ABI_LIBCXXABI)
    if(LIBCXX_ABI_LIBCXXABI EQUAL -1)
      message("libc++ is not built as libc++abi. not safe to use thread_local on old libstdc++ runtime")
      #set(USE_STD_TLS OFF)
    else()
      file(GLOB_RECURSE LIBCXXABI_SO "${CMAKE_SYSROOT}/usr/lib/*libc++abi.so.1") #LIST_DIRECTORIES must be true (false by default for GLOB_RECURSE)
      foreach(so IN ITEMS ${LIBCXXABI_SO})
        execute_process(
          COMMAND ${READELF} -symbols ${LIBCXXABI_SO}
          OUTPUT_VARIABLE LIBCXXABI_SYMBOLS
          OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        string(REGEX MATCH "WEAK [A-Z ]* __cxa_thread_atexit_impl" WEAK__cxa_thread_atexit_impl "${LIBCXXABI_SYMBOLS}")
        if(NOT WEAK__cxa_thread_atexit_impl)
          message("libc++abi in build environment is too old to support thread_local on old libc runtime")
          #set(USE_STD_TLS OFF)
        endif()
        break()
      endforeach()
    endif()
  endif()
  file(GLOB_RECURSE LIBC_SO "${CMAKE_SYSROOT}/lib/*libc.so.6")
  execute_process(
    COMMAND ${READELF} -symbols ${LIBC_SO}
    OUTPUT_VARIABLE LIBC_SYMBOLS
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  string(FIND "${LIBC_SYMBOLS}" __cxa_thread_atexit_impl HAS__cxa_thread_atexit_impl)
  if(HAS__cxa_thread_atexit_impl EQUAL -1 AND NOT WEAK__cxa_thread_atexit_impl) # old libc + stdc++/libc++abi<4.0
    # libc++abi 4.0+ check use __cxa_thread_atexit_impl as weak symbol, and can fallback to libc++ own implementation
    message(STATUS "libc in build environment is too old to support C++11 thread_local without libc++abi 4.0+")
    set(USE_STD_TLS OFF)
  endif()
  #if(USE_STD_TLS AND NOT HAS__cxa_thread_atexit_impl EQUAL -1) # AND c++abi is none or libc++abi<4.0, then __cxa_thread_atexit generated by clang(for thread_local) can be replaced by __cxa_thread_atexit_impl
  #  link_libraries(-Wl,-defsym,__cxa_thread_atexit=__cxa_thread_atexit_impl) # libc++ abi is not libc++abi, e.g. stdc++/supc++ abi. clang generated __cxa_thread_atexit is defined in libc++abi 4.0+
  #endif()
else() # gcc files can be found by clang
  if(NOT USE_STDCXX VERSION_LESS 4.8)
  # Selected GCC installation: always the last (greatest version), no way to change it
    add_compile_options(-nostdinc++)
    file(GLOB_RECURSE CXX_DIRS LIST_DIRECTORIES true "${CMAKE_SYSROOT}/usr/include/*c++")
    list(FILTER CXX_DIRS INCLUDE REGEX "/c\\+\\+$")
    foreach(dir IN ITEMS ${CXX_DIRS})
      add_compile_options("-cxx-isystem ${dir}/${USE_STDCXX}")      
    endforeach()
  endif()
endif()

if(CLANG_AS_LINKER)
  link_libraries(-Wl,--build-id -fuse-ld=lld) # -s: strip
  if(USE_COMPILER_RT)
    link_libraries(-rtlib=compiler-rt)
  endif()
else()
  #set(CMAKE_LINER      "lld" CACHE INTERNAL "linker" FORCE)
  set(LINUX_LD_FLAGS "${LINUX_LD_FLAGS} --build-id --sysroot=${CMAKE_SYSROOT}") # -s: strip
  macro(set_cc_clang lang)
    set(CMAKE_${lang}_LINK_EXECUTABLE
        "<CMAKE_LINKER> -flavor gnu <CMAKE_${lang}_LINK_FLAGS> <LINK_FLAGS> <LINK_LIBRARIES> <OBJECTS> -o <TARGET>")                
    set(CMAKE_${lang}_CREATE_SHARED_LIBRARY
        "<CMAKE_LINKER> -flavor gnu <CMAKE_${lang}_LINK_FLAGS> <CMAKE_SHARED_LIBRARY_${lang}_FLAGS> <LINK_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_${lang}_FLAGS> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
    set(CMAKE_${lang}_CREATE_SHARED_MODULE
        "<CMAKE_LINKER> -flavor gnu <CMAKE_${lang}_LINK_FLAGS> <CMAKE_SHARED_MODULE_${lang}_FLAGS> <LINK_FLAGS> <CMAKE_SHARED_MODULE_CREATE_${lang}_FLAGS> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
  endmacro()
  set_cc_clang(C)
  set_cc_clang(CXX)
endif()
#53472, 5702912
# Set or retrieve the cached flags. Without these compiler probing may fail!

set(CMAKE_AR         "${CMAKE_LLVM_AR}" CACHE INTERNAL "${CMAKE_SYSTEM_NAME} ar" FORCE)
#set(CMAKE_OBJCOPY    "${CMAKE_LLVM_OBJCOPY}" CACHE INTERNAL "${CMAKE_SYSTEM_NAME} objcopy" FORCE)
set(CMAKE_C_FLAGS    "${LINUX_FLAGS}" CACHE INTERNAL "${CMAKE_SYSTEM_NAME} c compiler flags" FORCE)
set(CMAKE_CXX_FLAGS  "${LINUX_FLAGS} ${LINUX_FLAGS_CXX}"  CACHE INTERNAL "${CMAKE_SYSTEM_NAME} c++ compiler/linker flags" FORCE)
set(CMAKE_ASM_FLAGS  "${LINUX_FLAGS}"  CACHE INTERNAL "${CMAKE_SYSTEM_NAME} asm compiler flags" FORCE)

set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
