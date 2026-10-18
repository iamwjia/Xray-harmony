# 同类客户端功能基线矩阵与差异化机会

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v0.1（初稿，功能矩阵部分待补取证） |
| 作者 | client-benchmark-analyst |
| 日期 | 2026-10-17 |
| 上游任务 | R3 |
| 下游消费方 | requirements-architect（Q1）、solution-architect（D1）、risk-planner（K1）、doc-integrator（Z1） |
| 状态 | 可用：§3 / §4 / §5 / §7 / §8 已取证；§6 矩阵部分单元格标【未核实】 |

> **本文件的定位**：不是"竞品功能罗列"，而是回答三个问题——**别人怎么实现的（架构与代价）**、**他们哪里做得不好（可引用的痛点）**、**我们凭什么能切进去（差异化机会）**。
> 每一处事实性结论都带来源；无法确认的写【未核实】，不猜。

---

## 0. 一页结论（TL;DR）

1. **HarmonyOS 上已经有跑通的 Xray 客户端，而且不止一个。** `popsiclelmlm/Hey` 是 Xray 官方 README `GUI Clients` 清单中唯一的 HarmonyOS 条目，**以 Xray 为主运行时**（sing-box 为可选第二内核），已实现 VPN 模式 + 代理模式全链路。另有 `arror/x4h`（同为 Xray-on-HarmonyOS，早期原型，5 commits）。
2. **「Go 内核编译成 .so + NAPI 同进程加载」在本平台上已被实证跑通**，不是待验证假设。cgo 契约窄到只有两个导出符号：`CGoInvoke(json)->json` 与 `CGoFree`。
3. **TUN 的接法上，有经验者选择了"不把 fd 交给内核"**：`VpnExtension` 拿 tun fd → tun2socks（gvisor 默认 / hev 备选）→ 本机 SOCKS → 内核出站。但这是**工程权衡**（双内核共用一套数据面 + 规避 gvisor 适配），**不能反推"OHOS 上 fd 直连内核不可行"**——Android 侧 `AndroidLibXrayLite` 就是 fd 直连的先例。
4. **真正的硬门槛不是 Xray，是 Go 运行时在 musl 上的 TLS 模型**。这堵墙（`GOOS=android` 必崩、`GOOS=linux` 被拒 dlopen）决定了我们必须依赖一个**个人维护的 beta 版 OHOS Go fork**。这是全项目最该被点名的隐性依赖。
5. **许可证边界是项目生命线**：Hey 本体 GPL-3.0（传染），libXray MIT，Xray-core MPL-2.0（文件级）。**思路可借鉴，Hey 的 .ets 代码不可抄**；干净路线 = `libXray(MIT) + 自研 ArkTS + 未修改的 Xray-core(MPL-2.0)`。
6. **差异化不在"多支持一个协议"，而在"可解释性"与"状态可信"**：v2rayNG 的高热 issue 集中在"连不上/不知道为什么不连上"（`io read/write on closed pipe` 反复出现）；HarmonyOS 又额外带来"进程一退 VPN 就停、无开机自启"的状态断层。这两块是现有产品都没解决好的空档，详见 §8。

---

## 1. 方法与证据边界

### 1.1 证据来源

**一手（本地源码，已克隆到 `D:\projects\xray-harmony\_research_src\`）**

| 目录 | 仓库 | 用途 | 说明 |
| --- | --- | --- | --- |
| `Hey/` | https://github.com/popsiclelmlm/Hey | **最高优先级竞品**，HarmonyOS NEXT + Xray | `git clone --depth 1` |
| `libXray/` | https://github.com/XTLS/libXray | Xray 官方维护的 embedding 库（c-shared） | 同上 |
| `AndroidLibXrayLite/` | https://github.com/2dust/AndroidLibXrayLite | Android 侧 Go 内核 + JNI 绑定先例 | 同上 |
| `v2rayNG/` | https://github.com/2dust/v2rayNG | Android 功能基线（不含 submodule 内容） | `--depth 1 --recurse-submodules=no` |

**二手（README / issue，未经源码复核的部分一律标注）**
- 各仓库 `README.md`；
- v2rayNG issue 列表（`https://github.com/2dust/v2rayNG/issues?q=is:issue+sort:comments-desc`），按评论数降序，§7 引用其编号与标题。

### 1.2 标注体系

| 标记 | 含义 |
| --- | --- |
| ✅ | 已在源码/文档中直接取证（附路径） |
| ◐ | 有间接证据（如目录存在、issue 提及），但未逐行确认 |
| ✗ | 明确不支持（有反向证据） |
| 【未核实】 | 本次未取证，**不作为结论使用** |

### 1.3 阅读范围留痕（GPL 合规用）

> 本节按 risk-planner 的要求记录，用于 GPL-3.0 衍生作品风险的抗辩基础：**只读结论、只做架构归纳，不复制代码**。

- 深读（逐行）：`Hey/entry/src/main/ets/vpn/HeyVpnAbility.ets`、`vpn/VpnConstants.ets`、`services/DiagnosticLog.ets`、`docs/building-native-cores.md`、`scripts/build_libxray_ohos.sh`（头部与 version-script 段）、`scripts/build_tun2socks_ohos.sh`（Fstat 补丁段）、`scripts/build_hev_ohos.sh`（头部）、`libXray/invoke.go`、`AndroidLibXrayLite/libv2ray_main.go`、`libv2ray_android.go`。
- 检索式浏览（grep 定位，不整文件通读）：`Hey/entry/src/main/ets/core/XrayConfig.ets`、`services/ConnectionController.ets`（VPN 启动/停止路径）。
- 只读文本：全部 `README.md`。
- **未做**：未将任何 GPL 源码复制进本项目；本文件内的代码片段仅用于说明平台机制（如 gvisor 补丁的替换语义），实现须独立编写。

---

## 2. 竞品全景

| 产品 | 平台 | 内核 | UI 技术栈 | 内核嵌入方式 | 许可证 | 与我们的关系 |
| --- | --- | --- | --- | --- | --- | --- |
| **Hey** | HarmonyOS NEXT | **Xray**（主）+ sing-box（可选） | ArkTS / ArkUI（Stage） | Go → `.so` + NAPI 同进程 | **GPL-3.0** | **同平台同内核的直接参照物**；技术可行性证明 |
| **x4h** | HarmonyOS | Xray-core | ArkTS | 未取证【未核实】 | GPL-3.0 | 同平台的第二实现，交叉验证来源 |
| **v2rayNG** | Android | Xray / v2fly | Kotlin + Android Views | Go → `.aar`（gomobile/JNI） | GPL-3.0 | 功能基线（最完整的"用户预期集合"） |
| **NekoBox** | Android | **sing-box** | Kotlin | sing-box → `libcore`（JNI） | GPL-3.0 | 功能基线 + 另一条内核路线 |
| **SFA / SFI** | Android / iOS | sing-box | Kotlin / SwiftUI | libbox（gomobile） | GPL-3.0-or-later | 内核抽象与配置模型的参考 |
| **v2rayN** | Windows | Xray / v2fly | WPF / Avalonia | 独立进程 + 本地端口 | GPL-3.0 | **反向参照**：桌面端可起子进程，我们不行 |
| Shadowrocket / Stash | iOS | 闭源 | — | 系统 NEPacketTunnelProvider | 闭源 | 仅作**体验基线**（不做功能取证） |

**一个结构性观察**：本领域几乎所有开源客户端都是 GPL 系；**唯一 MIT 的关键件是 libXray**。这直接决定了我们的架构边界（见 §3.10、§8）。

---

## 3. Hey 深度解剖（本次最高优先级竞品）

### 3.1 基本盘

