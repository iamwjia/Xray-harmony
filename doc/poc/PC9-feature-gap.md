# PC9 — 实现 vs 需求的功能差距分析

| 项目 | 内容 |
|---|---|
| 文档 | PC9 · 功能差距分析（实现 vs `doc/requirements.md` FR-01~FR-40 / NFR-01~NFR-13） |
| 作者 | requirements-architect |
| 日期 | 2026-10-18 20:30（**快照时间点**，见 §0.2） |
| 任务 | E18：评估当前实现相比需求缺哪些基本功能（安全 / 分流 / 激活关闭 / 代理参数） |
| 性质 | **只读分析**，不写代码、不改需求文档；结论全部来自源码阅读（`file:line`）与实测记录引用 |
| 上游 | `doc/requirements.md`、`doc/design.md`、`doc/poc/PC6-skeleton-build-log.md`、`entry/src/main/ets/**` |

---

## 0. 证据规则与快照

### 0.1 状态定义（三值，不放水）

| 状态 | 判定标准 |
|---|---|
| **已实现** | 有代码路径 **且** 有验证证据（真机/模拟器实测记录或可执行断言） |
| **部分** | 有代码但**未验证**（未编译通过 / 未真机跑过），**或**只实现了需求的子集 |
| **未实现** | 无对应代码，或只有数据结构/字段而无功能入口 |

> 本文件**不把"计划做"写成"部分实现"**。凡只有模型字段、没有可调用路径的，一律记 `未实现`（并在"差距"列注明"有模型无功能"）。

### 0.2 快照声明（重要：当前代码处于活跃修改中）

本分析基于 **2026-10-18 20:30** 的文件快照。检查期间以下文件在数分钟内被改动，结论已按最新快照取值，但**读者需知道这是移动靶**：

| 文件 | 最后修改 | 影响 |
|---|---|---|
| `service/SettingsStore.ets` | 20:29:56（**新增**） | 设置（routingMode / logLevel / onboardingDone）持久化正在落地 |
| `service/ConfigService.ets` | 20:30:08 | 已 import `RoutingMode` 与 `SettingsStore`（此前的"未 import 编译阻断"已修复） |
| `pages/Settings.ets` | 20:28:47 | 新增分流模式三按钮 UI |
| `service/KernelConfigBuilder.ets` | 20:28:29 | 新增 `buildRouting(mode)`，`buildWithNode` 增加第三个参数 |
| `pages/Index.ets` | 20:28:33 | `doConnect()` 读 `routingMode` 并传入 builder |
| `model/AppConfig.ets` | 20:26:04 | `RoutingMode` 枚举与 `rules` 数组 |
| `pages/Nodes.ets` / `ShareLinkParser.ets` / `NodeStore.ets` | 20:22–20:24 | 导入链路与节点持久化 |

**结论口径**：分流相关能力按"**刚接入、未编译验证**"记为 `部分`；安全存储、SOCKS 鉴权、订阅导入、VPN/tun 链路按"**无实现**"记为 `未实现`（与 leader 已核实事实一致，不重复验证）。

### 0.3 未验证项的统一标注

凡本文件写"未验证"，含义是：**该代码未经编译验证，或未经真机/模拟器执行**。仓库内唯一的实测记录是 `doc/poc/PC6-skeleton-build-log.md`（M2~M8 探针、启动链路、`startVpnExtensionAbility` 永久挂起 §11.5）。除此之外的执行证据一律视为不存在。

---

## 1. 差距总表

### 1.1 功能需求（FR-01 ~ FR-40）

> 列含义：**当前状态**（三值）｜**差距**（具体缺什么）｜**阻塞**（`VPN+tun2socks` 前置 = 需要先打通真实数据面；`真机` = 需要设备验证；`无` = 纯应用层可做）

