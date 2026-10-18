# HarmonyOS NEXT 平台能力与硬约束调研

> 任务：R2 · 作者：harmony-platform-analyst（HarmonyOS 平台能力与系统约束专家）
> 版本：v1.1（2026-10-17）· 服务对象：需求文档（Q1）、设计方案（D1）、风险与计划（Z1）
> 变更：v1.1 增补 §3.1.0（API Level 下限）、§3.1.1（系统 vs 应用的工作量分界）、§3.4（形态 B 成立性）、§3.5（2203002 归因性）、§3.6（分应用代理）、§8（三个高频问题直答）、E8~E13；并按 leader 要求对"无审批/2203002/注册资本/60 日/100 台"逐条加注证据强度。
> 路径说明：项目根目录已迁移至 `D:\projects\xray-harmony`，本文件为正本；团队共享目录下的 `artifacts/` 为副本。
> 结论口径：本文所有能力判定落到 **API 名称 / 权限名称 / 文档依据**，并按四态标注：
> `① 可用（三方应用，无审批）` `② 需权限（normal/系统权限但可自助获得）` `③ 需资质/审批（ACL 白名单、企业资质、行政许可证）` `④ 不可用（三方应用）`
> 文档未覆盖或存在版本/机型差异的，标 **【待真机验证】** 并给出验证方法。

---

## 0. TL;DR（给需求与架构的 8 条硬结论）

| # | 结论 | 影响 |
|---|---|---|
| 1 | **tun 级全局代理三方可用**：`VpnExtensionAbility`（`module.json5` 中 `extensionAbilities.type = "vpn"`）自 **API 11** 起对三方开放，只依赖 `ohos.permission.INTERNET`（normal / system_grant），首次启动由**系统弹窗**让用户授权 → **官方文档未设任何申请/审批环节**【此为推论：文档无审批描述 + 依赖权限为 normal 级；非官方否定性声明】 | 产品可行性成立；"VPN 资质"不是开发前置条件 |
| 2 | **默认形态是"单一 VPN 连接"**：已激活时再启动会被拒绝（`2203002 VPN exist already`）；**API 20+ 另提供"系统多 VPN 能力"**——须先 `generateVpnId()` 生成 vpnId 并写入 `VpnConfig.vpnId` 才能共存，且"当前系统多VPN能力**仅支持 IPv4**"。**澄清**：低版本（<API 20）一律按单 VPN 处理；API 20+ 是"可指定 vpnId 共存"而非自动共存，**文档未说明该能力是否有额外准入限制（是否仅限特定场景/企业）→【待验证】（§7 E6 判别法：两个三方 VPN 同时激活，看是否都成功且路由/图标并存）** | 交互措辞默认"必须先断开其他 VPN"；API 20+ 机型可选"并存模式"，但不得作为需求承诺 |
| 3 | **开机自启三方不可用**：`StaticSubscriberExtensionAbility`（`type:"staticSubscriber"`）官方标注**仅对系统应用开放**，且需设备预置 `install_list_capability.json` 授权 `allowCommonEvent` | 需求中"开机自动连接"必须降级为手动启动 / 桌面卡片 / 通知快捷入口 |
| 4 | **无 VPN 专用长时任务类型**：长时任务类型表（`dataTransfer`/`audioPlayback`/`location`/`taskKeeping` 等）**不含 vpn**；且文档明确"调用 `startVpnExtensionAbility` 的应用进程退出时系统会主动停止 VPN" | 必须让宿主进程常驻；`taskKeeping` 需 restricted 权限（见 §4） |
| 5 | **Native 子进程在手机不可用**：`childProcessManager.startChildProcess` / `OH_Ability_CreateNativeChildProcess` / `OH_Ability_StartNativeChildProcess` 的设备行为差异为 **仅 PC/2in1、Tablet**，手机返回 `16000061`/`NCP_ERR_NOT_SUPPORTED` | 核心引擎只能**同进程 .so（NAPI 加载）**，不能"独立进程跑一个可执行文件" |
| 6 | **预构建 .so 有硬性工具链约束**：必须由 **OpenHarmony NDK 工具链**（clang + `--target={arch}-linux-ohos` + musl sysroot）编译，且其依赖库同样要求；ABI 为 `armeabi-v7a / arm64-v8a / x86_64` | Go 产物必须走"cgo + ohos clang 链接"或自建 port，属最高技术风险项（§2.4） |
| 7 | **安全存储能力完整**：凭据用 `@ohos.security.asset`（ASSET，≤1KB，AES256-GCM + TEE），密钥用 `@ohos.security.huks`，批量节点数据用 `relationalStore` 的 `StoreConfig.encrypt` | 安全需求无需降级，可直接写进验收标准 |
| 8 | **分发三档**：调试安装（UDID ≤100 台）→ 企业内部应用分发（组织内部发布证书，需独立未实名账号 + 企业实名）→ 应用市场（企业主体 + IP-VPN 类增值电信许可证，月级） | 商业化路径必须先做策略决策（详见 `harmony-permission-checklist.md`） |

---

## 1. 开发基线（Stage 模型 / ArkTS / ArkUI / 版本）

### 1.1 版本与工具链现状（截至 2026-10）

| 项 | 值 | 依据 |
|---|---|---|
| HarmonyOS 商用 Release 主线 | 5.0.0(API 12) → 6.0.0(API 20，2025-09-25) → 6.1.0(API 23，2026-04-20) → **6.1.1(API 24，API Release)**；Beta 线已到 API 26（`26.0.0 Beta1`） | 华为开发者版本说明（各 Release 公告）；OpenHarmony master 文档中新增接口标注"起始版本 26.0.0"可交叉印证 |
| DevEco Studio | 与 Release 同步：**6.1.x Release**（对应 API 23/24）；另有面向 `API 26.0.0 Beta1` 的 Beta 工具链 | 华为开发者联盟下载中心 |
| SDK 版本三元组 | `build-profile.json5` 中 `compileSdkVersion` / `compatibleSdkVersion`（= minSdkVersion）/ `targetSdkVersion` | 工程配置文档 |
| 应用模型 | **仅 Stage 模型**（`UIAbility` + `ExtensionAbility`，`module.json5` 声明式配置）。VPN 相关接口文档明确"仅可在 Stage 模型下使用" | `@ohos.net.vpnExtension` / `VpnExtensionAbility` 文档"模型约束" |
| 语言/UI | ArkTS（静态类型、类 TS 子集，**禁 `eval`/动态属性访问受限**）+ ArkUI 声明式 UI（`@Component`/`@Entry`/状态装饰器） | ArkTS 语言规范 |
| 并发 | `TaskPool`（受控线程池，推荐）/ `Worker`（独立线程，可加载 native）/ `@ohos.taskpool` + `Sendable` 跨线程对象 | ArkTS 并发文档 |

**建议的最低兼容版本**：

| 方案 | `compatibleSdkVersion` | 理由 | 代价 |
|---|---|---|---|
| **推荐** | **12（HarmonyOS NEXT 5.0.0）** | NEXT 首个商用 Release；`VpnExtensionAbility`(API 11) 早已可用；覆盖首批 NEXT 机型 | 放弃 4.x 及更早设备（那些设备无此 API，且非 NEXT 内核路线） |
| 进取 | 20（6.0.0） | 多 VPN（`generateVpnId`，API 20）、`protectProcessNet`（API 22）等新能力可用 | 丢掉 5.x 存量设备 |
| 保守 | 14~18 | 折中：既有较新 API，又覆盖 5.0.x/5.1.x | 需逐 API 校验起始版本 |

> 决策建议：`compatibleSdkVersion = 12`、`targetSdkVersion` 跟随最新 Release（24），并对 API 20+/22+ 的能力做**运行时版本判断**（`canIUse('SystemCapability.Communication.NetManager.Vpn')` + `deviceInfo.sdkApiVersion`）后降级。

### 1.2 工程形态

- 模块类型：`HAP`（入口/feature）、`HAR`（静态共享包）、`HSP`（动态共享包）。**Native so 可随 HAP 或 HAR 分发**；HAR 中的预构建库会随 HAR 打包到 `libs/` 目录。
- 应用沙箱：应用私有目录 `/data/storage/el2/base/...`；网络、文件、通知均按权限管控。
- 日志：`@ohos.hilog`（`hilog.info(domain, tag, fmt, args)`），Native 侧 `<hilog/log.h>`；调试用 `hdc shell hilog`。

---

## 2. Native 集成（NAPI / so 打包 / ABI / Go 产物）

### 2.1 完整链路（结论：**可用**，①）

```
ArkTS 侧  import xxx from 'libxxx.so'
   │  (import 触发 ModuleManager 加载 so)
   ▼
Native so  napi_module_register(&nm)  →  exports 上挂方法
   │  首次加载时执行模块注册；之后每次 import 复用同一实例
   ▼
C/C++ 实现（CMake 工程，链 libace_napi.z.so）
   │
   ▼
OpenHarmony NDK 工具链  clang --target=aarch64-linux-ohos --sysroot=<ndk>/sysroot
```

- 机制：OpenHarmony Node-API 基于 **Node.js 18.x LTS** 的 Node-API 规范扩展。
- 关键点：`napi_module_register` 注册模块；`napi_create_function` 导出方法；`napi_get_cb_info` 取参；`napi_create_reference` 管理长生命周期对象；跨线程回调需 `napi_threadsafe_function`。
- **性能注意**：NAPI 调用有跨语言开销，且 ArkTS 主线程被阻塞会掉帧 → 大流量数据面（tun fd 读写、加解密）应放独立 `Worker`/native 线程，UI 线程只做控制面。

### 2.2 so 打包与 ABI 要求（结论：**可用**，①；有硬约束）

| 约束 | 内容 | 依据 |
|---|---|---|
| 工具链 | 必须用 **OpenHarmony NDK**（`ohos.toolchain.cmake`）；编译参数 `--target={arch}-linux-ohos`、`--sysroot={ndk}/sysroot`；C++ 运行时 `OHOS_STL = c++_shared`（默认）或 `c++_static`，**同一应用内全部 native 库必须一致** | NDK 工程构建概述 |
| ABI | `OHOS_ARCH ∈ {armeabi-v7a, arm64-v8a, x86_64}`；手机实际只跑 **arm64-v8a**，模拟器 `x86_64` | 同上 |
| 预构建库 | **必须由 OpenHarmony NDK 工具链编译生成**，且其依赖库也要一并导入、同样由该工具链生成 | NDK 预构建库约束（原文） |
| SONAME | 预构建 so 必须设置 `SONAME`，否则链接器会把绝对路径写进 `DT_NEEDED`，安装后动态加载失败 | 同上（可用 `llvm-readelf -d x.so | grep SONAME` 校验） |
| 放置路径 | 模块 `libs/<abi>/libxxx.so`；HAR 中同理 | 同上 |
| 交叉编译三方 C/C++ 库 | OpenHarmony 官方提供 `tpc_c_cplusplus`（lycium）框架批量适配 | OpenHarmony SIG 仓库 |

### 2.3 Xray-core 接入的三条候选路线

| 路线 | 说明 | 可行性 | 主要风险 |
|---|---|---|---|
| **A. Go → c-shared so + NAPI 包装**（推荐做 PoC） | `CGO_ENABLED=1 CC=<ohos>/clang GOOS=linux GOARCH=arm64 go build -buildmode=c-shared` 产出 `libxray.so`，再写一层薄 C++ NAPI 胶水导出 start/stop/stats | **④风险最高但方向正确**，见 §2.4 | 工具链/ABI/信号/GC/体积 |
| B. 用 C/C++ 重写协议栈 | 不现实（Xray 协议族庞大） | ✗ | — |
| C. Go 编译为独立可执行文件，进程间通信 | 官方 NDK 只交付 so；且 **native 子进程在手机不可用**（§4.3） | **④不可用** | 沙箱 + 设备限制 |

