## Windows Cross Build via Clang-CL + LLD

toolchain file: win.clang.cmake

#### Requirements
- Copy of Windows SDK, only Include and Lib are used
- Copy of msvc sdk, only include and lib are used
- Symbolic links and clang vfs overlay for case sensitive filesystem. You can use scripts in https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download

#### Options
- WINSDK_DIR (or environment var WindowsSdkDir): win10 sdk dir containing Include and Lib
- WindowsSDKVersion (or environment var WindowsSDKVersion): win10 sdk version
- MSVC_DIR (or environment var VCDIR): msvc dir containing include and lib

## Raspberry Pi Host/Cross Build via Clang + LLD

toolchain file: rpi.clang.cmake

#### Requirements
- [Sysroot](https://sourceforge.net/projects/avbuild/files/raspberry-pi/rpi-sysroot.tar.xz/download)

#### Options
- RPI_SYSROOT or environment var RPI_SYSROOT
- USE_LIBCXX (optional, default off): use libc++ instead of libstdc++

## iOS

toolchain file: ios.cmake (https://github.com/wang-bin/ios.cmake)

#### Options
- IOS_ARCH: can be armv7, arm64, i386, x86_64 and any combination of above, e.g. "arm64;x86_64" to build universal 64bit binaries
- IOS_BITCODE (optional, default on)
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
- LTO (through option `USE_LTO`, default off)
- C++11 support for macOS 10.7
- asan, ubsan
- uninstall template

#### Defined CMake Vars

- RPI: if build for raspberry pi. CMAKE_<LANG>_COMPILER is required for cross build. `RPI_SYSROOT` or `RPI_VC_DIR` may be required for cross build
- HAVE_BRCM: bcm_host.h is found for RPI
- RPI_VC_DIR: the dir contains `include/bcm_host.h`
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
