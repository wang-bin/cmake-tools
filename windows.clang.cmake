# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2018-2024, Wang Bin
#
# clang-cl + lld to cross build apps for windows. can be easily change to other target platforms
# can not use clang --target=${ARCH}-none-windows-msvc because cmake assume it's cl if _MSC_VER is defined
# ref: https://github.com/llvm-mirror/llvm/blob/master/cmake/platforms/WinMsvc.cmake

# vars:
# WINSDK_DIR, WINSDK_VER, MSVC_DIR. If not set, environment vars WindowsSdkDir, WindowsSDKVersion, VCDIR are used
# CMAKE_SYSTEM_PROCESSOR: target arch, host arch is used if not set
# CMAKE_C_COMPILER: clang-cl path (optional)

# when cross building on a case sensitive filesystem, symbolic links for libs and vfs overlay for headers are required.
# You can download winsdk containing scripts to generate links and vfs overlay from: https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download
# msvc sdk: https://sourceforge.net/projects/avbuild/files/dep/msvcrt-dev.7z/download

# TODO: CMakeFindBinUtils.cmake find ar, rc lld etc.?
# TODO: mingw abi --target=${arch}-w64/pc-mingw32/windows-gnu
# TODO: msvc abi in gnu style: https://cmake.org/cmake/help/v3.15/release/3.15.html#compilers
# TODO: guess WINSDK_VER from sdk dir
# non-windows host: clang-cl invokes link.exe by default, use -fuse-ld=lld works. but -Wl, /link, -Xlinker does not work
option(CLANG_AS_LINKER "use clang as linker to invoke lld. MUST ON for now" OFF) # MUST use lld-link as CMAKE_LINKER on windows host, otherwise ms link.exe is used
option(USE_CLANG_CL "use clang-cl for msvc abi, or clang for gnu abi, same as clang --driver-mode=cl/gnu" ON)
option(USE_LIBCXX "use libc++ instead of libstdc++. set to libc++ path including include and lib dirs to enable" OFF)
option(UWP "build for uwp" OFF)
option(PHONE "build for phone" OFF)
option(ONECORE "build with oncore" OFF)
option(MIN_SIZE "build minimal size with optimizations enabled" ON) # ANGLE x86_32 crash(upload texture)