### 2.4 Go 产物接入：可行性与已知坑（**【待真机验证】项，本文最高优先级 PoC**）

**依据链**：
1. 官方 NDK 只提供 C/C++ 工具链，target triple 为 `aarch64-linux-ohos`（musl libc）；
2. Go 官方**没有 `ohos` 目标**（`go tool dist list` 输出中无 `ohos/*`；`GOOS ∈ {linux, android, ...}`）。→ 只能借道 `GOOS=linux GOARCH=arm64` 生成 ELF/aarch64 产物；
3. `-buildmode=c-shared` **必须** `CGO_ENABLED=1`，即必须提供一个能产出 ohos ABI 的 C 链接器（ohos clang）；
4. 纯 Go 静态可执行文件（`CGO_ENABLED=0`）在 OpenHarmony 设备上被验证可运行（社区样本：`GOOS=linux GOARCH=arm64` 静态二进制在 OpenHarmony 开发板上跑通 —— 来源：yuanlulu《鸿蒙开发板上跑 go 程序》，CSDN 2022），但**那是"系统内跑可执行文件"，不是"应用沙箱内加载 so"**，两者不可等同。

**已知坑清单（按严重度排序）**：

| # | 坑 | 现象 | 缓解 |
|---|---|---|---|
| P1 | 工具链/ABI 不匹配 | `dlopen` 失败 / `UnsatisfiedLinkError`；用 glibc 链接的 so 直接无法加载 | 用 ohos clang + musl sysroot 链接；`llvm-readelf -d` 校验 `DT_NEEDED` 只有 `libc.so/libc++_shared.so/libace_napi.z.so` 等 ohos 库 |
| P2 | cgo 与 musl 的未知兼容性 | 启动即 crash，栈回溯在 runtime/cgo | 先用**最小可验证 c-shared**（只导出 `Add(a,b)`）跑通，再逐步引入 `net`/`tls`/`quic` |
| P3 | Go runtime 与宿主信号冲突 | 随机 SIGSEGV/SIGURG 相关崩溃、`fatal error: unexpected signal` | Go 需要 SIGURG（抢占）/SIGPROF 等；宿主 ArkTS 运行时也在用信号 → 需 PoC 观察；必要时用 `GODEBUG=asyncpreemptoff=1` 降低信号依赖 |
| P4 | 沙箱 syscall 白名单 | `epoll_create1`/`getrandom`/`io_uring`/`clone` 被拒 → 网络不可用或线程创建失败 | 逐项探测；Go 不依赖 io_uring（v1.2x 未默认启用），风险可控 |
| P5 | **tun fd 跨语言传递 + protect 顺序** | 路由环路（代理流量自己又走 tun）→ 全部超时 | 顺序必须是：Go 建 socket → 取 fd（`SyscallConn().Control`）→ 回调 ArkTS 调 `VpnConnection.protect(fd)` → 再 `create(VpnConfig)`；`protect` 必须在 VPN 建立前完成 |
| P6 | 内存与体积 | Go so 常 15~30MB+；GC 的 STW 造成 UI 卡顿 | `-ldflags="-s -w"`、裁剪无用包（不用 `net/http` server 等）、GC 放独立线程/独立进程（VPN 扩展进程） |
| P7 | Go 的 DNS 解析 | musl + `cgo` DNS 走系统 resolver，可能与 Xray 自带 DNS/fake-ip 冲突 | Xray 侧关闭系统 DNS，统一走内置 DNS 客户端 + `VpnConfig.dnsAddresses` |
| P8 | Go panic 无法优雅降级 | 崩溃拖死整个应用（同进程） | 加 `recover` + 看门狗；崩溃后 UI 侧重连；Native crash 需 `faultLogger` 采集 |

**PoC 判定标准（能定论的最小实验）**：
- 实验 1（工具链）：最小 c-shared so 在真机 `arm64-v8a` 加载成功，`Add(1,2)==3` → 通过则 P1/P2 解除。
- 实验 2（网络）：so 内 `net.Dial("tcp", "1.1.1.1:443")` 成功 → P3/P4 解除。
- 实验 3（数据面）：取 socket fd → ArkTS `protect()` → `VpnConfig.create()` 拿到 tun fd → Go 侧读写 tun，浏览器能出网 → P5 解除，**核心可行性定论**。
- 任一实验失败，则回退到"§3.5 替代路径"，并把结论上报 Leader 重新评估产品形态。

---

## 3. 代理 / VPN 能力（本次最关键）

### 3.1 明确判断

> **HarmonyOS NEXT 对三方应用开放 tun 级 VPN 能力。xray-harmony 可以做"全局代理客户端"，不需要任何华为侧资质审批。**（①）

**证据（三处互相印证）**：
1. `VpnExtensionAbility` 模块定位原文："**VpnExtensionAbility 模块提供三方 VPN 相关能力**，提供三方 VPN 创建、销毁等生命周期回调"；首批接口 **API 11** 起；"仅可在 Stage 模型下使用"。华为侧文档同源：`js-apis-vpnextensionability`（HarmonyOS 5.0.0/API 12 配套文档）。
2. `@ohos.net.vpnExtension` 定位原文："**三方 VPN 管理模块**，支持三方 VPN 的启动和停止功能……当前提供三方 VPN 能力主要用于**创建虚拟网卡及配置 VPN 路由信息**，连接隧道过程及内部连接的协议需要应用内部自行实现"。
3. 开发指导（含示例工程 VPNControl_Case）明确给出：`module.json5` 里 `extensionAbilities[].type = "vpn"`；调用 `vpnExtension.startVpnExtensionAbility(want)` → 系统弹授权框 → 授权后回调 `onCreate` → 建隧道 → `protect()` → `create(config)` → 读写虚拟网卡。

> ### 3.1.0 API Level 下限（leader / 需求侧必答，明确回答）
>
> - **对三方开放的下限 = API 11**。原文："本模块首批接口从 API version 11 开始支持。后续版本的新增接口，采用上角标单独标记接口的起始版本。"（`@ohos.net.vpnExtension` / `VpnExtensionAbility` 同）
> - **商用 Release 起点 = HarmonyOS NEXT 5.0.0（API 12）**：API 11 只存在于 5.0.0 之前的开发者版本；华为侧 API 12 配套文档已正式收录 `VpnExtensionAbility` 模块。
> - 后续能力的下限阶梯：`generateVpnId`（多 VPN）= **API 20**；`protectProcessNet` = **API 22**；`createVpnObserver`/`onAuthorizationResult`（授权结果回调）= **26.0.0**；`destroy(vpnId)` = **API 20**。
> - **工程结论**：`compatibleSdkVersion = 12` 即可保证 VPN 能力可用且无需运行时降级判断；若产品要求"多 VPN 共存"才需把下限抬到 20。
> - **【待真机验证】项**：API 11 实机（非商用 Release）上的可用性未验证。**验证方式**：API 11 设备/模拟器安装最小 VPN demo，观察 `startVpnExtensionAbility` 是否回调 `onCreate`。由于 NEXT 商用机最低为 API 12，该不确定性不影响交付，可不做。

**关键 API 清单**：

| 能力 | API | 备注 |
|---|---|---|
| 启动/停止 VPN 扩展 | `vpnExtension.startVpnExtensionAbility(want)` / `stopVpnExtensionAbility(want)` | `bundleName` 必须与本应用一致；只允许停止自己启动的扩展 |
| 生命周期 | `VpnExtensionAbility.onCreate/onDestroy` | 在 `onDestroy` 里 `destroy()` 清理 |
| 创建连接对象 | `vpnExtension.createVpnConnection(ctx: VpnExtensionContext)` | 必须在 `startVpnExtensionAbility` 成功之后 |
| 建虚拟网卡 | `VpnConnection.create(config: VpnConfig): Promise<number>` | **返回 tun 的 fd** |
| 保护隧道 socket | `VpnConnection.protect(socketFd: number)` | 防路由环路，必须在 create 前 |
| 进程级保护 | `VpnConnection.protectProcessNet()`（API 22+） | 保护整个进程的流量不走 VPN |
| 销毁 | `destroy()`（API 11+）/ `destroy(vpnId)`（API 20+） | 配对调用，避免资源泄漏 |
| 多 VPN 标识 | `generateVpnId(): Promise<string>`（API 20+） | 当前**仅支持 IPv4** |
| 授权结果监听 | `vpnExtension.createVpnObserver()` + `onAuthorizationResult(cb)`（API 26.0.0 起） | 低版本无此 API，需用错误码兜底 |

**`VpnConfig` 与产品能力的映射（对分流/DNS 需求极其重要）**：

| 字段 | 类型 | 与 Xray 能力的对应 |
|---|---|---|
| `addresses` | `LinkAddress[]` | tun 网段（如 `10.0.0.5/24`） |
| `routes` | `RouteInfo[]`（**最多 1024 条**） | "绕过大陆/GFW 分流"的**系统层**落地手段：按 CIDR 决定哪些流量进 tun |
| `dnsAddresses` | `string[]` | VPN 激活期间被代理应用的 DNS 查询服务器（可指向本地 DNS/fake-ip） |
| `mtu` | `number` | 建议 1400 起（UDP/TLS 分片敏感） |
| `isIPv4Accepted` / `isIPv6Accepted` | `boolean` | 【官方原文】"是否支持IPv4……默认值为true。**注意**：若支持IPv4功能，需要在addresses中配置IPv4类型的IP地址。" / "是否支持IPv6……**默认值为false**。注意：若支持IPv6功能，需要在addresses中配置IPv6类型的IP地址。" → **默认 IPv6 不支持 ⇒ v6 流量不进 tun**（见 §9.6） |
| `isBlocking` | `boolean` | 【官方原文】"是否阻塞模式。true表示阻塞模式，false表示非阻塞模式，默认值为false。"（**文档未定义"阻塞"的具体语义**，如未就绪时是否丢弃、进程退出后是否保留阻断 → 见 §9.6） |
| `mtu` | `number` | 【官方原文】"最大传输单元MTU值（单位：字节）。**取值范围：[576，1500]**" |
| `trustedApplications` / `blockedApplications` | `string[]`（包名） | **分应用代理（应用级分流）**，两者互斥、不能同时配置 |

> 架构含义：**Xray 的路由分流有两层落地** —— 系统层（`routes` + `trusted/blockedApplications`，粒度有限）与引擎层（Xray 内部 routing + sniffing，粒度细）。设计文档必须明确：默认走"引擎层分流"（`routes` 全量入 tun + Xray 内部按域名/IP 规则决定直连或代理），系统层只用于"排除 Xray 自身/本机管理流量"。

> **`dnsAddresses` 能否指向本地 fake-ip / 127.0.0.1？**（D1 追问：三种寻址方式的风险排序）
> - **官方原文只说用途，未设"必须外部可达"的限制，也**未明确支持**"指向 tun 内地址/回环地址"**："DNS服务器地址信息。配置DNS服务器地址后，VPN启动状态下，被代理的应用上网时，使用配置的DNS服务器进行DNS查询。"→ 因此**三种方式在文档层面都是"未覆盖"，不是"已支持"**。
> - **候选 A（推荐，风险低）：tun 网段内地址，如 `10.0.0.2:53`，由应用在 tun fd 上监听/应答。** 依据：与官方语义一致（系统把该地址当 DNS 服务器，查询包按 `addresses` 网段路由进入 tun）；这是移动端 fake-ip 的常规做法，文档未禁止。**状态：文档未禁止但未明文支持 →【待实测 E14-A】**。
> - **候选 B（风险高，仅作备选）：`127.0.0.1:53`。** 额外引入三重未知：回环监听是否被允许、<1024 端口是否受限（E10）、系统 resolver 是否把回环地址当有效 DNS。**状态：【待实测 E14-B】**。
> - **候选 C（不推荐）：外部可达 DNS（如 `223.5.5.5`）。** 语义最保险，但等于放弃应用内 DNS 接管 → 无法做 fake-ip/域名分流，且不解决 DNS 泄漏。仅作对照组。
> - **补充约束**：无论 A/B，`routes` 必须覆盖该 DNS 地址所在网段（A 通常由 `addresses` 的网段路由自动覆盖，**需实测确认**），否则 DNS 查询不会进 tun、表现为"域名全部解析失败但 IP 直连可用"。


