# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2018-2019, Wang Bin
#
# clang-cl + lld to cross build apps for windows. can be easily change to other target platforms
# can not use clang --target=${ARCH}-none-windows-msvc19.0 because cmake will test msvc flags
# ref: https://github.com/llvm-mirror/llvm/blob/master/cmake/platforms/WinMsvc.cmake

# vars:
# WINSDK_DIR, WINSDK_VER, MSVC_DIR. If not set, environment vars WindowsSdkDir, WindowsSDKVersion, VCDIR are used
# CMAKE_SYSTEM_PROCESSOR: target arch, host arch is used if not set
# CMAKE_C_COMPILER: clang-cl path (optional)

# when cross building on a case sensitive filesystem, symbolic links for libs and vfs overlay for headers are required.
# You can download winsdk containing scripts to generate links and vfs overlay from: https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download
# msvc sdk: https://sourceforge.net/projects/avbuild/files/dep/msvcrt-dev.7z/download
# WARNING: rc is required for win host build

# as: clang -target armv7-win32-gnu
# /bin/link will be selected by cmake
# non-windows host: clang-cl invokes link.exe by default, use -fuse-ld=lld works. but -Wl, /link, -Xlinker does not work
option(CLANG_AS_LINKER "use clang as linker to invoke lld. MUST ON for now" OFF) # MUST use lld-link as CMAKE_LINKER on windows host, otherwise ms link.exe is used
option(USE_CLANG_CL "use clang-cl, same as clang --driver-mode=cl" ON)
option(USE_LIBCXX "use libc++ instead of libstdc++. set to libc++ path including include and lib dirs to enable" OFF)
option(UWP "build for uwp" OFF)
option(PHONE "build for phone" OFF)
option(ONECORE "build with oncore" OFF)

# Export configurable variables for the try_compile() command. Or set env var like llvm
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  CMAKE_C_COMPILER # avoid find_program multiple times
  CMAKE_SYSTEM_NAME
  CMAKE_SYSTEM_PROCESSOR
  MSVC_DIR
  WINSDK_DIR
  WINSDK_VER
)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}) # ${CMAKE_SYSTEM_NAME}-Clang-C.cmake is missing
set(CMAKE_CROSSCOMPILING ON) # turned on by setting CMAKE_SYSTEM_NAME?
# FIXME: msvcrtd.lib is required
if(NOT CMAKE_SYSTEM_NAME)
  if(UWP)
    set(CMAKE_SYSTEM_NAME WindowsStore)
    set(WINRT 1)
    set(WINSTORE 1)
  elseif(PHONE)
    set(CMAKE_SYSTEM_NAME WindowsPhone)
    set(WINRT 1)
    set(WINSTORE 1)
  else()
    set(CMAKE_SYSTEM_NAME Windows)
    set(WINDOWS_DESKTOP 1)
  endif()
endif()

macro(dec_to_hex VAR VAL)
  if (${VAL} LESS 10)
    SET(${VAR} ${VAL})
  else()
    math(EXPR A "55 + ${VAL}")
    string(ASCII ${A} ${VAR})
  endif()
endmacro(dec_to_hex)
if(NOT CMAKE_SYSTEM_VERSION)
  set(CMAKE_SYSTEM_VERSION 6.0) # default is latest(10.0) set by windows.h
endif()
string(REGEX MATCH "([0-9]*)\\.([0-9]*)" matched ${CMAKE_SYSTEM_VERSION})
set(WIN_MAJOR ${CMAKE_MATCH_1})
set(WIN_MINOR ${CMAKE_MATCH_2})
dec_to_hex(WIN_MAJOR_HEX ${WIN_MAJOR})
dec_to_hex(WIN_MINOR_HEX ${WIN_MINOR})
set(WIN_VER_HEX 0x0${WIN_MAJOR_HEX}0${WIN_MINOR_HEX})

if(CMAKE_SYSTEM_NAME STREQUAL WindowsPhone)
  add_definitions(-DWINAPI_FAMILY=WINAPI_FAMILY_PHONE_APP -D_WIN32_WINNT=0x0603) ## cmake3.10 does not define _WIN32_WINNT?
  set(CMAKE_SYSTEM_VERSION 8.1)
elseif(CMAKE_SYSTEM_NAME STREQUAL WindowsStore)
  add_definitions(-DWINAPI_FAMILY=WINAPI_FAMILY_APP -D_WIN32_WINNT=0x0A00)
  set(CMAKE_SYSTEM_VERSION 10.0)
else()
  add_definitions(-D_WIN32_WINNT=${WIN_VER_HEX})
