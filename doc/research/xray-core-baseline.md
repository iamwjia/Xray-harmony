# Xray-core 能力基线与可嵌入性评估

> 任务：R1 ｜ 作者：xray-core-analyst ｜ 证据基准日：2026-10-17
> 证据基准 commit：`95461cc14839d3a0b8e86c4d3f305235c6ba835d`（Xray-core HEAD，2026-10-17）、tag `v26.3.27`（最新 GA）
> 证据等级约定：**【源码】**=本地克隆源码 + 文件:行号@commit 可直接核对；**【官方文档】**=官方站点/官方 README 明示；**【实践】**=可复现的第三方工程记录（含具体仓库与文件）；**【待验证】**=未取得一手证据，已给出验证方式。

---

## 0. 结论摘要（给下游直接引用）

1. **基线锚定 v26.3.27（GA，2026-03-27），不要锚 HEAD。** HEAD（`95461cc`，版本号 26.10.10）比 GA 超前约 7 个月，且 GA 之后 11 个 tag 全部标记为 prerelease。**HEAD/预发布能力不得作为 MVP 依赖。**
2. **MPL-2.0 是「文件级 copyleft」，不传染 App 代码，但对「改过的 Xray 源文件」有强制开源义务。** 不修改源码、仅以 `.so` 分发时，义务主要是随包给 LICENSE + 来源声明 + Source Code 获取方式；一旦改了 Xray 的任何源文件（包括为 OHOS 打的补丁），这些文件必须以 MPL-2.0 公开。
3. **协议面以 VLESS 为核心，XTLS-Vision 仅 VLESS 可用；Shadowsocks 已包含 SS2022 方法族；GA 已有 Hysteria 与内置 TUN。** GA 入站协议 10 类、出站协议 12 类（含 HEAD 独有 masque）。
4. **传输面已发生代际更替：QUIC 传输与 HTTP/H2/H3 传输已被移除，gRPC / WebSocket / HTTPUpgrade 已被标记为 deprecated，官方推荐路线是 XHTTP（`splithttp`）。** 因此「WS/gRPC 老配置」在 2026 版 Xray 上属于**过渡可用**，新设计应以 XHTTP 为主线。**不要按 v2ray 时代的传输认知做设计。**
5. **REALITY 有硬约束：仅支持 RAW(tcp) / XHTTP / gRPC 三种承载**（源码显式校验，非文档口径）。这直接限定了「REALITY + 传输」的组合空间。
6. **控制面不足以支撑「无缝热切换节点」。** gRPC 能增删 inbound/outbound、加删用户、加删路由规则、查流量、重启日志；**但没有「改单个 outbound 的目标地址」的原语，也没有整体配置热重载**。业界做法（v2rayNG / Hey）是**停核 + 重载 JSON + 起核**。D1 的进程模型必须按「可快速重启内核」而非「零重启热切换」设计。
7. **进程内库是手机端唯一可行形态**（HarmonyOS 应用沙箱不允许拉起任意子进程）。**结论确定，无需再验证。**
8. **HarmonyOS 上 Go 产物可用的唯一已知路径是 `GOOS=openharmony` 的第三方 Go fork + TLSDESC 构建**（依据：`popsiclelmlm/Hey` 的真机排查记录）。标准 `GOOS=android` 产物在 musl 环境的外来线程上会 SIGSEGV；标准 `GOOS=linux` 产物带 initial-exec TLS，musl 拒绝 `dlopen`。**这是 P-02/P-03 的关键输入，见 §5.1。**
9. **工具链版本刚好卡住：GA 要求 `go 1.26`，社区 OHOS Go fork 现为 go1.26.5 → 可用；HEAD 要求 `go 1.27` → 当前 fork 编不了。** 这是「必须锚 GA」的第二个技术理由（第一个是稳定性）。
10. **Xray 不强制依赖 TUN 与 VPN fd。** 纯 SOCKS 入站（支持 UDP）即可完整工作；fakedns/DNS 劫持均不依赖 TUN。**但 Xray 出站 socket 必须能绕过 TUN 回落物理网卡**，其机制是 `sockopt.mark` / `sockopt.interface`，该能力在 HarmonyOS 上【待验证】。

---

## 1. 版本与许可

### 1.1 版本号与发布节奏

| 项目 | 事实 | 来源 |
|---|---|---|
| 版本号方案 | CalVer `v<YY>.<M>.<D>`，同时镜像一个 Go modules 友好的 SemVer tag（`v26.3.27` ↔ `v1.260327.0`）。原因是 Go modules 要求 major ≥2 时必须把 major 写进 import path | 【官方文档】libXray README "Versioning" 节；【源码】本地 `git fetch` 已观察到 tag `v1.260327.0` 与 `v26.3.27` 指向同一 commit |
| 最新 GA（非 prerelease） | **v26.3.27**，发布于 2026-03-27T17:51:11Z | 【官方文档】GitHub Releases API `/releases/latest` |
| GA 之后的版本 | `v26.5.3`(05-03)、`v26.5.9`(05-09)、`v26.6.1`(06-01)、`v26.6.22`(06-22)、`v26.6.27`(06-27)、`v26.7.11`(07-11)、`v26.7.28`(07-28)、`v26.9.8`(09-08)、`v26.9.9`(09-08)、`v26.9.30`(09-30)、`v26.10.10`(10-10) —— **全部 `prerelease: true`** | 【官方文档】GitHub Releases API `/releases?per_page=50` |
| 发布节奏 | 2026-03→2026-10 共 11 个预发布 tag，约 **每月 1–1.5 个**；GA 与预发布的比例约 1:11 | 同上，按 `published_at` 统计 |
| HEAD 版本常量 | `Version_x=26, Version_y=10, Version_z=10`（即 26.10.10） | 【源码】`core/core.go:21-23@95461cc` |

**对 xray-harmony 的含义**：上游处于「频繁预发布、GA 稀疏」的节奏，且 HEAD 长期领先 GA 半年以上。选型上必须做**版本钉死 + 升级评估**，不能跟随 latest（latest 往往是 prerelease）。

### 1.2 依赖的 Go 版本（直接影响能否用 OHOS fork 构建）

| 版本 | `go.mod` 的 go 指令 | 来源 |
|---|---|---|
| GA v26.3.27 | `go 1.26` | 【源码】`go.mod:3@v26.3.27` |
| HEAD 95461cc | `go 1.27` | 【源码】`go.mod:3@95461cc` |
| 社区 OHOS Go fork 现状 | go1.26.5（第三方 fork，带 `openharmony` 端口 + arm64 TLSDESC） | 【实践】Hey `docs/harmonyos-go-tls-wall.md`「现状（2026-09）」节 |

**结论**：**GA（go 1.26）刚好能被 OHOS Go fork（go1.26.5）编译；HEAD（go 1.27）在 fork 跟进 1.27 之前无法构建。** 这是「锚 GA」的硬技术理由。

