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

# --- M2/M3/M5: our NAPI module; library name defines the .so name (libentry.so) ---
add_library(entry SHARED napi_init.cpp cgo_bridge.cpp)

# --- M5: libcgoping.so is loaded via dlopen at runtime (NOT called through a linked symbol) ---
# hvigor only packs .so that participate in the CMake link graph, so we attach it as an
# IMPORTED target to guarantee it lands in the HAP's libs/<abi>/. At runtime we still use
# dlopen() + dlsym() (see cgo_bridge.cpp), i.e. the call path is runtime-resolved.
set(CGOPING_SO "${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}/libcgoping.so")
if(EXISTS "${CGOPING_SO}")
    add_library(cgoping SHARED IMPORTED)
    set_target_properties(cgoping PROPERTIES IMPORTED_LOCATION "${CGOPING_SO}")
    target_link_libraries(entry PUBLIC libace_napi.z.so prebuilt libhilog_ndk.z.so cgoping)
    message(STATUS "M5: libcgoping.so attached for packaging: ${CGOPING_SO}")
else()
    target_link_libraries(entry PUBLIC libace_napi.z.so prebuilt libhilog_ndk.z.so)
    message(WARNING "M5: libcgoping.so NOT found at ${CGOPING_SO} (run toolchain/build-cgoping.ps1 -Arch ...)")
endif()

# --- M6 / P-02: libxray.so (real Xray kernel). Same packaging rule as M5:
# it must appear in the CMake link graph or hvigor will not put it into the HAP.
# At runtime we still load it with dlopen() + dlsym("CGoInvoke").
set(XRAY_SO "${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}/libxray.so")
if(EXISTS "${XRAY_SO}")
    add_library(xraycore SHARED IMPORTED)
    set_target_properties(xraycore PROPERTIES IMPORTED_LOCATION "${XRAY_SO}")
    target_link_libraries(entry PUBLIC xraycore)
    message(STATUS "M6: libxray.so attached for packaging: ${XRAY_SO}")
else()
    message(WARNING "M6: libxray.so NOT found at ${XRAY_SO}")
endif()