| FR | 需求（简） | 优先级 | 当前状态 | 差距（证据 → 缺什么） | 阻塞 |
|---|---|---|---|---|---|
| FR-01 | 分享链接导入单节点 | P0 | 部分 | `Nodes.ets:42-63 doImport` + `ShareLinkParser.parse`（`:45`）支持 vless/vmess/trojan/ss 四协议；**未编译验证、未真机跑过**；失败文案为解析器直出（`ShareLinkParser.ets:47-63`），未做"URL 结构错误/参数缺失/凭据无效"四类归因 | 无 |
| FR-02 | 订阅链接导入（含 Base64） | P0 | **未实现** | 全仓无 HTTP 封装：`grep createHttp/@kit.NetworkKit/rcp` 无命中（仅 DevPanel/VpnExtAbility 有 NetworkKit 的 vpnExtension 导入）；`AppConfig.ets:71-78 Subscription` 类**只有字段**，无下载/解析/UI/落盘；`ConfigService.ets:122-139` 只有 `addNode` 单条 | 无（但需新增网络权限用法） |
| FR-03 | 节点列表 CRUD 与排序 | P0 | 部分 | 有：列表 `Nodes.ets:92-114`、选中 `pick()`、导入去重 `ConfigService.addNode`；**缺：编辑、删除、排序、分组**（无任何 `removeNode/updateNode/moveNode`）；无"用户移除的节点不被订阅恢复"概念 | 无 |
| FR-04 | 手动新建/编辑节点与参数校验 | P0 | **未实现** | `XrayNode`（`AppConfig.ets:39-68`）有全部字段，但**无表单页、无保存入口**；无 REALITY 仅 `raw/xhttp/grpc` 的组合校验；无 `http` 传输的拦截（反而能映射到已移除的 `http`，见 §5-①） | 无 |
| FR-05 | 配置生成与合法性校验 | P0 | 部分 | 有生成：`KernelConfigBuilder.buildMinimal/buildWithNode`（`:22`/`:31`），全部值经 `esc()`（`:122`）转义；**缺：生成前校验**（无 schema/端口/字段必填校验）、**无纯函数快照测试**、无"规则数超上限即阻止启动" | 无 |
| FR-06 | 分流模式三态 | A · P0 | 部分 | 有：`RoutingMode`（`AppConfig.ets:32-36`）、`buildRouting`（`KernelConfigBuilder.ets:48-60`）、`Settings.ets:63-80` 三按钮、`Index.ets:62-70` 传入；**缺：编译验证、真机验证**；RULE 模式仅 8 个内网网段（`:56-59`），**无 geosite/geoip**；GLOBAL 模式不生成 routing 段（`:52-54`，等价"全走 proxy"但未显式声明） | 真机 |
| FR-07 | 自定义路由规则编辑 | A · P1 | **未实现** | `RoutingRule`（`AppConfig.ets:81-89`）有模型、`createDefaultConfig` 塞了 1 条假规则 `geosite:cn`（`:249-254`），但**无 UI、无增删改、且该规则不进内核**（builder 不读 `rules`） | 无 |
| FR-08 | DNS 策略（默认隧道内解析） | A · P0 | **未实现** | 生成配置里**无 `dns` 段、无 `dnsAddresses`**（`KernelConfigBuilder.ets:22-40` 全量字段可核）；无 DNS 设置 UI；无"回落系统 DNS"防护 | VPN+tun2socks |
| FR-09 | 节点切换（快速重启内核） | A · P0 | 部分 | 有"停→换→启"的零件：首页断开 `Index.ets:85-99`、重连 `:62-83`、`KernelService.stop/start`；**缺：一次性切换动作、切换中 UI 状态、失败回退到原节点**；切换耗时无测量 | 真机 |
| FR-10 | 建立连接与首次 VPN 授权引导 | A · P0 | **未实现** | 当前"连接"= 起本地 socks 内核（`Index.ets:62-83` → `KernelService.start`），**完全不涉及 `startVpnExtensionAbility`**；`VpnExtAbility.ets:16-23` 只有 onCreate/onDestroy 打日志，**未调用 `createVpnConnection/create()`**；无授权说明页 | VPN+tun2socks |
| FR-11 | 长时任务保活与常驻通知 | A · P0 | **未实现** | 全仓无 `startBackgroundRunning`；`module.json5` 仅声明 `ohos.permission.INTERNET`，**无 `KEEP_BACKGROUND_RUNNING`、无 backgroundModes** | VPN+tun2socks |
| FR-12 | VPN 冲突诊断（2203002） | A · P0 | **未实现** | 无 2203002 分支、无"其他 VPN 已激活"提示与重试；`DevPanel.ets:92-108` 的 M4 只把 `BusinessError.code` 打到界面/日志 | VPN+tun2socks |
| FR-13 | **UI 状态与真实隧道状态一致（红线1）** | 共用 · P0 | 部分 | 有单向派生骨架：`ConnectionViewModel.deriveView()`（`:98-126`）、`Index.refreshAll()`、`KernelService.queryRunning()` 以 `getXrayState.running` 为准（`:107-113`）；**缺：`running=true` 只代表内核进程活着，不代表隧道可用**（无 tun、无出站探测）→ 当前"已连接"文案在语义上已偏乐观；无 `BEARER_VPN` 事件、无系统侧被动停止感知、冷启动不探测而直接读内存态 | VPN+tun2socks |
| FR-14 | **终止可感知（红线2）** | 共用 · P0 | **未实现** | 无"上次连接中断原因"记录（无落盘会话标记）、无首屏中断横幅；杀进程后重开只会看到"未连接" | 无 |
| FR-15 | **事实不通可检出（红线3）** | 共用 · P0 | **未实现** | 无数据面健康探测、无"已连接但无流量"独立状态（`ConnState` 只有 4 态，`ConnectionViewModel.ets:14-19`） | VPN+tun2socks |
| FR-16 | 中断后的恢复体验 | 共用 · P0 | 部分 | 有半个前提：节点与选中项重启后仍在（`ConfigService.ets:42-51` + `NodeStore`）；**缺：恢复入口、一键恢复、分类错误处置**；首页只有"连接"按钮，无"上次节点 + 一键恢复" | 无 |
| FR-17 | 首次连接一次性明示（四要素模态） | 共用 · P0 | **未实现** | `AppSettings.onboardingDone`（`AppConfig.ets:96`）有字段、`SettingsStore` 正在加持久化，但**无模态 UI、无四要素文案** | 无 |
| FR-18 | 网络切换后自动重连 | A · P0 | **未实现** | 无 `connection.on('netAvailable')`/网络状态监听（全仓无 `@ohos.net.connection` 引用） | VPN+tun2socks |
| FR-19 | IPv6 纳入隧道（四条件） | A · P0 | **未实现** | 无 `VpnConfig`，四条件（flag/v6 地址/v6 routes/内核 v6 出站）全部不具备 | VPN+tun2socks |
| FR-20 | IPv6 保护状态可见 | A · P0 | **未实现** | 无诊断页、无 IPv6 状态行 | VPN+tun2socks |
| FR-21 | 分应用分流（免权限配置模式） | A · P0 | **未实现** | 无 `trustedApplications/blockedApplications`、无预置应用表、无三路配置入口 | VPN+tun2socks |
| FR-22 | 连接诊断（分步定位） | 共用 · P0 | 部分 | 有错误人话化：`KernelService.humanize()`（`:85-104`）把 `unknown method/config/listen/unparsable` 四类翻译，并在首页展示（`Index.ets:54-60`）；**缺：分步诊断页（内核加载/配置合法性/隧道/出站/DNS 五项）、缺"展开原始错误"** | 部分需 VPN+tun2socks |
| FR-23 | 日志查看与导出（脱敏） | 共用 · P0 | **未实现** | `Logger.ets:12-23` 只有 info/warn/error → hilog，**无级别过滤、无落盘、无脱敏、无导出入口**；且会把完整节点串打印进日志（见 `ConfigService.ets:110/127/137`） | 无 |
| FR-24 | 崩溃诊断（上次异常退出） | 共用 · P0 | **未实现** | 无崩溃标记落盘、无"上次异常退出"呈现、无诊断包 | 无 |
| FR-25 | 流量与连接统计 | 共用 · P1 | **未实现** | 未调用 `CGoQueryStats`/stats；无 UI | VPN+tun2socks |
| FR-26 | 订阅更新 | 共用 · P1 | **未实现** | 无订阅实体落盘（`subscriptions` 字段无人写）、无更新入口 | 无（依赖 FR-02） |
| FR-27 | 桌面卡片/快捷启动 | 共用 · P1 | **未实现** | 无卡片/快捷方式配置，无 `EntryFormAbility` | 无 |
| FR-28 | 停用/重置/清除数据 | 共用 · P1 | **未实现** | 无清除入口；`ConfigService.save()` 明写未实现（`:153-160`） | 无 |
| FR-29 | 许可与来源声明（MPL-2.0） | 共用 · P0 | **未实现** | `Settings.ets:86-92` 仅显示"内核：libXray v26.7.28"，**无 MPL-2.0 全文、无源码获取方式、无第三方依赖清单** | 无 |
| FR-30 | 预置应用包名表 | A · P0 | **未实现** | 无表、无搜索、无更新机制 | VPN+tun2socks |
| FR-31 | 协议/传输支持集合 | 共用 · P0 | 部分 | 有 vless/vmess/trojan/ss + `raw/ws/grpc/mkcp`（`KernelConfigBuilder.networkOf:126-140`）+ TLS/REALITY；**缺：xhttp、httpupgrade**（枚举里都没有，`AppConfig.ets:16-22`）；**`http2` 被映射成 `http`（`:133-135`），而 `http` 传输在目标内核版本已移除**；**REALITY 缺 `publicKey/shortId`（`:114-117` 只有 serverName+fingerprint）** → 真机必然握手失败 | 无（但需真机逐个协议验证） |
| FR-32 | 应用内局部代理（形态 B） | B · P2 | **未实现** | 无本地 SOCKS→应用内代理矩阵、无端口控制面板 | 无 |
| FR-33 | 多语言 | 共用 · P1 | **未实现** | 全部中文硬编码字符串（`Index.ets:112-113` 等），无 resources 多语言目录使用 | 无 |
| FR-34 | 无障碍基础能力 | 共用 · P1 | **未实现** | 无 accessibility 属性、无读屏标签、无焦点顺序声明 | 无 |
| FR-35 | 本地入站端口安全 | 共用 · P0 | 部分 | 有回环：`KernelConfigBuilder.ets:24/33` `listen:"127.0.0.1"`；**缺：随机端口（固定 `18080`，`:19`）、缺鉴权（`auth:"noauth"`）、无风险提示** | 无 |
| FR-36 | 数据面健康探测与自愈 | A · P0 | **未实现** | 无探测定时器、无自动重启内核、无"需用户介入"状态；`KernelService` 只在 start 时校验一次 running | VPN+tun2socks |
| FR-37 | 规则命中可解释 | A · P1 | **未实现** | 无 per-connection 记录 | VPN+tun2socks |
| FR-38 | 高级字段三层能力 | 共用 · P1 | **未实现** | 无 `mtu/mux/fingerprint/sockopt` 字段、无生成结果查看、无 JSON 导入转换 | 无 |
| FR-39 | 接管面变更必须断连并告知 | A · P0 | **未实现** | 无"接管面字段"概念（因无 `VpnConfig`）；当前改分流模式只需重建内核，不涉及断连提示 | VPN+tun2socks |
| FR-40 | `startVpnExtensionAbility` 超时兜底 | A · P0 | 部分 | 有实测证据（`PC6-skeleton-build-log.md` §11.5：6s 后仍 pending）与 6s 日志（`DevPanel.ets:63-65`），**但无 5~10s 主动超时 → 提示 → 重试的 UI 闭环**；且主连接路径根本未调用该 API | 真机（真因为设备侧缺组件） |

