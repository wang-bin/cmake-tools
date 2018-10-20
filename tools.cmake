# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2018, Wang Bin
##
# defined vars:
# - EXTRA_INCLUDE
# defined functions
# -

# TODO: pch, auto add target dep libs dir to rpath-link paths. rc file
#-z nodlopen, --strip-lto-sections, -Wl,--allow-shlib-undefined
# harden: https://github.com/opencv/opencv/commit/1961bb1857d5d3c9a7e196d52b0c7c459bc6e619
# clang/gcc: -fms-extensions
# enable/add_c_flags_if()

# always set policies to ensure they are applied on every project's policy stack
# include() with NO_POLICY_SCOPE to apply the cmake_policy in parent scope
# TODO: vc 1913+  "-Zc:__cplusplus -std:c++14" to correct __cplusplus. see qt msvc-version.conf. https://blogs.msdn.microsoft.com/vcblog/2018/04/09/msvc-now-correctly-reports-__cplusplus/
# libcxx macros: add_compile_flags_if_supported, add_link_flags_if, add_link_flags_if_supported
# cmake_dependent_option
# add_flag_if_not(flags XXX_FLAG_ON) # XXX_FLAG_OFF is set by add_flag

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
option(USE_LTO "Link time optimization. 0: disable; 1: enable; N: N parallelism. thin: thin LTO. TRUE: max parallelism" 0)
option(SANITIZE "Enable address sanitizer. Debug build is required" OFF)
option(COVERAGE "Enable source based code coverage(gcc/clang)" OFF)
option(STATIC_LIBGCC "Link to static libgcc, useful for windows" OFF) # WIN32 AND CMAKE_C_COMPILER_ID GNU 
option(NO_RTTI "Enable C++ rtti" ON)
option(NO_EXCEPTIONS "Enable C++ exceptions" ON)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

include(CMakeParseArguments)
include(CheckCCompilerFlag)
include(CheckCXXCompilerFlag)

# set CMAKE_SYSTEM_PROCESSOR, CMAKE_SYSROOT, CMAKE_<LANG>_COMPILER for cross build
# defines RPI_VC_DIR for use externally
if(EXISTS ${CMAKE_SYSROOT}/opt/vc/include/bcm_host.h) # CMAKE_SYSROOT can be empty
  set(RPI_SYSROOT ${CMAKE_SYSROOT})
  set(RPI 1)
else()
  execute_process(
      COMMAND ${CMAKE_C_COMPILER} -print-sysroot  #clang does not support -print-sysroot
      OUTPUT_VARIABLE CC_SYSROOT
      ERROR_VARIABLE SYSROOT_ERROR
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(EXISTS ${CC_SYSROOT}/opt/vc/include/bcm_host.h)
    set(RPI_SYSROOT ${CC_SYSROOT})
    set(RPI 1)
  endif()
endif()
if(RPI)
  if(EXISTS /dev/vchiq)
    message("Raspberry Pi host build")
  else()
    message("Raspberry Pi cross build")
    set(CMAKE_CROSSCOMPILING TRUE)
  endif()
  #set(CMAKE_SYSTEM_PROCESSOR armv6)
  set(OS rpi)
  # unset os detected as host when cross compiling
  unset(APPLE)
  unset(WIN32)
  add_definitions(-DOS_RPI)
  if(NOT RPI_VC_DIR)
    if(${RPI_SYSROOT} MATCHES ".*/$")
      set(RPI_VC_DIR ${RPI_SYSROOT}opt/vc)
    else()
      set(RPI_VC_DIR ${RPI_SYSROOT}/opt/vc)
    endif()
  endif()
endif()

if(NOT ARCH)
# cmake only probes compiler arch for msvc as it's 1 toolchain per arch. we can probes other compilers like msvc, but multi arch build(clang for apple) is an exception
# here we simply use cmake vars with some reasonable assumptions
  set(ARCH ${CMAKE_C_COMPILER_ARCHITECTURE_ID}) # msvc only, MSVC_C_ARCHITECTURE_ID
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
if(WINDOWS_PHONE OR WINDOWS_STORE) # defined when CMAKE_SYSTEM_NAME is WindowsPhone/WindowsStore
  set(OS WinRT)
  if(ARCH STREQUAL ARMV7)
    set(ARCH arm)
  endif()
  set(WINRT 1)
  set(WINSTORE 1)
endif()
if(WINRT AND NOT WINRT_SET AND NOT CMAKE_GENERATOR MATCHES "Visual Studio")
  # SEH?
  if(WINDOWS_PHONE)
    add_definitions(-DWINAPI_FAMILY=WINAPI_FAMILY_PHONE_APP) #_WIN32_WINNT=0x0603 # TODO: cmake3.10 does not define _WIN32_WINNT even if CMAKE_SYSTEM_VERSION is set? only set for msvc cl
  else()
    add_definitions(-DWINAPI_FAMILY=WINAPI_FAMILY_APP)
  endif()
  #add_compile_options(-ZW) #C++/CX, defines __cplusplus_winrt
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -appcontainer -nodefaultlib:kernel32.Lib -nodefaultlib:Ole32.Lib")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -appcontainer -nodefaultlib:kernel32.Lib -nodefaultlib:Ole32.Lib")
endif()