| 项 | 值 | 来源 |
| --- | --- | --- |
| 定位 | "A native network tunnel and protocol debugging client for HarmonyOS NEXT. Bring your own server." | `Hey/README.md` |
| Xray 官方背书 | Xray-core `README.md` 的 `GUI Clients` → `HarmonyOS` 下唯一条目 | `_research_src/Xray-core/README.md:149-150` |
| 主运行时 | **Xray**（"The Xray path is the production path"） | `Hey/README.md` |
| 次运行时 | sing-box，可选，仅 VPN + 单出站（自述 "preview runtime"） | `Hey/README.md` |
| 内嵌内核版本 | libXray `v26.7.28` → xray-core `v1.260327.1-0.20260728075948-5ca6f4b7d4dc` | `Hey/scripts/build_libxray_ohos.sh:52`、`:32-34` |
| SDK | target `6.0.1(21)` / compatible `5.1.1(19)` | `Hey/README.md` |
| 仓库规模 | 26 commits / 40 stars / 15 forks / 单人维护 | GitHub 仓库页 |
| 分发 | **只发源码，不发 HAP**，需自备签名构建 | `Hey/README.md`（"This repository ships source code only"） |
| 许可证 | 本体 GPL-3.0；内含 Xray-core(MPL-2.0)、libXray(MIT)、sing-box(GPL-3.0-or-later)、tun2socks(MIT)、hev-socks5-tunnel(MIT) | `Hey/README.md`、`THIRD-PARTY-NOTICES.md` |

### 3.2 进程与生命周期模型

**这是对我们架构最关键的一节。**

```
┌─────────────────────────┐         Want(单向)          ┌──────────────────────────────┐
│  主进程（UIAbility）      │ ─────────────────────────► │  VPN 扩展进程（VpnExtensionAbility）│
│  ConnectionController    │  parameters: {             │  HeyVpnAbility                │
│                          │    xrayConfigJson: "<完整JSON>",│  ├─ createVpnConnection()     │
│  · 配置生成（ArkTS）       │    coreType: "xray"|"singbox"│  ├─ create(vpnConfig) → tunFd │
│  · 订阅/节点/路由 UI       │  }                          │  ├─ startNativeXray(json)     │
│  · 回前台对账              │                             │  ├─ startNativeTun2Socks(fd)  │
│                          │ ◄─────────────────────────  │  └─ 2s 统计定时器 / 5s 网络轮询  │
│  轮询读 DiagnosticLog      │   状态回传：JSONL 日志文件     │        （唯一后台存活的组件）     │
└─────────────────────────┘                             └──────────────────────────────┘
                                                                    │
                                                    ┌───────────────┴────────────────┐
                                                    │  同进程内：tun2socks ⇄ 127.0.0.1:18082 │
                                                    │           ⇄ Xray 出站           │
                                                    └────────────────────────────────┘
```

**已取证的四个关键事实：**

1. **VPN 模式下，内核运行在 VPN 扩展进程内，不在主进程。**
   主进程只做 `vpnExtension.startVpnExtensionAbility(createVpnWant(configJson))`（`Hey/entry/src/main/ets/services/ConnectionController.ets:127`），配置经 `Want.parameters.xrayConfigJson` 单向传入（`Hey/entry/src/main/ets/vpn/VpnConstants.ets:64-74`）。扩展进程内自己完成 `createVpnConnection()` → `create(vpnConfig)` 拿 `tunFd` → `startNativeXray(configJson, filesDir)` → `startNativeTun2Socks(tunFd, 127.0.0.1, 18082, mtu)`（`HeyVpnAbility.ets:88`、`:109`、`:117`、`:132`）。
   → **Xray、tun2socks、TUN fd 三者同进程**，`127.0.0.1:18082` 是**进程内 loopback**，不跨进程。
   → 这是平台逼出来的：**tun fd 只在扩展进程可拿**。

2. **代理模式（proxy-only）是例外**：主进程直接 `startNativeXray`，`tunRunning=false`（`ConnectionController.ets:231`、`:63-66`）。两种模式互斥。

3. **跨进程没有双向 IPC**。启动成败靠主进程**轮询读扩展进程写的 JSONL 日志文件**（`waitForDiagnosticEvent`，`ConnectionController.ets:131-139`，超时 10s / 12s）。日志实现是普通文件：`filesDir/hey-vpn-diagnostics.jsonl`，`fileIo` 追加写，超 256KB 截断到 160KB（`services/DiagnosticLog.ets:4-6`、`:21-31`）。**没有用 hilog 做控制信号，也没用 IPC/RPC**——是"文件当管道"的土办法。

4. **孤儿问题的方向是反的**：扩展进程本身是内核宿主，进程死则内核与 TUN 一起消失，不存在"主进程内核孤儿"。真正的代价是**主进程被回收后扩展仍存活、隧道继续跑**，主进程回前台必须重新对账（Hey 为此写了跨进程标志 `services/NetSceneStopFlag.ets`，并在日志里记录 `sessionId` 区分会话）。

**另一条与平台能力直接相关的设计**：`NetScenePoll` 用 `setInterval(5000)` 在**扩展进程内**轮询当前网络（`HeyVpnAbility.ets:36-37`、`:154-210`）。注释写明原因：**扩展进程是 HarmonyOS 唯一在后台保持存活的组件**，自驱动定时器在后台/熄屏仍会触发，而后台收不到 `connection.on` 网络变更事件。→ 这条直接印证了我们"后台能力只有扩展进程"的判断，并给出了一个可用的后台感知手段。

### 3.3 数据面（TUN 接法）

```
HarmonyOS VPN TUN fd
  → libheytun2socks.so（gvisor，默认）  或  libhevsocks5tun.so（hev，纯 C）
  → 127.0.0.1:18082（Xray 本地 SOCKS/mixed 入站）
  → Xray outbound（proxy / direct / block）
```

- 两个引擎**运行时二选一**（设置项 `useHevTun`），停止统一走 `stopNativeTun2Socks`（原生侧按引擎分发）。
- **明确不导出 `CGoSetTunFd`**：「不导出 `CGoSetTunFd`：数据面走 tun2socks，libxray 只提供本地 SOCKS 入站和测速」（`Hey/docs/building-native-cores.md:101`；另见 `build_libxray_ohos.sh:26`）。
- sing-box 同样不接管 fd：「sing-box 因此不需要把 tun fd 交给核心（无 OpenTun / gvisor tun 栈），与 Xray 路径一致」（`HeyVpnAbility.ets:112-114`）→ **"两个内核共用一套数据面"是明确的设计意图**，不是无奈之举。

**为什么最终走中继而不是 fd 直连：两条证据，务必分清"文档写的"与"推测的"**

| 解释 | 性质 | 依据 |
| --- | --- | --- |
| **① 工具链版本约束 + 构建确定性**：当时 OHOS Go fork 只到 go1.24.5，而带 `proxy/tun` 的 xray-core 要求 go1.25.7+；同时 tun2socks 的 `go.mod` 是 go1.23.4、不依赖 xray-core，**构建确定性更高** | **作者文档明写**（已逐行核实） | `Hey/docs/harmonyos-go-tls-wall.md` **§6**（版本鸿沟：`v1.250803.0` 无 `proxy/tun`，`v1.260206.0` 有但 `go.mod` 是 1.25.7）、**§7**（四条好处：tun2socks `go.mod` 1.23.4 / Xray 只需 SOCKS 入站 / 不需要 `CGoSetTunFd`+`proxy/tun`+`TunFdKey` / TLS 走 fork+TLSDESC） |
| **② 出站绕过 TUN 的 socket 约束**：全局 VPN 下内核自身出站也会被 tun 吸回，需要 `sockopt.mark` / `sockopt.interface` 之类手段把内核自己的连接摘出隧道，这在 HarmonyOS 上待验证 | **推测（合理但未证实）** | R1《xray-core-baseline》指出"真正的门槛是出站绕过 TUN"；Hey 文档未以此为由 |

> **写进 design.md 时的正确表述**：Hey 选择中继的**文档化理由是工具链版本 + 构建确定性**（①）；"出站绕过 TUN"（②）是一个**同样需要验证的独立障碍**，不能裁成"Hey 因此放弃 fd 直连"。两者都构成我们保留 B 路径时必须先做的验证项。
>
> **归因边界（已与 R1 对齐）**：`harmonyos-go-tls-wall.md` §6/§7 **通篇未提"出站绕过 TUN"**；R1《xray-core-baseline》也只把版本鸿沟与构建确定性归因给 Hey，`sockopt.mark`/`interface` 是独立的"门槛块"，未被归因为 Hey 的动机。两份文档口径一致。

### 3.4 内嵌内核与 cgo 契约