### 3.1.1 系统做了什么 / 应用必须自己做什么（工作量分界，**必读**）

> 这一节回答"调了 `VpnExtensionAbility` 是不是就有 VPN 了"。答案是**没有**。

| 环节 | 归属 | 依据（官方原文） |
|---|---|---|
| 用户信任授权弹窗 + 状态栏 VPN 钥匙图标 | **系统** | "在VPN应用首次启动连接之前，系统会显示VPN连接授权对话框……当VPN启动连接成功时，状态栏显示一个VPN (钥匙) 图标" |
| 创建虚拟网卡、返回 tun fd | **系统** | `VpnConnection.create(): Promise<number>` "返回指定虚拟网卡的文件描述符 fd" |
| 下发路由、DNS、MTU、分应用名单 | **系统**（按应用给的 `VpnConfig` 执行） | `VpnConfig` 字段表："VPN虚拟网卡的IP地址"/"路由信息(目前最多可配置1024条路由)"/"DNS服务器地址信息……被代理的应用上网时，使用配置的DNS服务器进行DNS查询" |
| 隧道建立（VLESS/VMess/Trojan/Shadowsocks/Reality/XTLS、TLS、QUIC/mKCP/gRPC/WS 等） | **应用自行实现** | "当前提供三方VPN能力主要用于创建虚拟网卡及配置VPN路由信息，**连接隧道过程及内部连接的协议需要应用内部自行实现**" |
| tun fd 的读写、IP 包解析、TCP/IP 栈或用户态转发 | **应用自行实现** | 开发步骤："**处理虚拟网卡的数据，如：读写操作**" |
| socket `protect()` 的调用时机与顺序（防路由环路） | **应用自行实现** | "通过VpnConnection.protect保护前一步建立的UDP隧道"（必须早于 `create`） |
| 连接状态机、重连、统计、日志、配置热更新 | **应用自行实现** | — |

**工作量含义（给 D1/Z1 的输入）**：三方要自己交付一个**完整的用户态隧道客户端**——协议栈、用户态 TCP/IP 或包转发、DNS 拦截、分流决策、进程守护、统计上报全部在应用内。`VpnExtensionAbility` 只提供"最后一公里"（虚拟网卡 + 路由 + DNS 下发 + 授权与状态展示）。
→ 这也是本项目"必须复用 Xray-core 而不是自研协议"的根本原因；也是 P-01 PoC 必须四件事串通（NAPI 加载 so + 隧道封装 + tun fd 读写 + protect 顺序）的原因。

### 3.2 权限与资质（明确区分）

| 问题 | 答案 |
|---|---|
| 需要声明什么权限？ | 仅 `ohos.permission.INTERNET`（normal，声明即生效）。**没有** VPN 相关的第三方权限申请（`ohos.permission.MANAGE_VPN` 属系统级，三方无需也不可用） |
| 需要企业资质/白名单/特殊申请吗？ | **系统层面未见任何申请环节**【推论：官方文档未描述 VPN 能力的申请/审批流程，且其依赖权限 `ohos.permission.INTERNET` 为 normal + system_grant；非官方否定性声明】。开发/调试/内部分发未检索到华为人工审批；只有"公开上架应用市场"才涉及类目资质（IP-VPN 类增值电信业务经营许可证，且该资质要求来源于行业解读而非华为规范文档）—— 见 §6 与 `harmony-permission-checklist.md` |
| 用户侧有什么门槛？ | 首次启动**系统弹 VPN 授权对话框**（用户信任授权）；成功后状态栏出现 VPN 钥匙图标；`stopVpnExtensionAbility` 调用方必须已获该授权 |
| 有没有隐藏限制？ | ✅ 系统**同一时刻只支持 1 个 VPN 连接服务**（官方原文："目前系统仅支持启动一个VPN连接服务，当VPN已经启动时应用新调用启动接口会收到系统拒绝错误"）。⚠️ **错误码语义需拆两层**：`2203002` 的官方定义是"**VPN 连接已存在 / VPN已经被创建**"（`VpnConnection.create()` 的错误码表），**官方未区分"本应用重复创建"与"其他应用已激活"**；"其他应用已激活"那句原文在启动接口处，且**未给错误码** → 后者属**【待验证】**（§7 E8）。✅ 服务生命周期受调用方进程约束：**"当调用 startVpnExtensionAbility 接口的应用进程退出时"系统会主动停止 VPN**。✅ `VpnExtensionAbility` 内**不允许引用** `@ohos.contact`、`@ohos.geolocation/geoLocationManager`、`@ohos.multimedia.audio`、`camera`、`telephony.call/sim/sms`（会导致进程异常退出）—— 这意味着**引擎侧不能依赖音频/电话/定位 API**，日志与状态上报要走 `hilog` + IPC。✅ GUEST 用户不能创建 VPN（`2203001`） |

### 3.3 若"不可用"才有意义的替代路径（本项目**不需要**，但作降级备案）

| 替代路径 | 形态 | 体验损失 | 可行性 |
|---|---|---|---|
| 本地端口 + 应用内代理 | Xray 起 SOCKS5/HTTP 入站于 `127.0.0.1:1080`，用户在各 App 内手动填代理 | **极大**：HarmonyOS 无全局 SOCKS 设置；仅浏览器/少数 App 支持自定义代理 → 只剩"浏览器场景" | ③ 需确认具体 App 支持度 |
| Wi-Fi 手动代理 | 系统 Wi-Fi 设置里"代理=手动"填服务器/端口（HTTP 代理口径） | 大：仅 HTTP(S)，且随 Wi-Fi 切换失效；能否填 `127.0.0.1` 与是否支持 SOCKS **【待真机验证】** | ② |
| 纯浏览器（ArkWeb 内代理） | 仅自研 WebView 容器内转发 | 只能替代"浏览器"，无法覆盖其他 App | ① |

**替代路径的验证方法**：`设置 → WLAN → 已连接网络 → 代理 → 手动`，填 `127.0.0.1:1080`（SOCKS 服务），观察系统浏览器与其他 App 是否出网；同时抓 `hilog` 看是否报连接失败。若仅 HTTP 生效，则记录"SOCKS 不支持"。

### 3.4 形态 B（本地代理客户端：loopback + 用户手动配置）成立性评估

> 形态 A（tun）已定为主线，本节为**备选形态的成立性边界**，逐条回答"缺一即 B 不能作为 MVP 主线"的三问。格式：结论 + 依据 + 限制条件 + 对需求的影响。

#### B-1 loopback 监听（本地 SOCKS5 / HTTP CONNECT 服务）

| 项 | 内容 |
|---|---|
| **结论** | **受限（技术可行，产品不可行）** —— 应用可以创建并 listen 本地 TCP 端口，**但"用户能不能用上"取决于第三方应用自身是否支持代理配置，而 HarmonyOS 没有系统级 SOCKS 代理开关** |
| **依据** | 【官方原文】`socket.constructTCPSocketServerInstance()` + `tcpServer.listen(ipAddress)`（`NetAddress{address, port}` 可任意指定本地地址与端口），见《使用Socket访问网络》网络指导；【官方原文】"应用退后台后，Socket 可能会断开，当应用重新回到前台，发生通信失败时，需匹配错误码并重新创建新的TCP/UDP Socket"；【官方原文】需要 `ohos.permission.INTERNET`（normal） |
| **限制条件** | ① 权限：仅 `INTERNET`（normal），**无额外权限、无审核**；② 端口：文档**未给出**端口范围限制或并发连接数限制（**未找到**"<1024 需特权"的表述）→ 监听 `127.0.0.1:1080` 属未明文禁止，**【待真机验证】**；③ 版本：无 API 级别门槛（socket 很早开放）；④ ABI：不涉及；⑤ 审核：开发期无审核 |
| **对需求的影响** | "应用内起本地代理"可作为**技术能力**保留（用于"本应用内流量"、单机调试、给支持代理的 App 手动填地址），但**不能作为全局代理的产品形态**；若写需求，验收标准只能是"监听成功 + 应用内自测通过"，不能写"其他应用可透明走代理" |

#### B-2 进程可维持多久（后台存活机制）

| 项 | 内容 |
|---|---|
| **结论** | **受限** —— 进程中可用的保活机制只有"长时任务 + 常驻通知"一条；三方应用**没有**后台服务扩展组件可用，且官方明确"应用退后台后 Socket 可能会断开" |
| **依据** | 【官方原文】长时任务：`startBackgroundRunning` 成功后"通知栏显示与长时任务相关联的消息，用户删除通知栏消息时，系统会自动停止长时任务"；"如果一个应用创建了多个UIAbility，一个UIAbility申请长时任务后，整个应用下的所有进程均不会被挂起"；【官方原文】`ServiceExtensionAbility` 文档文件名带 `-sys`，标题即"（仅对系统应用开放）"；【官方原文】`AppServiceExtensionAbility`（API 20 起）"当前仅支持2in1设备"且需 ACL 权限 `ohos.permission.SUPPORT_APP_SERVICE_EXTENSION`，"该ACL权限当前只对企业普通应用开放申请" |
| **限制条件** | ① 机制：`KEEP_BACKGROUND_RUNNING`（normal，声明即得）+ `backgroundModes` 某一 type + 系统通知（通知被用户删除 → 任务即停）；② 类型错配会被管控：申请 `dataTransfer` 就必须有真实传输业务，否则"应用退至后台会被挂起"；`dataTransfer` 还要求"进度首次更新不超过 10 分钟"，且"更新进度的通知类型必须为实况窗"；③ 若要 `taskKeeping`（语义最贴近常驻）→ 需 restricted 权限 `KEEP_BACKGROUND_RUNNING_SYSTEM`（system_basic + ACL）→ **需资质/审批**；④ 审核：开发期无审核，但长期滥用长时任务会被系统一致性校验命中；⑤ 耗电：长时任务受"典型负载"约束，负载持续偏高会被挂起或终止 |
| **对需求的影响** | 形态 B 的后台存活能力**不优于**形态 A（两者都要靠长时任务），且 B 还多一条"Socket 可能断开"的官方风险 → **B 在"进程维持"维度无法作为 A 的降级替代**；产品需求里"后台稳定代理 8 小时"这类 NFR 只能按 A 的口径验收 |

#### B-3 其他应用能否指向该 loopback 代理