**FR 汇总**：共 40 条。`已实现` **0** 条（无一条有真机/编译验证 + 完整验收）；`部分` **11** 条（FR-01/03/05/06/09/13/16/22/31/35/40）；`未实现` **29** 条。

> 说明：`已实现 = 0` 不是唱衰，而是执行 §0.1 的严格判定（当前代码未编译验证、未真机跑过完整链路）。一旦完成首次编译 + 真机跑通导入→起核→SOCKS 出网，FR-01/03/05/31 可整批升级为"已实现"。

### 1.2 非功能需求（NFR-01 ~ NFR-13）

| NFR | 类别 | 当前状态 | 差距 | 阻塞 |
|---|---|---|---|---|
| NFR-01 | 性能 | 未实现（也不应现在实现） | 无任何测量代码；`PC6` 日志里无 RSS/建连耗时数据 | 真机 |
| NFR-02 | 功耗 | 未实现 | 无功耗基线采集；无保活即无后台功耗问题 | 真机 |
| NFR-03 | 崩溃率 | 未实现 | 无会话计数、无崩溃采集 | 无 |
| NFR-04 | 恢复成功率 | 未实现 | 依赖 FR-14/16 的中断分类统计 | 无 |
| NFR-05 | 长跑退化 | 未实现 | 无长跑观测 | 真机 |
| NFR-06 | 安全 | **未实现** | 凭据明文：`NodeStore.ets:116/132` 注释 `TODO: HUKS/ASSET`；全仓无 `security.asset/huks/relationalStore/preferences` 引用；诊断包无、脱敏无 | 无 |
| NFR-07 | 隐私 | 部分 | 好的一面：无任何上传代码（无 HTTP 封装即无外联）；坏的一面：日志含凭据（`Logger` 打印完整节点串），属隐私泄漏面 | 无 |
| NFR-08 | 可用性 | 未实现 | 见 FR-33/34 | 无 |
| NFR-09 | 合规 | 部分 | 仅"关于"页显示内核版本（`Settings.ets:89`）；MPL 义务四项未落地（FR-29） | 无 |
| NFR-10 | 兼容性 | **偏离需求** | `build-profile.json5`：`compatibleSdkVersion = "26.0.0"`（需求要求 **12**）；当前仅 `INTERNET` 权限；未做 API 档位能力差异处理（64/256、`BEARER_VPN` 12+） | 无 |
| NFR-11 | fail-closed | 未实现 | 无阻断策略、无 IPv6 接管、无 DNS 防泄漏 | VPN+tun2socks |
| NFR-12 | 可维护性 | 部分 | 依赖版本仅"关于"页一行；无六字段依赖清单（含 ohos-go fork 锁版本） | 无 |
| NFR-13 | 崩溃可诊断 | 未实现 | 见 FR-24 | 无 |

