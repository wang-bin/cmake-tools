# TODO: elf harden. pch, auto add target dep libs dir to rpath-link paths. uninstall template
if(TOOLS_CMAKE_INCLUDED)
  return()
endif()
set(TOOLS_CMAKE_INCLUDED 1)

include(CheckCCompilerFlag)

# set RPI_SYSROOT, CMAKE_<LANG>_COMPILER for cross build
# defines RPI_VC_DIR for use externally
if(NOT RPI_SYSROOT)
  set(RPI_SYSROOT "/$ENV{RPI_SYSROOT}")
  if(EXISTS ${RPI_SYSROOT}/opt/vc/include/bcm_host.h) #clang does not support -print-sysroot.
    set(RPI_SYSROOT ${RPI_SYSROOT})
  else()
    execute_process(
        COMMAND ${CMAKE_C_COMPILER} -print-sysroot
        OUTPUT_VARIABLE CC_SYSROOT
        ERROR_VARIABLE SYSROOT_ERROR
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    set(RPI_SYSROOT ${CC_SYSROOT})
  endif()
endif()
if(RPI_SYSROOT OR RPI_VC_DIR)
  if(EXISTS ${RPI_VC_DIR}/include/bcm_host.h)
    set(HAVE_BRCM 1)
  else()
    find_file(HAVE_BRCM opt/vc/include/bcm_host.h 
        HINTS ENV RPI_SYSROOT
        PATHS ${RPI_SYSROOT}
        CMAKE_FIND_ROOT_PATH_BOTH
    )
  endif()
  if(HAVE_BRCM)
    if(RPI_SYSROOT STREQUAL / OR RPI_VC_DIR STREQUAL "/opt/vc" OR RPI_VC_DIR STREQUAL "/opt/vc/")
      message("Raspberry Pi host build")
    else()
      message("Raspberry Pi cross build")
      set(CMAKE_CROSSCOMPILING TRUE)
    endif()
    set(CMAKE_SYSTEM_NAME RaspberryPi)
    set(OS rpi)
    set(RPI 1)
    #set(ARCH armv6)
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
endif()

if(NOT ARCH)
  set(ARCH x86)
  if(CMAKE_CL_64)
      set(ARCH x64)
  elseif(CMAKE_SIZEOF_VOID_P MATCHES 8)
      set(ARCH x64)
  endif()
endif()

if(WINDOWS_PHONE OR WINDOWS_STORE) # defined when CMAKE_SYSTEM_NAME is WindowsPhone/WindowsStore 
  set(WINRT 1)
  set(WINSTORE 1)
  set(WIN32 1) ## defined in cmake?
  set(OS WinRT)
  # TODO: add cc/ld flags
endif()

if(NOT OS)
  if(WIN32)
    set(OS windows)
  elseif(APPLE)
    if(IOS)
      set(OS iOS)
    else()
      set(OS macOS)
    endif()
    set(ARCH universal)
  elseif(ANDROID)
    set(OS android)
    if(CMAKE_SYSTEM_NAME STREQUAL "Android") # use cmake android support instead of toolchain files from NDK
        set(ANDROID_ABI ${CMAKE_ANDROID_ARCH_ABI}) #CMAKE_SYSTEM_PROCESSOR
        set(ANDROID_STL ${CMAKE_ANDROID_STL_TYPE})
        set(ANDROID_TOOLCHAIN_PREFIX ${CMAKE_CXX_ANDROID_TOOLCHAIN_PREFIX})
    endif()
    set(ARCH ${ANDROID_ABI})
  endif()
endif()

# TODO: function ensure_cxx11
if(NOT CMAKE_CXX_STANDARD LESS 11)
  if(APPLE)
    if(POLICY CMP0063)
      cmake_policy(GET CMP0063 CMP0063_VAL)
    endif()
    if(NOT CMP0063_VAL OR CMP0063_VAL STREQUAL OLD)
      message("Set CMP0063 to NEW to get better compatibility")
    endif()
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
              message("Apple clang does not support c++11 for macOS 10.6")
          endif()
        else()
          set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
          # TODO: add function to run on target: install_name_tool -change /usr/lib/libc++.1.dylib @rpath/libc++.1.dylib $<TARGET_FILE:${TARGET_NAME}> ?
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
  if(ANDROID_STL MATCHES "^c\\+\\+_" AND CMAKE_C_COMPILER_ID STREQUAL "Clang") #-stdlib does not support gnustl
    # g++ has no -stdlib option. clang default stdlib is -lstdc++. we change it to libc++ to avoid linking against libstdc++
    # -stdlib=libc++ will find libc++.so, while android ndk has no such file. libc++.a is a linker script. Seems can be used for shared libc++
    #file(WRITE ${CMAKE_BINARY_DIR}/libc++.so "INPUT(-lc++_shared)") # SEARCH_DIR() is only valid for -Wl,-T
    #set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${CMAKE_BINARY_DIR} -stdlib=libc++")
    #set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${CMAKE_BINARY_DIR} -stdlib=libc++")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR} -stdlib=libc++")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR} -stdlib=libc++")
  else()
  # adding -lgcc in CMAKE_SHARED_LINKER_FLAGS will fail to link. add to target_link_libraries() or CMAKE_CXX_STANDARD_LIBRARIES_INIT in toolchain file
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR} -nodefaultlibs -lc")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LIBRARY_PATH_FLAG}${ANDROID_STL_LIB_DIR} -nodefaultlibs -lc")
  endif()
  #  -Wl,--exclude-libs,libgcc.a   https://android-review.googlesource.com/#/c/388556/