| 子问题 | 结论 | 依据 | 对需求的影响 |
|---|---|---|---|
| a) 三方应用自设 HTTP/代理指向 `127.0.0.1:port` | **受限，且比预期更窄**：存在应用级代理接口，但**只能由该应用自己设置、且只对走 `@ohos.net.http` 且显式 `usingProxy=true` 的请求生效** | **【官方原文】**`connection.setAppHttpProxy(httpProxy: HttpProxy)`（11+）："设置应用级Http代理配置信息。" 说明："**若需使用本接口所配置的代理信息，则需在 HttpRequestOptions 字段中将 usingProxy 设置为 true 以启用代理转发。本接口仅负责配置代理规则，不校验代理服务的有效性。**"（`js-apis-net-connection.md`）；另【官方问答口径】系统全局代理（Wi-Fi 设置）优先级高于应用级代理 | 可达范围进一步收窄：等于"该应用自愿且用 http 模块 + 开 usingProxy"；socket/自研网络库流量**不受影响** |
| b) 系统级 per-app proxy（非 root 可配置） | **不可用**：未检索到面向三方的"按应用代理"写入 API；系统级代理是**用户在设置应用中手动配置的 Wi-Fi 代理**（三方应用无写权限） | 【官方原文】Socket 指导 + 社区抓包实践（Wi-Fi 设置 → 代理 → 手动） | 需求不能写"自动为其他应用下发代理"；只能写"引导用户到设置页手动配置" |
| c) 是否只剩"本应用内流量" | **基本成立**：若不做系统级代理，形态 B 的可达范围 = 本应用 + 内置 WebView + 少数支持代理配置的应用 | 由 a)+b) 推出 | 若要写进产品，建议明确标注"仅浏览器/自研容器场景"，避免与形态 A 的能力混淆 |

**B 形态总判定**：**技术可行但产品价值不足**（不是"连监听都做不到"）。→ 给需求文档的措辞建议：`形态 B 可作为"局部/备用通道"存在（如内置浏览器代理、调试用途），不作 MVP 主线；平台不提供全局代理降级能力，因此形态 A 是唯一能覆盖全应用的路线`。

> **B 不是"更差的 A"，两者是不同维度的权衡（与 §4.2 联动收口）**：
> B 的**真实价值不在存活能力**（这一点它确实不优于 A：同样要靠长时任务，且多一条"退后台 Socket 可能断开"的官方风险），而在**权限侵入性与外部冲突**三个维度：
> ① **不需要用户授予 VPN 信任授权**（没有系统弹窗、没有状态栏 VPN 钥匙图标）→ 对企业内训/受限场景、对"用户不愿授权 VPN"的转化流失更友好；
> ② **不接管全局流量**（只影响显式指向它的流量）→ 隐私叙事更强、与其他代理工具**不冲突**；
> ③ **不占用系统唯一 VPN 槽位** → **不存在 `2203002` 冲突**，可与用户已有的 VPN 共存（A 做不到）。
> 代价是**覆盖面**：只有本应用 / 内置 WebView / 少数支持代理配置的 App（且应用级代理仅对 `@ohos.net.http` + `usingProxy=true` 的请求生效）。
> ⇒ 结论：**A 是"覆盖面优先"，B 是"低侵入 + 可共存优先"；不能互相替代，也不能把 B 写成 A 的降级档。**

#### B-4 loopback 监听的补充参数（供架构侧参考，非结论）

- 接口：`socket.constructTCPSocketServerInstance()` → `listen({address:'127.0.0.1', port:1080})`（ArkTS）；Native 侧可直接用 POSIX `bind/listen/accept`（同一 sandbox 进程）。
- 若采用 LocalSocket（`LocalSocketServer`，AF_UNIX）可避免占用 TCP 端口，但**只能被同应用/授权应用连接**，跨应用不可用 → 仅适合"UI ↔ 内核"的控制面 IPC，不能作代理入口。

### 3.5 `2203002` 的可归因性（P0"VPN 冲突提示"的验收口径）

| 项 | 内容 |
|---|---|
| **结论** | **部分可归因**：能拿到"已被占用"这一事实与错误码，**拿不到占用方身份**（无 bundleName / 应用名） |
| **依据** | 【官方原文】`2203002`："错误信息 VPN exist already, please execute destroy first. / 错误描述 VPN连接已存在……/ 可能原因 VPN已经被创建。"（`errorcode-net-vpn.md`）；`startVpnExtensionAbility` 的错误码表仅有 `401/16000001/16000002/16000006/16000008/16000011/16000050/16200001`，**无"已被其他应用占用"专用码**；`@ohos.net.vpnExtension` 全量接口中**没有**"查询当前 VPN 占用方"的方法（`createVpnObserver` 只监听本应用的授权结果，且 26.0.0 起才有） |
| **限制条件** | ① 无查询占用方的公开 API（系统应用侧 `net-vpn-sys.md` 不属于三方可用范围）；② 跨应用占用的实际错误码 **【待验证】**（见 §7 E8）；③ 无官方"跳转到 VPN 设置页"的 deep link 文档 → **【待验证】**（可尝试 `startAbility` 拉起设置应用，但 URI/abilityName 未公开承诺） |
| **对需求的影响** | P0 需求验收标准应写**强档 + 弱档两段**：强档（若 E8 证明可区分）"提示占用并给出跳转"；弱档（默认）"通用文案：检测到系统已有 VPN 连接，请先在系统设置中关闭其他 VPN 后重试"，并附"重试"按钮。**不要**在需求里承诺"显示占用应用名称" |

### 3.6 `VpnConfig` 分应用代理的开放性与上限（决定"分应用分流"排期）

| 项 | 内容 |
|---|---|
| **结论** | **对三方应用开放（①）**，是 `VpnConfig` 的正式字段，**无资质/无权限门槛**；文档**未给出**"可列应用数量上限" |
| **依据** | 【官方原文】`trustedApplications`："受信任的应用信息列表，以string类型表示的包名。配置此列表后，仅列表中的应用数据才能根据routes被VPN代理。注：trustedApplications和blockedApplications列表不能同时配置。"；`blockedApplications`："被阻止的应用信息列表……该列表中的应用数据不会被VPN代理，其他应用可以根据routes配置被VPN代理。"；开发指导示例 `trustedApplications: ['com.test.browser']`、`blockedApplications: ['com.test.games']` |
| **限制条件** | ① 二者**互斥**（白名单/黑名单二选一）→ 产品上"仅代理 A/B/C"与"排除 X/Y" 不能同时表达；② **粒度 = 应用（包名），不是进程/UID【官方原文·已确定】**："`blockedApplications`：被阻止的**应用信息列表**，string类型表示的**包名**……该**应用**的数据不会被VPN代理"；`trustedApplications` 同理（"仅列表中的**应用**数据才能根据routes被VPN代理"）→ **不存在"按进程/按 UID"的配置粒度**，故"要按进程分流"类需求在平台层无对应能力（只能在引擎层做）。**由此派生两个产品级坑（须写入需求）**：(a) 包名变更（改名/换渠道包）、同名不同签名、**应用分身（`appIndex`）/多用户**都会导致"同一个应用"匹配不上或匹配到错误实例 → 用户的"分应用设置"会**静默失效**，需提供列表校验/失效提示；(b) **失效检测的粒度只能到包名，"分身视为同一应用"**：若用户卸载主应用只留分身，检测可能判"包名仍存在"→ 白名单条目显示正常但实际指向错误实例（**这是 E22 的第二层影响，验收表述不得要求"检测到具体实例"**）；**剩余粒度未知项见 E22**；③ **条数上限【官方原文·已确定】**："API version 23前最多可配置**64 个**…；从 API version 23 开始最多可配置**256 个**"（黑名单同口径）→ 需求承诺按目标运行 API 档位写 64 或 256；④ `routes` 上限 **1024 条**为明确写死的约束；⑤ 版本：字段自 API 11 起随模块提供（`isIPv6Accepted` 等后续字段有版本差异） |
| **对需求的影响** | "分应用分流"可排 **P0**（能力确定），但需求必须写成二选一模式（白名单模式 **或** 黑名单模式），验收标准禁止出现"同时支持白名单与黑名单"；条数上限按"未限制但需实测"标注 |

### 3.7 结论

**xray-harmony 的 tun 级全局代理路线成立，且无资质前置。** 真正的技术风险集中在"Go 内核同进程接入"（§2.4），以及"VPN 活跃期间如何不被系统清理"（§4）。

---

## 4. 后台存活 / 生命周期

### 4.1 长时任务（Continuous Task）

| 项 | 内容 |
|---|---|
| 权限 | `ohos.permission.KEEP_BACKGROUND_RUNNING`（normal，声明即得） |
| 配置 | `module.json5` → `abilities[].backgroundModes: ["dataTransfer", ...]` |
| API | `backgroundTaskManager.startBackgroundRunning(context, bgMode, wantAgent): Promise<void>` / `stopBackgroundRunning(context)`；API 21+ 支持一次申请多个（≤10 个） |
| 类型全表 | `dataTransfer`、`audioPlayback`、`audioRecording`、`location`、`bluetoothInteraction`、`multiDeviceConnection`、`voip`(API 13+)、`taskKeeping`(API 21+ 手机)、`avPlaybackAndRecord`(API 22+)、`specialScenarioProcessing`(API 22+)、`nearlink`(26.0.0)；`wifiInteraction` **仅系统应用** |
| **无 vpn 类型** | 长时任务表**不包含** VPN/代理类型 → 需借用语义最近的类型 |
| 系统一致性校验 | "申请长时任务后，应用未执行相应的业务，系统会对应用进行管控，即应用退至后台会被挂起"；"业务类型与申请的不一致 → 挂起或终止" |
| `dataTransfer` 附加约束 | "若使用 `@ohos.request` 托管上传下载，即使申请 dataTransfer，退后台仍会被挂起"；"进度长时间（**首次更新超过 10 分钟**）未更新，长时任务会被取消"；进度通知**必须是实况窗** |
| 跨进程效果（**关键**） | "如果一个应用创建了多个 UIAbility，**一个 UIAbility 申请长时任务后，整个应用下的所有进程均不会被挂起**" |
| 通知 | 申请成功后通知栏出现长时任务通知；用户删除通知 → 系统自动停止长时任务 |
| 取消监听 | `on('continuousTaskCancel')`（API 15+）/ `on('continuousTaskSuspend')`（API 20+） |

### 4.2 VPN 与后台保活的组合结论（**关键设计约束**）

1. 官方**没有** VPN 专用长时任务；VPN 连接本身不自动获得后台豁免。
2. 官方明确"调用方应用进程退出 → 系统停止 VPN"。⇒ **必须让应用宿主进程常驻**，且按文档机制唯一可控手段是申请长时任务（可覆盖"整个应用所有进程"）。
3. 可用类型选择：
   - `dataTransfer`（②可自助）：语义不精确（有业务一致性校验与"10 分钟进度更新"约束）→ 需在 VPN 激活期间周期性更新实况窗进度，否则长时任务被取消。
   - `taskKeeping`（**③需资质**）：API 21+ 起对手机开放，但需 `ohos.permission.KEEP_BACKGROUND_RUNNING_SYSTEM`（restricted，ACL + AGC 白名单，邮件 `agconnect@huawei.com`，官方问答口径 **1 个工作日**）。语义最贴合"常驻后台服务"。
4. **【待真机验证】**：VPN 扩展进程（`VpnExtensionAbility`）在 VPN 连接期间是否会被独立冻结/清理，以及"仅申请 `dataTransfer` 长时任务 + 用实况窗保活"能否稳定支撑 8 小时以上。验证方法见 §7-E1。

### 4.3 进程模型相关限制（决定架构，③/④）

