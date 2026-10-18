// cgo_bridge.cpp — M5: load the Go c-shared library at runtime and call CGoPing().
//
// Purpose (P-03 evidence, no real device needed):
//   prove that the Go runtime (built with the OHOS fork, GOOS=openharmony) can
//   initialize *inside an OHOS app process* and execute an exported cgo call.
//
// Design notes:
//   * We deliberately do NOT link libcgoping.so. It is loaded with dlopen() so the
//     evidence is "runtime load + call", not "the loader resolved it at startup".
//   * The library path is derived from our own module path (dladdr on libentry.so),
//     because the app's native lib dir is not guaranteed to be on the loader search
//     path for a bare SONAME. The bare SONAME is still tried first.
//   * Every step is logged via hilog BEFORE it can crash, so a SIGSEGV can be
//     attributed to a stage (dlopen / dlsym / call) instead of "it just died".
//   * On success the payload is freed with the library's own CGoFree (never free()).
//
// NOTE: this file contributes ONE napi function, registered from napi_init.cpp
// (one NAPI module per .so — no second napi_module_register here).

#include <dlfcn.h>
#include <chrono>
#include <string>

#include "napi/native_api.h"
#include <hilog/log.h>

namespace {

// Signature of the exported entry points (see toolchain/smoke/cgoping.go).
using CGoPingFn = char *(*)();
using CGoFreeFn = void (*)(char *);

std::string DirNameOf(const std::string &path)
{
    size_t pos = path.find_last_of('/');
    if (pos == std::string::npos) {
        return std::string();
    }
    return path.substr(0, pos + 1);
}

// Directory that holds this very module (…/libs/<abi>/libentry.so).
std::string OwnModuleDir()
{
    Dl_info info{};
    if (dladdr(reinterpret_cast<void *>(&DirNameOf), &info) != 0 && info.dli_fname != nullptr) {
        return DirNameOf(info.dli_fname);
    }
    return std::string();
}

napi_value MakeString(napi_env env, const std::string &s)
{
    napi_value out = nullptr;
    napi_create_string_utf8(env, s.c_str(), s.size(), &out);
    return out;
}

} // namespace

// M5: dlopen libcgoping.so -> dlsym CGoPing -> call -> dlsym CGoFree -> free.
extern "C" napi_value M5CGoPing(napi_env env, napi_callback_info info)
{
    OH_LOG_INFO(LOG_APP, "M5 stage=begin");

    // Optional arg: explicit path to the .so (extracted from rawfile by ArkTS).
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string inputPath;
    if (argc >= 1 && argv[0] != nullptr) {
        napi_valuetype t = napi_undefined;
        napi_typeof(env, argv[0], &t);
        if (t == napi_string) {
            size_t len = 0;
            napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
            if (len > 0) {
                inputPath.resize(len + 1);
                napi_get_value_string_utf8(env, argv[0], &inputPath[0], len + 1, &len);
                inputPath.resize(len);
            }
        }
    }

    std::string tried;
    void *handle = nullptr;

    // 1) explicit path (from rawfile), 2) bare SONAME, 3) next to our own module
    if (!inputPath.empty()) {
        tried += "[arg:" + inputPath + "] ";
        handle = dlopen(inputPath.c_str(), RTLD_NOW);
        if (handle == nullptr) {
            const char *e0 = dlerror();
            tried += (e0 != nullptr ? e0 : "unknown");
            tried += " | ";
        }
    }
    if (handle == nullptr) {
        tried += "[soname] ";
        handle = dlopen("libcgoping.so", RTLD_NOW);
        if (handle == nullptr) {
            const char *e1 = dlerror();
            tried += (e1 != nullptr ? e1 : "unknown");
            tried += " | ";

            std::string dir = OwnModuleDir();
            std::string full = dir.empty() ? std::string("libcgoping.so") : (dir + "libcgoping.so");
            tried += "[path:" + full + "] ";
            handle = dlopen(full.c_str(), RTLD_NOW);
            if (handle == nullptr) {
                const char *e2 = dlerror();
                tried += (e2 != nullptr ? e2 : "unknown");
            }
        }
    }

    if (handle == nullptr) {
        OH_LOG_ERROR(LOG_APP, "M5 stage=dlopen FAILED %{public}s", tried.c_str());
        return MakeString(env, "M5 dlopen FAILED: " + tried);
    }
    OH_LOG_INFO(LOG_APP, "M5 stage=dlopen ok");

    // 2) resolve symbols
    auto ping = reinterpret_cast<CGoPingFn>(dlsym(handle, "CGoPing"));
    if (ping == nullptr) {
        const char *e = dlerror();
        OH_LOG_ERROR(LOG_APP, "M5 stage=dlsym CGoPing FAILED %{public}s", e != nullptr ? e : "unknown");
        dlclose(handle);
        return MakeString(env, std::string("M5 dlsym CGoPing FAILED: ") + (e != nullptr ? e : "unknown"));
    }
    auto freeFn = reinterpret_cast<CGoFreeFn>(dlsym(handle, "CGoFree"));
    OH_LOG_INFO(LOG_APP, "M5 stage=dlsym ok CGoFree=%{public}s", freeFn != nullptr ? "found" : "MISSING");

    // 3) call into Go — this is the actual P-03 evidence point
    OH_LOG_INFO(LOG_APP, "M5 stage=call begin");
    char *raw = ping();
    OH_LOG_INFO(LOG_APP, "M5 stage=call returned");

    if (raw == nullptr) {
        OH_LOG_ERROR(LOG_APP, "M5 stage=call returned NULL");
        dlclose(handle);
        return MakeString(env, "M5 called but CGoPing returned NULL");
    }

    std::string payload(raw);
    if (freeFn != nullptr) {
        freeFn(raw); // MUST use the library's own free (memory allocated by Go)
    }
    dlclose(handle);

    OH_LOG_INFO(LOG_APP, "M5 stage=done payload=%{public}s", payload.c_str());
    return MakeString(env, payload);
}