| 库 | 语言 | 导出符号 | 说明 |
| --- | --- | --- | --- |
| `libxray.so` | Go | **`CGoInvoke` / `CGoFree`**（仅此 2 个） | version-script `global: CGoInvoke; CGoFree; local: *;`（`build_libxray_ohos.sh:80-87`），链接参数 `:46` |
| `libsingbox.so` | Go | `CGoStartSingBox` / `CGoStopSingBox` / `CGoSetTunFd` / `CGoSingBoxVersion` | 第一方 wrapper `Hey/libsingbox/` |
| `libheytun2socks.so` | Go | `HeyTun2SocksStart` / `Stop` / `UploadBytes` / `DownloadBytes` | 第一方 adapter，基于 xjasonlyu/tun2socks v2.6.0 |
| `libhevsocks5tun.so` | **纯 C** | `hev_socks5_tunnel_main_from_str` / `_quit` / `_stats` | 上游 heiher/hev-socks5-tunnel 2.9.0 |

**调用信封（libXray）**：`{"apiVersion":1,"method":"…","payload":{…}}` → `{"success":bool,"data":…,"error":"…"}`，原生 JSON（非 base64）。
**方法集**（`libXray/invoke.go:37-64`）：`getFreePorts`、`decodeSubscriptionText`、`convertShareLinksToXrayJson`、`convertXrayJsonToShareLinks`、`generateAgeKeyPair`、`countGeoData`、`pingBatch`、`testXray`、`runXray`、`stopXray`、`xrayVersion`、`getXrayState`。请求/响应各限 16 MiB（`invoke.go:20-23`）。

**NAPI 侧**（`Hey/entry/src/main/cpp/napi_init.cpp`）不是简单转发，而是做了一层"语义化包装"：`PingOutbound`、`StartXray`、`StopXray`、`SetTunFd`、`GetStats`、`StartTun2Socks`、`StartHevTun`、`ValidateConfig`、`ConvertShareLinksToXrayJson` 等。**理由**：ArkTS 侧不该拼 method 字符串，也不该处理字符串生命周期（必须 `CGoFree`，不能用 `std::free`）。

### 3.5 配置生成策略

- **唯一事实源是内核原生 JSON**，由 ArkTS 侧生成：`core/XrayConfig.ets`（inbounds / outbounds / routing / dns / fakedns / metrics / sockopt 全套结构在 `:181-278`）。
- 生成结果**先过校验再启动**：`ValidateConfig`（`napi_init.cpp:970`）与 `testXray`。
- 本地 SOCKS 入站在 `127.0.0.1:18082`（`XrayConfig.ets:383-384`）。
  **端口版本提示**：`18082` 是**当前**取值（README "Current State" 与 `XrayConfig.ets` 一致）；`docs/harmonyos-go-tls-wall.md` §7/§8 里出现的 `10810` 是 2026-06 的历史快照，不要与当前值混引。
- 流量统计走 **Xray 自带 metrics（expvar）**：额外生成一个 dokodemo 入站 + 优先级最高的路由规则，把 metrics handler 暴露到 `http://127.0.0.1:18086/debug/vars`（`XrayConfig.ets:385-392`、`:1878-1893`）。**这是个很巧的做法**——不依赖 gRPC API，只用一份配置就拿到 per-tag 计数。
- 计算属性 `metricsServer` 仅在开启测速时注入（`XrayConfig.ets:1953`），关闭即不生成入站 → 少一个攻击面。

### 3.6 日志与统计

- 双通道：`hilog`（系统日志）+ 自建 JSONL 诊断日志（可导出、可轮转）。
- 统计：扩展进程内 2s 定时器采集（`HeyVpnAbility.ets:35`、`:265-302`），**优先读 Xray metrics 端点，失败回退到原生桥自己的计数**。
- 日志来源分级：`vpn` / `vpn-stats` / `core`（`CoreLogReader.ets`）。

### 3.7 功能完成度（做完了什么）

据 `Hey/README.md`「Implemented In Code」+ 源码目录结构（`Hey/entry/src/main/ets/`）：

| 能力 | 状态 | 取证 |
| --- | --- | --- |
| 节点/订阅管理 | ✅ 多订阅组、组内选中节点、自定义 UA、过滤、前后置字段、手动/到期/WorkScheduler 后台刷新、搜索排序清理 | `README.md`；`features/subscriptions/` |
| 导入 | ✅ 订阅 URL、v2rayN plain/base64、Xray outbound/完整 JSON、Clash 风格 YAML 代理条目、WireGuard 配置、二维码、系统分享文本、10+ 协议深链 | `README.md`；`core/ShareLinkParser.ets` |
| 导出 | ✅ 分享链接、二维码、路由规则 JSON、全量本地备份 JSON | `README.md` |
| 测速 | ✅ 真实延迟测试（走原生桥，非 ICMP 假 ping） | `README.md`；`services/DelayTester.ets` |
| 路由分流 | ✅ 流量模式、域名策略、用户自写规则集、锁定规则、process/port/network/protocol 匹配、规则导入导出 | `README.md`；`core/RoutingRules.ets` |
| DNS / FakeDNS | ✅ DNS 字段、FakeDNS 池、sniffing（含 `routeOnly`） | `XrayConfig.ets:219`、`:277`、`:2237-2240`、`:2777-2798` |
| TUN / 系统代理 | ✅ VPN 模式（tun2socks 中继）+ 代理模式（本地 SOCKS/HTTP） | `HeyVpnAbility.ets`；`README.md` |
| 分应用代理 | ◐ allow/bypass 两模式 + 手填包名；**但 HarmonyOS 不向三方应用暴露已安装应用枚举**，只能手输或从内置少量常用包名里选 | `README.md`；`core/PerAppProxy.ets`；`pages/PerApp.ets` |
| 快捷开关/桌面卡片 | ✅ 桌面卡片（Form）+ 桌面快捷方式 + `hey://` 深链 + 系统分享导入 | `controlcardability/ControlCardAbility.ets`；`core/ControlCard.ets` |
| 日志与流量统计 | ✅ 见 §3.6 | `services/DiagnosticLog.ets`；`features/logs/` |
| 配置导入导出/多配置切换 | ✅ JSON 导入、备份/恢复、多订阅组切换 | `README.md`；`services/BackupManager.ets` |
| 网络场景自动化 | ✅ 可信 Wi-Fi SSID 列表 + 蜂窝开关，**只自动断开不自动连接** | `README.md`；`pages/NetworkScenario.ets` |
| 多语言 | ✅ 中/英 + 更多 | `core/I18n.ets`；`pages/Language.ets` |
| 双内核切换 | ◐ Xray 完整；sing-box 仅 VPN + 单出站，无策略组/代理链/完整配置/流量统计 | `README.md`「Known Limits」 |

**覆盖率判断**：以 v2rayNG 的功能集为分母，Hey 覆盖约 **80%**，缺口集中在"内置规则集/内置订阅源"（这是它**刻意的设计原则**，不是没做完）与 sing-box 路径的完整度。

### 3.8 明确没做的（及其性质）

`Hey/README.md` 的 `Design Principle` 写得很硬：「**Ship no intended use. Let the user work it out.**」——凡属"App 替用户做决定"的功能一律不做：

- 不内置任何服务器地址、订阅源、规则集、地区/国家预设；
- 出厂默认的测速 URL、出口地址查询、所有 DNS 字段**全为空**；
- 深链/分享/扫码一律"先展示完整目标，再等用户显式确认"，不静默添加或请求；
- 无法枚举已安装应用 → 分应用页面只给"输入提示"，不做自动列表。

**评价**：这是一套**面向"自备服务器的技术用户"**的产品哲学，把"合规与责任"降到了最低（不提供任何可用目标），但也**主动放弃了大众用户**。我们的产品定位不同（见 §8.5），所以这块不应照抄。

### 3.9 成熟度评级（我的判断）

| 维度 | 评级 | 依据 |
| --- | --- | --- |
| 功能完整度 | **高**（同类 80%） | §3.7 |
| 工程严谨度 | **高** | 构建脚本自带产物校验（`nm -D` / `strings` / `readelf` 三段核验，`build_libxray_ohos.sh:32-34`）、坑位写成文档（`docs/` 三篇）、脚本里有 `compliance_scan.sh` 守"措辞合规" |
| 生产可用性 | **中** | 只发源码、无 release、无真机矩阵、单人维护、40 star；自述「仍需更多真机与系统版本覆盖」 |
| 可复现性 | **中高** | 构建链完整可复现，但依赖**个人 beta 版 Go fork**（§3.11） |
| 对我们的价值 | **极高** | 它不是"产品竞品"，是**技术可行性证明 + 踩坑地图**：别人用几天踩出来的坑，文档里有 3 篇 |