| 能力 | 结论 | 依据 |
|---|---|---|
| 创建 ArkTS 子进程 `childProcessManager.startChildProcess(srcEntry, mode)` | **仅 Tablet / PC/2in1**；手机返回 `16000061 Operation not supported` | 接口"设备行为差异" |
| 创建 ArkTS 子进程 `startArkChildProcess`（API 12+） | 手机返回 `801 Capability not supported` | 同上 |
| 创建 Native 子进程 `OH_Ability_CreateNativeChildProcess` / `StartNativeChildProcess`（API 12+） | API 13 及之前仅 PC/2in1；API 14+ 仅 PC/2in1 与 Tablet；**手机返回 `NCP_ERR_NOT_SUPPORTED`** | `native_child_process.h` 设备行为差异 |
| 子进程数量上限 | 与 `childProcessManager` 合计 ≤512；`SELF_FORK` 不计入 | 同上 |
| 子进程限制 | 不支持创建 UI；不支持依赖 Context 的 API；子进程内不能再建子进程；随父进程退出而退出 | 同上 |
| 结论 | **手机上不能"起一个独立进程跑代理内核"**，也不能 fork 后 exec 任意可执行文件 | — |

⇒ 架构只能是：**UIAbility（控制面） + VpnExtensionAbility（数据面，同进程或独立进程的 .so）**，Xray-core 以 so 形式被 NAPI 加载进其中一方。

### 4.4 开机自启（④不可用）

- `StaticSubscriberExtensionAbility`（`module.json5` 中 `type:"staticSubscriber"` + `metadata` 指向 `subscribe.json`）文档标题即写明 **"静态订阅公共事件（仅对系统应用开放）"**；且"当前仅支持预置应用配置该文件"（`/system/variant/phone/base/etc/app/install_list_capability.json` 的 `allowCommonEvent`）。
- 生命周期：`onReceiveEvent()` 执行完 **15 秒后销毁**（即便对系统应用也不适合做长驻）。
- ⇒ 三方应用**没有**开机自启通道。需求侧必须改写为：桌面卡片/服务卡片一键连接、通知栏常驻操作、以及"检测到上次异常断开 → 启动后首页强提示重连"。

---

## 5. 安全存储与敏感配置落盘

| 数据类型 | 建议方案 | 关键能力 | 约束 |
|---|---|---|---|
| 凭据类（uuid、订阅 token、节点密码、Reality 私钥） | **ASSET**（`@ohos.security.asset`） | AES256-GCM 加解密在 **TEE** 内完成；属主访问控制；锁屏状态控制（开机后可访问/首次解锁后/解锁状态）；可要求用户认证（指纹/人脸/PIN），认证有效期最长 10 分钟 | **单条 ≤1KB**；以"业务身份 + 别名"为唯一索引（别名需唯一）；预留 12 个 `DATA_LABEL_*` 自定义属性；批量查询建议 ≤40 条/次；**应用卸载会清除数据**（`IS_PERSISTENT=true` 可保留）；不支持沙箱应用/应用分身访问群组数据 |
| 加密密钥（用于节点库批量加密） | **HUKS**（`@ohos.security.huks`） | 密钥生成/导入/销毁、加解密、签名验签、密钥派生、访问控制；明文密钥不出安全环境 | 需自行设计密钥别名与用途（`HuksKeyPurpose` / `HuksKeyAlg`） |
| 节点库/订阅/路由规则等批量数据 | **RDB**（`@ohos.data.relationalStore`）+ `StoreConfig.encrypt = true` | 数据库以密文存储、密态工作；**加密属性在创建库时确定，不可变更** | 加密后无法用外部工具打开（利于安全，不利于调试，需要自建导出） |
| UI 偏好（主题、上次选中的节点索引等非敏感项） | `@ohos.data.preferences` | 轻量 KV | **不要放敏感数据**（Preferences 非安全存储） |
| 日志 | `hilog` + 敏感字段脱敏 | — | 禁止打印订阅 URL/token/节点密码 |
| 备份/迁移 | ASSET 与应用生命周期绑定；`IS_PERSISTENT` 决定是否保留 | — | 需在需求侧定义"换机迁移 = 重新导入订阅"，并给出可验收用例 |

**结论：①可用**，安全需求（凭据不落明文、密钥在 TEE、库文件加密）**全部可满足**，无需降级。

---

## 6. 分发与合规

### 6.1 签名机制

| 环节 | 要求 |
|---|---|
| 签名物料 | `证书(.cer)` + `Profile(.p7b)` + 私钥（`.p12`），由 AGC 签发；签名工具链（`hapsigntool`/DevEco 一键签名） |
| 调试 | **调试证书 + 调试 Profile**，需绑定真机 UDID；调试设备上限 **100 台**【**待核实**：未逐字抓取到官方"100 台"原文，属开发者共识口径；请在 AGC 证书页人工复核】 |
| 发布 | 发布证书 + 发布 Profile；上架应用市场 |
| 企业内部 | **组织内部发布证书**（每账号最多 1 个）+ 组织内部发布 Profile，包与描述文件放自有服务器/云，用户直接下载安装（**不上架**） |
| 关键约束 | 企业内部发布链路要求：**一个未做过实名认证的、归属地中国大陆的华为开发者账号** → 完成"企业内部应用分发资格申请" → 企业开发者（企业内部应用分发）实名认证；且"当前企业内部应用发布仅支持 Stage 模型开发的 HarmonyOS 应用，暂不支持元服务" |

### 6.2 应用市场政策（VPN/代理类）

- 华为应用市场的类目资质要求见 AGC《应用资质要求》页（`developer.huawei.com/consumer/cn/devservice/doc/80301`）：【官方原文·总则】"应用(包含游戏)需提供符合适用的法律法规要求的资质文件……资质说明并未详尽，如有疑问可咨询客服，以最终审核意见为准。"
- **VPN/代理类对应的资质**【**社区观测值 / 行业解读**，非华为规范文档】：《增值电信业务经营许可证》（业务种类：国内互联网虚拟专用网业务，俗称 IP-VPN 许可证）。常见门槛（**代办/解读类页面口径，需法务复核**）：企业主体、经营范围含"增值电信业务"、注册资本跨省 1000 万 / 省内 100 万、股权无外资、3 名员工社保。
- **审查期限**【法规口径，**条款号待法务确认**】：《电信条例》体系下增值电信业务经营许可的审查期限为 60 日内；**社区实际办理周期 20~40 个工作日**（代办机构口径，非统计样本）。
- **[需向 AGC 审核确认]**：Xray 类"翻墙/规避网络管理"工具在大陆不属可上架的合规业务形态；即使具备 IP-VPN 许可证，也需业务与许可范围一致。**结论：公开上架路径存在实质性合规障碍，不建议作为主发布渠道。**
- 替代分发：① 企业内部应用分发（§6.1，适合 B 端/自用）；② 调试安装（适合内测，设备数上限待核实）；③ 海外市场/其他渠道（不在本文范围，需另做合规评估，且 Xray-core 为 MPL-2.0，分发须保留许可证与源码获取方式——许可证合规见 xray-core-analyst 的产出）。

---

## 7. 四态结论总表（验收用）

| # | 能力项 | API / 权限 | 四态 | 依据 | 备注 |
|---|---|---|---|---|---|
| 1 | Stage 模型 + ArkTS/ArkUI 开发 | `UIAbility`/`ExtensionAbility`、ArkTS | ① 可用 | 官方文档 | 无审批 |
| 2 | Native so 加载与调用 | NAPI / Node-API（Node 18.x LTS 规范）、`libace_napi.z.so` | ① 可用 | NDK 概述 + Node-API 简介 | — |
| 3 | 预构建 so 打包 | 须 OpenHarmony NDK 工具链编译，ABI `arm64-v8a` | ② 需权限（工具链合规） | NDK 预构建库约束 | 非"权限"，属硬性构建约束 |
| 4 | Go/Xray-core 同进程接入 | `-buildmode=c-shared` + ohos clang | **【待真机验证】** | 无 ohos 目标；工具链约束 | 最高风险，PoC 定论 |
| 5 | 独立进程跑内核 | `childProcessManager` / `native_child_process.h` | ④ 不可用（手机） | 设备行为差异：仅 PC/2in1、Tablet | — |
| 6 | tun 级全局代理 | `VpnExtensionAbility` + `vpnExtension.createVpnConnection` | ① 可用（需用户授权弹窗） | 官方模块定位与开发指导 | 无资质前置 |
| 7 | 分应用代理 | `VpnConfig.trustedApplications` / `blockedApplications` | ① 可用 | `VpnConfig` 字段说明 | 二者互斥 |
| 8 | 路由级分流 | `VpnConfig.routes`（≤1024 条） | ① 可用 | 同上 | 精细分流仍靠引擎层 |
| 9 | VPN 内 DNS 指定 | `VpnConfig.dnsAddresses` | ① 可用 | 同上 | 可指向本地 fake-ip |
| 10 | 多 VPN 并行 | `generateVpnId()` + `vpnId`（API 20+） | ① 可用（仅 IPv4） | 接口文档 | 单 VPN 限制在低版本仍生效 |
| 11 | 后台长时任务 | `ohos.permission.KEEP_BACKGROUND_RUNNING` + `backgroundModes` | ② 需权限（normal，自助） | 长时任务文档 | 无 vpn 类型；`dataTransfer` 有 10 分钟进度约束 |
| 12 | 高优后台保活 | `ohos.permission.KEEP_BACKGROUND_RUNNING_SYSTEM`（restricted） | ③ 需资质/审批（ACL 白名单；**官方问答口径约 1 个工作日，无 SLA 承诺**） | restricted-permissions（system_basic，API 20 起）+ AGC 问答口径 | 用于 `taskKeeping`（API 21+） |
| 13 | 开机自启 | `StaticSubscriberExtensionAbility` / `usual.event.BOOT_COMPLETED` | ④ 不可用（三方） | "仅对系统应用开放" + 预置文件授权 | 需改产品设计 |
| 14 | 常驻通知 | `@ohos.notificationManager`、长时任务通知 | ① 可用 | 长时任务通知说明 | 用户删通知即停任务 |
| 15 | 凭据安全存储 | `@ohos.security.asset` | ① 可用 | ASSET 简介 | ≤1KB/条 |
| 16 | 密钥管理 | `@ohos.security.huks` | ① 可用 | HUKS 简介 | TEE 内运算 |
| 17 | 加密数据库 | `relationalStore` `StoreConfig.encrypt` | ① 可用 | 数据加密指导 | 创建时确定不可改 |
| 18 | 应用签名/调试安装 | 调试证书 + Profile，UDID ≤100 | ② 需权限（自助，分钟级） | AGC 文档 | 无人工审批 |
| 19 | 企业内部应用分发 | 组织内部发布证书 + Profile | ③ 需资质（企业实名 + 分发资格） | 企业内部应用发布文档 | 需独立未实名账号 |
| 20 | 应用市场公开上架（VPN 类） | 类目资质（IP-VPN 许可证等） | ③ 需资质 + 合规存疑 | AGC 资质页 | 月级周期；不建议主渠道 |
| 21 | 系统级 SOCKS/全局代理设置 | 无公开 API（仅 Wi-Fi 手动代理，HTTP 口径） | ④ 不可用（作为全局方案） | 设置项实测截图/社区 | **【待真机验证】** SOCKS 支持度 |
| 22 | Wi-Fi/网络状态感知 | `ohos.permission.GET_NETWORK_INFO`、`GET_WIFI_INFO` | ② 需权限（normal） | 权限列表 | 用于断线重连 |
| 23 | 日志与可观测 | `@ohos.hilog` + `faultLogger`（Native crash） | ① 可用 | 官方文档 | 需脱敏 |
| 24 | loopback TCP 监听（形态 B 基础） | `socket.constructTCPSocketServerInstance()` + `listen(NetAddress)` | ② 需权限（仅 `INTERNET`，normal） | Socket 网络指导 | 端口/并发上限文档未述；**退后台 Socket 可能断开** |
| 25 | 其他应用指向本应用 loopback 代理 | — | ④ 不可用（作为全局方案） | 无系统级 SOCKS / per-app proxy 写入 API；`connection.setAppHttpProxy` 只能应用自设 | 可达范围 = 本应用 + 内置 WebView + 少数支持代理的 App |
| 26 | 三方写入系统级 / 按应用代理配置 | — | ④ 不可用 | 系统级代理由用户在设置中手动配置；三方可写接口未开放（全量接口清单待复核） | 需求只能写"引导用户手动配置" |
| 27 | 三方后台服务扩展组件 | `ServiceExtensionAbility` / `AppServiceExtensionAbility` | ④ 不可用（手机） | 前者"仅对系统应用开放"；后者"当前仅支持2in1设备"且需 ACL `ohos.permission.SUPPORT_APP_SERVICE_EXTENSION`（仅企业普通应用可申请） | 三方常驻唯一手段 = 长时任务 |
| 28 | 查询 VPN 占用方身份 | — | ④ 不提供 | `vpnExtension` 全量接口无该能力；`startVpnExtensionAbility` 错误码表无"被占用"专用码 | P0 冲突提示按弱档验收 |
| 29 | 系统级 SOCKS5 代理设置 | — | ④ 不可用（未见公开能力） | 设置应用仅"Wi-Fi → 代理 → 手动"（HTTP 代理口径）；SOCKS 支持度 **【待真机验证】** | 影响形态 B 可达范围 |
| 30 | 枚举已安装应用列表 | `bundleManager.getInstalledBundleList` | ④ 不可用（普通应用）/ ③ 企业 MDM | 需 `ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`（不在 normal 清单） | 分应用 UI 不能做"勾选列表" |
| 31 | 读他应用名称/图标/签名 | `getBundleInfo` / `getApplicationLabel` / `getSignatureInfo` | ③ 需审批（ACL，实务按 ④） | 三方需 `GET_BUNDLE_INFO_PRIVILEGED` | 同上 |
| 32 | 运行期 VPN 状态感知 | `VpnExtensionAbility.onDestroy` + `connection.on('netCapabilitiesChange')` + `NetBearType.BEARER_VPN`(12+) | ② 需权限（`GET_NETWORK_INFO`，normal）/ 部分【待验证】 | `js-apis-net-connection.md`、`vpnExtension` 无状态监听接口 | 无 VPN 专用回调；建议 ≤5s 档验收 |
| 33 | 授权结果为事件回调 | `vpnExtension.createVpnObserver().onAuthorizationResult` | ① 可用（**26.0.0 起**） | 官方原文"仅接收当前VPN的结果" | 低版本无此 API，需错误码兜底 |
| 34 | 分应用名单条数上限 | `VpnConfig.trustedApplications`/`blockedApplications` | ① 可用（**每列表 64 个 / API 23 起 256 个；两表互斥 ⇒ 实际上限 64/256，不相加**） | 【官方原文】字段表明确写死 + "不能同时配置" | 需求承诺按目标**运行** API 档位取值；超限行为见 E21 |
| 35 | 阻塞模式 | `VpnConfig.isBlocking` | ② 需权限（随 VPN 能力，无独立权限）/ **语义边界未文档化** | 官方原文只有"是否阻塞模式…默认 false" | 进程死亡后行为【待实测 E19】 |
| 36 | IPv6 代理 | `VpnConfig.isIPv6Accepted`（默认 **false**）+ `addresses` 配 v6 地址 | ① 可用（需显式开启） | 【官方原文】"默认值为false…需要在addresses中配置IPv6类型的IP地址" | **默认 v6 不进 tun → v6 绕过 VPN**，须在需求中明示 |