// ---------------------------------------------------------------------------
// M6 / P-02: load the REAL Xray kernel (libxray.so) and prove it responds.
//
// We deliberately send an envelope with an unknown method: the expected answer is
// a well-formed JSON with success=false. That proves (a) the .so loads, (b) the Go
// runtime inside it initialises, (c) xray-core's JSON handler ran and produced a
// structured error — without needing a real node or any network traffic.
// ---------------------------------------------------------------------------
using CGoInvokeFn = char *(*)(char *);
using CGoFreeXFn = void (*)(char *);

extern "C" napi_value M6CGoInvoke(napi_env env, napi_callback_info info)
{
    (void)info;
    OH_LOG_INFO(LOG_APP, "M6 stage=begin");

    std::string tried;
    void *handle = nullptr;

    tried += "[soname] ";
    handle = dlopen("libxray.so", RTLD_NOW);
    if (handle == nullptr) {
        const char *e1 = dlerror();
        tried += (e1 != nullptr ? e1 : "unknown");
        tried += " | ";

        std::string dir = OwnModuleDir();
        std::string full = dir.empty() ? std::string("libxray.so") : (dir + "libxray.so");
        tried += "[path:" + full + "] ";
        handle = dlopen(full.c_str(), RTLD_NOW);
        if (handle == nullptr) {
            const char *e2 = dlerror();
            tried += (e2 != nullptr ? e2 : "unknown");
        }
    }
    if (handle == nullptr) {
        OH_LOG_ERROR(LOG_APP, "M6 stage=dlopen FAILED %{public}s", tried.c_str());
        return MakeString(env, "M6 dlopen FAILED: " + tried);
    }
    OH_LOG_INFO(LOG_APP, "M6 stage=dlopen ok");

    auto invoke = reinterpret_cast<CGoInvokeFn>(dlsym(handle, "CGoInvoke"));
    if (invoke == nullptr) {
        const char *e = dlerror();
        OH_LOG_ERROR(LOG_APP, "M6 stage=dlsym CGoInvoke FAILED %{public}s", e != nullptr ? e : "unknown");
        dlclose(handle);
        return MakeString(env, std::string("M6 dlsym CGoInvoke FAILED: ") + (e != nullptr ? e : "unknown"));
    }
    auto freeFn = reinterpret_cast<CGoFreeXFn>(dlsym(handle, "CGoFree"));
    OH_LOG_INFO(LOG_APP, "M6 stage=dlsym ok CGoFree=%{public}s", freeFn != nullptr ? "found" : "MISSING");

    // Deliberately invalid method -> expect JSON with success=false.
    const std::string request =
        "{\"apiVersion\":1,\"method\":\"__p02_probe__\",\"payload\":{}}";

    auto t0 = std::chrono::steady_clock::now();
    OH_LOG_INFO(LOG_APP, "M6 stage=call begin");
    char *raw = invoke(const_cast<char *>(request.c_str()));
    auto t1 = std::chrono::steady_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    OH_LOG_INFO(LOG_APP, "M6 stage=call returned elapsed_ms=%{public}lld", static_cast<long long>(ms));

    if (raw == nullptr) {
        OH_LOG_ERROR(LOG_APP, "M6 stage=call returned NULL");
        dlclose(handle);
        return MakeString(env, "M6 CGoInvoke returned NULL");
    }

    std::string payload(raw);
    if (freeFn != nullptr) {
        freeFn(raw);
    }
    dlclose(handle);

    OH_LOG_INFO(LOG_APP, "M6 stage=done elapsed_ms=%{public}lld payload=%{public}s",
                static_cast<long long>(ms), payload.c_str());
    // Prefix the elapsed time so the ArkTS side can log it without native-log plumbing.
    return MakeString(env, "[elapsed_ms=" + std::to_string(static_cast<long long>(ms)) + "] " + payload);
}