if(WINDOWS_XP AND MSVC AND NOT WINDOWS_XP_SET) # move too win.cmake?
  set(WIN_MINOR 01)
  if(CMAKE_CL_64)
    set(WIN_MINOR 02)
  endif()
  add_definitions(-D_WIN32_WINNT=0x05${WIN_MINOR})
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -SUBSYSTEM:CONSOLE,5.${WIN_MINOR}")
endif()

if(NOT OS)
  if(WIN32)
    set(OS windows)
  elseif(APPLE)
    if(IOS)
      set(OS iOS)
      if(IOS_UNIVERSAL)
        set(ARCH)
      endif()
    else()
      set(OS macOS)
    endif()
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
  endif()
endif()

if(ARCH MATCHES 86_64 OR ARCH MATCHES AMD64)
  set(ARCH x64)
endif()
if(ARCH MATCHES 86)
  set(ARCH x86)
endif()

if(APPLE)
  set(CMAKE_INSTALL_NAME_DIR "@rpath")
endif()

if(CMAKE_CXX_STANDARD AND NOT CMAKE_CXX_STANDARD LESS 11)
  if(CMAKE_VERSION VERSION_LESS 3.1)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++${CMAKE_CXX_STANDARD}") # $<COMPILE_LANGUAGE:CXX> requires cmake3.4+
    endif()
  endif()
  if(APPLE)
    # Check AppleClang requires cmake>=3.0 and set CMP0025 to NEW. FIXME: It's still Clang with ios toolchain file
    if(NOT CMAKE_C_COMPILER_ID STREQUAL AppleClang) #headers with objc syntax, clang attributes error
      if(CMAKE_C_COMPILER_ID STREQUAL Clang)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
      else() # FIXME: gcc can not recognize clang attributes and objc syntax
      endif()
    endif()
    if(IOS)
    else()
      message("CMAKE_OSX_DEPLOYMENT_TARGET:${CMAKE_OSX_DEPLOYMENT_TARGET}")
      if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 10.9)
        if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 10.7)
          if(CMAKE_C_COMPILER_ID STREQUAL AppleClang)
              message("Apple clang does not support c++${CMAKE_CXX_STANDARD} for macOS 10.6")
          endif()
        else()
          set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
        endif()
      endif()
    endif()
  endif()
endif()

if(MSVC AND CMAKE_C_COMPILER_VERSION VERSION_GREATER 19.0.23918.0) #update2
  add_compile_options(-utf-8)  # no more codepage warnings
endif()

