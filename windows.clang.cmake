# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2018, Wang Bin
#
# clang-cl + lld to cross build apps for windows. can be easily change to other target platforms
# can not use clang --target=${ARCH}-none-windows-msvc19.0 because cmake will test msvc flags
# -Xclang clang options

# /bin/link will be selected by cmake
# non-windows host: clang-cl invokes link.exe by default, use -fuse-ld=lld works. but -Wl, /link, -Xlinker does not work
option(CLANG_AS_LINKER "use clang as linker to invoke lld. MUST ON for now" OFF) # MUST use lld-link as CMAKE_LINKER on windows host, otherwise ms link.exe is used
option(USE_CLANG_CL "use clang-cl" ON)
option(USE_LIBCXX "use libc++ instead of libstdc++" OFF)
option(UWP "build for uwp" OFF)
option(PHONE "build for phone" OFF)
option(ONECORE "build with oncore" OFF)

set(CMAKE_CROSSCOMPILING ON) # turned on by setting CMAKE_SYSTEM_NAME
if(NOT CMAKE_C_COMPILER)
  set(CMAKE_C_COMPILER clang-cl)
  set(CMAKE_CXX_COMPILER clang-cl)
endif()
if(NOT CLANG_AS_LINKER)
  set(CMAKE_LINKER lld-link  CACHE INTERNAL "lld linker" FORCE)
endif()

if(NOT CMAKE_SYSTEM_PROCESSOR)
  set(CMAKE_SYSTEM_PROCESSOR x86)