# Export configurable variables for the try_compile() command. Or set env var like llvm
set(CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  CMAKE_C_COMPILER # avoid find_program multiple times
  CMAKE_CXX_COMPILER
  CMAKE_LINKER
  CMAKE_SYSTEM_NAME
  CMAKE_SYSTEM_PROCESSOR
  MSVC_DIR
  WINSDK_DIR
  WINSDK_VER
  WINSDK_VFS_OVERLAY_PATH
  WINSDK_LIB_SYMLINKS_DIR
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
  # TODO: console subsystem also for dll? version does not matter
  set(EXE_LFLAGS "-SUBSYSTEM:CONSOLE,${WIN_MAJOR}.0${WIN_MINOR}")
endif()

# llvm-ar is not required to create static lib: lld-link /lib /machine:${WINSDK_ARCH}
if(NOT CMAKE_C_COMPILER)
  set(CLANG_FULL_NAMES)
  foreach(ver RANGE 20 7 -1)
    list(APPEND CLANG_FULL_NAMES clang-cl-${ver})
  endforeach()
  list(APPEND CLANG_FULL_NAMES clang-cl-6.0 clang-cl-5.0 clang-cl-4.0 clang-cl)
  find_program(CMAKE_C_COMPILER ${CLANG_FULL_NAMES}
    HINTS /usr/local/opt/llvm/bin
    CMAKE_FIND_ROOT_PATH_BOTH
  )
  message("CMAKE_C_COMPILER: ${CMAKE_C_COMPILER}")
endif()

if(CMAKE_C_COMPILER)
  if(CMAKE_HOST_WIN32)
    set(_EXE .exe)
  endif()
  if(NOT LLVM_CONFIG) # TODO: move to llvm.cmake
    string(REGEX REPLACE "clang-cl(|-[0-9]+[\\.0]*)${_EXE}$" "llvm-config${_EXE}" LLVM_CONFIG "${CMAKE_C_COMPILER}")
  endif()
  if(NOT CMAKE_LINKER)
    string(REGEX REPLACE "clang-cl(|-[0-9]+[\\.0]*)${_EXE}$" "lld-link\\1${_EXE}" LLD_LINK "${CMAKE_C_COMPILER}")
    if(NOT EXISTS ${LLD_LINK}) # homebrew: lld not in llvm-19.1.6
      execute_process(
        COMMAND ${CMAKE_C_COMPILER} -print-prog-name=lld-link
        OUTPUT_VARIABLE LLD_LINK
        OUTPUT_STRIP_TRAILING_WHITESPACE
      )
    endif()
    set(CMAKE_LINKER ${LLD_LINK} CACHE FILEPATH "")
    message("CMAKE_LINKER:${CMAKE_LINKER}")
  endif()
  if(NOT CLANG_EXE)
    string(REGEX REPLACE "clang-cl(|-[0-9]+[\\.0]*)${_EXE}$" "clang\\1${_EXE}" CLANG_EXE "${CMAKE_C_COMPILER}")
  endif()
else()
  set(CMAKE_C_COMPILER clang-cl CACHE FILEPATH "")
  set(CMAKE_LINKER lld-link CACHE FILEPATH "")
endif()
set(CMAKE_CXX_COMPILER ${CMAKE_C_COMPILER} CACHE FILEPATH "")
if(EXISTS ${LLVM_CONFIG})
  execute_process(
    COMMAND ${LLVM_CONFIG} --bindir
    OUTPUT_VARIABLE LLVM_BIN
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
endif()

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" CMAKE_SYSTEM_PROCESSOR)
if(NOT CMAKE_SYSTEM_PROCESSOR)
  message("CMAKE_SYSTEM_PROCESSOR for target is not set. Must be aarch64(arm64), armv7(arm), x86(i686), x64(x86_64). Assumeme build for host arch: ${CMAKE_HOST_SYSTEM_PROCESSOR}.")
  set(CMAKE_SYSTEM_PROCESSOR ${CMAKE_HOST_SYSTEM_PROCESSOR})
endif()
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x.*64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "[aA][mM][dD]64")
  set(TRIPLE_ARCH x86_64)
  set(WINSDK_ARCH x64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "86")
  set(TRIPLE_ARCH i386)
  set(WINSDK_ARCH x86)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "a.*64ec")
  set(TRIPLE_ARCH arm64ec)
  set(WINSDK_ARCH arm64)
  add_compile_options(-D_ARM64EC_ -D_M_ARM64EC)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "a.*64")
  set(TRIPLE_ARCH aarch64)
  set(WINSDK_ARCH arm64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "[aA][rR][mM]")
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
#-nodefaultlib:kernel32.lib -defaultlib:${ONECORE_LIB}
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

set(_EXTRA_LIB_DIRS)
if(USE_LIBCXX)
  add_definitions(-D__WRL_ASSERT__=assert) # avoid including vcruntime_new.h to fix conflicts(assume libc++ is built with LIBCXX_NO_VCRUNTIME)
  set(CXX_FLAGS "${CXX_FLAGS} -I${USE_LIBCXX}/include/c++/v1")
  list(APPEND _EXTRA_LIB_DIRS "${USE_LIBCXX}/lib")
endif()
if(WINDOWS_DESKTOP AND WINSDK_ARCH MATCHES "arm")
  add_definitions(-D_ARM_WINAPI_PARTITION_DESKTOP_SDK_AVAILABLE=1)
  set(_ARM_WINAPI_PARTITION_DESKTOP_SDK_AVAILABLE_SET 1)
endif()
# https://bugs.llvm.org/show_bug.cgi?id=42843 # <type_traits> clang-cl-9 lld-link/link: error: duplicate symbol: bool const std::_Is_integral<bool> in a.obj and in b.obj
# CMAKE_CXX_COMPILER_VERSION is not detected in toolchain file
# TODO: llvm-15 SEH
# TODO: -winsysroot(lld-15 too), -winsdkversion, -winsdkdir, -vctoolsdir, -vctoolsversion
set(COMPILE_FLAGS #-Xclang -Oz #/EHsc
    --target=${TRIPLE_ARCH}-pc-windows-msvc # CMAKE_<LANG>_COMPILER_TARGET
    #-fms-extensions
    #-fms-compatibility-version=19.15
    #-Werror=unknown-argument
    #-Zc:dllexportInlines- # TODO: clang-8 http://blog.llvm.org/2018/11/30-faster-windows-builds-with-clang-cl_14.html
    -Zc:inline
    )