### 1.3 汇总统计

| 维度 | 数据 |
|---|---|
| FR 总数 / 已实现 / 部分 / 未实现 | 40 / **0** / **11** / **29** |
| MVP（P0）FR 数 | **30 条**（FR-01~06、08~24、29~31、35、36、39、40） |
| MVP 中 `未实现` / `部分` | **19 条** / **11 条** |
| V1·P2 中 `未实现` | **10 条**（FR-07/25/26/27/28/32/33/34/37/38） |
| 被平台侧阻塞（`VPN+tun2socks` 前置）的 `未实现` 项 | **13 条**（FR-08/10/11/12/15/18/19/20/21/30/36/37/39） |
| **纯应用层可推进的 P0 缺口** | **8 条完全可做**（FR-02/04/14/17/23/24/29/35 补全）＋ **3 条可部分推进**（FR-13/16/22），均不依赖数据面打通 |

---

## 2. 四个重点域

### 2.1 安全设置域

**有什么（证据）**
| 能力 | 现状 | 证据 |
|---|---|---|
| 配置/节点读取失败保护 | 加载失败不覆盖原数据、禁止写盘、首页横幅可见 | `ConfigService.ets:22-27/73-86`、`Index.ets:45-46/116-124`；`NodeStore.load()` 返回 null 语义（`NodeStore.ets:73-100`） |
| schema 版本保护 | 高版本拒绝加载，避免降级损坏 | `AppConfig.ets:186-189` |
| 本地入站仅回环 | `listen:"127.0.0.1"` | `KernelConfigBuilder.ets:24/33` |
| 日志错误归一化 | 内核原始错误进日志、人话给人看 | `KernelService.ets:85-104` |

