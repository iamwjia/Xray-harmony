/* M3 用的预编译库源码（手写 C，不是 Go）。
 * 目的：证明「预编译 .so + IMPORTED 链接 + dlopen 路径」在目标 ABI 上成立。
 * 构建方式见 doc/poc/PC6-skeleton-build-log.md（NDK clang，交叉编译到 arm64-v8a）。
 */
int prebuilt_add(int a, int b)
{
    return a + b;
}