list(APPEND LINK_FLAGS
    -opt:ref,icf,lbr # turned on by default in release mode (vc link.exe, not lld-link?)
    ${ONECORE_LIB}
    )
link_libraries(-incremental:no) # conflict with -opt:ref. /INCREMENTAL is append after LINK_FLAGS by cmake
set(OPT_REF_SET 1)

# generate_winsdk_vfs_overlay, generate_winsdk_lib_symlinks from llvm project https://github.com/llvm/llvm-project/blob/master/llvm/cmake/platforms/WinMsvc.cmake#L106
function(generate_winsdk_vfs_overlay winsdk_include_dir output_path)
  set(include_dirs)
  file(GLOB_RECURSE entries LIST_DIRECTORIES true "${winsdk_include_dir}/*")
  foreach(entry ${entries})
    if(IS_DIRECTORY "${entry}")
      list(APPEND include_dirs "${entry}")
    endif()
  endforeach()

  file(WRITE "${output_path}"  "version: 0\n")
  file(APPEND "${output_path}" "case-sensitive: false\n")
  file(APPEND "${output_path}" "roots:\n")

  foreach(dir ${include_dirs})
    file(GLOB headers RELATIVE "${dir}" "${dir}/*.h")
    if(NOT headers)
      continue()
    endif()

    file(APPEND "${output_path}" "  - name: \"${dir}\"\n")
    file(APPEND "${output_path}" "    type: directory\n")
    file(APPEND "${output_path}" "    contents:\n")

    foreach(header ${headers})
      file(APPEND "${output_path}" "      - name: \"${header}\"\n")
      file(APPEND "${output_path}" "        type: file\n")
      file(APPEND "${output_path}" "        external-contents: \"${dir}/${header}\"\n")
    endforeach()
  endforeach()
endfunction()

function(generate_winsdk_lib_symlinks winsdk_um_lib_dir output_dir)
  execute_process(COMMAND "${CMAKE_COMMAND}" -E make_directory "${output_dir}")
  file(GLOB libraries RELATIVE "${winsdk_um_lib_dir}" "${winsdk_um_lib_dir}/*")
  foreach(library ${libraries})
    string(TOLOWER "${library}" all_lowercase_symlink_name)
    if(NOT library STREQUAL all_lowercase_symlink_name)
      execute_process(COMMAND "${CMAKE_COMMAND}"
                              -E create_symlink
                              "${winsdk_um_lib_dir}/${library}"
                              "${output_dir}/${all_lowercase_symlink_name}")
    endif()

    get_filename_component(name_we "${library}" NAME_WE)
    get_filename_component(ext "${library}" EXT)
    string(TOLOWER "${ext}" lowercase_ext)
    set(lowercase_ext_symlink_name "${name_we}${lowercase_ext}")
    if(NOT library STREQUAL lowercase_ext_symlink_name AND
       NOT all_lowercase_symlink_name STREQUAL lowercase_ext_symlink_name)
      execute_process(COMMAND "${CMAKE_COMMAND}"
                              -E create_symlink
                              "${winsdk_um_lib_dir}/${library}"
                              "${output_dir}/${lowercase_ext_symlink_name}")
    endif()
  endforeach()
endfunction()