check_c_compiler_flag(-Wunused HAVE_WUNUSED)
if(HAVE_WUNUSED)
  add_compile_options(-Wunused)
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
  if(ANDROID_STL MATCHES "^c\\+\\+_")
    set(ANDROID_STL_LIB_DIR ${ANDROID_NDK}/sources/cxx-stl/llvm-libc++/libs/${ANDROID_ABI})
  elseif(ANDROID_STL MATCHES "^gnustl_")
    if(ANDROID_STL_PREFIX) # toolchain file from ndk
      set(ANDROID_STL_LIB_DIR ${ANDROID_NDK}/sources/cxx-stl/${ANDROID_STL_PREFIX}/libs/${ANDROID_ABI})
    elseif(CMAKE_ANDROID_NDK_TOOLCHAIN_VERSION) # can be clang. what if clang use gnustl?
      set(ANDROID_STL_LIB_DIR ${ANDROID_NDK}/sources/cxx-stl/gnu-libstdc++/${CMAKE_ANDROID_NDK_TOOLCHAIN_VERSION}/libs/${ANDROID_ABI})
    endif()
  endif()
  # stl link dir may be defined in ${ANDROID_LINKER_FLAGS}
  if(NOT CMAKE_SHARED_LINKER_FLAGS MATCHES "${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_NDK}/sources/cxx-stl")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR}")
  endif()
  # TODO: compiler-rt
  if(ANDROID_STL MATCHES "^c\\+\\+_" AND CMAKE_C_COMPILER_ID STREQUAL "Clang") #-stdlib does not support gnustl
    # g++ has no -stdlib option. clang default stdlib is -lstdc++. we change it to libc++ to avoid linking against libstdc++
    # -stdlib=libc++ will find libc++.so, while android ndk has no such file. libc++.a is a linker script. Seems can be used for shared libc++
    #file(WRITE ${CMAKE_BINARY_DIR}/libc++.so "INPUT(-lc++_shared)") # SEARCH_DIR() is only valid for -Wl,-T
    #set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${CMAKE_BINARY_DIR} -stdlib=libc++")
    #set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${CMAKE_BINARY_DIR} -stdlib=libc++")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -stdlib=libc++")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libc++")
  else()
  # adding -lgcc in CMAKE_SHARED_LINKER_FLAGS will fail to link. add to target_link_libraries() or CMAKE_CXX_STANDARD_LIBRARIES_INIT in toolchain file
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -nodefaultlibs -lc")
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
endif()

# project independent dirs
if(NOT WIN32 AND NOT CMAKE_CROSSCOMPILING AND EXISTS /usr/local/include)
  include_directories(/usr/local/include)
  list(APPEND EXTRA_LIB_DIR /usr/local/lib)
endif()
if(RPI)
  include_directories(${RPI_VC_DIR}/include)
  list(APPEND EXTRA_INCLUDE ${RPI_VC_DIR}/include)
endif()
if(EXISTS ${CMAKE_SOURCE_DIR}/external/lib/${OS}/${ARCH})
  list(APPEND EXTRA_LIB_DIR "${CMAKE_SOURCE_DIR}/external/lib/${OS}/${ARCH}")
endif()
if(EXISTS ${CMAKE_SOURCE_DIR}/external/include)
  include_directories(${CMAKE_SOURCE_DIR}/external/include)
  list(APPEND EXTRA_INCLUDE ${CMAKE_SOURCE_DIR}/external/include)
endif()


if(MSVC)
  add_compile_options(-D_CRT_SECURE_NO_WARNINGS)
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
  else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-exceptions")
  endif()
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
      list(APPEND ELF_HARDENED_CFLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2)
    endif()
    add_compile_options(${ELF_HARDENED_CFLAGS})
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${ELF_HARDENED_LFLAGS}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${ELF_HARDENED_EFLAGS}")
  endif()

