#include <string>
#include <cstdint>

#include "napi/native_api.h"

// Declared in the prebuilt shared library (libprebuilt.so, source: cpp/prebuilt/prebuilt.c)
extern "C" int prebuilt_add(int a, int b);

// M5: implemented in cgo_bridge.cpp (dlopen libcgoping.so + dlsym CGoPing).
extern "C" napi_value M5CGoPing(napi_env env, napi_callback_info info);

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