if(NOT CMAKE_HOST_WIN32) # assume CMAKE_HOST_WIN32 means in VS env, vs tools like rc and mt exists
  if(NOT EXISTS "${WINSDK_INCLUDE}/um/WINDOWS.H")
    set(case_sensitive_fs TRUE)
  endif()
  if(case_sensitive_fs)
    if(NOT WINSDK_VFS_OVERLAY_PATH)
      set(WINSDK_VFS_OVERLAY_PATH "${WINSDK_DIR}/vfs.yaml")
    endif()
    if(NOT EXISTS "${WINSDK_VFS_OVERLAY_PATH}")
      set(WINSDK_VFS_OVERLAY_PATH "${CMAKE_BINARY_DIR}/winsdk_vfs.yaml")
      if(NOT EXISTS ${WINSDK_VFS_OVERLAY_PATH})
        message("can not find vfs.yaml in windows sdk, generating one. or you can use winsdk from https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download")
        generate_winsdk_vfs_overlay("${WINSDK_INCLUDE}" "${WINSDK_VFS_OVERLAY_PATH}")
      endif()
    endif()
    if(NOT DEFINED WINSDK_LIB_SYMLINKS_DIR)
      set(WINSDK_LIB_SYMLINKS_DIR "${CMAKE_BINARY_DIR}/winsdk_lib_symlinks")
    endif()
    if(NOT EXISTS "${WINSDK_LIB_SYMLINKS_DIR}")
      message("generating windows sdk lib symlinks...")
      generate_winsdk_lib_symlinks("${WINSDK_LIB}/um/${WINSDK_ARCH}" "${WINSDK_LIB_SYMLINKS_DIR}")
    endif()
    list(APPEND _EXTRA_LIB_DIRS "${WINSDK_LIB_SYMLINKS_DIR}")
    if(CMAKE_VERSION VERSION_LESS 3.19.0)
      list(APPEND COMPILE_FLAGS -Xclang -ivfsoverlay -Xclang "${WINSDK_VFS_OVERLAY_PATH}")
    else()
      set(CMAKE_CLANG_VFS_OVERLAY "${WINSDK_VFS_OVERLAY_PATH}" CACHE INTERNAL "windows vfs")
      set(CMAKE_RC_FLAGS_INIT "-Xclang -ivfsoverlay -Xclang ${WINSDK_VFS_OVERLAY_PATH}") # cmake3.19 does not apply CMAKE_CLANG_VFS_OVERLAY for rc
    endif()
  endif()
endif()

set(IMSVC)
if(EXISTS "${MSVC_INCLUDE}")
  list(APPEND IMSVC "${MSVC_INCLUDE}")
  list(APPEND _EXTRA_LIB_DIRS "${MSVC_LIB}/${ONECORE_DIR}/${WINSDK_ARCH}/${STORE_DIR}")
endif()
if(EXISTS "${WINSDK_INCLUDE}")
  list(APPEND IMSVC
    "${WINSDK_INCLUDE}/ucrt"
    "${WINSDK_INCLUDE}/shared"
    "${WINSDK_INCLUDE}/um"
    "${WINSDK_INCLUDE}/winrt"
    # TODO: cppwinrt
  )
  list(APPEND _EXTRA_LIB_DIRS
    "${WINSDK_LIB}/ucrt/${WINSDK_ARCH}"
    "${WINSDK_LIB}/um/${WINSDK_ARCH}"
    )
endif()

# https://gitlab.kitware.com/cmake/cmake/-/issues/20658#note_804737
if(IMSVC)
  set(CMAKE_RC_STANDARD_INCLUDE_DIRECTORIES ${IMSVC})
  if(CMAKE_VERSION VERSION_LESS 3.19.0)
    foreach(d ${IMSVC})
      list(APPEND COMPILE_FLAGS -imsvc ${d})
    endforeach(d ${IMSVC})
  else()
    set(CMAKE_C_STANDARD_INCLUDE_DIRECTORIES ${IMSVC})
    set(CMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES ${IMSVC})
  endif()
endif()

set(VSCMD_VER $ENV{VSCMD_VER})
if(NOT VSCMD_VER)
  list(APPEND LINK_FLAGS
    # Prevent CMake from attempting to invoke mt.exe. It only recognizes the slashed form and not the dashed form.
    /manifest:no
    )
endif()