**缺什么（用户路径缺口 → FR）**
| # | 缺口 | 用户想做什么 / 现在做不到 | FR | 优先级 |
|---|---|---|---|---|
| S-1 | **凭据明文落盘** | 用户以为"节点密码只在本机安全区"；实际随 `PersistentStorage` 明文 JSON 落盘（`NodeStore.ets:116`） | NFR-06 / FR-29 | **P0，安全级** |
| S-2 | 无日志脱敏 | 用户反馈问题时把日志发出去，等于把 UUID/密码发出去（`ConfigService` 打印整串） | FR-23 / NFR-07 | **P0** |
| S-3 | 无诊断包导出与指纹 | 用户无法"一键导出可诊断信息"；也没有导出包指纹以便核对未被篡改 | FR-23/FR-24 | **P0** |
| S-4 | SOCKS 无鉴权、固定端口 18080 | 同机任意应用可白嫖代理（对应 v2rayNG #5457，347 评论） | FR-35 | **P0** |
| S-5 | 无隐私开关/无"清空日志" | 用户无法主动清痕 | FR-28 / NFR-07 | P1 |
| S-6 | 无防误操作护栏 | 无"清除全部配置"二次确认（因整体无清除功能）；无"切换接管面会断连"提示（因无 VPN） | FR-28 / FR-39 | P1 |
| S-7 | 无 loopback 风险告知 | 用户不知道本机有代理端口在监听 | FR-35 | P0 |

**建议优先级**：S-1（明文凭据）> S-2（日志脱敏）> S-4（鉴权+随机端口）> S-3（诊断包）> S-7 > S-6/S-5。

### 2.2 分流设置域

**有什么（证据）**
| 能力 | 现状 | 证据 |
|---|---|---|
| 三模式枚举 | `GLOBAL/RULE/DIRECT`，默认 `RULE` | `AppConfig.ets:32-36/93` |
| 三模式 UI | 设置页三按钮 | `Settings.ets:63-80` |
| 模式写入内核配置 | `buildWithNode(node, port, routingMode)` → `buildRouting()` | `KernelConfigBuilder.ets:31-39/48-60`；`Index.ets:62-70` |
| 持久化 | **正在落地**：`SettingsStore`（20:29:56 新增）+ `ConfigService` 已 import | `SettingsStore.ets:1-80`、`ConfigService.ets:1-4` |
| 规则模型 | `RoutingRule{id,matchType,pattern,action,enabled}` | `AppConfig.ets:81-89` |

**缺什么**
| # | 缺口 | 用户路径缺口 | FR | 优先级 |
|---|---|---|---|---|
| R-1 | **RULE 模式没有真正的分流规则** | 用户选"规则"以为国外走代理、国内直连；实际只有 8 个内网网段直连，**所有公网流量（含国内站点）全走代理** | FR-06/FR-07 | **P0（语义误导，比缺功能更危险）** |
| R-2 | 无 geo 资源（geoip.dat/geosite.dat） | 用户无法获得"绕过大陆"这类预期行为 | FR-06/FR-07 | P0 |
| R-3 | 无自定义规则 UI | 用户无法加"某域名直连/某 IP 拦截" | FR-07 | P1 |
| R-4 | `createDefaultConfig` 塞的 `geosite:cn` 假规则不进内核 | 用户以为默认有一条国内直连规则；实际 builder 完全忽略 `rules` | FR-05/FR-07 | **P0（假承诺）** |
| R-5 | 无分应用分流 | 用户无法"只让某几个应用走代理" | FR-21 | P0（阻塞于 VPN 链路） |
| R-6 | 分流模式切换与"接管面变更"未区分 | 未来接入 VPN 后，改分应用/路由属接管面，需断连告知；当前无此概念 | FR-39 | P0（依赖 VPN） |
| R-7 | 模式切换无生效反馈 | 用户改完模式不知道是否已生效（需重连才生效，UI 未说明） | FR-13/FR-39 | P1 |

**建议优先级**：R-1/R-4（语义纠正，可与 R-2 合并成"规则集最小可用"）> R-2 > R-3 > R-7 > R-5/R-6（随 VPN 链路）。

### 2.3 激活 / 关闭域

**有什么（证据）**
| 能力 | 现状 | 证据 |
|---|---|---|
| 首页开关 | 单按钮 连接/断开，四态展示 | `Index.ets:101-108/135-138`；`ConnectionViewModel.ets:98-126` |
| 真实内核状态为准 | start 后以 `getXrayState.running` 确认为 CONNECTED | `KernelService.ets:130-143` |
| 超时兜底（内核启动） | 8s 超时 → ERROR 并显示原因 | `KernelService.ets:116-127/141`；`Index.ets:71-82` |
| 失败路径可演示 | DevPanel 可注入非法配置 | `DevPanel.ets:206-212`、`KernelService.ets:165-172` |
| 状态迁移表 | 合法迁移白名单，非法迁移被拒 | `ConnectionViewModel.ets:43-71` |

**缺什么**
| # | 缺口 | 用户路径缺口 | FR | 优先级 |
|---|---|---|---|---|
| A-1 | **没有"接管全设备流量"的激活** | 用户点"连接"后，只有本机 `127.0.0.1:18080` 的 SOCKS 在跑，**手机其他应用完全不受影响**；用户会认为"连上了却没用" | FR-10/FR-19/FR-21 | **P0（阻塞于 VPN+tun2socks）** |
| A-2 | 无 VPN 首次授权引导 | 授权弹窗出现时用户不知道为何需要 | FR-10 | P0（阻塞） |
| A-3 | 无开机恢复（平台不支持）+ 无启动即恢复 | 重开应用后不自动恢复上次连接，也无"一键恢复" | FR-14/FR-16 | **P0（纯应用层可做）** |
| A-4 | 无副开关（仅本应用生效） | 用户想"只给自己用浏览器/本应用"，现在只能起内核但无应用内代理入口 | FR-32（V1） | P2 |
| A-5 | 无断开原因提示（系统侧） | 被系统/其他 VPN 打断后，用户只看到"未连接" | FR-13/FR-14 | P0 |
| A-6 | 无 `startVpnExtensionAbility` 超时闭环 | 实测该 Promise 可能永久挂起（`PC6 §11.5`），当前仅日志提示，**无 5~10s 超时 + 重试** | FR-40 | **P0（真机）** |
| A-7 | 无保活/常驻通知 | 退到后台后内核是否被杀未知（未验证），无长时任务 | FR-11 | P0（阻塞） |
| A-8 | 无健康探测/自愈 | "已连接"可能早已不通 | FR-15/FR-36 | P0 |