endif()
if(CMAKE_SYSTEM_VERSION LESS 6.0 AND CMAKE_SYSTEM_VERSION GREATER 5.0 AND NOT WINRT AND NOT WINCE)
  set(WINDOWS_XP 1) # x86: 5.1, x64: 5.2
  set(WINDOWS_XP_SET 1)
endif()
if(CMAKE_SYSTEM_VERSION LESS 6.0)
  set(EXE_LFLAGS "-SUBSYSTEM:CONSOLE,${WIN_MAJOR}.0${WIN_MINOR}")
endif()

# llvm-ar is not required to create static lib: lld-link /lib /machine:${WINSDK_ARCH}
if(NOT CMAKE_C_COMPILER)
  find_program(CMAKE_C_COMPILER clang-cl-9 clang-cl-8 clang-cl-7 clang-cl-6.0 clang-cl-5.0 clang-cl-4.0 clang-cl
    HINTS /usr/local/opt/llvm/bin
    CMAKE_FIND_ROOT_PATH_BOTH
  )
  message("CMAKE_C_COMPILER: ${CMAKE_C_COMPILER}")
  if(CMAKE_C_COMPILER)
    if(CMAKE_HOST_WIN32)
      set(_EXE .exe)
    endif()
    string(REGEX REPLACE "clang-cl(|-[0-9]+[\\.0]*)${_EXE}$" "lld-link\\1${_EXE}" LLD_LINK "${CMAKE_C_COMPILER}")
    set(CMAKE_LINKER ${LLD_LINK} CACHE FILEPATH "")
    message("CMAKE_LINKER:${CMAKE_LINKER}")
  else()
    set(CMAKE_C_COMPILER clang-cl CACHE FILEPATH "")
    set(CMAKE_LINKER lld-link CACHE FILEPATH "")
  endif()
  set(CMAKE_CXX_COMPILER ${CMAKE_C_COMPILER} CACHE FILEPATH "")
endif()


if(NOT CMAKE_SYSTEM_PROCESSOR)
  message("CMAKE_SYSTEM_PROCESSOR for target is not set. Must be aarch64(arm64), armv7(arm), x86(i686), x64(x86_64). Assumeme build for host arch: ${CMAKE_HOST_SYSTEM_PROCESSOR}.")
  set(CMAKE_SYSTEM_PROCESSOR ${CMAKE_HOST_SYSTEM_PROCESSOR})