# ICF, ELF only? ICF is enbled by vc release mode(/opt:ref,icf)
# FIXME: -fuse-ld=lld is not used. wrong result for android. what about linux desktop? lflags -fuse-ld=lld in linux.clang.cmake works?
test_lflags(WL_ICF_SAFE "-Wl,--icf=safe") # gnu binutils  # FIXME: can not be used with -r
  if(WL_ICF_SAFE)
    link_libraries(${WL_ICF_SAFE})
  else() # --icf=all is only safe with clang-7.0+ -faddrsig(default on)
    check_c_compiler_flag("-faddrsig" HAVE_FADDRSIG) # ndk18 clang7.0svn does not support it?
    if(HAVE_FADDRSIG)
      # add_compile_options(-faddrsig) # addrsig is turned on by default. building for COFF with -faddrsig results in wrong symbols, e.g. depended __impl_ prefix are removed
      test_lflags(WL_ICF_ALL "-Wl,--icf=all")
      if(WL_ICF_ALL)
        link_libraries(${WL_ICF_ALL})
      endif()
    endif()
  endif()
endif()

test_lflags(WL_NO_SHLIB_UNDEFINED "-Wl,--no-allow-shlib-undefined")
if(WL_NO_SHLIB_UNDEFINED)
  link_libraries(${WL_NO_SHLIB_UNDEFINED})
endif()
test_lflags(AS_NEEDED "-Wl,--as-needed") # not supported by 'opensource clang+apple ld64'
if(AS_NEEDED)
  link_libraries(${AS_NEEDED})
endif()
# Dead code elimination
# https://gcc.gnu.org/ml/gcc-help/2003-08/msg00128.html
# https://stackoverflow.com/questions/6687630/how-to-remove-unused-c-c-symbols-with-gcc-and-ld
test_lflags(GC_SECTIONS "-Wl,--gc-sections") # FIXME: can not be used with -r
if(GC_SECTIONS)
  check_c_compiler_flag("-Werror -ffunction-sections" HAVE_FUNCTION_SECTIONS)
  if(HAVE_FUNCTION_SECTIONS)
    set(DCE_CFLAGS -ffunction-sections) # check cc, mac support it but has no effect
    if(NOT WIN32) # mingw gcc will increase size
      list(APPEND DCE_CFLAGS -fdata-sections)
    endif()
    if(DCE_CFLAGS)
      add_compile_options(${DCE_CFLAGS})
    endif()
  endif()
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${GC_SECTIONS}")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${GC_SECTIONS}")
endif()
# TODO: what is -dead_strip equivalent? elf static lib will not remove unused symbols. /Gy + /opt:ref for vc https://stackoverflow.com/questions/25721820/is-c-linkage-smart-enough-to-avoid-linkage-of-unused-libs?noredirect=1&lq=1

if(STATIC_LIBGCC)
  #link_libraries(-static-libgcc) cmake2.8 CMP0022
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -static-libgcc")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libgcc")
endif()

# If parallel lto is not supported, fallback to single job lto
if(USE_LTO)
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
      elseif(USE_LTO STREQUAL thin)
        set(LTO_FLAGS "-flto=thin")
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
    add_compile_options(${LTO_CFLAGS})
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${LTO_LFLAGS}")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LTO_LFLAGS}")
    # gcc-ar, gcc-ranlib
  endif()
endif()


if(SANITIZE)
  add_compile_options(-fno-omit-frame-pointer -fsanitize=address,undefined)
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fsanitize=address,undefined")
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
  message("CMAKE_OBJCOPY:${CMAKE_OBJCOPY}")
  mark_as_advanced(CMAKE_OBJCOPY)
