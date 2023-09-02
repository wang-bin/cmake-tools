# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2023, Wang Bin
##
# defined vars:
# - EXTRA_INCLUDE
# defined functions
# -

# TODO: pch, auto add target dep libs dir to rpath-link paths. rc file
#-z nodlopen, --strip-lto-sections, -Wl,--allow-shlib-undefined
# harden: https://github.com/opencv/opencv/commit/1961bb1857d5d3c9a7e196d52b0c7c459bc6e619
# llvm-objcopy --weaken-symbol
# windres, llvm-mt, mt, exe/dll manifest
# always set policies to ensure they are applied on every project's policy stack
# include() with NO_POLICY_SCOPE to apply the cmake_policy in parent scope
# TODO: vc 1913+  "-Zc:__cplusplus -std:c++14" to correct __cplusplus. see qt msvc-version.conf. https://blogs.msdn.microsoft.com/vcblog/2018/04/09/msvc-now-correctly-reports-__cplusplus/
# MinSizeRelWithDebInfo
# cmake_dependent_option
# add_link_options, target_link_options/directories,
if(POLICY CMP0022) # since 2.8.12. link_libraries()
  cmake_policy(SET CMP0022 NEW)
endif()
if(POLICY CMP0063) # visibility. since 3.3
  cmake_policy(SET CMP0063 NEW)
endif()

if(TOOLS_CMAKE_INCLUDED)
  return()
endif()
set(TOOLS_CMAKE_INCLUDED 1)

option(ELF_HARDENED "Enable ELF hardened flags. Toolchain file from NDK override the flags" ON)
option(USE_LTO "Link time optimization. 0: disable; 1: enable; N: N parallelism. thin: thin LTO. TRUE: max parallelism. See also CMAKE_INTERPROCEDURAL_OPTIMIZATION" 0)
option(SANITIZE "Enable address sanitizer. Debug build is required" OFF)
option(COVERAGE "Enable source based code coverage(gcc/clang)" OFF)
option(STATIC_LIBGCC "Link to static libgcc, useful for windows" OFF) # WIN32 AND CMAKE_C_COMPILER_ID GNU
option(NO_RTTI "Enable C++ rtti" ON)
option(NO_EXCEPTIONS "Enable C++ exceptions" ON)
option(LIBCXX_COMPAT "compatible with legacy libc++, supports new header from toolchain but link against legacy libs in sysroot, also required at runtime if hardened is enabled. e.g. libc++17 -fno-exceptions may requires __libcpp_verbose_abort." ON)
option(USE_ARC "Enable ARC for ObjC/ObjC++" ON)
option(USE_BITCODE "Enable bitcode for Apple" OFF)
option(USE_BITCODE_MARKER "Enable bitcode marker for Apple" OFF)
option(MIN_SIZE "Reduce size further for clang" OFF)
option(USE_CFGUARD "Enable control flow guard" ON)
option(USE_MOLD "Use mold linker" OFF) # smaller binary for apple

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

include(CMakeParseArguments)
include(CheckCCompilerFlag)
include(CheckCXXCompilerFlag)
include(${CMAKE_CURRENT_LIST_DIR}/add_flags.cmake NO_POLICY_SCOPE)

# set CMAKE_SYSTEM_PROCESSOR, CMAKE_SYSROOT, CMAKE_<LANG>_COMPILER for cross build
# if host/cross gcc build has opt/vc in sysroot, assume it's for rpi, and defines RPI_VC_DIR for use externally
if(NOT RPI)
  execute_process(
      COMMAND ${CMAKE_C_COMPILER} -print-sysroot  #clang does not support -print-sysroot
      OUTPUT_VARIABLE CC_SYSROOT
      ERROR_VARIABLE SYSROOT_ERROR
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(EXISTS ${CC_SYSROOT}/opt/vc/include/bcm_host.h)
    set(RPI_SYSROOT ${CC_SYSROOT})
    set(RPI 1)
    set(OS rpi)
    add_definitions(-DOS_RPI=1)
    # unset os detected as host when cross compiling
    unset(APPLE)
    unset(WIN32)
    if(NOT EXISTS /dev/vchiq)
      set(CMAKE_CROSSCOMPILING TRUE)
    endif()
    add_link_options(-L=/opt/vc/lib)
    message("Raspberry Pi cross build: ${CMAKE_CROSSCOMPILING}")
  endif()
endif()

if(NOT ARCH)
# cmake only probes compiler arch for msvc as it's 1 toolchain per arch. we can probes other compilers like msvc, but multi arch build(clang for apple) is an exception
# here we simply use cmake vars with some reasonable assumptions
  set(ARCH ${CMAKE_C_COMPILER_ARCHITECTURE_ID}) # msvc only, MSVC_C_ARCHITECTURE_ID
  if(NOT ARCH)
    set(ARCH ${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}) # if languages has no c but c++, e.g. flutter generated projects
  endif()
  if(NOT ARCH)
    # assume CMAKE_SYSTEM_PROCESSOR is set correctly(e.g. in toolchain file). can equals to CMAKE_HOST_SYSTEM_PROCESSOR, e.g. ios simulator
    set(ARCH ${CMAKE_SYSTEM_PROCESSOR})
    if(NOT ARCH)
      set(ARCH ${CMAKE_HOST_SYSTEM_PROCESSOR})
    endif()
  endif()
endif()

if(WIN32 AND NOT WINDOWS_PHONE AND NOT WINDOWS_STORE)
  set(WINDOWS_DESKTOP 1)
endif()
if(WIN32)
  if(ARCH STREQUAL ARMV7)
    set(ARCH arm)
  elseif(ARCH STREQUAL ARM64)
    set(ARCH arm64)
  endif()
endif()
if(WINDOWS_PHONE OR WINDOWS_STORE)
  set(OS WinRT)
  set(WINRT 1)
  set(WINSTORE 1)
endif()
if(WINDOWS_DESKTOP AND ARCH MATCHES "arm" AND NOT _ARM_WINAPI_PARTITION_DESKTOP_SDK_AVAILABLE_SET)
  add_definitions(-D_ARM_WINAPI_PARTITION_DESKTOP_SDK_AVAILABLE=1)
endif()
set(WIN_VER_DEFAULT 6.0)
if(WINRT AND NOT WINRT_SET)
  # SEH?
  if(WINDOWS_PHONE)
    set(WIN_VER_DEFAULT 6.3)
    if(NOT CMAKE_GENERATOR MATCHES "Visual Studio")
      add_definitions(-DWINAPI_FAMILY=WINAPI_FAMILY_PHONE_APP)
    endif()
  else()
    set(WIN_VER_DEFAULT 10.0)
    if(NOT CMAKE_GENERATOR MATCHES "Visual Studio")
      add_definitions(-DWINAPI_FAMILY=WINAPI_FAMILY_APP)
    endif()
  endif()
  #add_compile_options(-ZW) #C++/CX, defines __cplusplus_winrt
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -appcontainer -nodefaultlib:kernel32.Lib -nodefaultlib:Ole32.Lib")
  set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -appcontainer -nodefaultlib:kernel32.Lib -nodefaultlib:Ole32.Lib")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -appcontainer -nodefaultlib:kernel32.Lib -nodefaultlib:Ole32.Lib")
