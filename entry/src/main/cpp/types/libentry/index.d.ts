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