### 待真机验证项与验证方法

> **验证设备档位要求（方法论注记）**：凡是"某 API 版本起"才具备的能力（如 `trustedApplications` 的 256 上限 = API 23 起、`onAuthorizationResult` = 26.0.0 起、`protectProcessNet` = API 22 起、多 VPN `generateVpnId` = API 20 起、`taskKeeping` 长时任务 = API 21 起），验收**必须指定该档位的新设备**。测试设备通常是老机型（易获得、成本低），导致这类"新档位行为"**不是漏测，而是从来不可能测到**——属结构性盲区，须在计划里显式分配设备，否则对应 E 项形同未做。
> **落地要求（必填字段）**：每个 E/VD 项若涉及"某版本起"的能力，**必须填写「所需设备 API 档位」字段**；缺该字段的项视为"未定义验收设备"，不得进入执行。且"**待执行**"与"**缺设备（阻塞）**"必须区分为两种状态——混同会高估进度。

| 编号 | 待验证问题 | 验证方法 | 判定标准 |
|---|---|---|---|
| E1 | VPN 活跃期间，仅靠 `dataTransfer` 长时任务 + 实况窗进度，应用/VPN 能否稳定存活 ≥8h | 真机跑 8h：`hdc shell hilog | grep -E "continuousTaskCancel|Vpn"`；锁屏 + 后台 + 切换 Wi-Fi | 无 `continuousTaskCancel`、VPN 未断连、无进程重建日志 |
| E2 | `VpnExtensionAbility` 进程是否会被单独冻结/清理 | 观察 VPN 活跃期间 `hdc shell "ps -ef | grep <bundle>"` 的进程存活与重启迹象；同时看 tun fd 是否失效 | 进程 pid 稳定、fd 可读写 |
| E3 | Go c-shared so 能否加载并联网（§2.4 实验 1/2） | 最小 so PoC | `Add()` + `Dial()` 均成功 |
| E4 | tun fd 交给 Go 后数据面能否通（§2.4 实验 3） | 完整 PoC：protect → create → 读写 | 浏览器可访问外网，且无路由环路 |
| E5 | 系统 Wi-Fi 手动代理是否支持 SOCKS5 / 是否允许 `127.0.0.1` | 设置里配 `127.0.0.1:1080`，用 SOCKS 服务观察 | 若仅 HTTP 生效，则替代路径价值进一步下降 |
| E6 | 多 VPN（`generateVpnId`）在目标机型/版本上是否可用 | 连续启动两个 VPN 扩展，观察第二个是否成功 | 成功=可用；报错则按"单 VPN"设计 |
| E7 | `VpnExtensionAbility` 内 `hilog` + IPC 上报链路的可用性（因禁止部分 Kit） | 在扩展内调用 `@ohos.notificationManager`、`@ohos.net.connection` 等，观察是否崩溃 | 不崩溃即可用；崩溃则改由 UIAbility 侧承接 |
| E8 | **其他应用已激活 VPN 时，我方启动/创建的错误码**（决定 P0 冲突提示强度） | 装机两个 VPN demo：A 启动并确认状态栏钥匙图标 → B 调用 `startVpnExtensionAbility` 与 `create()`，**两处分别记录 `BusinessError.code` 与 `message`** | 若 `create()` 返回 `2203002` 则可归因"已被占用"；若返回其它码或 `start` 阶段直接失败，需按调用点分别写文案 |
| E9 | **VPN 活跃期是否"无需"长时任务也不被冻结**（决定"后台存活"是 P0 还是伪需求，以及是否必须承担"常驻通知"体验成本） | **对照实验（同一真机、同一节点、同一版本，仅改一个变量）**：A 组申请 `dataTransfer` 长时任务（含实况窗进度更新）；B 组**不申请**任何长时任务。两组分别做：① 退后台 + 锁屏 30 min；② 退后台 + 锁屏 2 h（含一次 Wi-Fi↔蜂窝切换）。采集：`hdc shell hilog \| grep -E "continuousTaskCancel\|continuousTaskSuspend\|Vpn\|Suspend\|Freeze"`；`hdc shell "ps -ef \| grep <bundle>"` 记录 pid 是否变化；每组做 3 次取"连接存活率"（未断连次数/3） | A 组存活率 <3/3 → 长时任务方案本身不成立，需换方案；B 组存活率 <3/3 而 A 组 =3/3 → "后台存活"必须 P0 且必须承担常驻通知；两组均 3/3 → "后台存活"可降为 V1 稳定性项 |
| E10 | loopback 监听是否受端口/并发限制（形态 B 前提） | 应用内 `listen({address:'127.0.0.1', port:1080})` 与 `<1024` 端口各试一次；并发压 50 连接 | 均成功 → 无限制；`<1024` 失败 → 记录高权限端口限制 |
| E11 | 跨应用能否连到本应用 loopback 端口（形态 B 前提） | A 应用 listen 回环端口；B 应用（或 `hdc shell` 内 `curl`/`nc`）连接该端口 | 可连 → loopback 跨应用可达；不可连 → 形态 B 连"应用间借用"都不成立 |
| E12 | ~~`trustedApplications` 条数上限~~ **已由官方原文回答，无需实测** | 【官方原文】"trustedApplications … API version 23前最多可配置64个…；从 API version 23 开始最多可配置256个"；`blockedApplications` 同口径，且"**trustedApplications和blockedApplications列表不能同时配置**" → **两列表各自 64/256，但因互斥不能同时生效 ⇒ 实际可用上限就是 64/256，不相加** | **结论：按目标运行 API 档位取 64 / 256**（同一 HAP 在 API 22 设备上仍按 64，见 E21-b） |
| E21 | 分应用名单**超限行为**（截断 / 报错 / 静默失效）——静默失效是最坏形态 | a) 在 API 22 档配置 65 个包名，看 `create()` 是否报错；b) **必须验"实际生效"**：对第 65 个应用（用 `curl`/`ping` 走该应用流量或观察其出口 IP）确认是否真的走了 VPN；c) 在 API 23+ 档重复 257 个。**所需设备 API 档位：API 22 一台 + API 23+ 一台** | 报错 → 可安全拦截；**静默截断 → 升级为安全级风险**（用户以为走代理、实际直连），UI 必须自行做硬上限拦截 |
| E22 | 分应用名单在**应用分身 / 多用户**场景下的匹配语义（同一包名、不同 appIndex/用户，是否可分别选中）**及其对"失效检测"的连带影响** | 开启应用分身（`appIndex` 1~5）与第二用户，给同一包名配白名单，分别验证主应用 / 分身 / 其他用户的流量是否都走 VPN；再看 `create()` 是否报错。**第二层验证**：卸载主应用、只留分身，观察"包名存在性检测"是否仍判存在（若判存在 → 白名单条目显示正常但实例错误） | 全部走 VPN → 名单是"包名级、覆盖所有实例"，UI 必须说明"分身无法单独排除"，且**失效检测只能到包名粒度**；可区分 → 记录区分方式；报错 → 平台不支持分身场景，需 UI 硬拦截。**所需设备 API 档位：API 12+ 且系统支持应用分身** |
| E13 | 是否存在可拉起 VPN/网络设置页的 Want（用于冲突提示跳转） | 尝试 `startAbility` 拉起设置应用常见 abilityName/URI，观察是否被系统拦截（三方显式拉起会被限制） | 可拉起 → 强档交互成立；不可 → 只给文案 + "重试" |
| E14 | `dnsAddresses` 三种寻址方式哪条真正可用（决定 FakeDNS 实现路径，D1 `D-12` 依赖） | **A/B/C 三组分别测、不可混测**：A = tun 网段内地址（如 `10.0.0.2:53`，应用在 tun fd 上应答）；B = `127.0.0.1:53`；C = 外部 DNS（如 `223.5.5.5`，对照组）。每组观测 4 项：① tun fd 上是否收到 DNS 查询；② 是否有包泄漏到物理网卡；③ 大响应（>512B，TXT/DNSSEC 类）能否解析（验 MTU/分片）；④ 应用能否正常按域名访问 | 4 项全通过才算该方式可用。A 通过 → 主方案定 A；仅 C 通过 → 平台不允许应用接管 DNS，需降级为"纯 IP 路由 + 域名嗅探" |