endif()

if(WINDOWS_XP AND MSVC AND NOT WINDOWS_XP_SET) # move too win.cmake?
  set(WIN_VER_DEFAULT 5.1)
  if(CMAKE_CL_64)
    set(WIN_VER_DEFAULT 5.2)
  endif()
  unset(CMAKE_SYSTEM_VERSION)
  foreach(lang C CXX)
    set(CMAKE_${lang}_CREATE_CONSOLE_EXE -subsystem:console,${WIN_VER_DEFAULT}) # mingw: --subsystem name:x[.y]
    set(CMAKE_${lang}_CREATE_WIN32_EXE -subsystem:windows,${WIN_VER_DEFAULT}) # mingw: --subsystem name:x[.y]
  endforeach()
endif()

if(MSVC AND NOT CMAKE_CXX_SIMULATE_ID MATCHES MSVC AND NOT WIN_VER_HEX)
# cmake3.10 does not define _WIN32_WINNT even if CMAKE_SYSTEM_VERSION is set? only set for msvc cl
  macro(dec_to_hex VAR VAL)
    if (${VAL} LESS 10)
      SET(${VAR} ${VAL})
    else()
      math(EXPR A "55 + ${VAL}")
      string(ASCII ${A} ${VAR})
    endif()
  endmacro(dec_to_hex)
  if(NOT CMAKE_SYSTEM_VERSION)
    set(CMAKE_SYSTEM_VERSION ${WIN_VER_DEFAULT})
  endif()
  string(REGEX MATCH "([0-9]*)\\.([0-9]*)" matched ${CMAKE_SYSTEM_VERSION})
  set(WIN_MAJOR ${CMAKE_MATCH_1})
  set(WIN_MINOR ${CMAKE_MATCH_2})
  dec_to_hex(WIN_MAJOR_HEX ${WIN_MAJOR})
  dec_to_hex(WIN_MINOR_HEX ${WIN_MINOR})
  set(WIN_VER_HEX 0x0${WIN_MAJOR_HEX}0${WIN_MINOR_HEX})
  add_compile_options($<$<COMPILE_LANGUAGE:C,CXX>:-nologo>)
  add_definitions(-DUNICODE -D_UNICODE -D_WIN32_WINNT=${WIN_VER_HEX})
endif()

if(NOT OS)
  if(WIN32)
    set(OS windows)
  elseif(APPLE)
    if(MACCATALYST)
      set(OS macCatalyst)
    elseif(IOS)
      set(OS iOS)
    else()
      set(OS macOS)
    endif()
    set(ARCH) # assume always use multi arch library
  elseif(ANDROID)
    set(OS android)
    if(ANDROID_NDK_TOOLCHAIN_INCLUDED OR ANDROID_TOOLCHAIN) # ANDROID_NDK_TOOLCHAIN_INCLUDED is defined in r15
      set(ANDROID_NDK_TOOLCHAIN_INCLUDED TRUE)
    endif()
    if(NOT ANDROID_NDK_TOOLCHAIN_INCLUDED) # use cmake android support instead of toolchain files from NDK
        set(ANDROID_ABI ${CMAKE_ANDROID_ARCH_ABI}) #CMAKE_SYSTEM_PROCESSOR
        set(ANDROID_STL ${CMAKE_ANDROID_STL_TYPE})
        set(ANDROID_TOOLCHAIN_PREFIX ${CMAKE_CXX_ANDROID_TOOLCHAIN_PREFIX})
    endif()
    set(ARCH ${ANDROID_ABI})
  elseif(LINUX) # cmake 3.25
    set(OS Linux)
  else()
    set(OS ${CMAKE_SYSTEM_NAME}) # CMAKE_SYSTEM_NAME == Linux for cmake<3.25
  endif()
endif()

if(WIN32)
  if(ARCH MATCHES 86_64 OR ARCH MATCHES AMD64)
    set(ARCH x64)
  endif()
endif()
if(ARCH MATCHES 86 AND NOT ARCH MATCHES 64)
  set(ARCH x86)
endif()

if(APPLE)
  #add_compile_options(-target x86_64-apple-ios13.0-macabi -iframeworkwithsysroot /System/iOSSupport/System/Library/Frameworks)
  #link_libraries("-F /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.15.sdk/System/iOSSupport/System/Library/Frameworks")
  #add_compile_options(-gdwarf-2)
  set(CMAKE_INSTALL_NAME_DIR "@rpath")
  if(USE_BITCODE)
    add_compile_options(-fembed-bitcode)
    add_link_options(-fembed-bitcode)
  elseif(USE_BITCODE_MARKER)
    add_compile_options(-fembed-bitcode-marker)
    add_link_options(-fembed-bitcode-marker)
  endif()

  if(NOT IOS_BITCODE) # ios.cmake
    set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE ${USE_BITCODE})
  endif()
  if(USE_BITCODE)
    set(CMAKE_XCODE_ATTRIBUTE_BITCODE_GENERATION_MODE "bitcode") # Without this, Xcode adds -fembed-bitcode-marker compile options instead of -fembed-bitcode  set(CMAKE_C_FLAGS "-fembed-bitcode ${CMAKE_C_FLAGS}")
  endif()
endif()

