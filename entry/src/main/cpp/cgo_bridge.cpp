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

// --- POSIX sockets for the M9 proxy probe (native avoids ArkTS async-socket plumbing) ---
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <cstring>
#include <cstdlib>

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

// ---------------------------------------------------------------------------
// M8 / P-01 prerequisite: generic CGoInvoke bridge (method + payload from ArkTS).
//
// ArkTS passes the libXray method name and a payload JSON string, so the app can
// drive runXrayFromJson / stopXray / getXrayState without recompiling native code.
// Returns the raw JSON response (and never throws into ArkTS on business errors).
// ---------------------------------------------------------------------------
namespace {

std::string GetStringArg(napi_env env, napi_value v)
{
    std::string out;
    napi_valuetype t = napi_undefined;
    napi_typeof(env, v, &t);
    if (t != napi_string) {
        return out;
    }
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    if (len == 0) {
        return out;
    }
    out.resize(len + 1);
    napi_get_value_string_utf8(env, v, &out[0], len + 1, &len);
    out.resize(len);
    return out;
}

} // namespace

extern "C" napi_value M8Invoke(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    const std::string method = (argc >= 1) ? GetStringArg(env, argv[0]) : std::string();
    const std::string payloadJson = (argc >= 2) ? GetStringArg(env, argv[1]) : std::string("{}");
    if (method.empty()) {
        return MakeString(env, "{\"success\":false,\"data\":null,\"error\":\"method required\"}");
    }

    void *handle = dlopen("libxray.so", RTLD_NOW);
    if (handle == nullptr) {
        std::string dir = OwnModuleDir();
        std::string full = dir.empty() ? std::string("libxray.so") : (dir + "libxray.so");
        handle = dlopen(full.c_str(), RTLD_NOW);
    }
    if (handle == nullptr) {
        const char *e = dlerror();
        return MakeString(env, std::string("{\"success\":false,\"data\":null,\"error\":\"dlopen: ") +
                                   (e != nullptr ? e : "unknown") + "\"}");
    }

    auto invoke = reinterpret_cast<CGoInvokeFn>(dlsym(handle, "CGoInvoke"));
    auto freeFn = reinterpret_cast<CGoFreeXFn>(dlsym(handle, "CGoFree"));
    if (invoke == nullptr) {
        const char *e = dlerror();
        dlclose(handle);
        return MakeString(env, std::string("{\"success\":false,\"data\":null,\"error\":\"dlsym: ") +
                                   (e != nullptr ? e : "unknown") + "\"}");
    }

    const std::string request =
        "{\"apiVersion\":1,\"method\":\"" + method + "\",\"payload\":" + payloadJson + "}";
    OH_LOG_INFO(LOG_APP, "M8 invoke method=%{public}s request_bytes=%{public}d",
                method.c_str(), static_cast<int>(request.size()));

    auto t0 = std::chrono::steady_clock::now();
    char *raw = invoke(const_cast<char *>(request.c_str()));
    auto t1 = std::chrono::steady_clock::now();
    long long ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();

    std::string out = (raw == nullptr) ? std::string("{\"success\":false,\"data\":null,\"error\":\"NULL\"}")
                                       : std::string(raw);
    if (raw != nullptr && freeFn != nullptr) {
        freeFn(raw);
    }
    dlclose(handle);

    OH_LOG_INFO(LOG_APP, "M8 done method=%{public}s elapsed_ms=%{public}lld bytes=%{public}d",
                method.c_str(), static_cast<long long>(ms), static_cast<int>(out.size()));
    return MakeString(env, "[ms=" + std::to_string(ms) + "] " + out);
}

// ---------------------------------------------------------------------------
// Asset path for geoip/geosite.
//
// xray-core resolves `geosite:cn` / `geoip:cn` by READing files from the directory
// named by the `xray.location.asset` environment variable. ArkTS has no setenv, so
// this hook is the only way to point the kernel at the extracted geo files.
//
// MUST be called before runXrayFromJson: the routing rules are parsed when the
// instance is created, and a missing asset directory at that moment is a hard
// config error, not a lazy lookup.
// ---------------------------------------------------------------------------
extern "C" napi_value SetAssetPath(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    const std::string dir = (argc >= 1) ? GetStringArg(env, argv[0]) : std::string();
    if (dir.empty()) {
        return MakeString(env, "rejected: empty path");
    }
    // xray-core reads the lower-case dotted name; XRAY_LOCATION_ASSET is the
    // documented CLI convention. Set both so neither path silently misses.
    setenv("xray.location.asset", dir.c_str(), 1);
    setenv("XRAY_LOCATION_ASSET", dir.c_str(), 1);
    OH_LOG_INFO(LOG_APP, "asset path set len=%{public}d", static_cast<int>(dir.size()));
    return MakeString(env, "ok");
}