### 1.3 MPL-2.0 许可与分发合规（独立成节）

| 事项 | 结论 | 依据 |
|---|---|---|
| 许可证 | Mozilla Public License 2.0 | 【源码】仓库根 `LICENSE`；README "License" 节 |
| copyleft 粒度 | **文件级**（file-level / per-file），不是项目级 | 【官方文档】MPL-2.0 §3.1/§3.3 语义：义务绑定在「被修改的 Source Code Form 文件」上 |
| 未修改源码、仅分发 `.so`/静态库 | 需做到：①随分发物附 MPL-2.0 全文；②声明使用 Xray-core 及其版本与来源 URL；③告知如何获取 Source Code Form（指向上游仓库 + 自己发布的对应源码包）；④不限制接收者对 MPL 文件的权利。**App 自身代码（ArkTS/UI 层）不需要开源。** | 【官方文档】MPL-2.0 §3.2（Executable Form 分发须告知 Source Code 获取方式）、§3.3（Larger Work 可按其他条款分发） |
| 修改了 Xray 源文件（含为 OHOS 打的补丁、交叉编译适配、裁剪 distro） | **被修改的文件必须以 MPL-2.0 公开**，并保留原版权与许可声明；可以用「同一文件」的补充许可，但不得改变其许可 | 【官方文档】MPL-2.0 §3.1、§1.10（Modifications） |
| 以 Go module（`import`）方式嵌入 | 属 Larger Work，App 代码许可自由；若 patch 了 Xray 源文件则回到上一条 | 同上 |
| 与 GPL 的差别（易误解点） | MPL 不要求「链接即传染」，因此「闭源 App + Xray 内核」在合规上是成立的（这是 v2rayNG/NekoBox 等客户端能闭源上架的原因） | 【官方文档】MPL-2.0 FAQ（"MPL is a per-file copyleft"） |
| 第三方组件单独许可 | 官方发行包内含未修改的 Wintun 预编译二进制，按 PBL（Prebuilt Binaries License）再分发，是**可选运行时加载组件**，仅 Windows TUN 使用 | 【官方文档】README「Bundled Third-Party Components Redistribution → Wintun」 |
| 名称/商标 | 项目名 "Xray"、协议名 "VLESS"/"REALITY" 的商标使用需自查；App 名称不应暗示官方背书 | 【待验证】商标使用未见明确书面许可条款；验证方式：发 GitHub Discussion 询问或咨询法务 |

> ⚠️ **合规提醒（给 Z1/法务）**：本节是工程侧对 MPL-2.0 的保守解读，**不构成法律意见**。上架前建议由法务确认「华为 AppGallery 对开源 copyleft 组件的申报要求」与本节的对应关系。

---

## 2. 能力清单与协议 × 传输矩阵

### 2.1 入站 / 出站协议（双列：GA vs HEAD）

来源：【源码】`infra/conf/xray.go:28-60`（`inboundConfigLoader` / `outboundConfigLoader`，即 JSON 里 `"protocol"` 可取的值）

| 能力 | GA v26.3.27 | HEAD 95461cc | 说明 |
|---|---|---|---|
| VLESS | ✅ 入/出 | ✅ 入/出 | 入站/出站在 `proxy/vless/{inbound,outbound}` |
| VMess | ✅ 入/出 | ✅ 入/出 | |
| Trojan | ✅ 入/出 | ✅ 入/出 | |
| Shadowsocks（含 SS2022 方法族） | ✅ 入/出 | ✅ 入/出 | 2022 方法：`2022-blake3-aes-128-gcm` / `-aes-256-gcm` / `-chacha20-poly1305`，实现于 `proxy/shadowsocks_2022/shadowsocks_2022.go:165-167`，通过 `shadowsocks` 协议的 method 选用 |
| XTLS-Vision（`flow: xtls-rprx-vision`） | ✅（仅 VLESS） | ✅（仅 VLESS） | 常量 `XRV = "xtls-rprx-vision"` @`proxy/vless/vless.go:18`；account 注释 @`proxy/vless/account.go:34` |
| REALITY | ✅（security 层，非独立协议） | ✅ | 见 §2.3 组合约束 |
| WireGuard | ✅ 入/出 | ✅ 入/出 | L3 协议，非传输载体 |
| Hysteria（v2 形态） | ✅ 入/出 | ✅ 入/出 | `proxy/hysteria`，自带传输（`transport/internet/hysteria`） |
| 内置 TUN 入站（`"protocol":"tun"`） | ✅ **GA 即有** | ✅ | `proxy/tun`；配置结构 `infra/conf/tun.go:18-29`；`infra/conf/xray.go:41` 注册 |
| SOCKS / mixed / HTTP | ✅ 入；HTTP/SOCKS 出 | ✅ | `"mixed"` 是 socks+http 混合入站别名 |
| dokodemo-door / tunnel | ✅ 入 | ✅ | 任意 TCP/UDP 转发入口 |
| DNS 出站（`"protocol":"dns"`） | ✅ 出 | ✅ | 与 `app/dns` 配合 |
| blackhole / freedom / loopback | ✅ 出 | ✅ | |
| MASQUE（`"protocol":"masque"`） | ❌ **无** | ✅ 入/出 | `proxy/masque` 目录在 GA 树中不存在；HEAD 的 `infra/conf/xray.go:40,57` 才有 |

### 2.2 传输（transport）双列

来源：【源码】`infra/conf/transport_internet.go:18-48@95461cc`（`TransportProtocol.Build()`）与 GA 同函数 `:998-1022@v26.3.27`

| `network` 取值 | 内部 ProtocolName | GA | HEAD | 生命周期状态 |
|---|---|---|---|---|
| `raw` / `tcp` | `tcp` | ✅ | ✅ | 主力，REALITY 默认承载 |
| `xhttp` / `splithttp` | `splithttp` | ✅ | ✅ | **官方推荐主线**（XHTTP） |
| `kcp` / `mkcp` | `mkcp` | ✅ | ✅ | 可用（UDP 类） |
| `grpc` | `grpc` | ✅ | ✅ | ⚠️ **deprecated**，启动打印告警，建议迁 XHTTP stream-up H2 |
| `ws` / `websocket` | `websocket` | ✅ | ✅ | ⚠️ **deprecated**，建议迁 XHTTP H2 & H3 |
| `httpupgrade` | `httpupgrade` | ✅ | ✅ | ⚠️ **deprecated**，同上 |
| `hysteria` | `hysteria` | ✅ | ✅ | 独立传输（QUIC 之上） |
| `quic` | — | ❌ **已移除** | ❌ 已移除 | 返回错误，提示改用 XHTTP stream-one H3 |
| `h2` / `h3` / `http` | — | ❌ **已移除** | ❌ 已移除 | 返回错误，提示改用 XHTTP stream-one H2 & H3 |
| `masque` | `masque` | ❌ | ✅ | 仅 HEAD |
| `xdrive` | `xdrive` | ❌ | ✅ | 仅 HEAD（基于云盘/第三方存储承载，见 `transport/internet/xdrive`） |