if(CMAKE_CXX_STANDARD AND NOT CMAKE_CXX_STANDARD LESS 11)
  if(CMAKE_VERSION VERSION_LESS 3.1)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++${CMAKE_CXX_STANDARD}") # $<COMPILE_LANGUAGE:CXX> requires cmake3.4+
    endif()
  endif()
  if(APPLE)
    # Check AppleClang requires cmake>=3.0 and set CMP0025 to NEW. FIXME: It's still Clang with ios toolchain file
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL AppleClang) #headers with objc syntax, clang attributes error
      if(CMAKE_CXX_COMPILER_ID STREQUAL Clang)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
      else() # FIXME: gcc can not recognize clang attributes and objc syntax
      endif()
    endif()
    # CMAKE_OSX_DEPLOYMENT_TARGET is set to host os version by cmake if not set by user
    if(IOS)
      if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
        set(CMAKE_OSX_DEPLOYMENT_TARGET 8.0)
      endif()
    else()
      if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
        set(CMAKE_OSX_DEPLOYMENT_TARGET 10.9)
      endif()
      if(NOT CMAKE_OSX_ARCHITECTURES) # host build
        set(CMAKE_OSX_ARCHITECTURES ${CMAKE_SYSTEM_PROCESSOR})
      endif()
      if(CMAKE_OSX_ARCHITECTURES MATCHES arm64 AND CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 11.0)
        set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0)
      endif()
      if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 10.9)
        if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 10.7)
          if(CMAKE_CXX_COMPILER_ID STREQUAL AppleClang)
              message("Apple clang does not support c++${CMAKE_CXX_STANDARD} for macOS 10.6")
          endif()
        else()
          set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
        endif()
      endif()
    endif()
    message("CMAKE_OSX_DEPLOYMENT_TARGET: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
  endif()
endif()

if(USE_MOLD)
  add_link_options(-fuse-ld=mold)
endif()
if(MSVC AND CMAKE_C_COMPILER_VERSION VERSION_GREATER 19.0.23918.0) #update2
  add_compile_options(-utf-8)  # no more codepage warnings
endif()
check_cxx_compiler_flag("-W4 -WX -JMC" HAS_C_FLAG_JMC)
if(HAS_C_FLAG_JMC)
  add_compile_options($<$<AND:$<COMPILE_LANGUAGE:C,CXX>,$<CONFIG:DEBUG>>:-JMC>) # clang-cl-15 supports JMC with Zi(pdb) or Z7 enabled
endif()

if(WIN32 AND NOT CMAKE_SYSTEM_PROCESSOR MATCHES 64)
  if(MSVC)
    add_link_options(/LARGEADDRESSAWARE)
  else()
    add_link_options(-Wl,--large-address-aware)
  endif()
endif()

check_c_compiler_flag(-Wunused HAVE_WUNUSED)
if(HAVE_WUNUSED)
  add_compile_options(-Wunused)
endif()
if(APPLE AND USE_ARC)
  add_compile_options($<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>) #FIXME: OBJC/OBJCXX not recognized
endif()
# TODO: set(MY_FLAGS "..."), disable_if(MY_FLAGS): test MY_FLAGS, set to empty if not supported
# TODO: test_lflags(var, flags), enable_lflags(flags)
function(test_lflags var flags)
  string(STRIP "${flags}" flags_stripped)
  if("${flags_stripped}" STREQUAL "")
    return()
  endif()
  list(APPEND CMAKE_REQUIRED_LIBRARIES "${flags_stripped}") # CMAKE_REQUIRED_LIBRARIES scope is function local
  # unsupported flags can be a warning (clang, vc)
  if(MSVC)
    list(APPEND CMAKE_REQUIRED_LIBRARIES "/WX") # FIXME: why -WX does not work?
  else()
    list(APPEND CMAKE_REQUIRED_LIBRARIES "-Werror")
  endif()
  #unset(HAVE_LDFLAG_${var} CACHE) # cached by check_cxx_compiler_flag
  check_cxx_compiler_flag("" HAVE_LDFLAG_${var})
  if(HAVE_LDFLAG_${var})
    set(V "${${var}} ${flags_stripped}")
    string(STRIP "${V}" V)
    set(${var} ${V} PARENT_SCOPE)
  endif()
endfunction()

if(ANDROID)
  if(NOT ANDROID_NDK)
    if(CMAKE_ANDROID_NDK)
      set(ANDROID_NDK ${CMAKE_ANDROID_NDK})
    else()
      set(ANDROID_NDK $ENV{ANDROID_NDK})
    endif()
  endif()
  # TODO: ndk19 add toolchain sysroot, e.g. ${ANDROID_TOOLCHAIN_ROOT}/sysroot/usr/lib/${ANDROID_TOOLCHAIN_NAME}/${ANDROID_PLATFORM_LEVEL}
  if(ANDROID_TOOLCHAIN_NAME)
  string(REPLACE "-clang" "" ANDROID_TOOLCHAIN_NAME_BASE ${ANDROID_TOOLCHAIN_NAME})
  set(ANDROID_PLATFORM_LIBS_DIR ${ANDROID_SYSROOT}/usr/lib/${ANDROID_TOOLCHAIN_NAME_BASE}/${ANDROID_PLATFORM_LEVEL})
  if(NOT EXISTS "${ANDROID_PLATFORM_LIBS_DIR}") # ANDROID_SYSROOT is removed in r20
    set(ANDROID_PLATFORM_LIBS_DIR ${CMAKE_SYSROOT}/usr/lib/${ANDROID_TOOLCHAIN_NAME_BASE}/${ANDROID_PLATFORM_LEVEL})
  endif()
  if(ANDROID_STL MATCHES "^c\\+\\+_")
    set(ANDROID_STL_LIB_DIR ${ANDROID_NDK}/sources/cxx-stl/llvm-libc++/libs/${ANDROID_ABI})
    if(NOT EXISTS "${ANDROID_STL_LIB_DIR}")
      set(ANDROID_STL_LIB_DIR "${ANDROID_PLATFORM_LIBS_DIR}/../")
    endif()
  elseif(ANDROID_STL MATCHES "^gnustl_")
    if(ANDROID_STL_PREFIX) # toolchain file from ndk
      set(ANDROID_STL_LIB_DIR ${ANDROID_NDK}/sources/cxx-stl/${ANDROID_STL_PREFIX}/libs/${ANDROID_ABI})
    elseif(CMAKE_ANDROID_NDK_TOOLCHAIN_VERSION) # can be clang. what if clang use gnustl?
      set(ANDROID_STL_LIB_DIR ${ANDROID_NDK}/sources/cxx-stl/gnu-libstdc++/${CMAKE_ANDROID_NDK_TOOLCHAIN_VERSION}/libs/${ANDROID_ABI})
    endif()
  endif()
  # stl link dir may be defined in ${ANDROID_LINKER_FLAGS}
  if(NOT EXISTS "${ANDROID_PLATFORM_LIBS_DIR}/libc++.so" # ndk20+: stl also in sysroot and can be found by linker automatically
    AND NOT CMAKE_SHARED_LINKER_FLAGS MATCHES "${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_NDK}/sources/cxx-stl")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR}")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR}")
  endif()
  endif(ANDROID_TOOLCHAIN_NAME)
  # TODO: compiler-rt
  if(ANDROID_STL MATCHES "^c\\+\\+_" AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang") #-stdlib does not support gnustl
    # g++ has no -stdlib option. clang default stdlib is -lstdc++. we change it to libc++ to avoid linking against libstdc++
    # -stdlib=libc++ will find libc++.so, while android ndk has no such file. libc++.a is a linker script. Seems can be used for shared libc++
    #file(WRITE ${CMAKE_BINARY_DIR}/libc++.so "INPUT(-lc++_shared)") # SEARCH_DIR() is only valid for -Wl,-T
    #set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${CMAKE_BINARY_DIR} -stdlib=libc++")
    #set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${CMAKE_BINARY_DIR} -stdlib=libc++")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -stdlib=libc++")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -stdlib=libc++")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libc++")
  else()
  # adding -lgcc in CMAKE_SHARED_LINKER_FLAGS will fail to link. add to target_link_libraries() or CMAKE_CXX_STANDARD_LIBRARIES_INIT in toolchain file
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -nodefaultlibs -lc")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -nodefaultlibs -lc")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -nodefaultlibs -lc")
  endif()
  # -nodefaultlibs remove libm
  if(CMAKE_SHARED_LINKER_FLAGS MATCHES "-nodefaultlibs" OR ANDROID_STL MATCHES "_static") # g++ or static libc++ -nodefaultlibs/-nostdlib. libgcc defines __emutls_get_address (and more), x86 may require libdl
    link_libraries(-lgcc -ldl) # requires cmake_policy(SET CMP0022 NEW)
  endif()
  # -static-libstdc++: USE_NOSTDLIBXX(-nostdlib++) is added in r17 and "-static-libstdc++ -stdlib=libc++" does not work
