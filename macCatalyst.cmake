# use: -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0

set(CMAKE_SYSTEM_NAME iOS) # Modules/Platform/Apple-Clang.cmake:   elseif(CMAKE_SYSTEM_NAME MATCHES "iOS") set(CMAKE_${lang}_OSX_DEPLOYMENT_TARGET_FLAG "-miphoneos-version-min=")
set(MACCATALYST 1)
# FIXME: fatal error in iOS-Initialize.cmake if sdk is macosx
set(CMAKE_OSX_SYSROOT macosx)
set(CATALYST_FLAGS -target x86_64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi)
#set(CMAKE_C_FLAGS "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET} -target x86_64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi -iframework $/System/iOSSupport/System/Library/Frameworks")
#set(CMAKE_CXX_FLAGS "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET} -target x86_64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-macabi -iframework ${CMAKE_OSX_SYSROOT}/System/iOSSupport/System/Library/Frameworks")
add_compile_options(${CATALYST_FLAGS}  -iframeworkwithsysroot /System/iOSSupport/System/Library/Frameworks)
add_link_options(${CATALYST_FLAGS} -iframework /System/iOSSupport/System/Library/Frameworks)
# clang: warning: overriding '-mmacosx-version-min=13.0' option with '-target x86_64-apple-ios13.0-macabi' [-Woverriding-t-option]
set(CMAKE_USER_MAKE_RULES_OVERRIDE "${CMAKE_CURRENT_LIST_DIR}/override.maccatalyst.cmake")
