# 数据面：合并构建可行性验证

| 项目 | 内容 |
|---|---|
| 日期 | 2026-11-21 |
| 目的 | 验证「内核 + 转发层编进同一个 `.so`」这个前提是否成立 |
| 结论 | **成立**。arm64 产物 `libmerged.so` 构建成功，导出符号与 SONAME 均正确 |
| 未验证 | 该 `.so` 在真机上的加载与运行；转发功能本身未实现 |

## 1. 为什么要合并

架构约束：**一个进程只能加载一个 Go runtime**。内核（libXray）已经是 Go 共享库；
如果转发层另起一个 Go `.so`，两者会在同一进程里争用 runtime，行为不可预期。
因此数据面只能是「一个 `.so` 同时提供内核调用与转发启动」。

另一条相关约束：`tun fd` 只在 VPN 扩展进程内有效，主应用拿不到，
所以这个 `.so` 必须由**扩展进程**加载（而不是现在的首页进程）。

## 2. 验证过程

1. **纯 Go 交叉编译可行**：用 OHOS Go 工具链（`_toolchain/ohos-go-v1.26.5-beta1`），
   `GOOS=openharmony GOARCH=arm64 CGO_ENABLED=0 go build github.com/xjasonlyu/tun2socks/v2/engine`
   **通过**。标准 Go（bootstrap 那份）会直接报 `unsupported GOOS/GOARCH pair`，
   必须用 OHOS fork。
2. **合并 c-shared 构建可行**：模块 `_toolchain/merged` 同时 import libXray 与
   tun2socks engine，用 `-buildmode=c-shared` 构建：
   ```
   BUILD OK  72,423,280 bytes  soname=libmerged.so
   exports : Invoke, FreeString, StartTun2Socks
   ```
   导出恰好 3 个符号（version-script 生效），SONAME 正确（否则 DT_NEEDED 会写入
   构建期绝对路径，应用启动即失败）。

## 3. 体积影响（实测文件大小）

| 产物 | 大小 |
|---|---|
| `libxray.so`（未 strip） | 65.9 MB |
| `libmerged.so`（未 strip） | 69.1 MB |
| 增量 | **约 3.2 MB** |

比预期小得多：gvisor 的门槛没有想象中大，Xray 自身占绝大部分。
真机交付包仍按「stripped + compressNativeLibs」估算，此处不作结论。

## 4. 还差什么（按依赖顺序）

1. **设备加载验证**：合并 `.so` 能否在 OHOS 进程里被 dlopen、`Invoke` 是否照常工作。
   现状：只验证了"能构建"，没有验证"能运行"。
2. **`isSocketFD` 判定（已按源码核对，结论与设计文档不同）**：

   设计文档记的是「该检查失败会 `log.Fatal` 直接杀进程，必须打 Fstat 补丁」。
   对照当前使用的 gvisor 版本 `v0.0.0-20260701204157` 源码，这条**不成立**：

   ```go
   // pkg/tcpip/link/fdbased/endpoint.go:450
   func isSocketFD(fd int) (bool, error) {
       var stat unix.Stat_t
       if err := unix.Fstat(fd, &stat); err != nil {
           return false, fmt.Errorf("unix.Fstat(%v,...) failed: %v", fd, err)
       }
       return (stat.Mode & unix.S_IFSOCK) == unix.S_IFSOCK, nil
   }
   ```

   - 它是**普通返回值**，不是 `log.Fatal`；调用点 `endpoint.go:305` 也只是把错误返回给上层；
   - 对 tun fd 而言 `S_IFSOCK` 不成立 → 返回 `isSocket=false`，正是设备层期望的路径。

   所以**本版本不需要 Fstat 补丁**。设计文档那条结论应视为「针对旧版本参考实现」，
   待真机验证后再决定是否需要对文档做 superseded 标记。

   仍需真机确认的只有一件事：`unix.Fstat` / `unix.SetNonblock` 在 OHOS 上是否正常返回。

3. **转发实现**：`StartTun2Socks` 目前显式返回「未实现」，不伪装成功。要接线：
   tun fd → tun2socks 设备层 → loopback SOCKS（地址与口令来自运行期）。
4. **SOCKS UDP**：入站已改为 `udp:true`（配置层已验证内核接受），但 UDP ASSOCIATE
   的实际转发仍需在数据面接好后验证。
5. **扩展进程加载**：`.so` 要在 VPN 扩展进程加载，主应用的 `KernelService` 那套
   需要相应下移或做进程间协作，这是架构改动而不是小修改。

## 5. 复现

```
powershell -ExecutionPolicy Bypass -File .\toolchain\build-merged.ps1 -Arch arm64
```

产物在 `_toolchain/merged/build-arm64/libmerged.so`（**不入库**，与既有的
`libxray.so` 一致：二进制不入库，脚本可复现）。