**一句话**：**它证明"能做成"，但没证明"能卖"**。技术上我们不必再怀疑 Go 内核能不能上 HarmonyOS；产品上它主动放弃了大众市场，那正是我们的空间。

### 3.10 可直接借鉴 vs 不可借鉴（GPL 边界）

| 类别 | 内容 | 是否可用 |
| --- | --- | --- |
| **可借鉴（思路/架构/结论）** | 进程模型、数据面选型、cgo 契约设计、构建链组织、坑位清单、IPv6 路由写法、metrics 走 expvar 的取巧方式 | ✅ 可用于设计 |
| **不可抄（代码）** | 任何 `.ets` / `.ts` / `.cpp` / `.sh` 源码 | ❌ GPL-3.0 传染 |
| **可直接用（第三方 MIT/MPL）** | libXray（MIT）、tun2socks（MIT）、hev-socks5-tunnel（MIT）、Xray-core（MPL-2.0，未修改文件可分发） | ✅ 但需自行集成与留痕 |

### 3.11 隐性依赖（必须上报的风险）

**我们能编译出可用的 libxray.so，依赖一个个人维护的 beta 版 Go 工具链。**

- 原理：HarmonyOS 用 **musl** libc。Go 在 arm64 上存 goroutine 指针 `g` 的 TLS 模型决定了 c-shared 库能否被 `dlopen`、外来线程能否调 cgo：

  | 编法 | `g` 存在哪 | 在 HarmonyOS(musl) 上的结果 |
  | --- | --- | --- |
  | 标准 Go + `GOOS=android` | bionic 固定 TLS 槽 | `dlopen` 能过，但外来线程那个槽是垃圾 → **cgo→Go SIGSEGV** |
  | 标准 Go + `GOOS=linux` | initial-exec TLS | musl **拒绝 dlopen** 含 IE-TLS 的库 → 原生桥整体加载失败 |
  | **OHOS fork + `GOOS=openharmony`** | **TLSDESC** | `dlopen` 能过 **且**外来线程 cgo 正常 ✅ |

- 现役工具链：`star4277/ohos-go` **v1.26.5-beta1**（第三方 fork，在 openharmony-sig go1.24 树上 merge go1.26.5）。
- 官方 fork 封顶 **go1.24.5**，**编不动** libXray 主线（需要 go1.26）。
- 必须配 `CGO_CFLAGS="-ftls-model=global-dynamic"`；**不能加 `-tags netgo`**（openharmony 的 net 端口需要 cgo，加了会 `_C_getifaddrs undefined`）。

> 来源：`Hey/docs/building-native-cores.md` §1、§2.3、`harmonyos-go-tls-wall.md`。

**风险定性**：这不是"工具链选择问题"，是**供应链单点**——该 fork 停更/不跟上游，我们就被锁死在当前 Xray 版本上。缓解见 §9。

---

## 4. TUN 接入方式横向对比

### 4.1 三种形态

| 形态 | 定义 | 代表 |
| --- | --- | --- |
| **A. 系统 VPN + tun2socks 中继** | 系统给 tun fd → 用户态 tun2socks 栈 → 本地 SOCKS → 内核 | **Hey**（OHOS）、v2rayNG 的 hev/badvpn 路径 |
| **B. 系统 VPN + fd 直连内核** | 系统给 tun fd → 直接交给内核自身的 TUN 入站 | **AndroidLibXrayLite**（env `xray.tun.fd`）、sing-box 的 `OpenTun`/gvisor 栈 |
| **C. 仅本地代理端口** | 不起 VPN，只在 `127.0.0.1` 开 SOCKS/HTTP，由系统代理或他应用接入 | Hey 的 proxy-only 模式、v2rayN 桌面默认 |

### 4.2 体验代价对比

| 维度 | A. tun2socks 中继 | B. fd 直连内核 | C. 仅本地端口 |
| --- | --- | --- | --- |
| 全局接管 | ✅ 系统级 | ✅ 系统级 | ❌ 需应用自己支持代理 |
| 分应用 | ✅ 靠 VPN 配置的 allow/bypass 列表 | ✅ 同 A | ❌ 无 |
| 数据路径 | 多一跳用户态转发（tun→stack→socks→内核） | 少一跳 | 无 tun 开销 |
| 吞吐/延迟 | 略低（多一次内存拷贝与协议解析） | 更优 | 最优（但只覆盖支持代理的应用） |
| UDP/QUIC | 依赖 tun2socks 栈的 UDP 实现（gvisor 支持，但需验证） | 由内核自身处理 | 取决于应用 |
| fd 约束 | 只要 fd 能读写在同进程即可 | **fd 跨进程传递 + 内核需适配 Fstat**（OHOS VPN fd 拒 `Fstat`，见 §9-K3） | 无 |
| 实现复杂度 | 中（多一个 .so） | 低（少一个 .so）但踩坑深 | 低 |
| 可替换性 | 高（引擎可换：gvisor / hev），**可做降级兜底** | 低（与内核绑定） | — |
| 双内核支持 | ✅ 一套数据面服务两个内核 | ❌ 每个内核各自实现 | ✅ |
| 已知失败形态 | 引擎 `log.Fatal` 自杀（补丁未命中） | 内核 TUN 入站初始化失败 / 不可用 | 应用不认代理 → "没网" |

### 4.3 结论

- **不要把 A 与 B 写成"对错"，它们是权衡。**
  - A 的收益：**一套数据面服务两个内核**（Hey 正是这么设计的，`HeyVpnAbility.ets:112-114`）、引擎可换、失败可降级；代价：多一跳、多一个 .so、需要 gvisor 补丁。
  - B 的收益：路径短、少一个组件；代价：与内核强绑定、需要 fd 跨进程或同进程、需要内核适配 OHOS fd 的 `Fstat` 拒绝行为。
- **Android 侧 B 有先例**（`AndroidLibXrayLite.StartLoop(config, tunFd)` → `xray.tun.fd`），所以**不能写"B 在 OHOS 上已被否决"**，只能写"未在 OHOS 上验证"。
- **建议**：默认 A（有 OHOS 先例、可降级），B 保留为待验证候选（PoC 里的对照实验）。
- **C 不能作为主形态**（无全局接管、无分应用），但**应保留为降级模式**（VPN 授权失败 / 扩展进程不可用时的兜底，等价于 Hey 的 proxy-only）。

---

## 5. 内核绑定方式对比（移动端 Go 内核 embedding）

| 项目 | 绑定形态 | 导出面 | 配置怎么传 | 日志/统计怎么拿 | fd 怎么传 |
| --- | --- | --- | --- | --- | --- |
| **libXray** | Go `-buildmode=c-shared`，通用分发入口 | `CGoInvoke(json)/CGoFree` | JSON 请求体内 `payload.xrayJson` | 返回值 + 应用侧轮询 `pingBatch`；**metrics 需自己开 expvar 入站** | 不提供（设计上不接管 TUN） |
| **AndroidLibXrayLite** | gomobile bind（`.aar`/JNI） | 每能力一个方法（`StartLoop`/`StopLoop`/`QueryStats`/`MeasureOutboundDelay`…） + `CoreCallbackHandler` 接口回调 | `StartLoop(configContent, tunFd)` 直接传字符串 | `CoreCallbackHandler.Startup/Shutdown/OnEmitStatus` 回调 + `statsManager` | **`tunFd int32` 参数 → env `xray.tun.fd`** |
| **Hey（我们的参照）** | libXray 的 `.so` + **自写 C++ NAPI 包装层** | NAPI 语义化方法（`StartXray`/`PingOutbound`/`GetStats`…） | 主进程生成的完整 JSON，经 `Want` 传入扩展进程 | 2s 轮询 expvar `/debug/vars`，失败回退原生计数 | fd 给 tun2socks，不给内核 |
| **NekoBox** | sing-box `libcore`（JNI） | Kotlin 侧薄封装 | 完整 JSON | sing-box 自身统计 | 内置（sing-box 自有 tun 栈） |
| **v2rayNG** | AndroidLibXrayLite `.aar` | 同上 | 模板 + 参数替换后生成 JSON | `CoreCallbackHandler` + 自建统计 | fd 直连（`xray.tun.fd`） |

**三条可复用的设计结论：**