# libsupc++.a seems useless (not found in cmake & qt), but it's added by ndk for gnustl_shared even without exception enabled.
  string(REPLACE "\"${ANDROID_STL_LIB_DIR}/libsupc++.a\"" "" CMAKE_CXX_STANDARD_LIBRARIES_INIT "${CMAKE_CXX_STANDARD_LIBRARIES_INIT}")
  if(CMAKE_CXX_STANDARD_LIBRARIES_INIT) # cmake does not add supc++, check supc++ to avoid setting CMAKE_CXX_STANDARD_LIBRARIES to empty(no stl)
    set(CMAKE_CXX_STANDARD_LIBRARIES "${CMAKE_CXX_STANDARD_LIBRARIES_INIT}")
  endif()
  # CMAKE_SYSTEM_LIBRARY_PATH?
  if(EXISTS "${ANDROID_PLATFORM_LIBS_DIR}") # AND ANDROID_NDK_REVISION
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-rpath-link,${ANDROID_PLATFORM_LIBS_DIR}")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -Wl,-rpath-link,${ANDROID_PLATFORM_LIBS_DIR}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-rpath-link,${ANDROID_PLATFORM_LIBS_DIR}")
  endif()
  # -Wl,--no-rosegment: https://github.com/catboost/catboost/commit/09fd7c42734918de6c0c576b808fefedf855f5f6
endif()

# project independent dirs
if(RPI)
  include_directories(${RPI_VC_DIR}/include)
  list(APPEND EXTRA_INCLUDE ${RPI_VC_DIR}/include)
endif()

if(MIN_SIZE AND CMAKE_BUILD_TYPE MATCHES MinSizeRel AND CMAKE_C_COMPILER_ID MATCHES "Clang" AND NOT MSVC)
  add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX>:-Xclang;-Oz>")
endif()
if(NO_RTTI)
  if(MSVC)
    if(CMAKE_CXX_FLAGS MATCHES "/GR " OR CMAKE_CXX_FLAGS MATCHES "/GR$") #/GR is set by cmake, warnings if simply appending -GR-
      string(REPLACE "/GR" "-GR-" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    else() # clang-cl
      set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -GR-")
    endif()
  else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-rtti")
    #add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-fno-rtti;-fno-exceptions>")
  endif()
endif()
if(NO_EXCEPTIONS)
  if(MSVC)
    add_definitions(-D_HAS_EXCEPTIONS=0)
    if(NOT WINRT)
      if(CMAKE_CXX_FLAGS MATCHES "/EHsc" OR CMAKE_CXX_FLAGS MATCHES "/EHsc$") #/EHsc is set by cmake
        string(REPLACE "/EHsc" "-EHs-c-a-" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}") # cl default is off
      else() # clang-cl
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -EHs-c-a-")
      endif()
    endif()
    #add_cxx_flags_if_supported(-d2FH4-)  #/d2FH4: FH4 vcruntime140_1. no effect?
    #add_link_flags_if_supported(-d2:-FH4-)
  else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-exceptions")
    if(CMAKE_CXX_COMPILER_ID MATCHES Clang AND LIBCXX_COMPAT) # no harm even for gnustl
# apple clang, android, linux
      add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-D_LIBCPP_AVAILABILITY_HAS_NO_VERBOSE_ABORT=1>)
    endif()
  endif()
endif()


if(USE_CFGUARD AND MSVC)
# https://docs.microsoft.com/zh-cn/visualstudio/releasenotes/vs2015-rtm-vs#visual-c-performance-and-code-quality
  add_compile_options($<$<COMPILE_LANGUAGE:C,CXX>:-guard:cf>) #-d2guard4: legacy flag for cl(vs<2015) # fix latest angle crash
  add_link_options(-guard:cf)
  if(NOT OPT_REF_SET)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -opt:ref,icf,lbr")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -opt:ref,icf,lbr")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -opt:ref,icf,lbr")
  endif()
endif()
if(USE_CFGUARD AND MINGW)
  add_compile_options_if_supported(-mguard=cf)
  add_link_flags_if_supported(-mguard=cf)
endif()