endif()
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x.*64")
  set(TARGET_TRIPLE_ARCH x86_64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "86")
  set(TARGET_TRIPLE_ARCH i386)
  set(LIB_ARCH x86)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "a.*64")
  set(TARGET_TRIPLE_ARCH arm64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(TARGET_TRIPLE_ARCH armv7)
endif()
if(NOT LIB_ARCH)
  set(LIB_ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()
set(CMAKE_SYSTEM_NAME Windows) # assume host build if not set, host flags will be used, e.g. apple clang flags are added on macOS
if(UWP)
  set(CMAKE_SYSTEM_NAME WINDOWS_STORE)
  set(WINRT 1)
endif()
if(PHONE)
  set(CMAKE_SYSTEM_NAME WINDOWS_PHONE)
  set(WINRT 1)
endif()
if(WINRT)
  set(WINSTORE 1)
endif()
if(NOT CMAKE_SYSTEM_VERSION)
  if(UWP)
    set(CMAKE_SYSTEM_VERSION 6.3)
  elseif(WINRT OR ONECORE)
    set(CMAKE_SYSTEM_VERSION 6.2)
  else()
    set(CMAKE_SYSTEM_VERSION 5.1)
  endif()
endif()

set(USE_STD_TLS ON)

# flags for both compiler and linker
if(USE_CLANG_CL)
# /std:<value>
  set(WIN_FLAGS "-fms-compatibility -fms-extensions")
endif()
set(WIN_FLAGS "${WIN_FLAGS} --target=${TARGET_TRIPLE_ARCH}-none-windows-msvc19.13.0 -MD") # /arch:${ARCH} has no effect?
#set(WIN_FLAGS "${WIN_FLAGS} -triple ${TARGET_TRIPLE_ARCH}-none-windows-msvc19.13.0 -MD") # /arch:${ARCH} has no effect?
#set(WIN_FLAGS "${WIN_FLAGS} -nostdinc") # skip clang include dir. FIXME: will omit /imsvc options
set(WIN_FLAGS_CXX)

# Sysroot.
if(NOT WindowsSdkDir)
  set(WindowsSdkDir $ENV{WindowsSdkDir})
endif()
if(NOT WindowsSDKVersion)
  set(WindowsSDKVersion $ENV{WindowsSDKVersion})
endif()
if(NOT WindowsSDKVersion)
  set(WindowsSDKVersion 10.0.16299.0)
endif()
if(NOT VCDIR)
  set(VCDIR $ENV{VCDIR})
endif()

#set(CMAKE_SYSROOT ${WIN_SYSROOT})

# llvm-ranlib is for bitcode. but seems works for others. "llvm-ar -s" should be better
# macOS system ranlib does not work
set(CMAKE_RANLIB llvm-ranlib)
set(CMAKE_LLVM_AR llvm-ar)
# llvm-ar for all host platforms. support all kinds of file, including bitcode
get_filename_component(LLVM_DIR ${CMAKE_RANLIB} DIRECTORY) #clang-cl -v: InstalledDir: /usr/local/opt/llvm/bin

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# CMake 3.9 tries to use CMAKE_SYSROOT_COMPILE before it gets set from CMAKE_SYSROOT, which leads to using the system's /usr/include. Set this manually.
# https://github.com/android-ndk/ndk/issues/467
if(CMAKE_SYSROOT)
  set(CMAKE_SYSROOT_COMPILE "${CMAKE_SYSROOT}")
endif()
#set(WIN_CC_FLAGS "-g")
# Debug and release flags.
#set(WIN_CC_FLAGS_DEBUG "-O0 -fno-limit-debug-info")
#set(WIN_CC_FLAGS_RELEASE "-O2 -DNDEBUG")


if(NOT CMAKE_HOST_WIN32)
# llvm-rc error on windows. no effect on other hosts
set(CMAKE_RC_COMPILER_INIT llvm-rc CACHE INTERNAL "windows llvm rc" FORCE)
set(CMAKE_RC_COMPLIER llvm-rc CACHE INTERNAL "windows llvm rc" FORCE)
set(CMAKE_GENERATOR_RC llvm-rc CACHE INTERNAL "windows llvm rc" FORCE)

  if(USE_LIBCXX)
    set(WIN_FLAGS_CXX "${WIN_FLAGS_CXX} -fdelayed-template-parsing -stdlib=libc++") # for both compiler & linker
    # clang generates __cxa_thread_atexit for thread_local, but armhf libc++abi is too old. linking to supc++, libstdc++ results in duplicated symbols when linking static libc++. so never link to supc++. rename to glibc has __cxa_thread_atexit_impl!
  else() # gcc files can be found by clang
    add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-nostdinc++>")
  endif()

  add_compile_options("/imsvc ${VCDIR}/include")
  foreach(m IN ITEMS shared ucrt um winrt)
    add_compile_options("/imsvc ${WindowsSdkDir}/Include/${WindowsSDKVersion}/${m}")
  endforeach()
  link_libraries(/libpath:${VCDIR}/lib/${LIB_ARCH})
  foreach(m IN ITEMS ucrt um)
    link_libraries(/libpath:${WindowsSdkDir}/Lib/${WindowsSDKVersion}/${m}/${LIB_ARCH})
  endforeach()
  macro(WIN_cc_clang lang)
    set(CMAKE_${lang}_LINK_EXECUTABLE
      "<CMAKE_LINKER> <CMAKE_${lang}_LINK_FLAGS> <LINK_FLAGS> <LINK_LIBRARIES> <OBJECTS> -o <TARGET>")                
    set(CMAKE_${lang}_CREATE_SHARED_LIBRARY
      "<CMAKE_LINKER> <CMAKE_${lang}_LINK_FLAGS> <CMAKE_SHARED_LIBRARY_${lang}_FLAGS> <LINK_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_${lang}_FLAGS> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
    set(CMAKE_${lang}_CREATE_SHARED_MODULE
      "<CMAKE_LINKER> <CMAKE_${lang}_LINK_FLAGS> <CMAKE_SHARED_MODULE_${lang}_FLAGS> <LINK_FLAGS> <CMAKE_SHARED_MODULE_CREATE_${lang}_FLAGS> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
  endmacro()

  # clang-cl: /U... is treated as option /U, use -- to treat as file
  # FIXME: MUST change /usr/local/share/cmake/Modules//Platform/Windows-MSVC.cmake +286
  macro(__windows_compiler_clang_cl lang)
    set(CMAKE_${lang}_COMPILE_OBJECT
      "<CMAKE_${lang}_COMPILER> ${CMAKE_START_TEMP_FILE} ${CMAKE_CL_NOLOGO}${_COMPILE_${lang}} <DEFINES> <INCLUDES> <FLAGS> /Fo<OBJECT> /Fd<TARGET_COMPILE_PDB>${_FS_${lang}} -c -- <SOURCE>${CMAKE_END_TEMP_FILE}"
      CACHE INTERNAL "clang-cl ${lang} command" FORCE)
  endmacro()
  if(USE_CLANG_CL)
    __windows_compiler_clang_cl(C)
    __windows_compiler_clang_cl(CXX)
  endif()
  if(NOT CLANG_AS_LINKER)
    WIN_cc_clang(C)
    WIN_cc_clang(CXX)
  endif()
endif()
if(CLANG_AS_LINKER)
  link_libraries(-Wl,--build-id -fuse-ld=lld) # -s: strip
else()
  #set(CMAKE_LINER      "lld" CACHE INTERNAL "linker" FORCE)
  set(WIN_LD_FLAGS "${WIN_LD_FLAGS} --build-id")# --sysroot=${CMAKE_SYSROOT}") # -s: strip

endif()
#53472, 5702912
# Set or retrieve the cached flags. Without these compiler probing may fail!

set(CMAKE_AR         "${CMAKE_LLVM_AR}" CACHE INTERNAL "windows llvm ar" FORCE)
set(CMAKE_C_FLAGS    "${WIN_FLAGS}" CACHE INTERNAL "windows llvm c compiler flags" FORCE)
set(CMAKE_CXX_FLAGS  "${WIN_FLAGS} ${WIN_FLAGS_CXX}"  CACHE INTERNAL "windows llvm c++ compiler/linker flags" FORCE)
set(CMAKE_ASM_FLAGS  "${WIN_FLAGS}"  CACHE INTERNAL "windows llvm asm compiler flags" FORCE)
