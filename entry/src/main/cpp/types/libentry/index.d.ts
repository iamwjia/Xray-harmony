export const hello: () => string;
export const prebuiltAdd: (a: number, b: number) => number;
// dlopen the Go c-shared library at runtime and call CGoPing().
// soPath: absolute path of the extracted libcgoping.so (optional; falls back to SONAME search).
export const probeGoPing: (soPath?: string) => string;
// M6 / P-02: dlopen libxray.so and call CGoInvoke with a deliberately invalid method.
export const probeGoInvoke: () => string;
// M7 / P-02: call real libXray methods (xrayVersion / getXrayState).
export const probeKernelVersion: () => string;
// M8: generic bridge — invoke(method, payloadJson) => response JSON
export const invokeKernel: (method: string, payloadJson: string) => string;
// SOCKS inbound + freedom outbound probe (forwarding path evidence)
export const probeSocksForward: () => string;
// geo: set the asset directory for geoip.dat / geosite.dat.
// Must be called BEFORE invokeKernel('runXrayFromJson', ...), otherwise
// `geosite:cn` / `geoip:cn` rules fail to resolve.
export const setAssetPath: (dir: string) => string;
// TCP connect + HTTP GET from inside the app process (host reachability).
// Returns "[tcp=OK][connect_ms=..][http_ms=..][status=..][body=..]" or "[tcp=FAIL]...".
// Rationale: the emulator shell has no curl/wget/nc, and an ICMP reply proves
// nothing about whether a TCP port accepts a connection.
export const probeHostHttp: (host: string, port: number, path: string) => string;
// SOCKS5 (username/password) -> HTTP GET through the kernel's inbound.
// socksPort/user/pass come from SocksGuard; the request exits via the node outbound.
export const probeSocksThroughKernel: (socksPort: number, user: string, pass: string,
  targetHost: string, targetPort: number, path: string) => string;