**建议优先级**：A-6（超时闭环，真机可做）> A-3（恢复体验）> A-5（断开原因）> A-1/A-2/A-7/A-8（随 VPN+tun2socks 主线）> A-4（V1）。

### 2.4 代理参数设置域

**有什么（证据）**
| 能力 | 现状 | 证据 |
|---|---|---|
| 分享链接解析 | vless/vmess/trojan/ss；ws/grpc/h2/tcp/mkcp；tls/reality/none；sni/path/host/serviceName/flow | `ShareLinkParser.ets:45-64`、`:66-77`（映射表）、`:130-160`（vless 字段） |
| 节点持久化 | `PersistentStorage` + JSON + schema | `NodeStore.ets:44-100` |
| 节点选中 | 列表点选、自动选首个 | `Nodes.ets:33-39`、`ConfigService.ets:42-51` |
| 协议出站生成 | vless（含 flow）/vmess/trojan/ss | `KernelConfigBuilder.ets:61-95` |
| 日志级别设置 | 四档按钮（**但 Logger 未按级别过滤**） | `Settings.ets:46-56`；`Logger.ets:12-23` |

**缺什么**
| # | 缺口 | 用户路径缺口 | FR | 优先级 |
|---|---|---|---|---|
| P-1 | 无订阅导入 | 用户只有一条链接，几十个节点要手工粘几十次 | FR-02 | **P0（纯应用层）** |
| P-2 | 无节点编辑/删除/排序 | 打错一个字只能重导；无法整理 | FR-03/FR-04 | **P0** |
| P-3 | 无测速/延迟测试 | 用户无法判断"哪个节点能用"（对应 v2rayNG #1346 类痛点） | FR-25（待补） | P1 |
| P-4 | 无 MTU/UDP/SOCKS 端口设置 | `udp:false` 硬编码（`KernelConfigBuilder.ets:25/34`），用户无法开 UDP；端口固定 18080 | FR-35/FR-38 | P1（UDP 是 P0 级体验差） |
| P-5 | 无分流/DNS 参数入口 | 见 §2.2 与 FR-08 | FR-08 | P0（DNS） |
| P-6 | 无 XHTTP / HTTPUpgrade 传输 | 新协议节点导入后无法连接（`TransportKind` 无对应项） | FR-31 | P1（但会影响可用率） |
| P-7 | REALITY 参数不全 | 导入 REALITY 节点必然握手失败（缺 `publicKey/shortId`） | FR-31 | **P0（功能不可用）** |
| P-8 | SS2022 无方法白名单 | 用户导入 `2022-blake3-*` 可能以 `aes-256-gcm` 兜底解析错误 | FR-31 | P1 |
| P-9 | 无多配置/多订阅切换 | 只有一个 nodes 列表，无 profile 概念 | FR-26 | P2 |
| P-10 | 无高级字段（mtu/mux/fingerprint） | 无法调优，也无法排障 | FR-38 | P1 |

**建议优先级**：P-7（REALITY 参数，直接影响"能不能连"）> P-1（订阅）> P-2（编辑删除）> P-4（UDP/端口）> P-5（DNS）> P-6 > P-3 > P-10 > P-8 > P-9。

---

## 3. MVP 缺口清单（不补就不能给普通用户用）

> 排序原则：**先解除"看起来能用其实没用"的语义风险 → 再补"能用"的必要件 → 最后补"好用"**。工作量：小 ≤0.5 人日 / 中 0.5~2 人日 / 大 >2 人日（含真机与排障）。