1. **"窄契约 + JSON 信封"优于"宽 API + 每能力一函数"**：libXray 只有 2 个导出符号，加方法不改 ABI、不改符号表，非常适合我们这种"内核版本会持续升级"的场景。
2. **必须有明确的字符串生命周期约定**：`CGoFree` 释放，禁止 `std::free`（`building-native-cores.md:100`）。这类细节不写进设计文档，后来人一定会踩。
3. **统计不建议自己做计数器**：内核侧 metrics 才是真相。Hey 用"额外一个 dokodemo 入站 + 最高优先级路由规则"把 expvar 暴露在本机端口，是个成本极低且不改内核的实现路径。
4. **libXray 没有 ohos 构建目标，且明确不保证 API 稳定性**（只兼容 Xray-core 最新 release；构建 target 只有 `android`/`apple`/`linux`/`windows`）——来源：R1 交接 §2。**结论：我们只能借它的 `cgo_bridge/` 结构与导出面设计，产物必须自建 `-buildmode=c-shared`**。这也意味着我们的构建链要自己维护"libXray 版本 ↔ xray-core 版本 ↔ Go 工具链版本"的三方对齐表。
5. **切节点大多需要重启内核**：Xray 的 gRPC 控制面没有"改 outbound 地址"原语，也没有整体配置热重载（DNS/policy/FakeDNS 改动更是必须重启）。所以客户端只有两条路：`停核 → 重载 JSON → 起核`，或**启动时预置全部候选 outbound + 靠 balancer 切换**。后者是低延迟切换的正解，也是我们做"快速切换节点"体验的关键设计点（来源：R1 交接 §3.2）。

---

## 6. 功能矩阵

> 图例：✅ 有（已取证） / ◐ 部分、需插件或条件受限 / ✗ 明确无 / 【未核实】 / — 不适用
> 每行末尾给出该行的主要来源。"Hey" 列取证最充分，"v2rayNG" 列以 Cloned 源码目录 + issue 交叉佐证，"NekoBox/SFA" 列部分依赖 README，未逐条取证。

| 功能 | v2rayNG | NekoBox | SFA/SFI | v2rayN(桌面) | **Hey(OHOS)** | 来源 |
| --- | --- | --- | --- | --- | --- | --- |
| 订阅：单链接/base64 | ✅ | ✅ | ✅ | ✅ | ✅ | v2rayNG `ui/subscription/`；NekoBox README（支持 v2rayN 格式）；Hey README |
| 订阅：Clash 订阅 | ◐ 需转换 | ✅ | ◐ | ◐ | ◐ 仅解析 Clash 风格 **proxy 条目**，不解析完整 Clash 配置 | NekoBox README；Hey README（"Clash-style YAML proxy entries"） |
| 订阅：分组/自动刷新 | ✅ | ✅ | ✅ | ✅ | ✅ 多组 + WorkScheduler 后台刷新 + 到期刷新 | Hey `features/subscriptions/`、`SubscriptionSchedulerPlan.ets` |
| 节点测速/延迟 | ✅ 含"真连接"测试 | ✅ | ✅ | ✅ | ✅ 真实延迟（走原生桥） | v2rayNG issue #782/#6089；Hey `services/DelayTester.ets` |
| 路由：域名/IP/GeoIP/geosite | ✅ | ✅ | ✅ | ✅ | ◐ 引擎支持，但**不内置任何规则集**，全部用户手写 | v2rayNG `ui/routing/`；Hey README「ships no built-in region or country rule sets」 |
| 路由：应用分流 | ✅ | ✅ | ✅ | — | ◐ 两模式可配，但**无法枚举已安装应用**，只能手填包名 | v2rayNG `ui/perappproxy/`；Hey README |
| DNS 自定义 | ✅ | ✅ | ✅ | ✅ | ✅ | Hey `core/DnsAddresses.ets`、`XrayConfig.ets:219` |
| FakeDNS | ◐【未核实】 | ✅ | ✅ | ◐【未核实】 | ✅ 含"空域名列表会被内核判非法"的规避处理 | Hey `XrayConfig.ets:2237-2240` |
| TUN / 系统代理 | ✅ 两者 | ✅（VPN） | ✅（VPN） | ◐ 桌面无 TUN，靠端口+系统代理 | ✅ VPN + 代理双模式 | 见 §4 |
| 分应用代理 | ✅ | ✅ | ✅ | — | ◐ 同"路由：应用分流" | 同上 |
| 快捷开关/桌面卡片 | ✅ 快捷方式/磁贴 | ◐ | ◐ | — | ✅ 桌面卡片(Form) + 快捷方式 + 深链 | v2rayNG `ui/shortcut/`；Hey `ControlCardAbility.ets` |
| 日志与流量统计 | ✅ | ✅ | ✅ | ✅ | ✅ 双通道日志 + 2s 统计（优先内核 metrics） | v2rayNG `ui/logcat/`；Hey §3.6 |
| 配置导入导出 | ✅ | ✅ | ✅ | ✅ | ✅ JSON 导入、分享链接导出、全量备份/恢复 | Hey `services/BackupManager.ets`、`pages/Backup.ets` |
| 多配置/多节点切换 | ✅ | ✅ | ✅ | ✅ | ✅ 多订阅组 + 组内选中 | Hey `features/subscriptions/` |
| **切节点是否需重启内核** | **是**（无"改 outbound 地址"原语） | **是** | **是** | 是 | **是**（重新生成 JSON → 停核 → 起核） | R1 交接 §3.2：gRPC 只能增删 inbound/outbound、加删用户/单条路由，**无热重载** |
| 网络变化自动处理 | ✅ | ✅ | ✅ | — | ◐ 仅"可信网络自动断开"，**不自动连** | Hey README |
| 开机自启 | ✅ | ✅ | ◐ | ✅ | ✗ 平台不提供（三方应用无开机自启） | 平台约束（见 `harmony-platform-constraints.md`） |
| 按流量计费/月度统计 | ◐ | ◐ | ◐ | ✅ | ✅ 持久化流量合计 | Hey README「persistent traffic totals」 |
| 多语言 | ✅ | ✅ | ✅ | ✅ | ✅ | Hey `core/I18n.ets` |
| 双内核切换 | ✅ Xray/v2fly | ✗（sing-box） | ✗ | ✅ | ◐ Xray 完整 / sing-box 预览 | Hey README |

**矩阵的读法（比答案更重要）**：
- **不存在"别人有我们没有"的核心缺口**——除了"内置规则集/内置订阅源"（Hey 刻意不做，v2rayNG/NekoBox 做了）。
- **OHOS 侧的两处真实退化**是平台性的，不是实现懒惰：**开机自启（无）+ 已安装应用枚举（无）**。这两条必须写进需求的范围边界，不能承诺。
- 表格里 **FakeDNS / v2rayN 桌面 TUN** 等若干单元格标了【未核实】——v0.2 补取证后再定稿，不要据此做需求取舍。

> ⚠️ **本矩阵刻意不含"传输协议支持"列**。原因不是"传输都废了"，而是**传输已分成两档，按老清单打勾会失真**（判据：GA v26.3.27，R1 源码核实）：
> - **已移除**：`quic` / `h2` / `h3` / `http` —— 配置加载**直接报错**（`infra/conf/transport_internet.go:1013-1017` → `PrintRemovedFeatureError` 并返回 error），不是"能用但有警告"。
> - **deprecated 但可用**：`ws` / `grpc` / `httpupgrade` —— `PrintNonRemovalDeprecatedFeatureWarning(...)` 后 **`return "grpc", nil`**（`:1006-1011`，函数名里的 "NonRemoval" 就是判据），**仅启动告警**；上游建议迁 XHTTP。
> - 主线是 **XHTTP**；REALITY 仅支持 `raw`/`xhttp`/`grpc`。
>
> **对需求文档的直接结论**：竞品"支持 ws/grpc 节点"是**真实能力**，绝不能记成"已废弃"——ws/grpc 是绝大多数机场的实际传输，漏掉它会直接造成用户可感知的功能缺失。协议/传输清单必须锚定具体内核版本（GA vs HEAD 要求不同 Go 版本）。

---

## 7. 用户痛点（带来源）

> 方法：以 v2rayNG 的 issue 列表（按评论数降序）为"用户预期集合"的代表样本；分类维度是**设计缺陷 / 平台限制 / 生态问题**——因为三者的应对完全不同。

### 7.1 实证样本（v2rayNG，按评论数）