list(APPEND COMPILE_FLAGS -DUNICODE -D_UNICODE)
if(NOT CMAKE_SYSTEM_NAME STREQUAL Windows) # WINRT is not set for try_compile
  if(NOT WINSDK_ARCH STREQUAL "arm") # TODO: -EHsc internal error for arm
      list(APPEND COMPILE_FLAGS -EHsc)
  endif()
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
# -Oz + /O1 is minimal size, but may generate wrong code(i386 crash). "/MD /O1 /Ob1 /DNDEBUG" is appended to CMAKE_${lang}_FLAGS_MINSIZEREL_INIT by cmake
if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "a.*64")
# FIXME: CMAKE_C_FLAGS_MINSIZEREL cmake3.19+ no effect?
    set(_CRT_FLAG_MultiThreaded -MT)
    set(_CRT_FLAG_MultiThreadedDLL -MD)
    set(_CRT_FLAG_MultiThreadedDebug -MTd)
    set(_CRT_FLAG_MultiThreadedDebugDLL -MDd)
    set(_CRT_FLAG_ -MD)
    set(_CRT_FLAG ${_CRT_FLAG_${CMAKE_MSVC_RUNTIME_LIBRARY}})
  if(NOT MIN_SIZE)
    set(_OPTIMIZE_FLAG -Ob1) # llvm8 fatal error: error in backend: .seh_ directive must appear within an active frame
  endif()
  set(CMAKE_C_FLAGS_MINSIZEREL "-Xclang -Oz ${_OPTIMIZE_FLAG} -DNDEBUG ${_CRT_FLAG}")
  set(CMAKE_CXX_FLAGS_MINSIZEREL "${CMAKE_C_FLAGS_MINSIZEREL}")
  unset(_OPTIMIZE_FLAG)
  unset(_CRT_FLAG)
  unset(_CRT_FLAG_)
  unset(_CRT_FLAG_MultiThreadedDebugDLL)
  unset(_CRT_FLAG_MultiThreadedDebug)
  unset(_CRT_FLAG_MultiThreadedDLL)
  unset(_CRT_FLAG_MultiThreaded)
endif()

string(REPLACE ";" " " LINK_FLAGS "${LINK_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS "${LINK_FLAGS} ${EXE_LFLAGS}" CACHE STRING "" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "${LINK_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "${LINK_FLAGS}" CACHE STRING "" FORCE)
link_directories(${_EXTRA_LIB_DIRS}) # link_directories(BEFORE|AFTER ) in user code will work. CMAKE_*_LINKER_FLAGS will be always before link_directories()

# CMake populates these with a bunch of unnecessary libraries, which requires
# extra case-correcting symlinks and what not. Instead, let projects explicitly
# control which libraries they require.
set(CMAKE_C_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)

if(EXISTS ${LLVM_BIN})
  set(LLVM_RC ${LLVM_BIN}/llvm-rc${_EXE})
  set(LLVM_MT ${LLVM_BIN}/llvm-mt${_EXE})
  set(LLVM_LIB ${LLVM_BIN}/llvm-lib${_EXE})
else()
  execute_process(
    COMMAND ${CLANG_EXE} -print-prog-name=llvm-rc
    OUTPUT_VARIABLE LLVM_RC
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  execute_process(
    COMMAND ${CLANG_EXE} -print-prog-name=llvm-mt
    OUTPUT_VARIABLE LLVM_MT
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  # -print-prog-name=llvm-lib result is E:/LLVM/bin\llvm-lib, Invalid character escape '\l'.
  string(REGEX REPLACE "clang-cl(|-[0-9]+[\\.0]*)${_EXE}$" "llvm-lib\\1${_EXE}" LLVM_LIB "${CMAKE_C_COMPILER}")
endif()
# rc rule: void cmNinjaTargetGenerator::WriteCompileRule(const std::string& lang)
set(CMAKE_RC_COMPILER_INIT ${LLVM_RC} CACHE INTERNAL "${CMAKE_SYSTEM_NAME} llvm rc" FORCE)
set(CMAKE_RC_COMPLIER ${LLVM_RC} CACHE INTERNAL "${CMAKE_SYSTEM_NAME} llvm rc" FORCE)
set(CMAKE_GENERATOR_RC ${LLVM_RC} CACHE INTERNAL "${CMAKE_SYSTEM_NAME} llvm rc" FORCE)
set(CMAKE_AR ${LLVM_LIB}  CACHE INTERNAL "${CMAKE_SYSTEM_NAME} llvm-lib for static libs since cmake 3.18" FORCE) # cmake<3.18 CMAKE_AR="lld-link -lib" for static lib

if(WINSDK_ARCH STREQUAL "arm")
  set(CMAKE_TRY_COMPILE_CONFIGURATION Release) # default is debug, /Zi error for arm
endif()
# Allow clang-cl to work with macOS paths.
set(CMAKE_USER_MAKE_RULES_OVERRIDE "${CMAKE_CURRENT_LIST_DIR}/override.windows.clang.cmake")
