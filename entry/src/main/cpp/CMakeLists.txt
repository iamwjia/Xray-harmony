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
# NOTE: this EXISTS() check is evaluated at *configure* time; after adding a new
# per-ABI .so you must force a re-configure (touch this file / clean entry/build),
# otherwise that ABI silently links without the kernel. (Hit this on 2026-10-18.)
set(XRAY_SO "${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}/libxray.so")
if(EXISTS "${XRAY_SO}")
    add_library(xraycore SHARED IMPORTED)
    set_target_properties(xraycore PROPERTIES IMPORTED_LOCATION "${XRAY_SO}")
    # 关键：**不要**让 libxray.so 进入 libentry.so 的 DT_NEEDED。
    # 一旦成为 DT_NEEDED，动态加载器会在**进程启动时**就加载它，Go runtime 随即初始化
    # 并快照 environ；之后 ArkTS 再 setenv("xray.location.asset") 对 Go 的
    # os.LookupEnv 完全无效。实测表现：内核去 /system/bin/geosite.dat 找资源并失败。
    # --as-needed + 不引用其符号 = 不进 DT_NEEDED，但仍留在 link 图里供 hvigor 打包。
    target_link_options(entry PRIVATE "-Wl,--as-needed")
    target_link_libraries(entry PUBLIC xraycore)
    message(STATUS "M6: libxray.so attached for packaging: ${XRAY_SO}")
else()
    message(WARNING "M6: libxray.so NOT found at ${XRAY_SO}")
endif()