endif()

# FIXME: clang 3.5 (rpi) lto link error (ir object not recognized). osx clang3.9 link error
# USE_LTO=0,false,off to disable lto, 1 to enable lto, >1 to enable parallel lto with given jobs, other values (e.g. TRUE, -1) to enable parallel lto with maximum jobs
# If parallel lto is not supported, fallback to single job lto
# TODO: lld linker (e.g. for COFF /opt:lldltojobs=N)
option(USE_LTO "Link time optimization." 0)
if(USE_LTO)
  if(MSVC)
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
      else()
        cmake_host_system_information(RESULT CPUS QUERY NUMBER_OF_LOGICAL_CORES)
      endif()
      if(CPUS GREATER 1)
        set(LTO_FLAGS "-flto=${CPUS}") # parallel lto requires more memory and may fail to link
        set(CMAKE_REQUIRED_LIBRARIES_OLD ${CMAKE_REQUIRED_LIBRARIES})
        set(CMAKE_REQUIRED_LIBRARIES "${CMAKE_REQUIRED_LIBRARIES} ${LTO_FLAGS}") # check_c_compiler_flag() does not check linker flags. CMAKE_REQUIRED_LIBRARIES scope is function local
        check_c_compiler_flag(${LTO_FLAGS} HAVE_LTO_${CPUS})
        set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES_OLD})
        set(HAVE_LTO ${HAVE_LTO_${CPUS}})
      endif()
      if(NOT HAVE_LTO_${CPUS}) # android clang, icc etc.
        set(LTO_FLAGS "-flto")
        set(CMAKE_REQUIRED_LIBRARIES_OLD ${CMAKE_REQUIRED_LIBRARIES})
        set(CMAKE_REQUIRED_LIBRARIES "${CMAKE_REQUIRED_LIBRARIES} ${LTO_FLAGS}") # check_c_compiler_flag() does not check linker flags. CMAKE_REQUIRED_LIBRARIES scope is function local
        check_c_compiler_flag(${LTO_FLAGS} HAVE_LTO)
        set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES_OLD})
      endif()
      if(HAVE_LTO) # android clang fails to use lto because of LLVMgold plugin is not found
        set(LTO_CFLAGS ${LTO_FLAGS})
        set(LTO_LFLAGS ${LTO_FLAGS})
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


#include_directories($ENV{UNIVERSALCRTSDKDIR}/Include/$ENV{WINDOWSSDKVERSION}/ucrt)
# starts with "-": treated as a link flag. VC: starts with "/" and treated as a path