| # | 缺口 | 对应 FR | 工作量 | 需真机 | 阻塞上架 | 依赖 |
|---|---|---|---|---|---|---|
| M-1 | **"已连接"语义纠正**：在无 tun 的情况下不得表述为"已连接/已保护"；改为"本地代理已启动（仅本机）" | FR-13 | 小 | 否 | 是（虚假宣传风险） | 无 |
| M-2 | **REALITY 参数补全**（`publicKey/shortId/spiderX`）或**导入时明确拒绝** | FR-31 | 小 | 是 | 是（功能不可用） | 无 |
| M-3 | **`http` 传输拦截**：`http2/h2` 映射到已移除的 `http` → 导入即明确报错，不得生成必失败配置 | FR-31 | 小 | 否 | 是 | 无 |
| M-4 | **`startVpnExtensionAbility` 超时闭环**（5~10s → 提示 → 重试） | FR-40 | 小 | 是 | 是 | 无 |
| M-5 | **凭据安全存储**（ASSET/HUKS 或至少 RDB 加密），迁移 `credentialRef` | NFR-06/FR-29 | 中 | 否 | 是（隐私合规） | 无 |
| M-6 | **日志脱敏 + 级别过滤 + 导出诊断包** | FR-23/NFR-07 | 中 | 否 | 是 | M-5（导出包不得含凭据） |
| M-7 | **首次连接一次性明示（四要素）** | FR-17 | 小 | 否 | 是（合规/期望管理） | M-1 |
| M-8 | **终止可感知 + 一键恢复** | FR-14/FR-16 | 中 | 否 | 是 | 无 |
| M-9 | **本地端口安全**（随机端口 + 默认鉴权 + 风险提示） | FR-35 | 小 | 否 | 是（安全） | 无 |
| M-10 | **订阅导入**（HTTP 拉取 + Base64 解析 + 批量入库/去重） | FR-02 | 中 | 否 | 否（体验强相关） | 无 |
| M-11 | **节点编辑/删除** | FR-03/FR-04 | 中 | 否 | 否 | M-10（批量后更需管理） |
| M-12 | **规则集最小可用**（内置 geo 或明确降级说明；删除"假 geosite:cn"承诺） | FR-06/FR-07 | 中 | 否 | 是（语义一致性） | 需确定资源内置策略（体积） |
| M-13 | **DNS 策略最小实现**（隧道内 DNS，防回落） | FR-08 | 中 | 是 | 否 | VPN+tun2socks |
| M-14 | **VPN 激活链路**（`createVpnConnection` + tun2socks + 前台保活通知） | FR-10/FR-11/FR-19 | **大** | 是 | 是 | **PC3/J-01** |
| M-15 | **22 03002 冲突提示 + 授权引导** | FR-10/FR-12 | 小 | 是 | 是 | M-14 |
| M-16 | **健康探测与自愈（最小版：探测 + 停隧道 + 提示）** | FR-15/FR-36 | 中 | 是 | 是 | M-14 |
| M-17 | **许可与来源声明页（MPL 四项义务）** | FR-29 | 小 | 否 | 是（法务） | 无 |
| M-18 | **IPv6 接管+阻断 + 状态可见** | FR-19/FR-20 | 中 | 是 | 是（fail-closed） | M-14 |
| M-19 | **分应用分流（预置表+手输）** | FR-21/FR-30 | 中 | 是 | 否 | M-14 |

**最小可给别人试用的门槛判断**：M-1~M-9 + M-14 + M-15 全部完成（约 **12 项**，其中 1 项"大"）才具备"交给普通用户且不被立刻当骗子/当 bug"的条件；M-10~M-13 决定"用起来是否顺手"。

---

## 4. 三条判断

### 4.1 距离"能给别人试用"还差几项？

- **严格口径**：**12 项**（M-1~M-9、M-14、M-15，含 1 项大工作量）。
- **乐观口径**（只求"技术上能代理全设备流量"）：**3 项**（M-14 VPN 激活链路 + M-4 超时闭环 + M-2 REALITY 参数），但其后果是"能跑，但用户不知道自己在被保护什么、出错也说不清"，属于把我们自己最忌的"状态说谎"交付出去——**不建议**。
- 若只做纯应用层（不碰 VPN），**6~7 人日量级**可把 M-1/M-2/M-3/M-6/M-7/M-8/M-9/M-17 做完，得到一个"诚实、可诊断、但不接管全局流量"的骨架产品。

### 4.2 哪几项"看起来简单但实际有坑"？

| # | 项目 | 坑在哪 |
|---|---|---|
| 1 | **分流规则**（M-12） | 规则不是"多写几条 JSON"：①RULE 模式与 IPv6 的交互（v6 目标命中 `ip` 规则要写 v6 前缀，否则 v6 全走代理）；②与防环的交互（`sockopt.mark`/`protect` 未定，规则写错会自己代理自己）；③与 DNS 的交互（`domainStrategy:IPIfNonMatch` 会引入额外解析与延迟，且 fake-ip 下域名匹配失效）；④geo 资源体积与启动耗时直接冲突（内置 geosite 会让 HAP 体积与冷启动上涨） |
| 2 | **凭据安全存储**（M-5） | 不是"调用 ASSET 就完了"：单条 ≤1KB 限制（R2 §5）、迁移需要一次性把明文洗掉（含 `PersistentStorage` 旧副本）、卸载后数据清除语义、以及"迁移失败不能丢节点"的回滚路径 |
| 3 | **终止可感知**（M-8） | 需要"上次会话标记"落盘且**必须在崩溃前写入**（崩溃时写不了盘）；还要与"用户主动断开"区分，否则会把正常退出误报成异常中断（假告警比不告警更伤信任） |
| 4 | **超时兜底**（M-4） | 该 Promise 实测**既 resolve 也 reject 都不发生**（PC6 §11.5），所以超时不能靠 `catch`；必须以"计时器 + 状态对账"实现，且重试要有次数上限，否则会变成"无限弹授权窗"的骚扰 |
| 5 | **随机端口 + 鉴权**（M-9） | 鉴权对 tun2socks/内核入站是**双端改动**（生成配置 + 中继侧凭据），且一旦启用就必须处理"端口变化导致内核重启"（配置变更即重启），否则会出现"端口变了但中继还在旧端口"的半死状态 |

