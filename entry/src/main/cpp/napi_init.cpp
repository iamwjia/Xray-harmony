#include <string>
#include <cstdint>

#include "napi/native_api.h"

// Declared in the prebuilt shared library (libprebuilt.so, source: cpp/prebuilt/prebuilt.c)
extern "C" int prebuilt_add(int a, int b);

// M5: implemented in cgo_bridge.cpp (dlopen libcgoping.so + dlsym CGoPing).
extern "C" napi_value M5CGoPing(napi_env env, napi_callback_info info);
// M6: implemented in cgo_bridge.cpp (dlopen libxray.so + dlsym CGoInvoke).
extern "C" napi_value M6CGoInvoke(napi_env env, napi_callback_info info);
// M7: real libXray methods (xrayVersion / getXrayState) — proves xray-core is initialised.
extern "C" napi_value M7CGoVersion(napi_env env, napi_callback_info info);
// M8: generic CGoInvoke bridge (method + payload JSON from ArkTS).
extern "C" napi_value M8Invoke(napi_env env, napi_callback_info info);
// M9: start SOCKS inbound + freedom outbound, request through it, compare exit IP.
extern "C" napi_value M9ProxyProbe(napi_env env, napi_callback_info info);
// geo: point xray-core at the directory holding geoip.dat / geosite.dat.
// Must be called before runXrayFromJson (rules are parsed at instance creation).
extern "C" napi_value SetAssetPath(napi_env env, napi_callback_info info);

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
        {"m5CGoPing", nullptr, M5CGoPing, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"m6CGoInvoke", nullptr, M6CGoInvoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"m7CGoVersion", nullptr, M7CGoVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"m8Invoke", nullptr, M8Invoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"m9ProxyProbe", nullptr, M9ProxyProbe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAssetPath", nullptr, SetAssetPath, nullptr, nullptr, nullptr, napi_default, nullptr},
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