> **重要纠偏（相对 v2ray/Xray 1.x 时代的普遍认知）**：`quic` 与 `h2/h3/http` 传输在 GA v26.3.27 里**已经是"已移除"状态，不是"支持"**；`ws/grpc/httpupgrade` 是"还能跑但被劝退"。任何把「WS + TLS」「gRPC」「QUIC」当作长期主线的设计都需重新评估。

### 2.3 协议 × 传输支持矩阵（关键：组合约束）

传输由**每个 outbound 自己的 `streamSettings.network`** 决定（【源码】`infra/conf/xray.go:232`，`StreamSetting *StreamConfig`），因此协议与传输基本正交；**例外是自带传输的协议，以及 REALITY 的显式限制**。

| 协议 \ 传输 | raw/tcp | xhttp(splithttp) | mkcp | ws ⚠️ | grpc ⚠️ | httpupgrade ⚠️ | hysteria | quic ❌ | masque | xdrive |
|---|---|---|---|---|---|---|---|---|---|---|
| VLESS（+Vision flow） | ✅ **主力** | ✅ | ✅ | ✅ | ✅ | ✅ | — | ❌ | — | — |
| VLESS + REALITY | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| VMess | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | ❌ | — | — |
| Trojan | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | ❌ | — | — |
| Shadowsocks / SS2022 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | ❌ | — | — |
| SOCKS / HTTP 出站 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | ❌ | — | — |
| WireGuard（L3） | 不适用（自身即隧道） | | | | | | | | | |
| Hysteria | 不适用（自带 QUIC 传输，`network:"hysteria"`） | | | | | | | | | |
| MASQUE（HEAD） | 不适用（自带 `network:"masque"`） | | | | | | | | | |

**REALITY 组合约束的源码依据**：【源码】`infra/conf/transport_internet.go:66-68` —— `if config.ProtocolName != "tcp" && config.ProtocolName != "splithttp" && config.ProtocolName != "grpc" { return error("REALITY only supports RAW, XHTTP and gRPC for now.") }`

**TLS 层可用性**：`security` 取 `none` / `tls` / `reality`（【源码】`transport_internet.go:43-68`）；TLS 支持 uTLS 指纹伪装与 ECH（`tlsSettings.fingerprint` / `echConfigList`，见 `:57-63`）。

### 2.4 Go 产物接入 OpenHarmony（本文最高优先级 PoC 输入）

#### 2.4.1 工具链（唯一已知可用组合）

来源：**【实践】** `popsiclelmlm/Hey` 仓库 `docs/harmonyos-go-tls-wall.md`（2026-06 排查记录 + 2026-09 现状更新）+ `docs/building-native-cores.md`

| 项 | 值 |
|---|---|
| Go 工具链 | 第三方 fork `star4277/ohos-go` **v1.26.5-beta1**（go1.26.5，带 `openharmony` 端口 + arm64 TLSDESC）；历史方案为 `gitcode.com/openharmony-sig/ohos_golang_go` branch `release-branch.go1.24`（go1.24.5） |
| 目标三元组 | `GOOS=openharmony GOARCH=arm64` |
| CC / CXX | `<DevEco>/sdk/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang(++)` |
| sysroot | `<DevEco>/sdk/default/openharmony/native/sysroot`（由上述 clang 驱动自动带出；OHOS NDK 标准布局，【待验证】具体路径随 DevEco 版本变化） |
| 关键 CGO 标志 | `CGO_ENABLED=1`、`CGO_CFLAGS="-ftls-model=global-dynamic"`、`GOTOOLCHAIN=local` |
| 产物形态 | `-buildmode=c-shared` → `libxray.so`（Android 侧惯例见 libXray `cgo_bridge/`） |
| 是否可用 gomobile | **否**。libXray 的 build 脚本只有 `android` / `apple` / `linux` / `windows` 四个 target，无 ohos；Hey 走自建 `c-shared`（`scripts/build_libxray_ohos.sh`） |
| 禁止项 | `GOOS=openharmony` 下**不要加 `-tags netgo`**，OpenHarmony 的 net 端口需要 cgo，否则报 `_C_getifaddrs undefined` |

#### 2.4.2 为什么不能直接用 `GOOS=android`

| 方案 | 结果 | 机制 |
|---|---|---|
| `GOOS=android GOARCH=arm64` + OHOS clang | **能产出可 `dlopen` 的 `.so`，但会在外来线程（ArkTS / VPN Extension 线程）上 SIGSEGV** | Android target 按 bionic 规则把 goroutine 指针 `g` 放在**固定 TLS 槽**，产物**没有真正的 `PT_TLS` 段**（`llvm-readelf -l libxray.so \| grep TLS` 为空）。HarmonyOS 运行 musl，该固定槽不归 Go runtime 管理：槽值为 0 时走 `needm` 侥幸可用，槽为垃圾值时直接当 `g` 用 → SIGSEGV |
| `GOOS=linux GOARCH=arm64` | **musl 拒绝 `dlopen`** | 用真 ELF TLS 但会带 initial-exec TLS 模型，musl 不接受这类共享库被动态加载 |
| `GOOS=openharmony`（fork） | ✅ 可用 | 产物同时具备 `PT_TLS` 段与 `R_AARCH64_TLSDESC` 重定位，满足「musl 能 `dlopen`」+「外来线程能进入 Go runtime」两个条件 |

#### 2.4.3 已知失败模式清单（PoC 直接对照排查）

| # | 失败现象 | 根因 | 规避/修复 | 证据 |
|---|---|---|---|---|
| F-1 | VPN 扩展进程启动后**零回写**即退出；hilog 见 `SIGSEGV(SEGV_MAPERR)`，崩在进入 `libxray.so` 的第一个 cgo 调用附近 | `GOOS=android` 产物的 bionic 固定 TLS 槽假设 | 改用 `GOOS=openharmony` + `-ftls-model=global-dynamic` | 【实践】tls-wall §1–§4 |
| F-2 | 症状随系统 OTA 变化（同二进制「以前能跑现在崩」） | 外来线程 TLS 初值/线程布局随系统版本变化，放大了 F-1 | 同上；并在启动早期做一次最小 cgo 冒烟 | 【实践】tls-wall §3 |
| F-3 | `dlopen` 后调用 `setenv` 崩溃 | OHOS runtime 的 `environ` 被抢占（与 TLS 无关的第二个坑） | 避免在 `dlopen` 之后 `setenv`；改为显式传参/写配置文件 | 【实践】tls-wall 文首「现状」节 + building-native-cores §5 |
| F-4 | gVisor / tun2socks 的 `fdbased` endpoint 初始化失败 | **HarmonyOS VPN fd 支持 `readv`/`writev`，但拒绝 `Fstat`**，而 gVisor 用 `unix.Fstat` 判断 fd 是否 socket | patch `isSocketFD` 直接返回 `false` | 【实践】tls-wall §9 |
| F-5 | 编译报 `_C_getifaddrs undefined` | `GOOS=openharmony` 下加了 `-tags netgo` | 去掉 `netgo` tag | 【实践】tls-wall §10 |
| F-6 | 链接/加载或启动即崩，且工程里有多个 Go 产物 | **一个进程只能有一个 Go runtime**（`libxray.so` + 另一个独立编译的 Go 库共存） | 把需要的 Go 包合并进**同一次**构建产出单一 `.so`；或拆到不同进程 | 【官方文档】libXray README WARNING（引 Go #18976 / #15956） |