// ---------------------------------------------------------------------------
// M9 / P-01 prerequisite: prove the kernel forwards traffic over a real socket.
//
// Two layers are kept strictly separate (do NOT merge them in reports):
//   (a) forwarding path  : SOCKS inbound -> Xray -> freedom outbound -> internet
//   (b) node egress      : only true when the exit IP differs from the direct IP.
// With a `freedom` outbound (a) holds but (b) does not — exit IP == direct IP.
// Swapping `freedom` for a real node outbound is the only change needed later.
// ---------------------------------------------------------------------------
namespace {

int ConnectTcp(const std::string &host, int port, int timeoutSec)
{
    struct addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *res = nullptr;
    if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &res) != 0 || res == nullptr) {
        return -1;
    }
    int fd = -1;
    for (auto *p = res; p != nullptr; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd < 0) {
            continue;
        }
        struct timeval tv{};
        tv.tv_sec = timeoutSec;
        tv.tv_usec = 0;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        if (connect(fd, p->ai_addr, p->ai_addrlen) == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    return fd;
}

bool SendAll(int fd, const void *buf, size_t len)
{
    const char *p = static_cast<const char *>(buf);
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, p + sent, len - sent, 0);
        if (n <= 0) {
            return false;
        }
        sent += static_cast<size_t>(n);
    }
    return true;
}

std::string RecvAll(int fd)
{
    std::string out;
    char buf[2048];
    for (;;) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) {
            break;
        }
        out.append(buf, static_cast<size_t>(n));
        if (out.size() > 64 * 1024) {
            break;
        }
    }
    return out;
}

// Returns the full HTTP response (status line + headers + body).
std::string HttpGet(int fd, const std::string &host, const std::string &path)
{
    std::string req = "GET " + path + " HTTP/1.1\r\nHost: " + host +
                      "\r\nUser-Agent: xray-harmony-poc\r\nConnection: close\r\n\r\n";
    if (!SendAll(fd, req.data(), req.size())) {
        return std::string();
    }
    return RecvAll(fd);
}

// First line of the response, e.g. "HTTP/1.1 200 OK" (empty if malformed).
std::string RespStatusLine(const std::string &resp)
{
    size_t e = resp.find("\r\n");
    return (e == std::string::npos) ? std::string() : resp.substr(0, e);
}

// Body of the response (everything after the first blank line).
std::string RespBody(const std::string &resp)
{
    size_t pos = resp.find("\r\n\r\n");
    return (pos == std::string::npos) ? std::string() : resp.substr(pos + 4);
}

// SOCKS5 (no auth) CONNECT by domain, then HTTP GET through it.
std::string HttpGetViaSocks(const std::string &socksHost, int socksPort,
                            const std::string &host, int port, const std::string &path,
                            std::string *err)
{
    int fd = ConnectTcp(socksHost, socksPort, 3);
    if (fd < 0) {
        *err = "socks connect failed";
        return std::string();
    }
    const unsigned char hello[3] = {0x05, 0x01, 0x00};
    if (!SendAll(fd, hello, sizeof(hello))) {
        *err = "socks hello send failed";
        close(fd);
        return std::string();
    }
    unsigned char sel[2] = {0};
    if (recv(fd, sel, 2, 0) != 2 || sel[0] != 0x05) {
        *err = "socks hello reply invalid";
        close(fd);
        return std::string();
    }
    if (sel[1] != 0x00) {
        *err = "socks auth method rejected";
        close(fd);
        return std::string();
    }

    std::string req;
    req.push_back(0x05);
    req.push_back(0x01); // CONNECT
    req.push_back(0x00); // reserved
    req.push_back(0x03); // domain
    req.push_back(static_cast<char>(host.size()));
    req += host;
    req.push_back(static_cast<char>((port >> 8) & 0xFF));
    req.push_back(static_cast<char>(port & 0xFF));
    if (!SendAll(fd, req.data(), req.size())) {
        *err = "socks connect send failed";
        close(fd);
        return std::string();
    }

    unsigned char rep[4] = {0};
    if (recv(fd, rep, 4, 0) != 4 || rep[1] != 0x00) {
        *err = "socks connect rejected (rep=" + std::to_string(static_cast<int>(rep[1])) + ")";
        close(fd);
        return std::string();
    }
    int addrLen = 0;
    if (rep[3] == 0x01) {
        addrLen = 4;
    } else if (rep[3] == 0x03) {
        unsigned char l = 0;
        if (recv(fd, &l, 1, 0) != 1) {
            *err = "socks addr len read failed";
            close(fd);
            return std::string();
        }
        addrLen = l;
    } else if (rep[3] == 0x04) {
        addrLen = 16;
    } else {
        *err = "socks unknown atyp";
        close(fd);
        return std::string();
    }
    char drain[32] = {0};
    if (recv(fd, drain, addrLen + 2, 0) <= 0) {
        *err = "socks addr drain failed";
        close(fd);
        return std::string();
    }

    std::string resp = HttpGet(fd, host, path);
    close(fd);
    if (resp.empty()) {
        *err = "no HTTP response through SOCKS (handshake+CONNECT ok)";
    }
    return resp;
}

std::string JsonEscape(const std::string &s)
{
    std::string out;
    out.reserve(s.size() + 16);
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out.push_back(c);
        }
    }
    return out;
}