if(CMAKE_C_COMPILER_ABI MATCHES "ELF")
  if(ELF_HARDENED)
    set(CFLAGS_STACK_PROTECTOR -fstack-protector-strong) # -fstack-protector-strong(since gcc4.9) is default for debian
    check_c_compiler_flag(${CFLAGS_STACK_PROTECTOR} HAVE_STACK_PROTECTOR_STRONG)
    if(NOT HAVE_STACK_PROTECTOR_STRONG)
      set(CFLAGS_STACK_PROTECTOR -fstack-protector)
    endif()
    set(ELF_HARDENED_CFLAGS -Wformat -Werror=format-security ${CFLAGS_STACK_PROTECTOR})
    set(ELF_HARDENED_LFLAGS "-Wl,-z,relro -Wl,-z,now")
    set(ELF_HARDENED_EFLAGS "-fPIE")
    if(NOT SUNXI) # FIXME: why egl from x11 fails? MESA_EGL_NO_X11_HEADERS causes wrong EGLNativeWindowType? Scrt1.o is used if -pie
      #set(ELF_HARDENED_EFLAGS "${ELF_HARDENED_EFLAGS} -pie")
    endif()
    if(ANDROID)
      if(ANDROID_NDK_TOOLCHAIN_INCLUDED) # already defined by ndk: ANDROID_DISABLE_RELRO, ANDROID_DISABLE_FORMAT_STRING_CHECKS, ANDROID_PIE
        set(ELF_HARDENED_CFLAGS "")
        set(ELF_HARDENED_LFLAGS "")
        set(ELF_HARDENED_EFLAGS "")
      endif()
    else()
    endif()
    foreach(flag ${ELF_HARDENED_CFLAGS})
        add_compile_options($<$<COMPILE_LANGUAGE:C,CXX>:${flag}>)
    endforeach()
    foreach(flag -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2)
        add_compile_options($<$<AND:$<COMPILE_LANGUAGE:C,CXX>,$<NOT:$<CONFIG:Debug>>>:${flag}>)
    endforeach()
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${ELF_HARDENED_LFLAGS}")
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${ELF_HARDENED_LFLAGS}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${ELF_HARDENED_EFLAGS}")
  endif()

# ICF, ELF only? ICF is enbled by vc release mode(/opt:ref,icf)
# FIXME: -fuse-ld=lld is not used. wrong result for android. what about linux desktop? lflags -fuse-ld=lld in linux.clang.cmake works?
test_lflags(WL_ICF_SAFE "-Wl,--icf=safe") # gnu binutils, lld-15  # FIXME: can not be used with -r
  if(WL_ICF_SAFE)
    link_libraries(${WL_ICF_SAFE})
  else() # --icf=all is only safe with clang-7.0+ -faddrsig(default on)
    check_c_compiler_flag("-faddrsig" HAVE_FADDRSIG) # ndk18 clang7.0svn does not support it?
    if(HAVE_FADDRSIG)
      # add_compile_options(-faddrsig) # addrsig is turned on by default. building for COFF with -faddrsig results in wrong symbols, e.g. depended __impl_ prefix are removed
      add_link_flags_if_supported("-Wl,--icf=all")
    endif()
  endif()
endif()

# Dead code elimination
# https://gcc.gnu.org/ml/gcc-help/2003-08/msg00128.html
# https://stackoverflow.com/questions/6687630/how-to-remove-unused-c-c-symbols-with-gcc-and-ld
if(NOT MSVC) # clang-cl just ignore these
  is_link_flag_supported("-Wl,--gc-sections" GC_SECTIONS) # FIXME: can not be used with -r
  if(GC_SECTIONS)
    add_compile_options_if_supported("-ffunction-sections") # check cc, mac support it but has no effect
    check_c_compiler_flag("-Werror -ffunction-sections" HAVE_FUNCTION_SECTIONS)
    if(NOT WIN32) # mingw gcc will increase size
      add_compile_options_if_supported(-fdata-sections)
    endif()
    add_link_options("-Wl,--gc-sections")
  endif()
# TODO: what is -dead_strip equivalent? elf static lib will not remove unused symbols. /Gy + /opt:ref for vc https://stackoverflow.com/questions/25721820/is-c-linkage-smart-enough-to-avoid-linkage-of-unused-libs?noredirect=1&lq=1
# TODO: gcc -fdce
  add_link_flags_if_supported(
    -Wl,--no-allow-shlib-undefined
    -Wl,--as-needed  # not supported by 'opensource clang+apple ld64'
    -Wl,-z,defs # do not allow undefined symbols in shared library targets
    )
endif()
if(APPLE)
  add_link_flags(-dead_strip)
endif()
if(STATIC_LIBGCC)
  #link_libraries(-static-libgcc) cmake2.8 CMP0022
  add_link_flags_if_supported(-static-libgcc)
endif()

# If parallel lto is not supported, fallback to single job lto
if(USE_LTO) # with -Xclang -Oz (-plugin-opt=Oz/Os error)
# -fwhole-program-vtables
  unset(HAVE_LTO CACHE)
  if(MSVC AND NOT CMAKE_CXX_SIMULATE_ID MATCHES MSVC) # -GL is ignored by clang-cl
    set(LTO_CFLAGS "-GL")
    set(LTO_LFLAGS "-LTCG -IGNORE:4075")
  else()
    if(CMAKE_C_COMPILER_ID STREQUAL "Intel")
      if(CMAKE_HOST_WIN32)
        set(LTO_FLAGS "-Qipo")
      else()
        set(LTO_FLAGS "-ipo")
      endif()
    else()
      if(USE_LTO GREATER 0)
        set(CPUS ${USE_LTO})
      elseif(USE_LTO STREQUAL thin OR USE_LTO STREQUAL full)
        set(LTO_FLAGS "-flto=${USE_LTO}") #TODO: -Wa,--noexecstack warning on android. https://github.com/android-ndk/ndk/issues/776#issuecomment-415577082
        set(CMAKE_REQUIRED_LIBRARIES_OLD ${CMAKE_REQUIRED_LIBRARIES})
        set(CMAKE_REQUIRED_LIBRARIES "${CMAKE_REQUIRED_LIBRARIES} ${LTO_FLAGS}") # check_c_compiler_flag() does not check linker flags. CMAKE_REQUIRED_LIBRARIES scope is function local
        check_c_compiler_flag(${LTO_FLAGS} HAVE_LTO_THIN)
        set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES_OLD})
        set(HAVE_LTO ${HAVE_LTO_THIN})
      else()
        cmake_host_system_information(RESULT CPUS QUERY NUMBER_OF_LOGICAL_CORES) #ProcessorCount
      endif()
      if(CPUS GREATER 1)
        set(LTO_FLAGS "-flto=${CPUS}") # parallel lto requires more memory and may fail to link
        set(CMAKE_REQUIRED_LIBRARIES_OLD ${CMAKE_REQUIRED_LIBRARIES})
        set(CMAKE_REQUIRED_LIBRARIES "${CMAKE_REQUIRED_LIBRARIES} ${LTO_FLAGS}") # check_c_compiler_flag() does not check linker flags. CMAKE_REQUIRED_LIBRARIES scope is function local
        check_c_compiler_flag(${LTO_FLAGS} HAVE_LTO_${CPUS})
        set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES_OLD})
        set(HAVE_LTO ${HAVE_LTO_${CPUS}})
      endif()
      if(NOT HAVE_LTO) # android clang, icc etc.
        set(LTO_FLAGS "-flto")
        set(CMAKE_REQUIRED_LIBRARIES_OLD ${CMAKE_REQUIRED_LIBRARIES})
        set(CMAKE_REQUIRED_LIBRARIES "${CMAKE_REQUIRED_LIBRARIES} ${LTO_FLAGS}") # check_c_compiler_flag() does not check linker flags. CMAKE_REQUIRED_LIBRARIES scope is function local
        check_c_compiler_flag(${LTO_FLAGS} HAVE_LTO)
        set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES_OLD})
      endif()
      if(HAVE_LTO) # android clang fails to use lto because of LLVMgold plugin is not found
        set(LTO_CFLAGS ${LTO_FLAGS})
        if(NOT MSVC) # clang-cl linker(lld-link) ignores -flto, lto is builtin feature
          set(LTO_LFLAGS ${LTO_FLAGS})
        endif()
      endif()
    endif()
  endif()
  if(LTO_CFLAGS)
    add_compile_options($<$<COMPILE_LANGUAGE:C,CXX>:${LTO_CFLAGS}>) # flags are not recoginzed by nasm
    add_link_options(${LTO_LFLAGS})
    # gcc-ar, gcc-ranlib
  endif()
  # thin: LLVM ERROR: Unexistent dir: 'lto.o'
  if(APPLE AND NOT USE_LTO STREQUAL thin) # required by dSYM: https://github.com/conda-forge/gdb-feedstock/pull/23/#issuecomment-643008755
    add_link_options(-Wl,-object_path_lto,lto.o)
  endif()