#### 2.4.4 产物校验命令（PoC 判定标准）

```bash
strings -a libxray.so | grep -m1 'GOOS=openharmony'      # 确认是 fork 构建
llvm-readelf -l libxray.so | grep -i TLS                  # 必须有 PT_TLS
llvm-readelf -r libxray.so | grep -i TLSDESC              # 必须有 R_AARCH64_TLSDESC
nm -D libxray.so | grep ' T .*CGo'                        # 确认导出集（现役 libXray 仅 CGoInvoke/CGoFree）
```
判定：四条中**前三条任一不满足即视为 PoC 失败**（即使能跑也不稳）。

---

## 3. 配置模型要点

### 3.1 顶层结构

【源码】`infra/conf/xray.go:456-476@95461cc`

```
{
  "env": {},
  "log": {...}, "routing": {...}, "dns": {...},
  "inbounds": [...], "outbounds": [...],
  "policy": {...}, "api": {...}, "metrics": {...}, "stats": {...},
  "reverse": {...}, "fakeDns": {...},
  "observatory": {...}, "burstObservatory": {...},
  "version": {...}, "geodata": {...}          // geodata 为 HEAD 独有
}
```

| 节点 | 作用 | 客户端视角要点 |
|---|---|---|
| `inbounds` | 入站监听。字段：`protocol` / `port` / `listen` / `tag` / `streamSettings` / `sniffing`（`xray.go:135-141`） | 手机端典型：一条 `socks`/`mixed` 入站（供 tun2socks 或本地应用用）；若走原生 TUN 则再挂一条 `tun` 入站 |
| `outbounds` | 出站。额外字段：`sendThrough` / `mux` / `targetStrategy`（`xray.go:228-235`） | 节点列表 → 每条 outbound 一个 `tag`；`mux`（多路复用）对移动端省电/省握手有意义 |
| `routing` | 分流规则（domain / ip / port / inboundTag / process 等匹配 + balancer） | 客户端按「直连 / 代理 / 拦截 + 自定义规则」生成 rules；`tag` 是路由规则的锚点。**注意：分流的唯一可运行期调整点就在这一层**——平台侧 VPN 路由只能随连接一次性下发、无运行期增改（R3/platform 侧 K12），所以「分应用/分流」必须全部表达为 Xray 的 `routing.rules`，不能设计成"运行期改系统路由" |
| `dns` | 内置 DNS 服务器列表 + 查询策略（含 `hosts`、`queryStrategy`） | 决定「DNS 是否走代理」以及是否配合 FakeDNS |
| `fakeDns` | FakeDNS 池（`ipPool` / `poolSize`），配合 `dns` 的 `fakedns` 与 routing 使用 | 用于 TUN/透明代理下减少 DNS 泄漏与 RTT；**注意：走 SOCKS 入站时，若客户端本身已把域名交给 SOCKS（socks5 域名寻址），FakeDNS 非必需** |
| `stats` | 流量统计开关与策略 | 配合 gRPC `StatsService` 查询；App 侧「已用流量」即来自此 |
| `policy` | 各级（system/level）超时、缓冲区大小等 | 移动端可下调 buffer 以省内存（详见 §5.3） |
| `api` | 控制面开关：`tag` / `services`（HandlerService/StatsService/LoggerService/RoutingService/…） | **手机端建议只开 loopback + 随机端口，或干脆不走 gRPC 而用进程内库直调** |
| `observatory` / `burstObservatory` | 出站健康探测与自动择优 | 实现「自动选择最快节点」的内核侧能力，避免 App 层反复重启内核 |
| `metrics`（GA 已有） | Prometheus 风格指标输出 | 移动端一般关闭 |

### 3.2 客户端「按节点数据生成配置」的通常做法

【实践】依据：Hey README（"generates runtime Xray config from the selected profile"）+ libXray 导出面（`CGoRunXrayFromJSON` / `CGoQueryStats`，见 tls-wall §8）

标准三段式，**不是**把用户订阅原样喂给内核：

1. **解析层**：分享链接（`vless://`、`vmess://`、`trojan://`、`ss://`、`hysteria2://`、`tuic://`、`wireguard://`、`socks://`…）、Base64 订阅、Clash YAML、Xray JSON 片段 → 统一内部 `Node` 模型（协议、地址、端口、凭据、传输、security、mux、标签）。
2. **生成层**：`Node` + 全局策略（分流规则、DNS、日志级别）→ 完整 Xray JSON：`inbounds`（本地 socks/mixed 或 tun）+ 固定 tag 的 `direct`/`block` outbound + 选中节点 outbound + `routing` 规则表 + `dns`/`fakeDns`/`policy`/`stats`。
3. **下发层**：`启动(JSON)` → 校验 → 崩溃/失败回调 → `停止()`。

> 设计建议：把「生成层」做成**纯函数 + 快照**（同一 Node + 同一全局设置 → 同一 JSON），便于灰度、回滚、问题复现；这也是后续 `design.md` 里「配置生成策略」的最小契约。

---

## 4. 控制面能力边界

### 4.1 gRPC 服务清单

来源：【源码】各 `*.proto` 的 `service` 定义（@95461cc）

| 服务 | 方法 | 能做什么 | 不能做什么 |
|---|---|---|---|
| `xray.app.proxyman.command.HandlerService`（`app/proxyman/command/command.proto:86-105`） | `AddInbound` / `RemoveInbound` / `AlterInbound` / `ListInbounds` / `GetInboundUsers` / `GetInboundUsersCount` / `AddOutbound` / `RemoveOutbound` / `AlterOutbound` / `ListOutbounds` | 运行时增删 inbound/outbound；`Alter*` 只接受 `TypedMessage operation`（如 `AddUserOperation`/`RemoveUserOperation`） | **没有「把某个 outbound 的地址/端口/凭据改掉」的原语**；改节点 = `RemoveOutbound` + `AddOutbound`，且**已在途连接不断**（旧 outbound 连接不迁移） |
| `xray.app.stats.command.StatsService`（`app/stats/command/command.proto:85-92`） | `GetStats` / `GetStatsOnline` / `QueryStats` / `GetSysStats` / `GetStatsOnlineIpList` / `GetAllOnlineUsers` / `GetUsersStats` | 查上下行字节、连接数、在线 IP、系统内存/GC 等 | 不能重置/清零计数器（需重启内核） |
| `xray.app.log.command.LoggerService`（`app/log/command/config.proto:15-16`） | `RestartLogger` | 运行时重启日志后端（切文件/切级别） | 不能实时推送日志流（日志靠文件/标准错误，需 App 侧 tail） |
| `xray.app.observatory.command.ObservatoryService`（`app/observatory/command/command.proto:18-19`） | `GetOutboundStatus` | 查询各出站健康状态（延迟/存活） | 不负责切换，只提供数据 |
| `xray.app.router.command.RoutingService`（`app/router/command/command.proto:118-121+`） | `SubscribeRoutingStats` / `TestRoute` / `AddRule` / `RemoveRule` / `ListRule` / balancer 相关（`GetBalancerInfo` / `OverrideBalancerTarget`） | **运行时增删路由规则**、探路（TestRoute）、覆盖 balancer 选中目标 | 不能整体替换 routing 配置；不能改 DNS 配置 |
| `xray.app.version`（`app/version/config.proto`，仅配置结构） | — | 版本信息为配置项（`core_version`/`min_version`/`max_version`） | 无 RPC |