// Trim whitespace/newlines from a plain-text IP response.
std::string TrimText(const std::string &s)
{
    size_t b = s.find_first_not_of(" \t\r\n");
    size_t e = s.find_last_not_of(" \t\r\n");
    if (b == std::string::npos) {
        return std::string();
    }
    return s.substr(b, e - b + 1);
}

} // namespace

extern "C" napi_value M9ProxyProbe(napi_env env, napi_callback_info info)
{
    (void)info;
    OH_LOG_INFO(LOG_APP, "M9 stage=begin");

    void *handle = dlopen("libxray.so", RTLD_NOW);
    if (handle == nullptr) {
        std::string dir = OwnModuleDir();
        std::string full = dir.empty() ? std::string("libxray.so") : (dir + "libxray.so");
        handle = dlopen(full.c_str(), RTLD_NOW);
    }
    if (handle == nullptr) {
        const char *e = dlerror();
        return MakeString(env, std::string("M9 dlopen FAILED: ") + (e != nullptr ? e : "unknown"));
    }
    auto invoke = reinterpret_cast<CGoInvokeFn>(dlsym(handle, "CGoInvoke"));
    auto freeFn = reinterpret_cast<CGoFreeXFn>(dlsym(handle, "CGoFree"));
    if (invoke == nullptr) {
        dlclose(handle);
        return MakeString(env, "M9 dlsym CGoInvoke FAILED");
    }

    auto callMethod = [&](const std::string &method, const std::string &payloadJson) -> std::string {
        std::string req = "{\"apiVersion\":1,\"method\":\"" + method + "\",\"payload\":" + payloadJson + "}";
        char *raw = invoke(const_cast<char *>(req.c_str()));
        std::string out = (raw == nullptr) ? std::string("<NULL>") : std::string(raw);
        if (raw != nullptr && freeFn != nullptr) {
            freeFn(raw);
        }
        return out;
    };

    // SOCKS inbound on loopback + freedom outbound (no node: proves forwarding path only).
    const std::string cfg =
        "{\"log\":{\"loglevel\":\"warning\"},"
        "\"inbounds\":[{\"tag\":\"socks-in\",\"listen\":\"127.0.0.1\",\"port\":18080,"
        "\"protocol\":\"socks\",\"settings\":{\"auth\":\"noauth\",\"udp\":false}}],"
        "\"outbounds\":[{\"tag\":\"direct\",\"protocol\":\"freedom\"}]}";
    const std::string runPayload = "{\"configJSON\":\"" + JsonEscape(cfg) + "\"}";

    std::string runResp = callMethod("runXrayFromJson", runPayload);
    OH_LOG_INFO(LOG_APP, "M9 run=%{public}s", runResp.c_str());
    usleep(700 * 1000);

    std::string stateResp = callMethod("getXrayState", "{}");
    OH_LOG_INFO(LOG_APP, "M9 state=%{public}s", stateResp.c_str());

    // (1) through the kernel
    std::string socksErr;
    std::string proxyResp = HttpGetViaSocks("127.0.0.1", 18080, "checkip.amazonaws.com", 80, "/", &socksErr);
    std::string proxyStatus = RespStatusLine(proxyResp);
    std::string viaProxy = TrimText(RespBody(proxyResp));
    OH_LOG_INFO(LOG_APP, "M9 via-proxy status=%{public}s ip=%{public}s err=%{public}s",
                proxyStatus.c_str(), viaProxy.c_str(), socksErr.c_str());

    // (2) direct, for comparison
    std::string directIp;
    std::string directStatus;
    int fd = ConnectTcp("checkip.amazonaws.com", 80, 3);
    if (fd >= 0) {
        std::string directResp = HttpGet(fd, "checkip.amazonaws.com", "/");
        close(fd);
        directStatus = RespStatusLine(directResp);
        directIp = TrimText(RespBody(directResp));
    }
    OH_LOG_INFO(LOG_APP, "M9 direct status=%{public}s ip=%{public}s", directStatus.c_str(), directIp.c_str());

    std::string stopResp = callMethod("stopXray", "{}");
    dlclose(handle);

    std::string verdict;
    if (!viaProxy.empty() && !directIp.empty()) {
        verdict = (viaProxy == directIp) ? "SAME_IP(forwarding-only)" : "DIFF_IP(egress-changed)";
    } else {
        verdict = "INCONCLUSIVE";
    }

    std::string combined =
        "[verdict=" + verdict + "] run=" + runResp + " state=" + stateResp +
        " via_proxy_status=" + (proxyStatus.empty() ? std::string("<none>") : proxyStatus) +
        " via_proxy_ip=" + (viaProxy.empty() ? std::string("<none>") : viaProxy) +
        " socks_err=" + (socksErr.empty() ? std::string("-") : socksErr) +
        " direct_status=" + (directStatus.empty() ? std::string("<none>") : directStatus) +
        " direct_ip=" + (directIp.empty() ? std::string("<none>") : directIp) +
        " stop=" + stopResp;
    OH_LOG_INFO(LOG_APP, "M9 stage=done %{public}s", combined.c_str());
    return MakeString(env, combined);
}