endif()


if(SANITIZE)
# -fomit-frame-pointer smaller size, but asan will slow: https://github.com/android/ndk/issues/824
  # clang-cl: -Oy- = -fno-omit-frame-pointer -funwind-tables, -Oy = -fomit-frame-pointer -funwind-tables
  # memory sanitize does not supports macOS. address and thread can not be used together
  #add_compile_options(-fno-omit-frame-pointer -fno-optimize-sibling-calls -funwind-tables -fsanitize=address,undefined,integer,nullability)
  #set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fsanitize=address,undefined,integer,nullability -fsanitize-address-use-after-scope")
  #set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -fsanitize=address,undefined,integer,nullability -fsanitize-address-use-after-scope")
  #set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=address,undefined,integer,nullability -fsanitize-address-use-after-scope")
  add_compile_options(-fno-omit-frame-pointer -fno-optimize-sibling-calls -funwind-tables -fsanitize=address,undefined)
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fsanitize=address,undefined")
  set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -fsanitize=address,undefined")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=address,undefined")
endif()
if(COVERAGE)
  if(CMAKE_C_COMPILER_ID STREQUAL GNU)
    add_compile_options(-fprofile-arcs -ftest-coverage)
    link_libraries(-fprofile-arcs -ftest-coverage)
  elseif(CMAKE_C_COMPILER_ID STREQUAL Clang)
    add_compile_options(-fprofile-instr-generate -fcoverage-mapping)
    link_libraries(-fprofile-instr-generate -fcoverage-mapping)
  endif()
endif()
#include_directories($ENV{UNIVERSALCRTSDKDIR}/Include/$ENV{WINDOWSSDKVERSION}/ucrt)
# starts with "-": treated as a link flag. VC: starts with "/" and treated as a path