### 4.2 能力边界总表：能热做 / 必须重启内核

| 操作 | 结论 | 依据 |
|---|---|---|
| 增加/删除 inbound、outbound | ✅ 可运行时（gRPC） | HandlerService |
| 增加/删除用户（UUID/密码） | ✅ 可运行时（`AlterInbound`/`AlterOutbound` + `Add/RemoveUserOperation`） | 同上 |
| 查询流量/连接数/在线 IP | ✅ 可运行时 | StatsService |
| 切换日志文件/级别 | ✅ 可运行时 | LoggerService |
| 增加/删除**单条**路由规则 | ✅ 可运行时 | RoutingService `AddRule`/`RemoveRule` |
| 探路（给定目标查命中哪条规则/哪个 outbound） | ✅ 可运行时 | RoutingService `TestRoute` |
| **整体重载配置文件** | ❌ **无此能力** | 遍历全部 proto 无 reload/load 语义；官方运行模型是 `xray run -config`（libXray 亦只在启动时传入 JSON） |
| **「用另一个节点替换当前节点」的原子操作** | ❌ 只能组合「删旧建新」，且无连接迁移、无规则引用自动跟随 | 需自行维护 `tag` 一致性 |
| 改 DNS / FakeDNS 配置 | ❌ 必须重启 | 无对应 RPC |
| 改 policy（超时、缓冲区） | ❌ 必须重启 | 无对应 RPC |
| 清零统计计数 | ❌ 必须重启 | 无对应 RPC |

**→ 对 D1 进程模型的直接含义**：节点切换的工程最优解不是「gRPC 热改」，而是**「停核 → 重新 `core.New(config)` → 启动」的快速重启路径**（毫秒到百毫秒级，取决于是否重新解析 geo 资源），或者**在单实例内预置多条 outbound + 用 RoutingService `OverrideBalancerTarget` 切 balancer 目标**（可避免重启，但要求启动时就把候选节点全部建好，内存与握手成本上升）。**这两条路线需在 design.md 里做取舍，建议主路线「快速重启」，进阶「balancer 预置」。**

### 4.3 以 Go library 形式嵌入的可行性

| 项 | 结论 | 依据 |
|---|---|---|
| 可行性 | ✅ 高。`core.New(c *Config) (*Instance, error)` + `Instance.Start()/Close()` 是公开入口，`main/run.go` 只是它的 CLI 包装 | 【源码】`core/xray.go`（`Server`/`Instance` 定义）、`main/run.go` |
| 配置来源 | 两条路：①`infra/conf` 解析 JSON → `core.Config`；②直接构造 pb 结构。前者更省事，且会顺带完成协议注册（`infra/conf/xray.go` 内 `inboundConfigLoader/outboundConfigLoader`） | 【源码】`infra/conf/xray.go:27-61` |
| 包体控制 | 通过只 import 需要的组件（而非 `main/distro/all`）裁剪协议/传输，显著减小 `.so` | 【源码】`main/distro/all/all.go`（该文件即为"全量注册"清单，可裁剪） |
| 与 App 的交互面 | 官方 wrapper `XTLS/libXray` 已把「启停 / 查询 / 统计」封装为 C 导出（现役仅 `CGoInvoke` + `CGoFree`，方法经 `CGoInvoke` 分发） | 【实践】tls-wall「现状（2026-09）」节 |
| 硬约束 | **一个进程只能加载一个 Go runtime**：若还需 Go 写的 tun2socks，必须合进同一次构建 | 【官方文档】libXray README WARNING |

---

## 5. 移动端可嵌入性

### 5.1 构建链现状（Go 交叉编译）

| 目标 | 可行性 | 依据 |
|---|---|---|
| `linux/arm64`（纯静态，`CGO_ENABLED=0`） | ✅ 官方一等公民，`go build` 直接可用 | 【官方文档】README "One-line Compilation" |
| `android/arm64`（`CGO_ENABLED=1` + NDK clang） | ✅ 官方脚本给出完整命令（`GOOS=android GOARCH=arm64 CGO_ENABLED=1 CC=/path/to/aarch64-linux-android24-clang`） | 【官方文档】README "Reproducible Releases → For Android" |
| `openharmony/arm64` | ⚠️ **上游 Go 未支持**；需第三方 fork（`star4277/ohos-go` v1.26.5-beta1，带 TLSDESC）；上游 fork 未跟到 go1.27 | 【实践】tls-wall §5、§「现状」；【待验证】上游是否在 go1.27/1.28 加入 ohos 端口 |
| 本机验证 | ❌ 本机**未安装 Go 工具链**（`go version` → command not found），`GOOS/GOARCH` 目标支持情况未能在本地验证 | 环境限制，见 §6-U1 |

### 5.2 三种集成形态差异对比

| 维度 | ① 进程内库（c-shared `.so` + NAPI） | ② 独立子进程（fork/exec xray -config） | ③ 系统 VPN 服务承载 |
|---|---|---|---|
| 形态说明 | `libxray.so` 由 App 进程 `dlopen`，经 NAPI 调 C 导出 | App 打包可执行文件，`posix_spawn`/`fork+exec` 拉起，走 `xray run -config` | 由系统 VPN 框架（Android VpnService / iOS NE / HarmonyOS VPN Extension）持有 TUN，App/扩展把流量交给内核 |
| 手机端可行性 | ✅ 唯一可行（HarmonyOS 应用沙箱不允许拉起任意可执行文件） | ❌ 应用沙箱内不可行（无 exec 权限；HAP 里也没有可执行位概念） | ✅ 但它是**数据面载体**，与①/②是搭配关系，不是替代关系 |
| 单进程 Go runtime 约束 | 需注意（F-6），但可控 | 天然隔离（每进程一个 runtime） | 取决于承载进程 |
| 崩溃影响面 | 拖垮宿主进程/扩展进程 | 隔离良好，App 可守护重启 | 扩展进程崩溃 → VPN 断开，App 主进程可感知并重连 |
| 性能 | 最好（无 IPC、无额外拷贝） | 需 IPC/loopback 中转，多一次拷贝 | 依赖 TUN 实现，通常再叠一层 tun2socks → 多一跳 |
| 冷启动 | 快（无进程创建） | 慢（进程创建 + 动态链接） | 中（扩展进程与 TUN 建立固定开销） |
| 调试与可观测 | 差（同进程，日志混杂） | 好（独立 stdout/日志文件、可单独重启） | 中 |
| 与 Xray 官方支持度 | 高（libXray 官方 wrapper 即此形态） | 高（`xray run` 是一等用法） | 中（TUN 是 Xray 的一个 inbound 特性） |
| **本项目结论** | ✅ **采用** | ❌ 排除（平台不允许） | ✅ 必须（要接管全设备流量时）；与①组合，且必须先决定「TUN fd 给谁」 |

