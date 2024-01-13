set(CENTOS 1)
set(USE_CRT "")
set(TARGET_VENDOR -redhat)
include(${CMAKE_CURRENT_LIST_DIR}/linux.gcc.cmake)

set(CMAKE_SYSTEM_VERSION "${RHEL_MAJOR}.${RHEL_MINOR}")

# centos8 gdb8 supports dwarf5
if(RHEL_MAJOR LESS 8)
  add_compile_options($<$<AND:$<COMPILE_LANGUAGE:C,CXX>,$<CONFIG:Debug,RelWithDebInfo>>:-gdwarf-4>)
endif()