# Find binutils. FIXME: llvm-mingw objcopy is a bash script, but cmake use cmd to execute
if(NOT CMAKE_OBJCOPY)
  message(STATUS "Probing CMAKE_OBJCOPY...")
  if(ANDROID)
    set(CMAKE_OBJCOPY ${ANDROID_TOOLCHAIN_PREFIX}objcopy)
  elseif(DEFINED CROSS_PREFIX)
    set(CMAKE_OBJCOPY ${CROSS_PREFIX}objcopy)
  elseif(CMAKE_C_COMPILER_ID STREQUAL "GNU")
    # ${CMAKE_C_COMPILER} -print-prog-name=objcopy does not always work. WHEN?
    if(CMAKE_HOST_WIN32)
      string(REGEX REPLACE "gcc.exe$|cc.exe$" "objcopy.exe" CMAKE_OBJCOPY ${CMAKE_C_COMPILER})
    elseif(NOT APPLE)
      string(REGEX REPLACE "gcc$|cc$" "objcopy" CMAKE_OBJCOPY ${CMAKE_C_COMPILER})
    endif()
    # or 1st replace ${CMAKE_C_COMPILER}, 2nd replace ${CMAKE_OBJCOPY}
    if(CMAKE_OBJCOPY STREQUAL CMAKE_C_COMPILER)
      string(REGEX REPLACE "gcc[^/]*$" "objcopy" CMAKE_OBJCOPY ${CMAKE_OBJCOPY}) # /usr/bin/gcc-6
    endif()
  endif()
  execute_process(
      COMMAND ${CMAKE_OBJCOPY} -V
      ERROR_VARIABLE OBJCOPY_ERROR
      OUTPUT_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(OBJCOPY_ERROR) # llvm-objcopy on windows may be a bash script which can not be executed in cmd via cmake internal
    set(CMAKE_OBJCOPY "")
  endif()
  message("CMAKE_OBJCOPY:${CMAKE_OBJCOPY}")
  mark_as_advanced(CMAKE_OBJCOPY)
endif()
# mkdsym: create debug symbol file and strip original file.
function(mkdsym tgt)
  if(SANITIZE OR COVERAGE)
    return()
  endif()
  get_target_property(TYPE ${tgt} TYPE)
  if(NOT TYPE STREQUAL SHARED_LIBRARY AND NOT TYPE STREQUAL MODULE_LIBRARY)
    return()
  endif()
  if(APPLE)
# no dSYM for lto, dsymutil:
# warning: (x86_64) /tmp/lto.o unable to open object file: No such file or directory
# warning: no debug symbols in executable (-arch x86_64)
    add_custom_command(TARGET ${tgt} POST_BUILD
      COMMAND dsymutil $<TARGET_FILE:${tgt}># -o $<TARGET_FILE:${tgt}>.dSYM
      )
    return()
  endif()
  if(MSVC) # llvm-mingw can generate pdb too
    install(FILES $<TARGET_PDB_FILE:${tgt}> CONFIGURATIONS RelWithDebInfo Debug MinSizeRel DESTINATION bin OPTIONAL) #COMPILE_PDB_OUTPUT_DIRECTORY and COMPILE_PDB_NAME for static
    return()
  endif()
  if(CMAKE_OBJCOPY)
    if(${CMAKE_OBJCOPY} MATCHES ".*llvm-objcopy.*")
      #set(KEEP_OPT_EXTRA --strip-sections) # will leave an empty elf
    endif()
    add_custom_command(TARGET ${tgt} POST_BUILD
      COMMAND ${CMAKE_OBJCOPY} ${KEEP_OPT_EXTRA} --only-keep-debug $<TARGET_FILE:${tgt}> $<TARGET_FILE:${tgt}>.dsym # --only-keep-debug is .eh_frame section?
      COMMAND ${CMAKE_OBJCOPY} --strip-debug --strip-unneeded --discard-all --add-gnu-debuglink=$<TARGET_FILE:${tgt}>.dsym $<TARGET_FILE:${tgt}>
      )
    if(CMAKE_VERSION VERSION_LESS 3.0)
      get_property(tgt_path TARGET ${tgt} PROPERTY LOCATION) #cmake > 2.8.12: CMP0026
      # can not use wildcard "${tgt_path}*.dsym"
      if(ANDROID)
        install(FILES ${tgt_path}.dsym DESTINATION lib)
      else()
        get_property(tgt_version TARGET ${tgt} PROPERTY VERSION)
        # libxx.so.dsym, but $<TARGET_FILE:${tgt}> is libxx.so.x.y.z
        install(FILES ${tgt_path}.${tgt_version}.dsym DESTINATION lib)
      endif()
    else()
      install(FILES $<TARGET_FILE:${tgt}>.dsym DESTINATION lib)
    endif()
  endif()
endfunction()


#http://stackoverflow.com/questions/11813271/embed-resources-eg-shader-code-images-into-executable-library-with-cmake/11814544#11814544
# Creates C resources file from files in given directory
function(mkres files)
    #message("files: ${ARGC} arg0:${ARGV0}  argn:${ARGN}")
    # Create empty output file
    file(WRITE ${ARGV0} "")
    # Collect input files
    # Iterate through input files
    foreach(bin ${ARGN})
        # Get short filename
        string(REGEX MATCH "([^/]+)$" filename ${bin})
        # Replace filename spaces & extension separator for C compatibility
        string(REGEX REPLACE "\\.| |-" "_" filename ${filename})
        # Read hex data from file
        file(READ ${bin} filedata HEX)
        # Convert hex data for C compatibility
        string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," filedata ${filedata})
        # Append data to output file
        file(APPEND ${ARGV0} "static const unsigned char k${filename}[] = {${filedata}0x00};\nstatic const size_t k${filename}_size = sizeof(k${filename})-1;\n")
    endforeach()
endfunction()

# TODO: check target is a SHARED library
# TODO: -r can not mix with -icf -gc-sections
function(set_relocatable_flags)
  if(MSVC)
  else()
# can't use with -shared. -dynamic(apple) is fine. -shared is set in CMAKE_SHARED_LIBRARY_CREATE_${lang}_FLAGS, so we may add another library type RELOCATABLE in add_library
    test_lflags(RELOBJ "-r -nostdlib")
  endif()
  if(RELOBJ)
    # -r and -dead_strip cannot be used together
    list(LENGTH ARGN _nb_args)
    if(_nb_args GREATER 0)
      foreach(t ${ARGN})
        get_target_property(${t}_reloc ${t} RELOCATABLE)
        if(${t}_reloc)
          message("set relocatable object flags for target ${t}")
          set_property(TARGET ${t} APPEND_STRING PROPERTY LINK_FLAGS "${RELOBJ}")
          string(REPLACE "-dead_strip" "" CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}")
          string(REPLACE "-dead_strip" "" CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS}")
        endif()
      endforeach()
      #set_property(TARGET ${ARGN} APPEND_STRING PROPERTY LINK_FLAGS "${RELOBJ}")
      set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}" PARENT_SCOPE)
      set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS}" PARENT_SCOPE)
      set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS}" PARENT_SCOPE)
    else()
      set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${RELOBJ}" PARENT_SCOPE)
      set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${RELOBJ}" PARENT_SCOPE)
      string(REPLACE "-dead_strip" "" CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}")
      string(REPLACE "-dead_strip" "" CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS}")
      string(REPLACE "-dead_strip" "" CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS}")
    endif()
  endif()
endfunction()

# strip_local([target1 [target2 ...]])
# apply "-Wl,-x" to all targets if no target is set
# strip local symbols when linking. asm symbols are still exported. relocatable object target contains renamed local symbols (for DCE) and removed at final linking.

# exclude_libs_all([target1 [target2 ...]])
# exporting symbols excluding all depended static libs
function(exclude_libs_all)
  # TODO: check APPLE is enough because no other linker available on apple? what about llvm lld?
  test_lflags(EXCLUDE_ALL "-Wl,--exclude-libs,ALL") # prevent to export external lib apis
  if(NOT EXCLUDE_ALL)
    return()
  endif()
  list(LENGTH ARGN _nb_args)
  if(_nb_args GREATER 0)
    #set_target_properties(${ARGN} PROPERTIES LINK_FLAGS "${EXCLUDE_ALL}") # not append
    set_property(TARGET ${ARGN} APPEND_STRING PROPERTY LINK_FLAGS "${EXCLUDE_ALL}") # APPEND PROPERTY
  else()
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${EXCLUDE_ALL}" PARENT_SCOPE)
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${EXCLUDE_ALL}" PARENT_SCOPE)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${EXCLUDE_ALL}" PARENT_SCOPE)
  endif()
# CMAKE_LINK_SEARCH_START_STATIC
endfunction()

# TODO: to a target?
# set default rpath dirs and add user defined rpaths
function(set_rpath)
#CMAKE_SHARED_LIBRARY_RPATH_LINK_C_FLAG
  if(WIN32 OR ANDROID)
    return()
  endif()
  cmake_parse_arguments(RPATH "" "" "DIRS;TARGET" ${ARGN}) #ARGV?
  test_lflags(RPATH_FLAGS "-Wl,--enable-new-dtags")
  set(RPATH_FLAGS_LIST ${RPATH_FLAGS})
  set(LD_RPATH "-Wl,-rpath,")
# Executable dir search: ld -z origin, g++ -Wl,-R,'$ORIGIN', in makefile -Wl,-R,'$$ORIGIN'
# Working dir search: "."
# mac: install_name @rpath/... will search paths set in rpath link flags
  if(APPLE)
