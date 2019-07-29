# from libcxx HandleLibcxxFlags.cmake
# Mangle the name of a compiler flag into a valid CMake identifier.
# Ex: --std=c++11 -> STD_EQ_CXX11

# macros, global scope
macro(mangle_name str output)
  string(STRIP "${str}" strippedStr)
  string(REGEX REPLACE "^/" "" strippedStr "${strippedStr}")
  string(REGEX REPLACE "^-+" "" strippedStr "${strippedStr}")
  string(REGEX REPLACE "-+$" "" strippedStr "${strippedStr}")
  string(REPLACE "-" "_" strippedStr "${strippedStr}")
  string(REPLACE ":" "_COLON_" strippedStr "${strippedStr}")
  string(REPLACE "=" "_EQ_" strippedStr "${strippedStr}")
  string(REPLACE "+" "X" strippedStr "${strippedStr}")
  string(TOUPPER "${strippedStr}" ${output})
endmacro()

if(MSVC)
  set(WERROR "/W4 /WX") # FIXME: why -WX does not work?
else()
  set(WERROR "-Wall -Wextra -Wconversion -pedantic -Wfatal-errors -Werror")
endif()

function(add_compile_options_if_supported)
  foreach(flag ${ARGN})
    mangle_name("${flag}" flagname)
    check_cxx_compiler_flag("${WERROR} ${flag}" "SUPPORTS_${flagname}_FLAG") # c,c++
    if(${SUPPORTS_${flagname}_FLAG})
      add_compile_options(${flag})
    endif()
  endforeach()
endfunction()

# Add a list of flags to 'CMAKE_C_FLAGS'.
macro(add_c_flags)
  foreach(f ${ARGN})
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${f}")
  endforeach()
endmacro()

# If 'condition' is true then add the specified list of flags to
# 'CMAKE_C_FLAGS'
macro(add_c_flags_if condition)
  if (${condition})
    add_c_flags(${ARGN})
  endif()
endmacro()

# For each specified flag, add that flag to 'CMAKE_C_FLAGS' if the
# flag is supported by the C++ compiler.
macro(add_c_flags_if_supported)
  foreach(flag ${ARGN})
      mangle_name("${flag}" flagname)
      check_c_compiler_flag("${WERROR} ${flag}" "SUPPORTS_${flagname}_FLAG")
      add_c_flags_if(SUPPORTS_${flagname}_FLAG ${flag})
  endforeach()
endmacro()

# Add a list of flags to 'CMAKE_CXX_FLAGS'.
macro(add_cxx_flags)
  foreach(f ${ARGN})
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${f}")
  endforeach()
endmacro()

# If 'condition' is true then add the specified list of flags to
# 'CMAKE_CXX_FLAGS'
macro(add_cxx_flags_if condition)
  if (${condition})
    add_cxx_flags(${ARGN})
  endif()
endmacro()

# For each specified flag, add that flag to 'CMAKE_CXX_FLAGS' if the
# flag is supported by the C++ compiler.
macro(add_cxx_flags_if_supported)
  foreach(flag ${ARGN})
      mangle_name("${flag}" flagname)
      check_cxx_compiler_flag("${WERROR} ${flag}" "SUPPORTS_${flagname}_FLAG")
      add_cxx_flags_if(SUPPORTS_${flagname}_FLAG ${flag})
  endforeach()
endmacro()

# Add a list of flags to 'CMAKE_SHARED_LINKER_FLAGS' and 'CMAKE_EXE_LINKER_FLAGS'.
macro(add_link_flags)
  foreach(f ${ARGN})
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${f}")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${f}")
  endforeach()
endmacro()

# If 'condition' is true then add the specified list of flags to
# add_lflag_if_not
macro(add_link_flags_if condition)
  if (${condition})
    add_link_flags(${ARGN})
  endif()
endmacro()


function(is_link_flag_supported flag out)
  # unsupported flags can be a warning (clang, vc)
  set(CMAKE_REQUIRED_LIBRARIES_OLD ${CMAKE_REQUIRED_LIBRARIES})
  set(CMAKE_REQUIRED_LIBRARIES ${flag})
  list(APPEND CMAKE_REQUIRED_LIBRARIES ${WERROR})
  # can not check "-Werror ${flags}" because it will be used by not only linker but also -c and warns linker flags are unused
  check_cxx_compiler_flag("" "${out}") # out is cached
  #set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES}) # add for macro
endfunction()

# For each specified flag, add that flag to 'LIBCXX_LINK_FLAGS' if the
# flag is supported by the C++ compiler.
macro(add_link_flags_if_supported)
  foreach(flag ${ARGN})
    mangle_name("${flag}" flagname)
    is_link_flag_supported("${flag}" "SUPPORTS_${flagname}_FLAG")
    add_link_flags_if(SUPPORTS_${flagname}_FLAG ${flag})
    set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES})
  endforeach()
endmacro()