export const hello: () => string;
export const prebuiltAdd: (a: number, b: number) => number;
// M5: dlopen the Go c-shared library at runtime and call CGoPing().
// soPath: absolute path of the extracted libcgoping.so (optional; falls back to SONAME search).
export const m5CGoPing: (soPath?: string) => string;
// M6 / P-02: dlopen libxray.so and call CGoInvoke with a deliberately invalid method.
export const m6CGoInvoke: () => string;
// M7 / P-02: call real libXray methods (xrayVersion / getXrayState).
export const m7CGoVersion: () => string;
// M8: generic bridge — invoke(method, payloadJson) => response JSON
export const m8Invoke: (method: string, payloadJson: string) => string;
// M9: SOCKS inbound + freedom outbound probe (forwarding path evidence)
export const m9ProxyProbe: () => string;
// geo: set the asset directory for geoip.dat / geosite.dat.
// Must be called BEFORE m8Invoke('runXrayFromJson', ...), otherwise
// `geosite:cn` / `geoip:cn` rules fail to resolve.
export const setAssetPath: (dir: string) => string;
// M10: TCP connect + HTTP GET from inside the app process (E15 step 1 reachability).
// Returns "[tcp=OK][connect_ms=..][http_ms=..][status=..][body=..]" or "[tcp=FAIL]...".
// Rationale: the emulator shell has no curl/wget/nc, and an ICMP reply proves
// nothing about whether a TCP port accepts a connection.
export const m10HostProbe: (host: string, port: number, path: string) => string;
// M11: SOCKS5 (username/password) -> HTTP GET through the kernel's inbound.
// socksPort/user/pass come from SocksGuard; the request exits via the node outbound.
export const m11SocksProbe: (socksPort: number, user: string, pass: string,
  targetHost: string, targetPort: number, path: string) => string;
