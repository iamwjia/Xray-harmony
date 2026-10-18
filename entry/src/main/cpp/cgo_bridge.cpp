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
