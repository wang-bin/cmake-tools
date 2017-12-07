`include(tools.cmake)` after `project(...)`

## Features

- raspberry pi host build and cross build on mac/linux/windows
- C++11 for macOS 10.7
- Dead code elimination
- ELF hardened (through option `ELF_HARDENED`, default on)
- Windows XP support for VC (through option `WINDOWS_XP`, default on)
- Android system stdc++ dependency removal
- LTO (through option `USE_LTO`, default off)
- ELF separated debug symbol
- uninstall
- iOS features: https://github.com/wang-bin/ios.cmake
- Raspberry pi cross build using clang+lld

## Defined CMake Vars

- TOOLS_CMAKE_INCLUDED
- RPI: if build for raspberry pi. CMAKE_<LANG>_COMPILER is required for cross build. `RPI_SYSROOT` or `RPI_VC_DIR` may be required for cross build
- HAVE_BRCM: bcm_host.h is found for RPI
- RPI_VC_DIR: the dir contains `include/bcm_host.h`
- ARCH: x86, x64, universal(apple), ${ANDROID_ABI}
- WINRT, WINSTORE
- OS=rpi, iOS, macOS, WinRT, android

## Functions


## Defined C Macros
- OS_RPI: if build for raspberry pi


