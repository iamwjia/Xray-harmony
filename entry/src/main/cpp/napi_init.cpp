#include <string>
#include <cstdint>

#include "napi/native_api.h"

// Declared in the prebuilt shared library (libprebuilt.so, source: cpp/prebuilt/prebuilt.c)
extern "C" int prebuilt_add(int a, int b);

// implemented in cgo_bridge.cpp (dlopen libcgoping.so + dlsym CGoPing).
extern "C" napi_value ProbeGoPing(napi_env env, napi_callback_info info);
// implemented in cgo_bridge.cpp (dlopen libxray.so + dlsym CGoInvoke).
extern "C" napi_value ProbeGoInvoke(napi_env env, napi_callback_info info);
// M7: real libXray methods (xrayVersion / getXrayState) — proves xray-core is initialised.
extern "C" napi_value ProbeKernelVersion(napi_env env, napi_callback_info info);
// Generic CGoInvoke bridge (method + payload JSON from ArkTS).
extern "C" napi_value InvokeKernel(napi_env env, napi_callback_info info);
// Start SOCKS inbound + freedom outbound, request through it, compare exit IP.
extern "C" napi_value ProbeSocksForward(napi_env env, napi_callback_info info);
// geo: point xray-core at the directory holding geoip.dat / geosite.dat.
// Must be called before runXrayFromJson (rules are parsed at instance creation).
extern "C" napi_value SetAssetPath(napi_env env, napi_callback_info info);
// TCP connect + HTTP GET from inside the app process (host reachability).
extern "C" napi_value ProbeHostHttp(napi_env env, napi_callback_info info);
// SOCKS5 with username/password -> HTTP GET (end-to-end probe).
extern "C" napi_value ProbeSocksThroughKernel(napi_env env, napi_callback_info info);

namespace {

napi_value Hello(napi_env env, napi_callback_info info)
{
    (void)info;
    std::string msg = "hello from native";
    napi_value result = nullptr;
    napi_create_string_utf8(env, msg.c_str(), msg.size(), &result);
    return result;
}

napi_value PrebuiltAdd(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t a = 0;
    int32_t b = 0;
    napi_get_value_int32(env, argv[0], &a);
    napi_get_value_int32(env, argv[1], &b);

    napi_value result = nullptr;
    napi_create_int32(env, prebuilt_add(a, b), &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"hello", nullptr, Hello, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"prebuiltAdd", nullptr, PrebuiltAdd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeGoPing", nullptr, ProbeGoPing, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeGoInvoke", nullptr, ProbeGoInvoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeKernelVersion", nullptr, ProbeKernelVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"invokeKernel", nullptr, InvokeKernel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeSocksForward", nullptr, ProbeSocksForward, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAssetPath", nullptr, SetAssetPath, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeHostHttp", nullptr, ProbeHostHttp, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeSocksThroughKernel", nullptr, ProbeSocksThroughKernel, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

napi_module g_entryModule = {
    1,               // nm_version
    0,               // nm_flags
    nullptr,         // nm_filename
    Init,            // nm_register_func
    "entry",         // nm_modname (keep in sync with the .so name)
    nullptr,         // nm_priv
    {0},             // reserved
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&g_entryModule);
}
