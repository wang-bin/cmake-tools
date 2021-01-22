# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2021, Wang Bin
# use: -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0

set(CMAKE_SYSTEM_NAME Darwin) # Modules/Platform/Apple-Clang.cmake:   elseif(CMAKE_SYSTEM_NAME MATCHES "iOS") set(CMAKE_${lang}_OSX_DEPLOYMENT_TARGET_FLAG "-miphoneos-version-min=")
set(MACCATALYST 1)
#set(CMAKE_OSX_SYSROOT iphoneos) # fatal error if CMAKE_SYSTEM_NAME is iOS, in iOS-Initialize.cmake if sdk is macosx. modify to macosx later. can override CMAKE_OSX_SYSROOT and config twice
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0)
endif()
list(LENGTH CMAKE_OSX_ARCHITECTURES ARCH_COUNT)
if(ARCH_COUNT GREATER 1)
# -target arch triple will be replaced internally if -arch is set
  set(CATALYST_FLAGS -target apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi)
elseif(ARCH_COUNT EQUAL 1)
  set(CATALYST_FLAGS -target ${CMAKE_OSX_ARCHITECTURES}-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi)
else()
  set(CMAKE_OSX_ARCHITECTURES ${CMAKE_SYSTEM_PROCESSOR})
  if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES ${CMAKE_HOST_SYSTEM_PROCESSOR})
  endif()
  set(CATALYST_FLAGS -target ${CMAKE_OSX_ARCHITECTURES}-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi)
endif()
#set(CMAKE_C_FLAGS "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET} -target x86_64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi -iframework $/System/iOSSupport/System/Library/Frameworks")
#set(CMAKE_CXX_FLAGS "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET} -target x86_64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi -iframework ${CMAKE_OSX_SYSROOT}/System/iOSSupport/System/Library/Frameworks")
add_compile_options(${CATALYST_FLAGS}  -iframeworkwithsysroot /System/iOSSupport/System/Library/Frameworks)
add_link_options(${CATALYST_FLAGS} -iframework /System/iOSSupport/System/Library/Frameworks)
# clang: warning: overriding '-mmacosx-version-min=13.0' option with '-target x86_64-apple-ios13.0-macabi' [-Woverriding-t-option]
set(CMAKE_USER_MAKE_RULES_OVERRIDE "${CMAKE_CURRENT_LIST_DIR}/override.maccatalyst.cmake")
