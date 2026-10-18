cmake_minimum_required(VERSION 3.5.0)
project(xray_poc)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

# --- M3: prebuilt shared library (built separately by NDK, see doc/poc build log) ---
# 约定目录：entry/src/main/libs/<abi>/libprebuilt.so
# CMAKE_CURRENT_SOURCE_DIR = entry/src/main/cpp  ⇒  ../libs = entry/src/main/libs
set(PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}")
add_library(prebuilt SHARED IMPORTED)
set_target_properties(prebuilt PROPERTIES
    IMPORTED_LOCATION "${PREBUILT_DIR}/libprebuilt.so")

# --- M2/M3: our NAPI module; library name defines the .so name (libentry.so) ---
add_library(entry SHARED napi_init.cpp)

target_link_libraries(entry PUBLIC libace_napi.z.so prebuilt)