### 5.3 内存与启动开销基线

| 指标 | 数据 | 状态 |
|---|---|---|
| 空闲 RSS（单 outbound + 本地 socks 入站，无流量） | 无一手测量数据 | 【待验证】 |
| 启动到可接受连接耗时 | 无一手测量数据 | 【待验证】 |
| 影响内存的主要因子 | ①协议/传输数量（import 集合）；②`policy` 里的缓冲区大小；③并发连接数 × 每连接 buffer；④geo 数据（`geosite`/`geoip`）加载策略；⑤mux 是否开启 | 【源码】`app/policy`、`infra/conf/xray.go` policy 段 |
| 测量方法（PoC 用） | 在 `linux/arm64` 上用同一 JSON 跑 200 并发 TCP + 50 并发 UDP，记录 `VmRSS` 稳态与 P95 启动时间；再在真机用 `hilog` + 系统内存接口对照 | 建议纳入 P-02 |

> 说明：**本节刻意不给未测过的数字**。业界常见量级（Go 内核空闲十几 MB 到几十 MB）只能作为【待验证】预期，不得进入需求文档的性能指标。
>
> ⚠️ **回填规则**：本节数据由 **P-02 / P-24 实测回填**；**回填前，requirements.md / design.md 不得引用任何内存或启动耗时指标**（包括"业界量级""通常十几 MB"这类表述），需要占位时只能写「指标待 P-02/P-24 回填」。

### 5.4 TUN 依赖与「纯 SOCKS 入站」可行性（核对 Hey 的架构选择）

**核对结论：Xray 完全可以在「没有 TUN、没有 VPN fd」的前提下工作。**

| 问题 | 结论 | 依据 |
|---|---|---|
| Xray 是否支持纯 SOCKS 入站？ | ✅ `socks` / `mixed` 入站，且**支持 UDP**（`"udp": true`） | 【源码】`infra/conf/xray.go:33-34`；`infra/conf/socks.go:34,61`（`UDP bool json:"udp"` → `config.UdpEnabled`） |
| 是否有「必须有 TUN 才能工作」的模块？ | ❌ **没有**。`fakedns` / `dns` / `routing` / `stats` 都是应用层组件，与入站形态无关；FakeDNS 只需 DNS 流量被路由到内核 DNS 即可 | 【源码】`app/dns`、`app/dns/fakedns` 与入站类型无耦合 |
| TUN 入站是必需的吗？ | ❌ 可选。它是**一个普通 inbound**（`"protocol":"tun"`），且它自己也承认「这不是真正的 L3 VPN，而是代理的副作用」 | 【源码】`proxy/tun/README.md:117`（LIMITATION）|
| Xray 的 TUN 需要哪些平台能力？ | 需要创建/接管 L3 接口：Linux `ip tuntap`+路由；Windows Wintun DLL；macOS utun；**Android/iOS 则不自建接口，直接吃系统给的 fd**（`xray.tun.fd` / `XRAY_TUN_FD` 环境变量） | 【源码】`proxy/tun/README.md:213-341`；`common/platform/platform.go:29`（`TunFdKey = "xray.tun.fd"`）；`proxy/tun/tun_fd.go` |
| 是否强依赖系统 VPN fd？ | **不强依赖，但「让全设备流量进内核」必须依赖系统 VPN 提供的 TUN fd**（手机端没有别的合法途径） | 推论，依据同上 + HarmonyOS 平台约束（见 harmony-platform-analyst 产物） |
| Xray 自身 TUN 的能力上限 | IPv4/IPv6、TCP/UDP、ICMP **仅 Echo**；其它 ICMP 忽略；且「连接可建立」不代表真实可达（代理语义副作用） | 【源码】`proxy/tun/README.md:107-117` |
| 出站 socket 如何绕过 TUN（防环路） | `sockopt.mark`（`SO_MARK`）、`sockopt.interface`（绑定网卡）、`sockopt.tcpFastOpen` 等 | 【源码】`infra/conf/transport_sockopt.go:46,47,60` |

> ⚠️ **这条是 tun2socks / 全量 VPN 方案能否成立的真实门槛（不是可选项）**：
> 内核接管全设备流量后，**Xray 自己的出站连接也必须走物理网卡**，否则「出站 → 落入 TUN → 又回到 Xray」形成路由环路，方案直接跑不起来。
> 可用的两个机制只有：① `sockopt.mark` 打标 + 系统侧 `ip rule`/策略路由按 mark 走物理表；② `sockopt.interface` 直接把 socket 绑到物理网卡（`SO_BINDTODEVICE`/对应实现）。
> **二者在 HarmonyOS 上是否被允许、是否被应用沙箱/VPN 扩展权限限制，目前无一手证据 → 见 §6-U5，已并入 P-03。** 若两者都不可用，则「Xray 出站」必须换成另一种绕过手段（例如由 tun2socks 侧统一承接出站、内核只做协议），这会改变 §5.2 的形态选择——**因此 U5 必须在 D1 定稿前有结论**。

#### 5.4.1 「GA 有 tun 入站」≠「HarmonyOS 能直连 tun」（防误判，必读）

`proxy/tun` 在 GA v26.3.27 已注册可用，但其**入站形态是"自己创建 tun 设备"**（Linux `ip tuntap` / Windows Wintun / macOS utun / FreeBSD tun(4) 语义）。HarmonyOS 上应用**不能自己创建 tun 设备**，只有 `VpnExtensionAbility` 给的 tun fd，因此唯一可行形态是「**外部注入 fd**」。

**Xray-core 确实有 fd 注入路径，但它被平台构建约束锁死了**【源码，可判定】：

| 文件 | 构建约束 | 行为 |
|---|---|---|
| `proxy/tun/tun_fd.go:1` | `//go:build linux` | 外部 fd 注入实现**仅 Linux** |
| `proxy/tun/tun_android.go:1` | `//go:build android` | Android 走 `common/platform` 的 `xray.tun.fd`（`common/platform/platform.go:29`） |
| `proxy/tun/tun_default.go:1` | `//go:build !linux && !windows && !android && !darwin && !freebsd` | **stub**：所有方法直接 `return errors.New("Tun is not supported on your platform")`（`:17-47`） |