endif()
# mkdsym: create debug symbol file and strip original file.
function(mkdsym tgt)
  if(SANITIZE OR COVERAGE)
    return()
  endif()
  # TODO: find objcopy in target tools (e.g. clang toolchain)
  # TODO: apple support
  if(CMAKE_OBJCOPY)
    if(${CMAKE_OBJCOPY} MATCHES ".*llvm-objcopy.*")
      #add_custom_command(TARGET ${tgt} POST_BUILD
      #  COMMAND ${CMAKE_OBJCOPY} -only-keep=debug* $<TARGET_FILE:${tgt}> $<TARGET_FILE:${tgt}>.dsym
      #  COMMAND ${CMAKE_OBJCOPY} -strip-debug -add-section=.gnu-debuglink=$<TARGET_FILE:${tgt}>.dsym $<TARGET_FILE:${tgt}>
      #  )
    else()
      add_custom_command(TARGET ${tgt} POST_BUILD
        COMMAND ${CMAKE_OBJCOPY} --only-keep-debug $<TARGET_FILE:${tgt}> $<TARGET_FILE:${tgt}>.dsym
        COMMAND ${CMAKE_OBJCOPY} --strip-debug --strip-unneeded --discard-all --add-gnu-debuglink=$<TARGET_FILE:${tgt}>.dsym $<TARGET_FILE:${tgt}>
        )
    endif()
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
        file(APPEND ${ARGV0} "static const unsigned char k${filename}[] = {${filedata}0x00};\nstatic const size_t k${filename}_size = sizeof(k${filename});\n")
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
    list(LENGTH ARGN _nb_args)
    if(_nb_args GREATER 0)
      foreach(t ${ARGN})
        get_target_property(${t}_reloc ${t} RELOCATABLE)
        if(${t}_reloc)
          message("set relocatable object flags for target ${t}")
          set_property(TARGET ${t} APPEND_STRING PROPERTY LINK_FLAGS "${RELOBJ}")
        endif()
      endforeach()
      #set_property(TARGET ${ARGN} APPEND_STRING PROPERTY LINK_FLAGS "${RELOBJ}")
    else()
      set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${RELOBJ}" PARENT_SCOPE)
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
  cmake_parse_arguments(RPATH "" "" "DIRS" ${ARGN}) #ARGV?
  test_lflags(RPATH_FLAGS "-Wl,--enable-new-dtags")
  set(LD_RPATH "-Wl,-rpath,")
# Executable dir search: ld -z origin, g++ -Wl,-R,'$ORIGIN', in makefile -Wl,-R,'$$ORIGIN'
# Working dir search: "."
# mac: install_name @rpath/... will search paths set in rpath link flags
  if(APPLE)
    list(APPEND RPATH_DIRS @executable_path/../Frameworks @loader_path @loader_path/lib @loader_path/../lib) # macOS 10.4 does not support rpath, and only supports executable_path, so use loader_path only is enough
    # -install_name @rpath/... is set by cmake
  else()
    list(APPEND RPATH_DIRS "\\$ORIGIN" "\\$ORIGIN/lib" "\\$ORIGIN/../lib") #. /usr/local/lib:$ORIGIN
    set(RPATH_FLAGS "${RPATH_FLAGS} -Wl,-z,origin")
  endif()
  foreach(p ${RPATH_DIRS})
    set(RPATH_FLAGS "${RPATH_FLAGS} ${LD_RPATH}\"${p}\"") # '' on windows will be included in runpathU
  endforeach()
  #set(CMAKE_INSTALL_RPATH "${RPATH_DIRS}")
  #string(REPLACE ";" ":" RPATHS "${RPATH_DIRS}")
  #set(RPATH_FLAGS "${RPATH_FLAGS} ${LD_RPATH}'${RPATHS}'")
  if(NOT IOS) # iOS: -rpath can only be used when creating a dynamic final linked image
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${RPATH_FLAGS}" PARENT_SCOPE)
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
    # macOS only
    if(NOT IOS AND CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 10.7) # check host os?
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
  set(options PUBLIC PRIVATE INTERFACE)
  cmake_parse_arguments(TGT_SRC "${options}" "" "" ${ARGN})
  set_property(TARGET ${tgt} APPEND PROPERTY SOURCES ${TGT_SRC_UNPARSED_ARGUMENTS})
endfunction(target_sources)
