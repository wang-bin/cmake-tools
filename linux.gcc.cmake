# This file is part of the cmake-tools project. It was retrieved from
# https://github.com/wang-bin/cmake-tools
#
# The cmake-tools project is licensed under the new MIT license.
#
# Copyright (c) 2017-2024, Wang Bin
#
# gcc cross build
#
# LINUX_FLAGS: flags for both compiler and linker
# CMAKE_SYSTEM_PROCESSOR: REQUIRED
# CMAKE_C_COMPILER: REQUIRED

include(${CMAKE_CURRENT_LIST_DIR}/linux.cmake)

# include dirs: g++ -x c++ -Wp,-v -E - </dev/null
# link dirs:    gcc -print-search-dirs  |grep libraries |sed 's,libraries: =,,' |tr ':' '\n' |xargs readlink -f

if(NOT USE_STDCXX VERSION_LESS 4.8)
# Selected GCC installation: always the last (greatest version), no way to change it
  add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-nostdinc++>")
  #file(GLOB_RECURSE CXX_DIRS LIST_DIRECTORIES true "${CMAKE_SYSROOT}/usr/include/*c++") # c++ is dir, so LIST_DIRECTORIES must be true (false by default for GLOB_RECURSE)
  add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-isystem${CMAKE_SYSROOT}/usr/include/c++/${USE_STDCXX}>") # c++. no space after -cxx-isystem
  add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-isystem${CXXCONFIG_H_DIR}>") # c++config.h.  no space after -cxx-isystem
  add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-isystem${CMAKE_SYSROOT}/usr/include/c++/${USE_STDCXX}/backward>") # c++. no space after -cxx-isystem
  # use libgcc of gcc is ok
  add_link_options(-B${CMAKE_SYSROOT}/usr/lib64 -B${CMAKE_SYSROOT}/usr/lib/gcc/${TARGET_TRIPPLE}/${USE_STDCXX})
endif()
add_compile_options(-isystem${CMAKE_SYSROOT}/usr/include) # prefer sysroot over compiler libgcc and libc dirs. MUST be after c++ dirs to ensure include_next works


if(NOT CMAKE_C_COMPILER)
  execute_process(COMMAND ${TARGET_TRIPPLE}-gcc --version RESULT_VARIABLE _CC_RET ERROR_QUIET OUTPUT_QUIET)
  if(_CC_RET EQUAL 0)
    set(CMAKE_C_COMPILER ${TARGET_TRIPPLE}-gcc CACHE INTERNAL "${CMAKE_SYSTEM_NAME} c compiler" FORCE)
  else()
    set(CMAKE_C_COMPILER ${TRIPLE_ARCH}-linux-gnu-gcc CACHE INTERNAL "${CMAKE_SYSTEM_NAME} c compiler" FORCE)
  endif()
endif()
if(NOT CMAKE_CXX_COMPILER)
  string(REGEX REPLACE "-gcc$" "-g++" CMAKE_CXX_COMPILER ${CMAKE_C_COMPILER})
endif()
message("CMAKE_C_COMPILER=${CMAKE_C_COMPILER}, ${CMAKE_CXX_COMPILER}")
set(CMAKE_C_FLAGS    "${LINUX_FLAGS}" CACHE INTERNAL "${CMAKE_SYSTEM_NAME} c compiler flags" FORCE)
set(CMAKE_CXX_FLAGS  "${LINUX_FLAGS} ${LINUX_FLAGS_CXX}"  CACHE INTERNAL "${CMAKE_SYSTEM_NAME} c++ compiler/linker flags" FORCE)
set(CMAKE_ASM_FLAGS  "${LINUX_FLAGS}"  CACHE INTERNAL "${CMAKE_SYSTEM_NAME} asm compiler flags" FORCE)
set(CMAKE_CXX_LINK_FLAGS "${LINUX_LINK_FLAGS_CXX}" CACHE INTERNAL "additional c++ link flags")