# Find binutils
if(NOT CMAKE_OBJCOPY)
  message("Probing CMAKE_OBJCOPY...")
  if(ANDROID)
    set(CMAKE_OBJCOPY ${ANDROID_TOOLCHAIN_PREFIX}objcopy)
  elseif(DEFINED CROSS_PREFIX)
    set(CMAKE_OBJCOPY ${CROSS_PREFIX}objcopy)
  elseif(CMAKE_C_COMPILER_ID STREQUAL "GNU") # $<C_COMPILER_ID:GNU> does not work
    # ${CMAKE_C_COMPILER} -print-prog-name=objcopy does not always work. WHEN?
    if(CMAKE_HOST_WIN32)
      string(REGEX REPLACE "gcc.exe$|cc.exe$" "objcopy.exe" CMAKE_OBJCOPY ${CMAKE_C_COMPILER})
    else()
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
  # TODO: find objcopy in target tools (e.g. clang toolchain)
  # TODO: apple support
  if(CMAKE_OBJCOPY)
    add_custom_command(TARGET ${tgt} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${tgt}> $<TARGET_FILE:${tgt}>.orig
      COMMAND ${CMAKE_OBJCOPY} --only-keep-debug $<TARGET_FILE:${tgt}> $<TARGET_FILE:${tgt}>.dsym
      COMMAND ${CMAKE_OBJCOPY} --strip-debug --strip-unneeded --discard-all $<TARGET_FILE:${tgt}>
      COMMAND ${CMAKE_OBJCOPY} --add-gnu-debuglink=$<TARGET_FILE:${tgt}>.dsym $<TARGET_FILE:${tgt}>
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
        file(APPEND ${ARGV0} "static const unsigned char k${filename}[] = {${filedata}0x00};\nstatic const size_t k${filename}_size = sizeof(k${filename});\n")
    endforeach()
endfunction()

# TODO: check target is a SHARED library
function(set_relocatable_flags)
  if(MSVC)

  else()
# can't use with -shared. -dynamic(apple) is fine. -shared is set in CMAKE_SHARED_LIBRARY_CREATE_${lang}_FLAGS, so we may add another library type RELOCATABLE in add_library
    set(LD_FLAGS "-r -nostdlib")
    set(CMAKE_REQUIRED_LIBRARIES "${LD_FLAGS}")
    check_c_compiler_flag("" HAVE_RO)
    if(NOT HAVE_RO)
      set(LD_FLAGS)
    endif()
  endif()
  if(LD_FLAGS)
    list(LENGTH ARGN _nb_args)
    if(_nb_args GREATER 0)
      foreach(t ${ARGN})
        get_target_property(${t}_reloc ${t} RELOCATABLE)
        if(${t}_reloc)
        message("set ro flags: ${LD_FLAGS}")
          set_property(TARGET ${t} APPEND_STRING PROPERTY LINK_FLAGS "${LD_FLAGS}")
        endif()
      endforeach()
      #set_property(TARGET ${ARGN} APPEND_STRING PROPERTY LINK_FLAGS "${LD_FLAGS}")
    else()
      set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${LD_FLAGS}" PARENT_SCOPE)
    endif()
  endif()
endfunction()

# strip_local([target1 [target2 ...]])
# apply "-Wl,-x" to all targets if no target is set
# strip local symbols when linking. asm symbols are still exported. relocatable object target contains renamed local symbols (for DCE) and removed at final linking.

# exclude_libs_all([target1 [target2 ...]])
# exporting symbols excluding all depended static libs
function(exclude_libs_all)
  if(NOT MSVC)
    if(NOT APPLE) # check APPLE is enough because no other linker available on apple. what about llvm lld?
      set(LD_FLAGS "${LD_FLAGS} -Wl,--exclude-libs,ALL") # prevent to export external lib apis
    endif()
  endif()
  if(NOT LD_FLAGS)
    message("no ld support")
    return()
  endif()
  list(LENGTH ARGN _nb_args)
  if(_nb_args GREATER 0)
    #set_target_properties(${ARGN} PROPERTIES LINK_FLAGS "${LD_FLAGS}") # not append
    set_property(TARGET ${ARGN} APPEND_STRING PROPERTY LINK_FLAGS "${LD_FLAGS}")
  else()
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${LD_FLAGS}" PARENT_SCOPE)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LD_FLAGS}" PARENT_SCOPE)
  endif()
# CMAKE_LINK_SEARCH_START_STATIC
endfunction()

# TODO: to a target?
# set default rpath dirs and add user defined rpaths
function(set_rpath)
  include(CMakeParseArguments)
  include(CheckCCompilerFlag)
#CMAKE_SHARED_LIBRARY_RPATH_LINK_C_FLAG
  if(WIN32 OR ANDROID)
    return()
  endif()
  cmake_parse_arguments(RPATH "" "" "DIRS" ${ARGN}) #ARGV?
  set(RPATH_FLAGS "")
  set(LD_RPATH "-Wl,-rpath,")
  set(LD_DTAGS "-Wl,--enable-new-dtags")
  set(CMAKE_REQUIRED_LIBRARIES "${LD_DTAGS}") # check_c_compiler_flag() does not check linker flags. CMAKE_REQUIRED_LIBRARIES scope is function local
  check_c_compiler_flag("" HAVE_DTAGS)
  if(HAVE_DTAGS)
    set(RPATH_FLAGS "${RPATH_FLAGS} ${LD_DTAGS}")
  endif()
# Executable dir search: ld -z origin, g++ -Wl,-R,'$ORIGIN', in makefile -Wl,-R,'$$ORIGIN'
# Working dir search: "."
# mac: install_name @rpath/... will search paths set in rpath link flags
  if(APPLE)
    list(APPEND RPATH_DIRS @executable_path/../Frameworks @loader_path @loader_path/lib) # macOS 10.4 does not support rpath, and only supports executable_path, so use loader_path only is enough
    # -install_name @rpath/... is set by cmake
  else()
      list(APPEND RPATH_DIRS "\\$ORIGIN" "\\$ORIGIN/lib") #. /usr/local/lib:$ORIGIN
    set(RPATH_FLAGS "${RPATH_FLAGS} -Wl,-z,origin")
  endif()
  foreach(p ${RPATH_DIRS})
    set(RPATH_FLAGS "${RPATH_FLAGS} ${LD_RPATH}\"${p}\"") # '' on windows will be included in runpathU
  endforeach()
  #string(REPLACE ";" ":" RPATHS "${RPATH_DIRS}")
  #set(RPATH_FLAGS "${RPATH_FLAGS} ${LD_RPATH}'${RPATHS}'")
  if(IOS AND NOT IOS_EMBEDDED_FRAMEWORK)
  else()
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${RPATH_FLAGS}" PARENT_SCOPE)
  endif()
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${RPATH_FLAGS}" PARENT_SCOPE)
endfunction()