# https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html
    list(APPEND RPATH_DIRS @loader_path/Libraries @loader_path @executable_path/../Frameworks) # macOS 10.4 does not support rpath, and only supports executable_path, so use loader_path only is enough
    if(NOT IOS AND NOT MACCATALYST)
      list(APPEND RPATH_DIRS  /opt/homebrew/lib /usr/local/lib)
    endif()
    # -install_name @rpath/... is set by cmake
  else()
    list(APPEND RPATH_DIRS "\\$ORIGIN" "\\$ORIGIN/lib" "\\$ORIGIN/../lib" "\\$ORIGIN/../../lib/${ARCH}") #. /usr/local/lib:$ORIGIN
    set(RPATH_FLAGS "${RPATH_FLAGS} -Wl,-z,origin")
    list(APPEND RPATH_FLAGS_LIST -Wl,-z,origin)
  endif()
  foreach(p ${RPATH_DIRS})
    set(RPATH_FLAGS "${RPATH_FLAGS} ${LD_RPATH}\"${p}\"") # '' on windows will be included in runpathU
    list(APPEND RPATH_FLAGS_LIST ${LD_RPATH}\"${p}\")
  endforeach()
  #set(CMAKE_INSTALL_RPATH "${RPATH_DIRS}")
  #string(REPLACE ";" ":" RPATHS "${RPATH_DIRS}")
  #set(RPATH_FLAGS "${RPATH_FLAGS} ${LD_RPATH}'${RPATHS}'")
  if(RPATH_TARGET AND IOS)
    get_target_property(tgt_reloc ${RPATH_TARGET} RELOCATABLE)
    if(NOT IOS OR NOT tgt_reloc) # iOS: -rpath can only be used when creating a dynamic final linked image
      #target_link_options(${RPATH_TARGET} PRIVATE ${RPATH_FLAGS_LIST}) #3.13
      target_link_libraries(${RPATH_TARGET} PRIVATE ${RPATH_FLAGS_LIST})
    endif()
  elseif(NOT IOS) # iOS: -rpath can only be used when creating a dynamic final linked image
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${RPATH_FLAGS}" PARENT_SCOPE)
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${RPATH_FLAGS}" PARENT_SCOPE)
  endif()
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${RPATH_FLAGS}" PARENT_SCOPE)
endfunction()


function(setup_dso_reloc tgt)
  set_relocatable_flags(${tgt})
  set_rpath()
  exclude_libs_all(${tgt})
  mkdsym(${tgt})  # MUST after VERSION set because VERSION is used un mkdsym for cmake <3.0
endfunction()

# setup_deploy: deploy libs, public headers(PUBLIC_HEADER as target property and target sources) and runtime binaries of tgt
function(setup_deploy tgt) # TODO: TARGETS(dso, static), HEADERS, HEADERS_DIR
  if(APPLE)
    # macOS SHARED_LIBRARY only
    get_target_property(TYPE ${tgt} TYPE)
    if(TYPE STREQUAL SHARED_LIBRARY AND NOT IOS AND CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 10.7) # check host os?
      add_custom_command(TARGET ${tgt} POST_BUILD
        COMMAND install_name_tool -change /usr/lib/libc++.1.dylib @rpath/libc++.1.dylib $<TARGET_FILE:${tgt}>
      )
    endif()
    #[=[
    # the following code is used to copy PUBLIC_HEADER(target property) manually if PUBLIC_HEADER is not part of target_sources
    get_target_property(IS_FWK ${tgt} FRAMEWORK)
    if(IS_FWK)
# PUBLIC_HEADER property seems not work for apple framework, so manually copy them
      get_target_property(PUBLIC_HEADER ${tgt} PUBLIC_HEADER)
      message("${tgt} PUBLIC_HEADER: ${PUBLIC_HEADER}")
      if(PUBLIC_HEADER)
        add_custom_command(TARGET ${tgt} POST_BUILD
          COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_DIR:${TARGET_NAME}>/Headers
          COMMAND ${CMAKE_COMMAND} -E copy_if_different ${PUBLIC_HEADER} $<TARGET_BUNDLE_DIR:${TARGET_NAME}>/Headers
          # WORKING_DIRECTORY does not support generator expr
        )
      endif()
    endif()
    #]=]
  endif()

  install(TARGETS ${tgt}
    EXPORT ${tgt}-targets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    FRAMEWORK DESTINATION lib
    PUBLIC_HEADER DESTINATION include/${PROJECT_NAME} # install target property PUBLIC_HEADER
    #PRIVATE_HEADER DESTINATION /private
    )
  install(EXPORT ${tgt}-targets
    DESTINATION lib/cmake/${tgt}
    FILE ${tgt}-config.cmake
  )
endfunction()

# uninstall target
configure_file(
    "${CMAKE_CURRENT_LIST_DIR}/cmake_uninstall.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    IMMEDIATE @ONLY)

add_custom_target(uninstall
    COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake)


################################### cmake compat layer ############################################
if(NOT CMAKE_VERSION VERSION_LESS 3.1)
  return()
endif()
function(target_sources tgt)
  if(POLICY CMP0051) # for TARGET_OBJECTS in SOURCES property. FIXME: not supported by old cmake
    cmake_policy(SET CMP0051 NEW)
  endif()
  set(multiValArgs PUBLIC PRIVATE INTERFACE)
  cmake_parse_arguments(TGT_SRC "" "" "${multiValArgs}" ${ARGN})
  set_property(TARGET ${tgt} APPEND PROPERTY SOURCES ${TGT_SRC_PUBLIC})
  set_property(TARGET ${tgt} APPEND PROPERTY SOURCES ${TGT_SRC_PRIVATE})
  set_property(TARGET ${tgt} APPEND PROPERTY SOURCES ${TGT_SRC_INTERFACE})
endfunction(target_sources)

if(NOT CMAKE_VERSION VERSION_LESS 3.13)
  return()
endif()
function(target_link_directories tgt)
  set(options BEFORE)
  set(multiValArgs PUBLIC PRIVATE INTERFACE)
  cmake_parse_arguments(TGT_LDIRS "${options}" "" "${multiValArgs}" ${ARGN})
  set_property(TARGET ${tgt} APPEND PROPERTY LINK_DIRECTORIES ${TGT_LDIRS_PUBLIC})
  set_property(TARGET ${tgt} APPEND PROPERTY LINK_DIRECTORIES ${TGT_LDIRS_PRIVATE})
  set_property(TARGET ${tgt} APPEND PROPERTY LINK_DIRECTORIES ${TGT_LDIRS_INTERFACE})
endfunction(target_link_directories)