### 4.3 哪几项用户会当成 bug，但实际是设计取舍？

| # | 现象（用户视角） | 实际原因（设计/平台取舍） | 建议的期望管理 |
|---|---|---|---|
| 1 | "连上了但 IP 没变 / 其他应用还是直连" | 当前只起本地 SOCKS，**未接管全局流量**（`Index.ets:62-83` 走 `KernelService`，非 VPN 链路） | M-1：文案改为"本地代理已启动（仅本机）"；接入 VPN 前不得使用"已连接" |
| 2 | "选了规则模式，访问国内网站还是走代理" | RULE 模式当前只有内网网段直连，**无 geo 规则**（`KernelConfigBuilder.ets:56-59`） | 设置页与首次说明写明"规则模式当前=仅内网直连"；或在 R-2 完成前默认用"全局"并明示 |
| 3 | "导入 REALITY 节点连不上，其他客户端能连" | REALITY 缺 `publicKey/shortId`（`:114-117`），生成配置不可用 | 导入时校验必填参数并明确报错（M-2），不要静默生成必失败配置 |
| 4 | "改了分流模式没反应" | 模式在**下次启动内核**时生效（配置生成时机决定），切换不会自动重连 | 保存后提示"下次连接生效，是否立即重连" |
| 5 | "后台一会儿就断了" | 无长时任务、无 VPN 扩展进程存活（`module.json5` 无 `KEEP_BACKGROUND_RUNNING`） | 首次连接明示（FR-17 第 4 要素）；恢复体验兜底（M-8） |
| 6 | "切换节点会闪断" | 控制面无整体热重载，节点切换=停核+重载+起核（R1 §4.2） | UI 显示"切换中/重连中"，并说明"切换会短暂中断"（FR-09/FR-39） |
| 7 | "退出应用后代理没了，系统还提示 VPN"（未来接入后） | 平台行为：进程退出即停 VPN（R2 §3.2） | FR-17 明示 + FR-14 终止可感知 |

---

## 5. 附：实现与需求的**冲突项**（需求侧看到的真问题，供实现负责人取舍）

| # | 冲突 | 证据 | 需求怎么说 |
|---|---|---|---|
| ① | `http2/h2` 被映射为 `"http"` 传输，而 `http` 在目标内核 GA 版本**已移除**（加载即报错） | `ShareLinkParser.ets:75`（`h2/http → HTTP2`）+ `KernelConfigBuilder.ets:133-135`（`HTTP2 → "http"`） | FR-31：**不支持** `quic/h2/h3/http`，导入即明确提示；不得生成必失败配置 |
| ② | REALITY 只下发 `serverName + fingerprint`，缺 `publicKey/shortId` | `KernelConfigBuilder.ets:114-117` | FR-31：REALITY 仅 `raw/xhttp/grpc` 且参数必须完整；否则应前置拒绝 |
| ③ | `compatibleSdkVersion = 26.0.0` | `build-profile.json5` | NFR-10：需求要求 **12**（HarmonyOS NEXT 5.0.0 起），否则设备覆盖与"64/256 分应用上限"分档策略都落不了地 |
| ④ | 固定端口 `18080` + `auth:"noauth"` + `udp:false` | `KernelConfigBuilder.ets:19/25/34` | FR-35：回环 + 随机端口 + **默认开启鉴权**；UDP 能力未纳入需求但用户会预期（见 P-4） |
| ⑤ | `createDefaultConfig` 塞入 `geosite:cn` 规则，但 builder 完全不读 `rules` | `AppConfig.ets:249-254` vs `KernelConfigBuilder.ets:48-60` | FR-05/FR-07：要么规则真正进内核，要么不写"默认已有国内直连"这种假承诺 |
| ⑥ | `Logger` 打印完整节点串（含 `credentialRef`） | `ConfigService.ets:110/127/137`、`ShareLinkParser` 相关日志 | NFR-06/FR-23：日志与导出包不得含凭据 |

---

## 6. 待补 FR（当前无对应编号的缺口）

| # | 缺口 | 为什么需要新 FR | 建议编号 |
|---|---|---|---|
| 1 | 节点测速 / 延迟测试 | FR-25 只覆盖"流量统计"，不含"可用性测量"；而这是用户"哪个节点能用"的核心诉求（R3 §7.1 #1346） | FR-41 |
| 2 | 节点分组 / 多配置（profile）切换 | FR-26 只覆盖订阅更新，不含 profile 概念 | FR-42 |
| 3 | UDP 转发能力开关 | FR-31 只承诺协议/传输，未承诺 UDP 数据面；当前 `udp:false` 硬编码 | FR-43 |
| 4 | 设置项持久化的完整性约束（写失败必须可见） | `SettingsStore.save()` 返回 false 但当前无 UI 消费（与 `ConfigService.save()` 同类问题） | FR-44（或并入 NFR-06） |

---

*本文档为只读分析产物，不改变 `requirements.md` 任何结论。若实现侧对某条"部分/未实现"判定有异议，请给出可执行的验证证据（编译通过 + 真机路径），我据此更新状态而不改需求。*