---

## 8. 三个高频问题的直接回答（供 leader / requirements / risk 三处复用）

**Q1「VPN 活跃期间是否仍需长时任务/前台通知才能不被系统冻结？」**
**答：官方没有"VPN 免于冻结"的正面表述，也没有 VPN 专用长时任务类型。** 现有官方事实链是：① 长时任务类型表**不含 vpn**；② "调用 `startVpnExtensionAbility` 接口的应用进程退出时"系统会主动停止 VPN；③ "一个 UIAbility 申请长时任务后，整个应用下的所有进程均不会被挂起"。
→ **工程口径**：**必须**申请 `KEEP_BACKGROUND_RUNNING`（normal，零等待）+ `backgroundModes` 让进程常驻，否则按文档语义 VPN 随进程退出而断；**但"不申请是否也稳定"尚无官方结论**，属 **E9 对照实验**（已列为审查项）。给需求的写法："后台稳定代理为 P0，实现依赖长时任务（`dataTransfer` + 实况窗进度，或 `taskKeeping` + ACL）"，不要写"系统自动保活"。

**Q2「`VpnConfig` 分应用代理对三方开放吗？」**
**答：开放（①），无权限/资质门槛**；但 `trustedApplications` 与 `blockedApplications` **互斥**（二选一），包名粒度，文档未给条数上限（E12 实测）。→ **"分应用分流"可排 P0**，需求须明确模式二选一。

**Q3「系统是否暴露占用 VPN 的其他应用身份（2203002 冲突提示）？」**
**答：不暴露。** `@ohos.net.vpnExtension` 无查询占用方接口；`startVpnExtensionAbility` 错误码表也无"被占用"专用码；`2203002` 的官方原文只到"VPN exist already / VPN已经被创建"。
→ **验收标准默认走弱档**："提示系统已有 VPN 连接，请先行断开后重试 + 重试按钮"；强档（显示占用应用名）**不可承诺**，需 E8/E13 证明后才可升级。

---

## 9.5 应用信息枚举能力 & VPN 运行期状态可观测性（MVP 必需，Q1/D1 追问补充）

> 来源：requirements-architect 的两个追问（分应用代理选应用的 UI 数据源 / VPN 被关闭时能否感知）。两条都直接决定 P0 是否成立，故单列一节。

### 9.5.1 能否枚举已安装应用 / 读取他应用信息

| 能力 | API | 权限要求（官方原文） | 三方可用性 | 四态 |
|---|---|---|---|---|
| 枚举**已安装应用列表** | `bundleManager.getInstalledBundleList(bundleFlags)` | "**需要权限：** `ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`" | 该权限**不在"对所有应用开放（normal）"清单**中，名称属企业/MDM 域 → 普通三方应用不可得 | **④ 不可用（普通应用）/ ③ 需资质（企业 MDM）**；是否仅限企业管控类应用文档未明写【待验证 E15】 |
| 按**包名**查 BundleInfo（名称/版本/图标） | `bundleManager.getBundleInfo(bundleName, flags, userId?)`（14+） | "**需要权限：** `ohos.permission.GET_BUNDLE_INFO_PRIVILEGED` or `ohos.permission.GET_BUNDLE_INFO`；**当调用方为三方应用时，需要申请 `ohos.permission.GET_BUNDLE_INFO_PRIVILEGED` 权限**" | `GET_BUNDLE_INFO`(normal) 仅对系统应用有效；三方必须走 `..._PRIVILEGED`（system_basic 级，需 ACL + 审核） | **③ 需资质/审批（ACL）**，且"查询其他应用信息"的必要性说明很难通过审核 → 实务上按 **④** 设计 |
| 取**应用显示名**（支持分身索引） | `bundleManager.getApplicationLabel(bundleName, appIndex)`（26.0.0+） | "**需要权限：** `ohos.permission.GET_BUNDLE_INFO_PRIVILEGED`" | 同上 | **③/④** |
| UID → 包名 | `bundleManager.getBundleNameByUid(uid)`（14+） | 同上（三方需 `..._PRIVILEGED`） | 同上 | **③/④** |
| 读**签名信息**（判断签名是否变化） | `bundleManager.getSignatureInfo(uid)`（18+） | 需 `GET_BUNDLE_INFO_PRIVILEGED`（同一权限族） | 同上 | **③/④** |
| 查**自身**信息 | `bundleManager.getBundleInfoForSelf(flags)` | 无权限要求 | 可用 | ① 可用 |
| 判断某链接能否被打开 | `bundleManager.canOpenLink(link)`（12+） | 无特殊权限（文档未列权限） | 可用，但只回答"某 URL scheme 有无处理者"，**不能反推包名列表** | ② 有限用途 |
| **系统 UI 应用选择器** | 未检索到面向三方的"通用应用选择器"组件（`photoAccessHelper`/`file.picker`/`contact` 均有专用 picker，但**没有**"选择任意已安装应用"的公开 picker） | — | — | **④ 未发现**（【待验证 E16】：确认是否存在 `AppPicker` 类组件） |

**结论（直接影响 P0 分应用代理的交互设计）**：

> **三方应用拿不到"已安装应用列表"，也拿不到其他应用的名称/图标/签名。**
> ⇒ 分应用代理的 UI **不能**做成"从应用列表勾选"，只能有三条现实路径：
> ① **手动输入包名**（最确定，体验最差，需配"如何查包名"的引导）；
> ② **引导用户在系统"应用管理/应用信息"里复制包名**（无 API，纯人工流程）；
> ③ 预置常见应用包名映射表（如浏览器/商店/银行类 Top-N），由我们维护 + 用户自定义补充 → **建议作为 MVP 的折中方案**（可离线、无需权限、可验收）。
> **验收标准建议**："用户可在 30 秒内完成一次分应用配置（预置列表 + 搜索 + 手动输入三条路径至少两条可用）"，**不要**写"从已安装应用中选择"。

### 9.5.2 VPN 运行期被关闭时，应用能否感知

| 观测面 | API / 回调 | 结论 | 依据 |
|---|---|---|---|
| 我方主动停止 | `vpnExtension.stopVpnExtensionAbility(want)` → `VpnExtensionAbility.onDestroy` 被调用 | **可感知（确定）** | 官方原文："stopVpnExtensionAbility后，您的VPN Extension Ability的onDestroy方法将被调用，您可在此刻destroy vpn连接。" |
| 用户在系统设置里关闭 VPN / 系统主动停止我方 VPN | `onDestroy` 是否一定触发 | **【待验证 E17】**：文档只承诺"我方调用 stop 时触发 onDestroy"，未承诺系统侧停止时必触发 | 文档无反向表述 |
| 授权结果 | `vpnExtension.createVpnObserver()` + `onAuthorizationResult(cb)` | **仅用于"首次授权弹窗结果"，不能用于运行期状态**；且 **26.0.0 起**才有 | 官方原文："注册用户授权结果监听器。授权结果在调用 startVpnExtensionAbility 弹出授权弹窗，用户点击弹窗后通知，**仅接收当前VPN的结果**。" |
| `VpnConnection` 状态查询/监听（如 `on('vpnStateChange')`） | — | **不存在**：`VpnConnection` 只有 `create`/`protect`/`destroy`/`generateVpnId`/`protectProcessNet` | `js-apis-net-vpnExtension.md` 全量方法清单 |
| **系统默认网络的承载类型**（间接探测，推荐） | `connection.getNetCapabilities(netHandle)` + `NetBearType.BEARER_VPN`（**API 12+**）；`connection.createNetConnection().on('netCapabilitiesChange', cb)` | **可感知（事件驱动）**：VPN 建立/拆除会改变默认网络的 bearerTypes，订阅事件即可在变化时刷新 UI；**语义是"默认网络是否 VPN 承载"，不等于"是否我方 VPN"**，须与自身状态机联合判定 | 官方原文：`NetBearType` 枚举 "`BEARER_VPN`（12+）| 4 | VPN网络。"；`getNetCapabilities` "需要权限：`ohos.permission.GET_NETWORK_INFO`"；`on('netCapabilitiesChange')` 事件订阅存在 |
| 应用自身进程被杀/重启 | `AbilityLifecycleCallback` / 冷启动状态重建 | 可感知（重启后状态重建） | 常规能力 |

**结论（给 P0「UI 状态与真实隧道状态严格一致」的验收口径）**：

> **存在"事件驱动"的感知路径，但不是 VPN 专用回调。**
> 推荐实现：**双通道** —— ① 我方 `onDestroy` + 自身连接状态机（覆盖主动停止/正常销毁）；② `connection.on('netCapabilitiesChange')` 监听 `BEARER_VPN` 的有无（覆盖外部关闭、被抢占、系统停止）。
> **时延档位建议**：事件驱动通常为亚秒~秒级，但无官方 SLA → 验收写「**≤5s 内反映**（事件驱动为主 + 3s 周期兜底轮询，轮询仅在 VPN 激活期间开启）」，**不要**写"≤1s 即时"。若要写即时档，需 E18 实测。

**两条给 D1 的补充判据（状态机与文案设计）**：

1. **"tun fd 写入成功"不等于"报文已上链"**：写入 tun 只是把包**入队**，队列满/协议层丢弃时写入仍可能返回成功。⇒ 一阶信号（fd 写返回值）只能判定"**应用侧交付链路**是否还活着"，不能判定"对端是否可达"；**二阶心跳（经隧道的 UDP 探测 + 期望回包）才是端到端可信信号**。两者要分开呈现或至少分开判定。
2. **异常原因不可归因 → 文案必须中性**：系统不提供"谁占用了 VPN / 因何被停止"（§3.5 + §7 #28），因此两维状态异常时**不能**写"已被其他 VPN 接管"这类断言，只能写"VPN 已断开，可能由系统或其他 VPN 应用引起"+ 重试；若要强档，需 E8/E13 通过后才可区分。


### 9.5.3 本节新增验证项

| 编号 | 待验证问题 | 验证方法 | 判定标准 |
|---|---|---|---|
| E15 | `ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST` 是否为普通三方应用可申请（还是仅企业 MDM） | 在 AGC 查询该权限是否可 ACL 申请；无果则尝试申请并记录驳回理由 | 可申请 → 枚举能力按②处理；仅企业 → 维持④ |
| E16 | 是否存在面向三方的"通用应用选择器"（AppPicker）组件 | 检索 `picker`/`appPicker` 相关 Kit 与 API 文档；尝试用 Want + `startAbilityForResult` 拉起系统选择器 | 找到 → UI 可改为选择器；找不到 → 采用 §9.5.1 的"预置列表 + 手动输入" |
| E17 | 系统侧停止 VPN（设置页关闭 / 资源管控 / 删除长时任务通知）时 `onDestroy` 是否被调用 | 分别触发三类停止，`hilog` 打点 `onDestroy` 是否到达；同时记录时延 | 必到达 → 可只依赖回调；否则必须叠加 `netCapabilitiesChange` 探测 |
| E18 | 上述双通道方案的端到端反映时延 | 三种停止路径各 10 次，记录"停止时刻 → UI 状态变更时刻"差值 | 有数据后决定 P0 写 ≤1s 还是 ≤5s（默认按 ≤5s） |

---

### 9.6 `isBlocking` 语义边界 & IPv6 泄漏（Q1 追问补充）

**官方原文（`js-apis-net-vpnExtension.md` `VpnConfig` 字段表，逐字）**