| # | 标题（原文） | 评论 | 归属 | 我们的解读 |
| --- | --- | --- | --- | --- |
| [#5457](https://github.com/2dust/v2rayNG/issues/5457) | [Feature Request] Don't expose socks5 port, protect TUN | **347** | **设计缺陷（安全）** | 本地 SOCKS 端口对同机任意应用开放 = 任何人装了你的客户端就能白嫖代理。**这是"本地端口"形态的固有代价**，我们需要默认端口随机化 + 访问控制/鉴权，而不是"开个 10808"。 |
| [#930](https://github.com/2dust/v2rayNG/issues/930) | 应用被小米手机加入"广告"（被系统判为风险应用） | 92 | **平台限制（生态）** | 国产 ROM 的合规/风控会把代理类应用标记为风险。上架审核与厂商白名单是**产品级风险**，不是技术问题。 |
| [#1346](https://github.com/2dust/v2rayNG/issues/1346) | 同样的节点，电脑可以使用，手机上不行 | 92 | 设计缺陷（诊断能力缺失） | **"能用/不能用"无法归因**是最大的体验黑洞。 |
| [#268](https://github.com/2dust/v2rayNG/issues/268) | 测试失败 `io read/write on closed pipe` | 63 | 设计缺陷（错误信息不可行动） | 内核错误直出用户，用户无从下手。 |
| [#2729](https://github.com/2dust/v2rayNG/issues/2729) | 升级到 1.8.12+ 后部分原来可用的节点无法使用 | 58 | 设计缺陷（升级回归） | **内核/配置升级会静默打断存量配置**，必须有兼容层与回滚。 |
| [#149](https://github.com/2dust/v2rayNG/issues/149) | EMUI 10 上无法正确开启 VPN 连接 | 48 | 平台限制（厂商实现差异） | 系统 VPN 能力在不同 ROM/版本上行为不一致 → **OHOS 上必须按系统版本做能力门禁**。 |
| [#2044](https://github.com/2dust/v2rayNG/issues/2044) | 路由"绕过大陆"时远程 DNS 用 1.1.1.1 导致完全无法上网（境内被墙） | 42 | 设计缺陷（默认值危险） | **错误的默认 DNS 会让人"连上了但没网"**，比连不上更难排查。默认值必须安全且可解释。 |
| [#782](https://github.com/2dust/v2rayNG/issues/782) | 点击"测试真连接"就崩溃 | 34 | 稳定性缺陷 | 测速路径是崩溃高发区（并发/生命周期管理）。 |
| [#4520](https://github.com/2dust/v2rayNG/issues/4520) | badvpn low performance | 27 | 架构缺陷（数据面性能） | 用户能感知 tun2socks 引擎的差异 → **数据面引擎是可感知的产品质量**，不是内部实现。 |
| [#4672](https://github.com/2dust/v2rayNG/issues/4672) | DNS hosts 无法作用于节点服务器地址 | 25 | 设计缺陷（分层不一致） | "DNS 设置"只对流量生效、不对节点解析生效 → 用户心智模型被打断。 |
| [#6089](https://github.com/2dust/v2rayNG/issues/6089) | Delay test UI bug | 25 | 界面缺陷 | 测速结果与 UI 状态不一致（又是"状态不可信"）。 |
| [#4641](https://github.com/2dust/v2rayNG/issues/4641) | 长时间运行后 CPU 占用异常 | 23 | 稳定性缺陷 | **长跑退化**。我们"打开即用、断开可恢复"的主张必须包含"不因长跑而崩"。 |
| [#403](https://github.com/2dust/v2rayNG/issues/403) | Android 10 下 FCM 经常断开连接 | 23 | 平台限制（通知通道） | 全局 VPN 会威胁推送通道 → **OHOS 上要预判 Push Kit 的影响并设计旁路**。 |
| [#5057](https://github.com/2dust/v2rayNG/issues/5057) | hev-socks5-tunnel stops working after a while | 22 | 稳定性缺陷（引擎） | **tun2socks 引擎会"跑着跑着死掉"**——正是 risk-planner 要区分的第二类失败形态。 |
| [#1499](https://github.com/2dust/v2rayNG/issues/1499) | ping 为 -1，报 `IO read/write on closed pipe` | 30 | 设计缺陷（诊断） | 同 #268，反复出现说明**从未被系统性解决**。 |
| [#5519](https://github.com/2dust/v2rayNG/issues/5519) | 增加 Browser Dialer 支持 | 32 | 功能缺口 | 高级用户要的"反指纹"能力，桌面端有、移动端没有。 |
| [#31](https://github.com/2dust/v2rayNG/issues/31) | 希望支持 Android TV | 32 | 形态扩展 | 形态需求（TV/车机）值得在路线图里留位，但非 MVP。 |

### 7.2 分类归纳（决定应对方式）

| 类别 | 占比（本样本） | 典型表现 | 应对方式 |
| --- | --- | --- | --- |
| **设计缺陷：可解释性** | 高 | #1346 / #268 / #1499 / #2729 / #6089 | **可以靠产品设计解决**——这是我们的主要机会（§8.1） |
| **设计缺陷：默认值危险** | 中 | #2044 / #4672 | 靠"安全默认 + 显式提示"解决 |
| **稳定性：长跑/引擎** | 中 | #4641 / #5057 / #782 | 靠工程纪律 + 看门狗 + 引擎可替换（§4 的 A 形态天然支持降级） |
| **平台限制** | 中 | #930 / #149 / #403 / 开机自启 / 应用枚举 | **不能靠产品解决**，只能范围外承认 + 设计绕行 |
| **形态扩展** | 低 | #31 / #5519 | 路线图留位，不进 MVP |

### 7.3 映射到 HarmonyOS：哪些痛点在 OHOS 上会更痛

| 痛点 | OHOS 上更痛还是更轻 | 原因 |
| --- | --- | --- |
| 本地 SOCKS 端口暴露（#5457） | **更痛** | tun2socks 中继架构**必然**开本地端口（Hey 用固定 18082），暴露面比"只监听用户显式开启的代理模式"更大 |
| 连不上无法归因（#1346/#268） | **更痛** | OHOS 生态新、用户与资料都少；日志拿取门槛更高（hilog 需要工具链） |
| 长跑退化（#4641） | **更痛** | 扩展进程是唯一后台存活组件，一旦退化没有"重启应用"的廉价恢复路径 |
| 推送通道被 VPN 影响（#403） | **待验证** | HarmonyOS Push Kit 与 VPN 的交互本次未取证【未核实】，需 PoC |
| 开机自启 | **更痛** | 平台直接不支持，只能靠"打开即用"弥补 |
| 分应用枚举 | **更痛** | 平台不暴露，产品只能接受"手填包名"的次优体验，或与系统能力方合作 |

---

## 8. 差异化机会（5 条）

> 每条四要素：**解决谁的什么问题 / 为什么现有产品没做好 / 我们凭什么能做 / 风险与代价**。
> 排序按"证据强度 × 我们可行性"。

### 8.1 「连不上」要能说清为什么——结构化连接诊断

- **谁的什么问题**：所有"节点在电脑上能用、在手机上不行"的用户（v2rayNG #1346，92 评论；#268/#1499 `io read/write on closed pipe` 反复出现）。他们要的不是更长的日志，是**一句可行动的结论**。
- **为什么现有产品没做好**：现有客户端把内核错误原样透出（`io read/write on closed pipe` 是典型的内核内部错误码），用户与错误码之间没有翻译层。Hey 做到了"结构化诊断日志"（JSONL + 分级 + 可导出），但**没有做错误归因**——它的日志是给人看的，不是给系统判断的。
- **我们凭什么能做**：Xray-core 的错误是可分类的（DNS 解析失败 / TLS 握手超时 / 被 RST / 时间不同步 / 出站不可达），而我们在**同进程内**持有内核（NAPI），可以拿到 `CGoInvoke` 返回的结构化 error，不需要解析日志文本。**这是"同进程嵌入"带来的、WebView/子进程架构拿不到的信息优势。**
- **风险**：错误分类表需要长期积累；过度翻译会掩盖真相 → 设计上"默认给结论，可展开原始错误"。

### 8.2 配置即真相：可视化编辑与原内核 JSON 双向一致

- **谁的什么问题**：高级用户在 GUI 里找不到某个字段，就去改 JSON，然后被 GUI 下一次保存覆盖掉；或反过来，GUI 设置的 DNS 不作用于节点解析（v2rayNG #4672，25 评论）。本质是**GUI 与配置文件两套模型**。
- **为什么现有产品没做好**：v2rayNG 走"模板 + 参数替换"，NekoBox 只解析 outbound（README 明示"分流规则等信息会被忽略"），GUI 天然只能覆盖模板内的字段。Hey 走的是另一条路——**ArkTS 直接生成完整内核 JSON**（`XrayConfig.ets`），并且提供 `ValidateConfig`、JSON 导入、完整配置导出。**Hey 这条是对的**，但它对"用户自写高级字段"的支持仍以"导入完整 JSON"为主。
- **我们凭什么能做**：我们可以采用"JSON 是唯一事实源、UI 是它的投影"这一模型（Hey 已验证可行），并往前走一步：**任何 UI 表达不了的字段，以"高级字段"形式原地编辑并回写 JSON**，杜绝覆盖。
- **风险**：JSON schema 演进（Xray 升级）需要迁移层；"自由编辑"会带来非法配置 → 必须有校验 + 可回滚（`testXray` 先行、失败不落地）。

### 8.3 规则与订阅的"可解释性"：告诉我这条连接为什么走了代理

- **谁的什么问题**：用户配了一堆规则，但不知道某次访问命中了哪一条；出问题时只能全关重试。国内用户的"分流不准"抱怨大多源于此。
- **为什么现有产品没做好**：分流是黑盒。v2rayNG/NekoBox 提供规则编辑与日志，但**没有"连接 → 命中规则"的可视映射**；Hey 甚至完全不内置规则集（设计原则），把这件事完全推给用户，进一步抬高门槛。
- **我们凭什么能做**：Xray-core 的 routing 日志/sniffing 结果在同进程可获取，且 Hey 已经证明"额外生成一个入站 + 路由规则"的取巧方式可行（metrics 就是这么接的）——同样的手法可以把"规则命中"变成结构化事件，而不是人肉读日志。
- **风险**：per-connection 记录有性能与隐私成本 → 默认关闭、仅调试时开启、只留最近 N 条。

### 8.4 「打开即用、断开可恢复」：把平台短板变成产品语言

- **谁的什么问题**：HarmonyOS 上没有开机自启、进程退出即停 VPN、长时任务无 vpn 类型。用户离开应用就断，回来状态还不一定对（v2rayNG 侧的对应痛点是 #6089 状态不一致、#4641 长跑退化）。
- **为什么现有产品没做好**：Android 客户端把"自启 + 常驻"当默认能力，产品叙事是"装好就不用管"；这个叙事在 OHOS 上不成立，而**目前没有产品为"不能常驻"重新设计交互**。Hey 有桌面卡片 + 快捷方式 + 深链（降低重连成本），也有跨进程状态对账（`NetSceneStopFlag`），但整体仍是"技术用户自己管"。
- **我们凭什么能做**：把"断"设计成常态而非故障：**一键恢复**（卡片/快捷方式/深链）+ **回前台先对账再渲染**（禁止沿用缓存状态）+ **扩展进程内的断线重连与看门狗**（扩展进程是唯一后台存活组件，这是 Hey 已验证的可用阵地）。
- **风险**：这些都需要"真实状态可读"，而 Hey 的实现是"日志文件轮询"这种脆弱办法 → **必须用正式 IPC + 显式超时对账**（这正是 solution-architect 的 D-30）。

### 8.5 面向"非技术用户"的默认值安全感（产品定位差异化）

- **谁的什么问题**：大众用户不理解"DNS 策略 / 域名解析 / 分流"，却会被默认值坑（v2rayNG #2044：默认远程 DNS 1.1.1.1 在境内被墙 → 连上了但没网）。
- **为什么现有产品没做好**：这个赛道的开源产品普遍面向技术用户，Hey 甚至把"由用户决定"写成了设计原则（`Ship no intended use`），**主动放弃大众市场**。这是它最明确的产品边界，也正是我们的空间。
- **我们凭什么能做**：我们可以做"有主张的默认值"——安全默认 DNS、离线可用的规则集、开箱可用的分流，同时保证**每一个默认值都可解释、可关闭**（避免变成另一种黑盒）。
- **风险**：**合规与责任**——内置规则集/预设会提高我们的内容责任；需与合规方确认边界（Hey 的 `compliance_scan.sh` 思路可借鉴：把"我们不提供任何目标"变成可执行的检查）。

### 8.6 明确不做的（负向差异化，同样重要）

| 不做 | 原因 |
| --- | --- |
| 不内置任何服务器/订阅源/节点分享 | 合规红线，且 Hey 已证明"不带目标"是可行的产品形态 |
| 不做节点测速排名/社区 | 同上 |
| 不承诺后台常驻/开机自启 | 平台不支持，承诺即违约 |
| 不抄 Hey 的 .ets 代码 | GPL-3.0 传染 |

---

## 9. 已知坑清单（跨项目可复用）

> 这些是别处踩过的坑，写在这里能省后来者几天。每条都有来源。

| # | 坑 | 现象 | 规避 | 来源 |
| --- | --- | --- | --- | --- |
| K1 | **Go-on-musl 的 TLS 墙** | `GOOS=android` 编出的 so 能 dlopen，外来线程调 cgo 必 SIGSEGV；`GOOS=linux` 的 IE-TLS 被 musl 拒绝 dlopen | 用带 TLSDESC 的 OHOS Go fork + `GOOS=openharmony` + `-ftls-model=global-dynamic`；禁用 `netgo` | `Hey/docs/building-native-cores.md` §1、§2.3 |
| K2 | **`dlopen` 之后禁止 `setenv`** | C 侧 `setenv` 导致 musl realloc `environ`，Go 初始化线程读到野指针 → **非主线程 SIGSEGV** | 所有要传给 Go 的环境变量（如 `XRAY_LOCATION_ASSET`）必须在**首次 dlopen 之前**设好；运行期参数走函数入参/JSON | `building-native-cores.md` §5 |
| K3 | **OHOS VPN fd 拒 `Fstat`**（但 readv/writev 正常） | gvisor fdbased 用 `unix.Fstat` 判断是否 socket，失败 → `engine.Start()` 直接 `log.Fatal` **杀整个进程** | 打补丁把 `isSocketFD` 改为 `return false, nil`（强制走非 socket Readv dispatcher）；补丁失配要报错退出而不是静默 | `Hey/scripts/build_tun2socks_ohos.sh:60-110`（本体 `:91-104`） |
| K4 | **冷 cgo 入口在扩展进程 SIGSEGV** | 真机 ALN-AL80 / HarmonyOS 6.1：VPN 扩展进程里调 `CGoTestXray`（配置预检）当场崩，扩展进程死亡 | 不在扩展进程做"预检类"冷调用；以正式 start 的结果为真相来源 | `HeyVpnAbility.ets:83-86` |
| K5 | **IPv6 `::/0` 路由被系统静默丢弃 → v6 从物理口泄漏** | 用 `gateway:{address:'::',family:2,port:0}` + `isDefaultRoute:true` 时，HarmonyOS 不把 `::/0` 装进 TUN（只保留地址自带的连接路由），全局 v6 直出；**同样的写法 v4 能生效、v6 不行** | v6 专用写法：`gateway:{address:''}` + `hasGateway:false` + `isDefaultRoute:false`（即使是 `::/0` 也填 `false`）；v4 保持原写法 | `Hey/entry/src/main/ets/vpn/VpnConstants.ets:221-239`；对照实验与真机验证见 `Hey/docs/ipv6-leak-prevention.md` §6（❌/✅ 对照表）；**该写法首现于 `arror/x4h` 的 `VpnConfigManager.ets`**（Hey §5.1），Hey 复现并在 ALN-AL80 上验证 |
| K10 | **`/proc` 不能作为"v6 是否进 TUN"的判据** | 曾据此误判为"平台不支持 v6"：VPN 路由进的是**独立策略路由表**，主表看不到 `::/0` 是正常现象（v4 的 `0.0.0.0/0` 同样不在主表却能走代理） | 判定改为**分协议打出口看 IP 归属**：`api-ipv4.ip.sb/ip` 与 `api-ipv6.ip.sb/ip` 分别测；归属=本地运营商即泄漏。`/proc` 只作参考 | `Hey/docs/ipv6-leak-prevention.md` §5.3、§1「判断泄漏的正确方法」、§9 |
| K11 | **"关闭 IPv6" ≠ "必然泄漏"**（前提修正） | 直觉上"不接管 v6 就不漏"是错的，而"接管 v6 + 核心侧 block"才是最优解 | 正确做法：**恒接管** v6（`isIPv6Accepted:true` + 单条 `::/0`），再在核心侧按开关处置——关：DNS `queryStrategy=UseIPv4` + 路由 `block ::/0` 秒拒（逼应用回落 v4）；开：转发给节点。**Clash/Mihomo 之所以"关 v6 也不漏"是因为它用 fake-ip，本机从不产生指向真实 v6 目标的流量** | `ipv6-leak-prevention.md` §8、§7.2、§5.2；`isIPv6Accepted` 官方默认 `false`（§4） |
| K12 | **VPN 路由只能一次性下发，没有增量接口** | 只有 `createVpnConnection().create(config)` 的 `VpnConfig.routes`，**无 `addRoute`/`setRoute`/`updateConfig`** → 运行期改路由只能重建 VPN 连接 | "IP 级路由"固定为 `0.0.0.0/0` + `::/0`（+ 可选 LAN 绕过表），**分流全部放内核规则**，避免把分流需求做成路由变更。**用户可感知后果（可直接写进验收标准）**：①改**路由级**配置（接管网段 / 分应用范围 / LAN 绕过）→ **必须重建 VPN，连接会断一下**；②只改**内核分流规则**（域名/IP/端口/进程匹配）→ **不需要重建 VPN**，只需更新内核配置（重启内核或走规则增删接口），隧道不断。 | `ipv6-leak-prevention.md` §4；`VpnConstants.ets:24-56`（LAN 绕过用 30 段 v4 前缀枚举，正是"路由不可增量"的后果） |
| K6 | **本地 SOCKS 端口默认对全网开放** | 同机任意应用可白嫖代理（安全） | 端口随机化 + 绑定仅回环 + 可选鉴权；不要用固定 10808/18082 作为唯一防线 | v2rayNG #5457（347 评论） |
| K7 | **错误的默认 DNS 会"连上了但没网"** | 远程 DNS 设为被墙地址 → 全局不可用，且难以归因 | 默认值必须"本地/安全优先"，并在设置页标注影响 | v2rayNG #2044 |
| K8 | **tun2socks 引擎会跑着跑着死** | `hev-socks5-tunnel` 一段时间后失效 | 引擎可替换（gvisor ↔ hev）+ 运行期健康探测 + 自动重启数据面 | v2rayNG #5057 |
| K9 | **已安装应用不可枚举（OHOS）** | 分应用代理只能手填包名 | 产品侧接受次优体验：常见应用快捷入口 + 包名输入 + 校验 | `Hey/README.md` |

---

## 10. 未核实项与 v0.2 待办

**未核实（不作为任何结论依据）**
1. FakeDNS 在 v2rayNG / v2rayN 的开启路径与默认值。
2. NekoBox / SFA 的订阅"完整配置"支持粒度（是否解析 routing 段）。
3. ~~`arror/x4h` 的实现细节~~ → **已解决**：`Hey/docs/ipv6-leak-prevention.md` §5.1 明确写明该写法来源就是 `arror/x4h` 的 `VpnConfigManager.ets`，且 §5.3/§6 记录了 Hey 自己的试错对照（ULA→全局、`/126`→`/64`、`::/0`→`2000::/3`、bypass 开关全部无效）与真机验证（`/proc/net/ipv6_route` 出现 `::/0`、`ip.sb` 归属从本地运营商变为节点机房）。**证据强度应表述为**：「单一参考实现（x4h 写法）+ Hey 的对照实验与真机验证（ALN-AL80）」，**仍不等于我们的目标机型/系统版本已证实**【未在我们机型验证】。
4. HarmonyOS Push Kit 与 VPN 共存的实际影响（对应 v2rayNG #403 的 OHOS 映射）。
5. Hey 在真机上的长跑表现（仓库无 benchmark，**不要编数字**）。

**v0.2 待办**
- [ ] 补齐 §6 中所有【未核实】单元格，并给每格独立脚注。
- [ ] 交叉验证 K5（`x4h` 或 HarmonyOS 官方的路由写入示例）。
- [ ] 补 SFA/SFI 的配置模型对比（sing-box 的 profile + rule-set 抽象，对需求文档的"分流可解释"有直接价值）。
- [ ] 补 v2rayN 桌面端的"多配置/策略组"设计（对 Q1 的 MVP 范围切分有参考）。

---

## 附录 A：来源索引

| 编号 | 来源 | 类型 |
| --- | --- | --- |
| S1 | `_research_src/Hey/README.md` | 源码库（GPL-3.0） |
| S2 | `_research_src/Hey/docs/building-native-cores.md` | 源码库文档 |
| S3 | `_research_src/Hey/docs/harmonyos-go-tls-wall.md` | 源码库文档 |
| S4 | `_research_src/Hey/entry/src/main/ets/vpn/HeyVpnAbility.ets` | 源码 |
| S5 | `_research_src/Hey/entry/src/main/ets/vpn/VpnConstants.ets` | 源码 |
| S6 | `_research_src/Hey/entry/src/main/ets/services/DiagnosticLog.ets` | 源码 |
| S7 | `_research_src/Hey/entry/src/main/ets/core/XrayConfig.ets` | 源码 |
| S8 | `_research_src/Hey/scripts/build_libxray_ohos.sh` / `build_tun2socks_ohos.sh` / `build_hev_ohos.sh` | 构建脚本 |
| S9 | `_research_src/libXray/invoke.go` / `invoke_model.go` / `android_wrapper.go` | 源码（MIT） |
| S10 | `_research_src/AndroidLibXrayLite/libv2ray_main.go` / `libv2ray_android.go` | 源码 |
| S11 | `_research_src/v2rayNG/`（源码目录结构） | 源码（GPL-3.0） |
| S12 | `_research_src/Xray-core/README.md:149-150` | 源码库 README |
| S13 | v2rayNG issues: #5457 / #930 / #1346 / #268 / #2729 / #149 / #2044 / #782 / #4520 / #4672 / #6089 / #4641 / #403 / #5057 / #1499 / #5519 / #31 | GitHub issue |
| S14 | `https://github.com/MatsuriDayo/NekoBoxForAndroid` README | 仓库 README |
| S15 | `https://github.com/arror/x4h` | 仓库页面 |
| S16 | `team-workspace/handoff/r1-to-r3-handoff.md` + `doc/research/xray-core-baseline.md` | R1 交接（Xray-core 侧边界、libXray 构建目标与稳定性承诺、传输代际、控制面能力边界） |

---

## 附录 B：修订记录

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| v0.1 | 2026-10-17 | 初稿：Hey 画像、构建链、已知坑、许可证三层、功能矩阵、痛点、5 条差异化机会 |
| v0.1-r1 | 2026-10-17 | 纳入 R1 交接：①§3.3 增加"为什么走中继"的双证据表（文档理由 vs 推测理由，禁止混用）②§5 增加 libXray 无 ohos target 且不保证 API 稳定 ③§5 增加"切节点必须重启内核/balancer 方案" ④§6 增加「切节点是否需重启内核」行 + 传输代际失真警告 ⑤附录 A 增加 S16 |
| v0.1-r2 | 2026-10-17 | ①**传输表述拆为两档**（quic/h2/h3/http 已移除且配置报错；ws/grpc/httpupgrade deprecated 但可用，`PrintNonRemovalDeprecatedFeatureWarning` 后 `return "grpc", nil`），并写明"竞品支持 ws/grpc 是真实能力，不得记成已废弃" ②§3.3 证据改为直接引用 `harmonyos-go-tls-wall.md` §6/§7（已逐行核实），补"归因边界"段 ③§3.5 补端口版本提示（18082 current vs 10810 历史快照）④§9 新增 K10 `/proc` 非判据、K11"关闭 v6 ≠ 必然泄漏"、K12 VPN 路由无增量接口，并重写 K5 证据链 ⑤§10 关闭 x4h 未核实项 |
| v0.1-r3 | 2026-10-17 | K12 补「用户可感知后果」：改**路由级**配置（接管网段/分应用范围/LAN 绕过）→ 必须重建 VPN（会断一下）；只改**内核分流规则** → 无需重建 VPN、隧道不断。可直接作为需求验收标准（来源：K12 约束推论，非新取证）。**本条为定稿后唯一允许的变更方式：修订记录追加，不重写正文** |