**结论（判定为"需改造"）**：以 `GOOS=openharmony` 构建时，`proxy/tun` 会编译到 `tun_default.go` 的 stub，**`"protocol":"tun"` 在 HarmonyOS 上必然启动失败**。所以：

> **"GA 有 tun 入站" ≠ "HarmonyOS 可直连 tun"。** 在 HarmonyOS 上使用 Xray 原生 TUN，必须**自行新增 `//go:build openharmony` 的实现文件**（补齐 fd 注入 + 规避 VPN fd 拒 `Fstat`，见 F-4），而**这些新增/修改的 Xray 源文件按 MPL-2.0 §3.1 必须以 MPL-2.0 公开**（见 §1.3）。这也解释了为什么 `popsiclelmlm/Hey` 选择绕开、改用 tun2socks（`docs/harmonyos-go-tls-wall.md` §6/§7）。
>
> 附带澄清一处易混点：`libXray` 现役**不再导出 `CGoSetTunFd`** 是「wrapper 的导出面收缩」，**不等于 Xray-core 没有 fd 能力**（core 走的是环境变量 `xray.tun.fd` / `XRAY_TUN_FD`）。两者要分开看，否则会把"我们只要自己包一层就能用"误判为可行——真正拦住它的是上面的 build 约束，而不是 wrapper。

**Hey 的做法与原因（可作为我们的对照先例）**
【实践】`popsiclelmlm/Hey` README + tls-wall §6/§7：
```
HarmonyOS VPN TUN fd
  → libheytun2socks.so（gVisor，默认）或 libhevsocks5tun.so
  → 127.0.0.1:18082（本地 SOCKS/mixed 入站）
  → Xray / sing-box outbound
```
它**明确放弃**把 TUN fd 直接交给 Xray（即不用 `CGoSetTunFd` + `proxy/tun`），理由有两条：
1. **当时**是 go 版本鸿沟：OHOS Go fork 只到 go1.24.5，而带 `proxy/tun` + `TunFdKey` 的 xray-core 已要求 go1.25.7+；
2. 数据面稳定：tun2socks 的 `go.mod` 是 go1.23.4，不依赖 xray-core，构建确定性高。
并且现役 libXray v26.7.28 **已不再导出 `CGoSetTunFd`**，native-TUN 路线在其工程里被搁置。

**归因边界（避免事后归因）**：上述「Hey 为什么绕开 native TUN」的两条理由**仅来自其自身文档**（go 版本鸿沟、数据面构建确定性）。**「出站 socket 必须绕过 TUN」这个门槛是本基线独立分析 Xray-core 能力得出的，Hey 文档并未以此为由**；两者验证方式完全不同（前者改工具链、后者做真机 PoC），在 design.md 中不得合并成同一件事。

**进程拓扑补充**【实践】（来源：R3 竞品分析 `client-benchmark.md` 对 Hey 的观察）：Hey 的 VPN 模式下**内核跑在 VPN 扩展进程内**（主进程 `startVpnExtensionAbility` 传配置，扩展进程自己 `createVpnConnection` 拿 fd 再起 Xray + tun2socks），**主进程与扩展进程之间没有双向 IPC，启动成败靠轮询 JSONL 日志文件判断**。→ 对 §5.2「调试与可观测」一列的含义：进程内库的结构化 error 只在**扩展进程内**可用，主进程天然只能拿到「日志/状态位」，这会直接约束 Q1 里"诊断能力"的需求边界。

> **给 D1 的取舍建议（不是结论，需 design.md 决策）**：> - 路线 A「TUN fd 直喂 Xray」（`proxy/tun` + `xray.tun.fd`）：链路最短、无额外用户态转发；但要求 Go fork 版本 ≥ xray-core 的 go 指令（当前 HEAD go1.27 会卡住），且要处理 F-4（fd 拒 `Fstat`）与 F-6（与 tun2socks 不能共存于同进程）。
> - 路线 B「TUN fd → tun2socks → SOCKS → Xray」（Hey 现役）：构建确定、与 Xray 版本解耦、可换内核（Hey 同时打包了 sing-box）；代价是多一层 gVisor 用户态转发（CPU/吞吐/延迟）。
> - **本基线不替 D1 选**，但要求 D1 明确写「为什么」，并给出 PoC 判定指标（吞吐、P95 延迟、CPU、崩溃率）。

---

## 6. 对 HarmonyOS 的未知项清单（每条：断言 ｜ 验证方式）

| ID | 断言/未知项 | 等级 | 验证方式 | 归属 |
|---|---|---|---|---|
| U1 | 本机无 Go 工具链，`GOOS/GOARCH` 支持情况未本地验证 | 【待验证】 | 在装 Go 1.27+ 的构建机执行 `go tool dist list \| grep -E 'linux/arm64\|ohos'`，并 `GOOS=linux GOARCH=arm64 go build ./main` | R1 环境限制 |
| U2 | 上游 Go 是否已在 1.27/1.28 支持 `GOOS=openharmony`（当前依据是第三方 fork） | 【待验证】 | 查 go.dev/doc/go1.27 release notes + `go tool dist list`；若支持则不再需要 fork | D1/Z1 |
| U3 | `star4277/ohos-go` v1.26.5-beta1 的稳定性与维护持续性（beta 版、个人 fork） | 【待验证】 | 观察 commit 活跃度、是否有 CI、是否有第二家企业使用；准备「自建 fork」兜底方案 | Z1（风险） |
| U4 | GA v26.3.27（go 1.26）能否被 go1.26.5 fork 直接编译出可用 `libxray.so`（含 `PT_TLS`+`TLSDESC`） | 【待验证·高优】 | P-02：按 §2.4.4 四命令校验；再跑真机冷启 cgo 冒烟 | P-02 |
| U5 | HarmonyOS 上的 `sockopt.mark` / `sockopt.interface` 是否被允许（决定出站能否绕过 TUN 防环路） | 【待验证·高优】 | 真机起 SOCKS 入站 + 全量 TUN 路由，观察是否环路；分别试 `mark` 与 `interface` | P-03 |
| U6 | HarmonyOS VPN fd 的 `Fstat` 拒绝行为是否在 API 23 / 更高版本仍一致 | 【实践+待验证】 | 用 `fstat()` 直接探测；参考 Hey 的 `isSocketFD` patch 是否仍需保留 | P-03 |
| U7 | 一个进程内除 libxray 外是否还有其它 Go 产物（如自研 tun2socks）→ 是否触发 F-6 | 【待验证】 | 若两者都需要，验证「合并单次构建」是否可行；否则拆进程 | D1 |
| U8 | Xray 内存/启动开销真机基线 | 【待验证】 | 按 §5.3 方法测量；给出 RSS、启动 P95、200 并发稳态 | P-02 |
| U9 | MPL-2.0 在 AppGallery 上架的申报口径（是否需在 HAP 内附 LICENSE 页面） | 【待验证】 | 查 AppGallery 审核规范 + 法务确认 | Z1 |
| U10 | HEAD 独有的 `proxy/masque`、`transport/internet/xdrive`、`app/geodata` 何时 GA、是否会改变传输选型 | 【待验证·观察项】 | 跟踪 release notes；**在此之前一律不作为设计依赖** | R1 观察项 |
| U11 | 官方 wrapper `libXray` 是否计划出 ohos target（若出，可省掉自建脚本） | 【待验证】 | 跟踪 libXray build 脚本与 issue；当前仅 `android/apple/linux/windows` | D1 |
| U12 | `proxy/tun` 是否支持 HarmonyOS | **已确认（不再待验证）**：【源码】`tun_default.go:1` 的 build tag 把 OHOS 排除在外，`GOOS=openharmony` 下编译到 stub 并必然报 "Tun is not supported on your platform"（`:17-47`）。→ 判定 **"需改造"**，见 §5.4.1 | 剩余未知仅在"若补 `//go:build openharmony` 实现，需多少工作量、fd 语义差异（Fstat）如何规避、以及由此产生的 MPL 开源义务（§1.3）"，验证方式见 P-03 | 已确认 + P-03 |

