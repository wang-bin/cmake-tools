## Windows Cross Build via Clang-CL + LLD

toolchain file: windows.clang.cmake

MSVC ABI compatible. Supports x86, x64, arm64(clang-8+).

#### Requirements
- Copy of Windows SDK, only Include and Lib are used
- Copy of msvc sdk, only include and lib are used

#### Options
- WINSDK_DIR (or environment var WindowsSdkDir): win10 sdk dir containing Include and Lib
- WINSDK_VER (or environment var WindowsSDKVersion): win10 sdk version
- MSVC_DIR (or environment var VCDIR): msvc dir containing include and lib
- UWP: build for uwp
- PHONE: build for windows phone
- ONECORE: use onecore
- USE_LIBCXX: use libc++ instead of msvcp

#### Defined CMake Vars
- WINRT: true if UWP or PHONE is set
- WINSTORE: same as WINRT
- WINDOWS_DESKTOP: not WINRT
- WINDOWS_XP: if CMAKE_SYSTEM_VERSION < 6.0

#### Defined C/C++ Macros
- _WIN32_WINNT

## Generic Linux Clang+LLD Toolchain

toolchain file: linux.clang.cmake

Clang(set by CMAKE_C_COMPILER or auto detect) and LLVM tools are auto detected and highest version is selected.

#### Options

Also applies for raspberry pi, sunxi etc.
- USE_LIBCXX: use libc++ instead of libstdc++
- USE_CXXABI: can be c++abi, stdc++ and supc++. Only required if libc++ is built with none abi
- USE_COMPILER_RT: use compiler-rt instead of libgcc as compiler runtime library
- USE_STDCXX: libstdc++ version to use, MUST be >= 4.8. default is 0, selected by compiler
- LINUX_SYSROOT: sysroot dir

## Legacy Raspberry Pi Host/Cross Build via Clang + LLD

toolchain file: rpi.clang.cmake

NOTE: using linux.clang.cmake and a generic linux sysroot is enough for a modern arm64 rpi OS. Legacy rpi(1~3) includes brcm libraries.

#### Requirements
- [Sysroot](https://sourceforge.net/projects/avbuild/files/raspberry-pi/rpi-sysroot.tar.xz/download)

#### Options
- USE_LIBCXX (optional, default off): use libc++ instead of libstdc++

#### Defined CMake Vars
- CMAKE_SYSTEM_PROCESSOR: armv6
- RPI: 1
- OS: rpi
- CMAKE_CROSSCOMPILING: auto detected

#### Defined C/C++ Macros
- OS_RPI

## iOS

toolchain file: ios.cmake (https://github.com/wang-bin/ios.cmake)

#### Options
- IOS_ARCH: can be armv7, arm64, i386, x86_64 and any combination of above, e.g. "arm64;x86_64" to build universal 64bit binaries
- IOS_BITCODE (optional, default off)
- IOS_EMBEDDED_FRAMEWORK (optional, default off)
- IOS_DEPLOYMENT_TARGET (optional)


## Additional Tools
`include(tools.cmake)` after `project(...)`

#### Features
- Dead code elimination
- ELF hardened (through option `ELF_HARDENED`, default is on)
- ELF separated debug symbol
- Windows XP support for VC (through option `WINDOWS_XP`, default is on)
- Android system stdc++ dependency removal
- LTO: USE_LTO=thin/0/1/N/AUTO, default is off
- C++11 support for macOS 10.7
- asan, ubsan
- uninstall template

#### Defined CMake Vars

- ARCH: x86, x64, ${ANDROID_ABI}, empty for apple multi-arch build
- WINRT, WINSTORE
- OS=rpi, iOS, macOS, WinRT, android

#### Functions
- enable_ldflags_if
- mkdsym: create elf debug symbol file
- mkres: convert any binary to C/C++ byte array
- set_relocatable_flags: enable relocatable object target
- exclude_libs_all: forbid exporting symbols from static dependencies
- set_rpath: rpath/runpath flags for ELF and Mach-O
- target_sources: compatible implementation for cmake < 3.1

#### Defined C Macros
- OS_RPI: if build for raspberry pi
