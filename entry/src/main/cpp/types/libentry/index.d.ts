export const hello: () => string;
export const prebuiltAdd: (a: number, b: number) => number;
// M5: dlopen the Go c-shared library at runtime and call CGoPing().
// soPath: absolute path of the extracted libcgoping.so (optional; falls back to SONAME search).
export const m5CGoPing: (soPath?: string) => string;