---

## 7. 参考来源

**源码（本地克隆，仅作调研，不进入交付目录）**
- `D:\projects\xray-harmony\_research_src\Xray-core`，HEAD `95461cc`（2026-10-17）；tag `v26.3.27` 已 fetch
- 关键文件：`core/core.go:21-23`（版本）、`go.mod:3`（go 指令）、`infra/conf/xray.go:27-61,456-476`（协议加载表 / 顶层配置）、`infra/conf/transport_internet.go:18-68`（传输枚举 / REALITY 约束）、`infra/conf/tun.go:18-29`（TUN 配置）、`infra/conf/socks.go:34,61`（SOCKS UDP）、`infra/conf/transport_sockopt.go:46,47,60`（mark/interface/TFO）、`common/platform/platform.go:29`（TunFdKey）、`proxy/vless/vless.go:18`（Vision flow）、`proxy/shadowsocks_2022/shadowsocks_2022.go:165-167`（SS2022 方法）、`proxy/tun/README.md`（TUN 全平台细节）、各 `app/*/command/*.proto`（控制面）、`main/distro/all/all.go`（组件注册表）

**官方文档**
- Xray-core GitHub Releases API（`/releases/latest`、`/releases?per_page=50`）——版本与节奏
- Xray-core README（License / One-line Compilation / Android 构建命令 / Wintun 第三方组件 / GUI Clients / Wrappers）
- MPL-2.0 许可正文与 Mozilla FAQ（文件级 copyleft、§3.1/§3.2/§3.3）
- libXray README（CalVer/SemVer 镜像、build targets、单进程单 Go runtime WARNING，引 Go #18976 / #15956）
- 官方站点 `https://xtls.github.io`（Project X 文档）

**社区实践（一手排查记录）**
- `popsiclelmlm/Hey`（HarmonyOS NEXT 客户端，ArkTS + VPN Extension + NAPI）：`README.md`、`docs/harmonyos-go-tls-wall.md`、`docs/building-native-cores.md`
- 参照工程：`XTLS/libXray`、`2dust/AndroidLibXrayLite`、`XTLS/X-flutter`

---

## 附：本文与下游的关系

| 下游 | 本文提供的输入 |
|---|---|
| D1（design.md） | 传输选型（XHTTP 主线 / WS-gRPC 过渡）、控制面边界（§4.2）决定进程模型、TUN 路线 A/B 取舍（§5.4）、构建链与工具链钉版（§2.4、§1.2） |
| Q1（requirements.md） | 能力边界四态（支持/部分/不支持/需改造）、性能指标只能来自实测（§5.3）、MPL 合规需求（§1.3） |
| Z1（risks） | §6 待验证清单即 PoC 候选池（U3/U4/U5/U6 为高优）、MPL 上架合规（U9） |
| P-01/P-02/P-03 | §2.4.3 失败模式对照表 + §2.4.4 判定命令 + §5.4 数据面两方案 |

---

## 修订记录

### v0.1-r2（2026-10-17）R1 × R3 传输事实冲突裁决

**冲突**：R3（`client-benchmark.md`）表述为「2026 版 Xray 已移除 `quic`/`h2`，`ws`/`grpc` 标记 deprecated」；R1 §2.2 分列为「`quic`/`h2`/`h3` 已移除」与「`ws`/`grpc`/`httpupgrade` deprecated 但可用」。

**裁决：R1 §2.2 正确，无需修订矩阵；R3 的合并表述需纠正。** 源码判据（@`v26.3.27`，GA）：

| 项 | 事实 | 判据 |
|---|---|---|
| `transport/internet/quic`、`h2`/`h3` 目录 | **已不存在** | `git ls-tree --name-only v26.3.27 transport/internet/` 输出中无 `quic`、`h2`、`h3` |
| 配置值 `"quic"` / `"h2"` / `"h3"` / `"http"` | **被拒绝并报错（致命）** | `infra/conf/transport_internet.go:1013-1017@v26.3.27`：`return "", errors.PrintRemovedFeatureError("QUIC transport …", "XHTTP stream-one H3")` / 同理 `h2|h3|http` → `XHTTP stream-one H2 & H3` |
| 配置值 `"ws"` / `"grpc"` / `"httpupgrade"` | **仍可使用**，仅打印 deprecation 告警后正常返回协议名（非致命） | 同文件 `:1006-1011@v26.3.27`：`errors.PrintNonRemovalDeprecatedFeatureWarning(...)` 之后 `return "grpc", nil` / `return "websocket", nil` / `return "httpupgrade", nil` |
| HEAD 95461cc 是否一致 | **一致**（`quic`/`h2` 仍移除，`ws`/`grpc`/`httpupgrade` 仍 deprecated-可用） | `infra/conf/transport_internet.go:26-38@95461cc` |

**给下游的措辞（请统一使用这一版）**：
> 「QUIC 传输与 HTTP(H2/H3) 传输在 GA v26.3.27 已被**移除**（配置直接报错，不加载）；gRPC / WebSocket / HTTPUpgrade 传输**仍可用但已 deprecated**（启动打印告警，官方建议迁移到 XHTTP）。因此对用户既有 `ws`/`grpc` 节点的兼容性**必须保留**，而 `quic`/`h2` 节点已无法通过 Xray 连接。」

**这一条对需求的直接影响**：Q1 的「协议兼容性」承诺必须按「支持 ws/grpc/httpupgrade（含告警）」与「不支持 quic/h2/h3（配置即错）」分开写，不能笼统写「兼容 Xray 全部传输」。

### v0.1-r1（2026-10-17）首版
正文 §0–§7 初稿落盘。