// ---------------------------------------------------------------------------
// M7 / P-02 (final): call a REAL libXray method that forces xray-core to answer.
//
// "xrayVersion" returns xray.XrayVersion(); a non-error answer means xray-core was
// actually initialised inside this process (not just the JSON dispatcher reached).
// "getXrayState" additionally reports whether an instance is currently running.
// ---------------------------------------------------------------------------
extern "C" napi_value M7CGoVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    OH_LOG_INFO(LOG_APP, "M7 stage=begin");

    void *handle = dlopen("libxray.so", RTLD_NOW);
    if (handle == nullptr) {
        std::string dir = OwnModuleDir();
        std::string full = dir.empty() ? std::string("libxray.so") : (dir + "libxray.so");
        handle = dlopen(full.c_str(), RTLD_NOW);
    }
    if (handle == nullptr) {
        const char *e = dlerror();
        OH_LOG_ERROR(LOG_APP, "M7 stage=dlopen FAILED %{public}s", e != nullptr ? e : "unknown");
        return MakeString(env, std::string("M7 dlopen FAILED: ") + (e != nullptr ? e : "unknown"));
    }

    auto invoke = reinterpret_cast<CGoInvokeFn>(dlsym(handle, "CGoInvoke"));
    auto freeFn = reinterpret_cast<CGoFreeXFn>(dlsym(handle, "CGoFree"));
    if (invoke == nullptr) {
        const char *e = dlerror();
        dlclose(handle);
        return MakeString(env, std::string("M7 dlsym CGoInvoke FAILED: ") + (e != nullptr ? e : "unknown"));
    }

    const std::string reqVersion =
        "{\"apiVersion\":1,\"method\":\"xrayVersion\",\"payload\":{}}";
    const std::string reqState =
        "{\"apiVersion\":1,\"method\":\"getXrayState\",\"payload\":{}}";
    // A method that does real work (binds a socket to find a free port) — used to show
    // that the calls are not all trivially 0 ms and that xray-core code actually runs.
    const std::string reqPorts =
        "{\"apiVersion\":1,\"method\":\"getFreePorts\",\"payload\":{\"count\":1}}";

    auto call = [&](const std::string &req, long long *elapsedMs) -> std::string {
        auto t0 = std::chrono::steady_clock::now();
        char *raw = invoke(const_cast<char *>(req.c_str()));
        auto t1 = std::chrono::steady_clock::now();
        *elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
        if (raw == nullptr) {
            return std::string("<NULL>");
        }
        std::string out(raw);
        if (freeFn != nullptr) {
            freeFn(raw);
        }
        return out;
    };

    long long msVersion = -1;
    long long msState = -1;
    long long msPorts = -1;
    std::string versionResp = call(reqVersion, &msVersion);
    std::string stateResp = call(reqState, &msState);
    std::string portsResp = call(reqPorts, &msPorts);

    if (freeFn != nullptr) {
        dlclose(handle);
    } else {
        dlclose(handle);
    }

    std::string combined = "[version_ms=" + std::to_string(msVersion) +
                           "][state_ms=" + std::to_string(msState) +
                           "][ports_ms=" + std::to_string(msPorts) + "] " +
                           "version=" + versionResp + " state=" + stateResp +
                           " ports=" + portsResp;
    OH_LOG_INFO(LOG_APP, "M7 stage=done %{public}s", combined.c_str());
    return MakeString(env, combined);
}