- `isBlocking`：「"是否阻塞模式。true表示阻塞模式，false表示非阻塞模式，默认值为false。"」→ **文档只给了布尔语义，没有定义"阻塞"到底阻塞什么、何时解除、进程退出后是否保留**。
- `isIPv6Accepted`：「"是否支持IPv6。true表示支持，false表示不支持，**默认值为false**。**注意**：若支持IPv6功能，需要在addresses中配置IPv6类型的IP地址。"」
- 生命周期（`连接VPN` 指导·服务生命周期）："为了保障设备的网络连接，当系统观察到VPN相关应用出现异常时会主动停止VPN连接：- 当调用startVpnExtensionAbility接口的应用进程退出时。- 当VPN服务进程销毁时。"

#### 三问结论

| 问题 | 结论 | 证据强度 | 依据 |
|---|---|---|---|
| ① 进程被杀瞬间：撤销 VPN 恢复直连，还是保留阻断无网络？ | **倾向"撤销 VPN 并恢复直连"**——因为官方明确"应用进程退出时系统会主动停止 VPN 连接"，VPN 被停止意味着 tun/路由被撤除；**但 `isBlocking` 在停止后的残留语义文档完全未写** | **【推论，待实测 E19】**（非官方表述） | 生命周期原文 + 字段表无死亡语义 |
| ② 泄漏窗口多长？ | **未知，必须实测**；测量方法见下 | **【待实测 E19-2】** | 无官方数据 |
| ③ v6 是否跟随阻断？ | **不跟随，且默认就是"v6 不进 tun"**：`isIPv6Accepted` 默认 **false**（且要求 `addresses` 里配 IPv6 地址才生效）⇒ 默认配置下 **IPv6 流量完全不进 tun**，`isBlocking` 也无从阻断它 → **"v4 阻断 / v6 直连漏出"是默认组合** | **【官方原文（默认值）+ 推论（泄漏形态）】** | 字段表 + 网络常识 |
| ④ `isBlocking` 与 IPv6 能否同时开？ | **语法上可同配**（两个独立可选 boolean，文档未声明互斥）；**语义是否冲突（blocking 时是否还能正常转发 v6）文档未写** → 需实测 | **【待实测 E20】** | 字段表未声明互斥 |

#### 实测方法（给 Q1 写"承诺边界"用）

**E19-1（死亡后是否撤销/保留）**
1. 三组配置：`isBlocking=false`（基线）、`isBlocking=true`、`isBlocking=true + isIPv6Accepted=true + v6 地址`。
2. 每组：VPN 连上 → 用 `hdc shell` 在设备侧持续 `ping -i 0.2 <公网IP>`（同时 poll `curl` 一域名）→ 在 PC 侧记录时刻 T0：`hdc shell kill -9 <pid>`（或用系统"强行停止"）。
3. 观测：杀进程后网络是"立即恢复直连"（ping 恢复）还是"持续不通"（ping 全丢且无恢复）。
4. 采样 **≥20 次**（覆盖冷/热启动、锁屏/亮屏、有无长时任务三种状态），记录「恢复直连 / 持续阻断」的比例。
5. **辅助判据（比 ping 更早、更确定）**：同步观察**状态栏 VPN 钥匙图标是否消失**——图标消失通常即代表系统已撤销 VPN（撤销先于"应用层感知到网络可用"）。日志侧再抓 `hilog` 中 Vpn 相关销毁记录做时间对齐。


**E19-2（泄漏窗口）**
- 仪器：PC 侧脚本持续 `ping -i 0.1`（100ms）×3 个目标 + 每 100ms 一次 DNS 查询；设备侧 `hilog` 打点进程死亡时间戳（或 `date +%s%3N` 记录 T0）。
- 指标：`T_restore - T0` = 泄漏窗口；记录**中位数 / P95 / 最大值**，采样 ≥20 次。
- 注意：若窗口 < 100ms，说明是"撤销即恢复"，可在需求里写"无实质 kill switch，窗口 ≤N ms"；若为秒级，必须写成"存在 N 秒直连泄漏窗口"，并在首次连接明示文案里体现。

**E20（blocking × v6 共存）**
- 配 `isBlocking=true` + `isIPv6Accepted=true` + v6 地址，验证：v4 是否正常转发（不是全断）、v6 是否进 tun、两者是否互不影响。判定：能同时工作 → 无冲突；v4 变全断 → blocking 与转发语义冲突，需二选一。

**对 Q1 的写作建议**：
- 在 E19 结果出来前，**不要**写"提供/不提供进程级 kill switch"任何绝对句；写法：「进程终止后的流量行为受系统 VPN 撤销策略影响，实测窗口与行为见 E19 回填」。
- **IPv6 必须单列一条风险**：默认 `isIPv6Accepted=false` ⇒ **v6 流量绕过 VPN**。需求侧要么写"仅 IPv4 代理（明示，并在 UI 标注）"，要么要求 `isIPv6Accepted=true` + 配 v6 地址（此时需 Xray 侧支持 v6 出站，且 `routes` 覆盖 v6）。

**对 D1 的文案约束（"文案即合规"，请写进设计文档的文案规范）**：
- 状态/保护范围类文案**只允许二值表述**，禁止"部分保护""基本安全""已尽力"等模糊态：只有 **`isIPv6Accepted=true` + `addresses` 含 IPv6 地址 + `routes` 覆盖 v6 + Xray 侧 v6 出站** 四条全满足，才可显示"IPv6 已纳入隧道"；其余任何组合一律显示"IPv6 未纳入（可能直连）"。
- 理由：**模糊态在合规上比"明确的未保护"更危险**——它让用户误以为存在某种保护，且出问题时我们无法证明自己没做过该承诺。同理，`isBlocking` 在 E19 回填前只允许写"进程终止后的流量行为见实测"，不得写"具备 kill switch"。
- **二值规则的边界（防止被过度执行）**：该规则针对的是**不可计数的模糊态**（"部分保护""基本安全""已尽力"）；**可枚举、可审计的事实陈述属于允许项**——例：「已代理 12 个应用，其中 3 个因未收录显示为未知应用（包名 xxx）」是**可验证事实**，应保留；「大部分流量已保护」不可审计，应禁止。**判据：这句话能否被审计验证（能否列出具体对象/数量/条件）**——能则允许，不能则禁止。若过度执行（删掉一切"部分"），会造成信息不足；反之保留话术则形成"自称合规"。


---

## 10. 给下游的接口约定

- 给 **requirements-architect（Q1）**：§4.4（无开机自启）、§3.2（单 VPN 限制 + 用户授权弹窗）、§5（安全存储能力上限，如 ASSET ≤1KB）、**§3.4（形态 B 三问：B 技术可行但产品不可行，平台无全局代理降级能力）**、**§3.5（2203002 归因：弱档验收）**、**§3.6（分应用代理：可排 P0，二选一 + 64/256 条上限）**、**§8（三个高频问题直接回答）**、**§9.5（枚举能力受限 → 分应用 UI 走"预置列表 + 手动输入"；运行期状态走双通道 + ≤5s 档）**、**§9.6（`isBlocking` 语义未定义 → 不写 kill switch 绝对句；IPv6 默认绕过 VPN 必须明示）**。
- 给 **solution-architect（D1）**：§2.3/§2.4（Go 同进程 so 是唯一路线）、§4.2（长时任务类型选择与 10 分钟进度约束）、§3.1 的 `VpnConfig` 字段表（分流/DNS 双层落地）、§4.3（手机不可用独立进程；`AppServiceExtensionAbility` 仅 2in1）、§3.6（分应用代理二选一）、**§9.5（权限清单里不要规划 `GET_BUNDLE_INFO_PRIVILEGED`；状态同步用 `netCapabilitiesChange` + `BEARER_VPN`）** 是架构的硬边界。
- 给 **risk-planner（Z1）**：§2.4 P1~P8 与 §7 的 E1~E14、§9.5.3 的 E15~E18 可转成 PoC 清单（判定阈值由 Z1 定义，本文只给"为什么重要 + 验证方法线索"）；注意"VPN 能力无审批"这一前提修正（见 `harmony-permission-checklist.md`）；原文与证据强度见 `harmony-evidence-quotes.md`。
- 给 **xray-core-analyst**：需要你确认 Xray-core 侧可关闭系统 DNS/系统解析、可用外部传入 fd 做数据面（而不是自己创建 tun），以及 Go 版本/构建标签对 musl + 无 cgo 依赖的处理方案。


---

## 9. 参考依据（官方优先）

1. `@ohos.net.vpnExtension (VPN增强管理)` — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/js-apis-net-vpnExtension.md ｜ 华为侧同源：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-vpnextensionability-V5
2. `连接VPN` 开发指导（含 `module.json5` 配置、`VpnConfig` 全字段、示例工程 VPNControl_Case） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/network/net-vpnExtension.md
3. VPN 错误码（`2203001`/`2203002`/`2203004` 等） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/errorcode-net-vpn.md
4. `长时任务(ArkTS)`（类型全表、一致性校验、跨 UIAbility 进程效果、通知约束） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/task-management/continuous-task.md
5. `静态订阅公共事件（仅对系统应用开放）` — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/basic-services/common-event/common-event-static-subscription-sys.md
6. `@ohos.app.ability.childProcessManager` — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-ability-kit/js-apis-app-ability-childProcessManager.md
7. `native_child_process.h`（Native 子进程 + 设备行为差异） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-ability-kit/capi-native-child-process-h.md
8. `NDK工程构建概述`（工具链、`OHOS_ARCH`、`OHOS_STL`、target triple） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/build-with-ndk-overview.md
9. `在NDK工程中使用预构建库`（预构建库必须由 NDK 工具链编译、SONAME 校验） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/build-with-ndk-prebuilts.md
10. `Node-API简介`（Node 18.x LTS 规范、加载与注册流程） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/napi-introduction.md
11. `Asset Store Kit简介` — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AssetStoreKit/asset-store-kit-overview.md
12. `Universal Keystore Kit简介` — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/UniversalKeystoreKit/huks-overview.md
13. 受限权限清单（`KEEP_BACKGROUND_RUNNING_SYSTEM` 等） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/restricted-permissions.md
14. `HarmonyOS 企业内部应用发布`（组织内部发布证书/Profile、资格申请、Stage 模型限制） — https://developer.huawei.com/consumer/cn/doc/app/agc-help-harmonyos-internalrelease-0000001756878768
15. AGC `应用资质要求` — https://developer.huawei.com/consumer/cn/devservice/doc/80301
16. 社区样本（Go 静态二进制在 OpenHarmony 设备上运行） — https://blog.csdn.net/yuanlulu/article/details/124758808
17. 社区样本（Wi-Fi 手动代理用于抓包，佐证系统提供 HTTP 代理设置） — https://www.cnblogs.com/baoto/p/18620918
18. `@ohos.bundle.bundleManager`（`getBundleInfo`/`getInstalledBundleList`/`getApplicationLabel`/`getBundleNameByUid`/`getSignatureInfo` 及各自权限） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-ability-kit/js-apis-bundleManager.md
19. `@ohos.net.connection`（`setAppHttpProxy` 11+、`getNetCapabilities`、`NetBearType.BEARER_VPN` 12+、`on('netCapabilitiesChange')`） — https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/js-apis-net-connection.md
20. 权限清单：`permissions-for-all.md`（normal 级，含 `INTERNET`/`GET_BUNDLE_INFO`/`GET_NETWORK_INFO`/`KEEP_BACKGROUND_RUNNING`）与 `restricted-permissions.md`（`KEEP_BACKGROUND_RUNNING_SYSTEM` 等 system_basic + ACL） — https://gitee.com/openharmony/docs/tree/master/zh-cn/application-dev/security/AccessToken

---

*下一步：本文与 `harmony-permission-checklist.md` 对齐去重后提交 R2 验收；E1~E7 验证明细移交 risk-planner 编入 PoC 清单。*