endif()
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x.*64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL AMD64)
  set(TRIPLE_ARCH x86_64)
  set(WINSDK_ARCH x64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "86")
  set(TRIPLE_ARCH i386)
  set(WINSDK_ARCH x86)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "a.*64")
  set(TRIPLE_ARCH aarch64)
  set(WINSDK_ARCH arm64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(TRIPLE_ARCH armv7)
  set(WINSDK_ARCH arm)
endif()

# check env vars set by vcvarsall.bat
if(CMAKE_HOST_WIN32 AND EXISTS "$ENV{WindowsSdkDir}")
else()
  if(NOT WINSDK_DIR)
    set(WINSDK_DIR "$ENV{WindowsSdkDir}")
    set(WINSDK_VER "$ENV{WindowsSDKVersion}")
  endif()
  set(WINSDK_INCLUDE "${WINSDK_DIR}/Include/${WINSDK_VER}")
  set(WINSDK_LIB "${WINSDK_DIR}/Lib/${WINSDK_VER}")
endif()
if(CMAKE_HOST_WIN32 AND EXISTS "$ENV{VCToolsInstallDir}")
else()
  if(NOT MSVC_DIR)
    set(MSVC_DIR "$ENV{VCDIR}")
  endif()
  set(MSVC_INCLUDE "${MSVC_DIR}/include")
  set(MSVC_LIB "${MSVC_DIR}/lib")
endif()

if(ONECORE)
  set(ONECORE_DIR onecore)
  if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(ONECORE_LIB OneCore.Lib)
  else()
    set(ONECORE_LIB OneCoreUAP.Lib)
  endif()
else()
  if(NOT CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(STORE_DIR store)
  endif()
endif()

if(USE_LIBCXX AND NOT EXISTS ${USE_LIBCXX}/include/c++/v1/__config)
  message(SEND_ERROR "USE_LIBCXX MUST be a valid dir contains libc++ include and lib")
endif()

if(USE_LIBCXX)
  add_definitions(-D__WRL_ASSERT__=assert) # avoid including vcruntime_new.h to fix conflicts(assume libc++ is built with LIBCXX_NO_VCRUNTIME)
  set(CXX_FLAGS "${CXX_FLAGS} -I${USE_LIBCXX}/include/c++/v1")
  list(APPEND LINK_FLAGS -libpath:"${USE_LIBCXX}/lib")
endif()
set(COMPILE_FLAGS #-Xclang -Oz #/EHsc
    --target=${TRIPLE_ARCH}-windows-msvc
    #-fms-compatibility-version=19.15
    )
list(APPEND LINK_FLAGS
    -opt:ref # turned on by default in release mode (vc link.exe, not lld-link?)
    ${ONECORE_LIB}
    )

if(NOT CMAKE_HOST_WIN32) # assume CMAKE_HOST_WIN32 means in VS env, vs tools like rc and mt exists
  if(NOT EXISTS "${WINSDK_INCLUDE}/um/WINDOWS.H")
    set(case_sensitive_fs TRUE)
  endif()
  if(case_sensitive_fs)
    if(NOT EXISTS "${WINSDK_DIR}/vfs.yaml")
      message(SEND_ERROR "can not find vfs.yaml. you can use winsdk from https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download")
    endif()
    list(APPEND COMPILE_FLAGS -Xclang -ivfsoverlay -Xclang "${WINSDK_DIR}/vfs.yaml")
  endif()
endif()

if(EXISTS "${MSVC_INCLUDE}")
  list(APPEND COMPILE_FLAGS -imsvc "${MSVC_INCLUDE}")
  list(APPEND LINK_FLAGS -libpath:"${MSVC_LIB}/${ONECORE_DIR}/${WINSDK_ARCH}/${STORE_DIR}")
endif()
if(EXISTS "${WINSDK_INCLUDE}")
  list(APPEND COMPILE_FLAGS
    -imsvc "${WINSDK_INCLUDE}/ucrt"
    -imsvc "${WINSDK_INCLUDE}/shared"
    -imsvc "${WINSDK_INCLUDE}/um"
    -imsvc "${WINSDK_INCLUDE}/winrt")
  list(APPEND LINK_FLAGS
    -libpath:"${MSVC_LIB}/${ONECORE_DIR}/${WINSDK_ARCH}/${STORE_DIR}"
    -libpath:"${WINSDK_LIB}/ucrt/${WINSDK_ARCH}"
    -libpath:"${WINSDK_LIB}/um/${WINSDK_ARCH}"
    )
endif()

set(VSCMD_VER $ENV{VSCMD_VER})
if(NOT VSCMD_VER)
  list(APPEND LINK_FLAGS
    # Prevent CMake from attempting to invoke mt.exe. It only recognizes the slashed form and not the dashed form.
    /manifest:no # why -manifest:no results in rc error?  TODO: check mt and rc?
    )
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL Windows) # WINRT is not set for try_compile
  list(APPEND COMPILE_FLAGS -DUNICODE -D_UNICODE -EHsc)
  list(APPEND LINK_FLAGS -appcontainer -nodefaultlib:kernel32.Lib -nodefaultlib:Ole32.Lib)
  if(CMAKE_SYSTEM_NAME STREQUAL WindowsStore) # checked by MSVC_VERSION
    list(APPEND LINK_FLAGS WindowsApp.lib) # win10 only
  elseif(CMAKE_SYSTEM_NAME STREQUAL WindowsPhone)
    list(APPEND LINK_FLAGS WindowsPhoneCore.lib RuntimeObject.lib PhoneAppModelHost.lib) # win10 only
  endif()
  set(WINRT_SET 1)
endif()

string(REPLACE ";" " " COMPILE_FLAGS "${COMPILE_FLAGS}")
set(CMAKE_C_FLAGS "${COMPILE_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${COMPILE_FLAGS} ${CXX_FLAGS}" CACHE STRING "" FORCE)

string(REPLACE ";" " " LINK_FLAGS "${LINK_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS "${LINK_FLAGS} ${EXE_LFLAGS}" CACHE STRING "" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "${LINK_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "${LINK_FLAGS}" CACHE STRING "" FORCE)

# CMake populates these with a bunch of unnecessary libraries, which requires
# extra case-correcting symlinks and what not. Instead, let projects explicitly
# control which libraries they require.
set(CMAKE_C_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)

set(CMAKE_RC_COMPILER_INIT llvm-rc CACHE INTERNAL "${CMAKE_SYSTEM_NAME} llvm rc" FORCE)
set(CMAKE_RC_COMPLIER llvm-rc CACHE INTERNAL "${CMAKE_SYSTEM_NAME} llvm rc" FORCE)
set(CMAKE_GENERATOR_RC llvm-rc CACHE INTERNAL "${CMAKE_SYSTEM_NAME} llvm rc" FORCE)
# Allow clang-cl to work with macOS paths.
set(CMAKE_USER_MAKE_RULES_OVERRIDE "${CMAKE_CURRENT_LIST_DIR}/override.windows.clang.cmake")
