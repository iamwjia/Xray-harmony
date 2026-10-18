# 权限与资质申请材料清单 + 时长预期（Interim 交付，R2 前置切片）

> 归属任务：R2（HarmonyOS NEXT 平台能力与硬约束调研）· 作者：harmony-platform-analyst
> 版本：v0.1（2026-10-17）· 状态：**Interim**，供关键路径决策使用；R2 主线继续，本文后续随 R2 全稿同步更新。
> 证据规则：每条结论给出 API / 权限全称 + 官方文档链接；时长区分【官方口径】与【社区观测值】两类，未拿到官方承诺的一律标注来源，不编造数字。

---

## 0. 结论先行（一句话）

**做 tun 级代理这件事本身在 HarmonyOS NEXT 上「无审批前置」**：`VpnExtensionAbility`（`extensionAbilities.type = "vpn"`）是面向三方开放的能力，只依赖 `ohos.permission.INTERNET`（normal 级、声明即生效），首次启动由**系统弹窗让用户授权**（这是用户授权，不是资质审批）。

> **证据强度声明（重要）**：「无审批」是基于**官方文档未设任何申请/审批流程** + 依赖权限为 normal/system_grant 推出的**推论**，并非官方否定性声明。逐字原文与证据强度见同目录 `harmony-evidence-quotes.md`（A2 节）。


因此关键路径的瓶颈**不是 VPN 能力审批**，而是：
1. **分发环节的资质**（只有在"公开上架华为应用市场"时才触发，涉及企业主体 + IP-VPN 类《增值电信业务经营许可证》，这是月级周期）；
2. **技术验证环节**（Go/Xray-core → `aarch64-linux-ohos` 共享库的可用性 PoC，见 R2 第 2 章）。

**在一个全新个人/小团队项目上，从今天起最快多久能拿到可做 tun 级代理的能力：**

| 目标形态 | 最快周期 | 说明 |
|---|---|---|
| **开发 + 真机自用（调试安装，≤100 台设备）** | **约 0.5~1 个工作日** | 个人开发者账号实名（人脸识别即时）+ 调试证书/Profile + 真机 UDID 绑定，全部在线自助，无人工审批 |
| **小范围内部分发（不上架市场）** | **约 3~8 个工作日** | 需另开一个**未做实名认证**的华为账号 → 企业实名认证（0~3 工作日）→ 企业内部应用分发资格 → 组织内部发布证书/Profile |
| **公开上架华为应用市场（含 VPN/代理类业务）** | **约 1~4 个月（不可压缩部分在许可证）** | 企业主体 + 《增值电信业务经营许可证》(IP-VPN 类) + 软著/备案 + 应用市场审核 |

> 即：**风险侧原先假设的"VPN 能力资质审批 3~15 天"在系统 API 层面并不存在**；3~15 天量级更接近"企业内部应用分发资格 + 企业证书"链路。真正不可压缩的长周期是**公开上架所需的电信业务经营许可证**。

---

## 1. 系统权限 / API 对应清单（开发期）

| # | 能力 | 权限全称 | 权限等级 / 获取方式 | 对应 API（含模块） | 四态结论 | 依据 |
|---|---|---|---|---|---|---|
| 1 | 联网（代理转发、订阅下载、DNS） | `ohos.permission.INTERNET` | normal，`module.json5` 中 `requestPermissions` 声明即生效，**无需人工审批** | `@ohos.net.socket`、`@ohos.net.http`、`vpnExtension` 全系 | **可用** | [net-vpnExtension 指导](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/network/net-vpnExtension.md)（原文："使用该功能需要 ohos.permission.INTERNET 权限"） |
| 2 | 建立 tun 虚拟网卡 / 配置路由 / DNS / 分应用代理 | 无独立权限；由 `VpnExtensionAbility` 承载 | `extensionAbilities` 中声明 `"type": "vpn"`；首次调用触发**系统授权弹窗**（用户决定，非资质） | `vpnExtension.startVpnExtensionAbility(want)` → `VpnExtensionAbility.onCreate` → `vpnExtension.createVpnConnection(ctx)` → `VpnConnection.create(VpnConfig)` | **可用（需用户授权）** | [@ohos.net.vpnExtension](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/js-apis-net-vpnExtension.md)、[开发指导](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/network/net-vpnExtension.md) |
| 3 | tun 数据面读写（用户态协议栈与内核 fd 交互） | 同上 | `VpnConnection.create()` 返回**虚拟网卡 fd**，由 Native 侧读写 | `VpnConnection.create(): Promise<number>`；`VpnConnection.protect(socketFd)` | **可用** | 同上（create 返回"虚拟网卡的文件描述符 fd"） |
| 4 | 后台长驻（VPN 活跃期间进程不被冻结） | `ohos.permission.KEEP_BACKGROUND_RUNNING` | normal，声明即生效；须在 `abilities[].backgroundModes` 指定类型 | `backgroundTaskManager.startBackgroundRunning(context, bgMode, wantAgent)` | **需权限（易得）+ 类型错配风险** | [长时任务(ArkTS)](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/task-management/continuous-task.md) |
| 5 | 计算型后台保活（`TASK_KEEPING`，API 21+ 手机可用） | `ohos.permission.KEEP_BACKGROUND_RUNNING_SYSTEM` | **restricted（受限）**，需 ACL + AGC 白名单配置 | `backgroundTaskManager.startBackgroundRunning(..., ['taskKeeping'], ...)` | **需资质/需审批（1 个工作日量级）** | [restricted-permissions](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/restricted-permissions.md)、长时任务文档 TASK_KEEPING 备注 |
| 6 | 网络状态感知（切换 Wi-Fi/蜂窝、断线重连） | `ohos.permission.GET_NETWORK_INFO` | normal，声明即生效 | `@ohos.net.connection`（`on('netAvailable')` / `getDefaultNet`） | **可用** | 权限列表 `permissions-for-all.md`（同目录 AccessToken 下） |
| 7 | Wi-Fi 信息（SSID / 代理配置感知） | `ohos.permission.GET_WIFI_INFO` | normal，声明即生效 | `@ohos.wifiManager` | **可用** | 同上 |
| 8 | 通知（VPN 状态常驻通知、流量统计） | 无（基础通知） | `notificationManager.publish` 无需权限 | `@ohos.notificationManager` | **可用** | 长时任务文档（申请长时任务成功后系统在通知栏展示关联通知） |
| 9 | **开机自启（VPN 随设备启动自动连接）** | 无可用权限 | `StaticSubscriberExtensionAbility`（`type: "staticSubscriber"`）**仅对系统应用开放**，且需设备侧预置文件 `install_list_capability.json` 授权 `allowCommonEvent` | `@ohos.commonEventManager`、`StaticSubscriberExtensionAbility.onReceiveEvent` | **不可用（三方应用）** | [静态订阅公共事件（仅对系统应用开放）](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/basic-services/common-event/common-event-static-subscription-sys.md)（原文："当前仅支持预置应用配置该文件"） |
| 10 | 敏感配置安全落盘（凭据、uuid、订阅 token） | 无（服务侧保证） | 免申请 | `@ohos.security.asset`（ASSET，≤1KB 短敏感数据，AES256-GCM + TEE）、`@ohos.security.huks`（密钥生成/加解密） | **可用** | [Asset Store Kit 简介](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AssetStoreKit/asset-store-kit-overview.md)、[HUKS 简介](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/UniversalKeystoreKit/huks-overview.md) |
| 11 | 代理核心（Xray-core）以 so 形式加载 | 无独立权限 | 依赖 NDK 工具链与 ABI（`arm64-v8a`） | NAPI（`libace_napi.z.so`）/ `napi_module_register` | **可用（工具链层面合规即可）** | [NDK 工程构建概述](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/build-with-ndk-overview.md)、[预构建库约束](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/build-with-ndk-prebuilts.md) |

**关键判断摘要（供风险侧直接引用）**

- 第 2、3 项（tun 级代理）**不涉及任何华为侧人工审核**，唯一闸门是用户首次授权弹窗。
- 系统**同一时刻只允许一个 VPN 连接服务**（已启动时新调用会被拒绝，错误码 `2203002 VPN exist already`），这是产品交互与降级设计必须考虑的外部约束，与资质无关。
- 第 9 项是硬限制：**HarmonyOS NEXT 三方应用无法开机自启**，产品需求中"开机自动连接"必须改为"引导用户手动启动 / 桌面卡片快捷启动"。

---

## 2. 分发侧资质清单（决定"给谁用"）

| # | 事项 | 全称 / 形态 | 前置条件（主体与材料） | 受理主体 | 时长 | 可否并行 | 依据 |
|---|---|---|---|---|---|---|---|
| A | 华为开发者账号实名 | 个人实名（人脸 / 银行卡 / 证件） | 身份证；人脸或银行卡可即时 | 华为开发者联盟 AGC | 人脸/银行卡**即时**；证件认证**1~3 个工作日**【官方口径】 | 与开发并行 | 华为账号实名认证 FAQ（个人 1~3 工作日、企业 0~3 工作日） |
| B | 调试证书 + 调试 Profile | `.cer` + `.p7b`（调试） | 需绑定真机 UDID；调试设备上限 **100 台** | AGC「证书、APP ID 和 Profile」 | 在线自助，**分钟级**【官方口径】 | 是 | [内部发布指导（同章节含证书体系）](https://developer.huawei.com/consumer/cn/doc/app/agc-help-harmonyos-internalrelease-0000001756878768) |
| C | 发布证书 + 发布 Profile | 发布证书 + 发布 Profile（上架用） | 需已实名账号、已创建 APP ID | AGC | 在线自助，分钟~小时级 | 是 | 同上 |
| D | 企业实名认证 | 企业开发者实名（银行对公 / 法人手机号 / 企业证件） | 营业执照、法人信息、对公账户 | 华为开发者联盟 | 对公账户**最快 30 分钟**；企业证件**0~3 个工作日**【官方口径】 | 是 | 华为账号实名认证 FAQ |
| E | 企业内部应用分发资格 | 资格申请（不上架市场的小范围分发通道） | **必须使用一个未做过实名认证的、归属地为中国大陆的华为开发者账号**（避免与原企业账号权限冲突）；随后完成"企业开发者（企业内部应用分发）实名认证" | 华为 AGC | 申请 + 实名认证合计**约 1~5 个工作日**（实名 0~3 天为官方口径，资格申请时长**未在文档中承诺**，【社区观测值】约 1~2 工作日） | 与 D 的部分材料可并行，但账号必须独立 | [HarmonyOS 企业内部应用发布](https://developer.huawei.com/consumer/cn/doc/app/agc-help-harmonyos-internalrelease-0000001756878768) |
| F | 组织内部发布证书 + Profile | `组织内部发布证书`（.cer，**每账号最多 1 个**）+ 组织内部发布 Profile | 已通过 E | AGC | 在线自助，分钟~小时级 | 否（依赖 E） | 同上 |
| G | 受限权限 ACL 白名单 | 受限权限（如 `KEEP_BACKGROUND_RUNNING_SYSTEM`）申请 | 需说明**具体权限清单 + 真实业务场景/必要性说明**；提交 APP ID 至 `agconnect@huawei.com` | AGC 运营 | **1 个工作日**【社区口径，官方问答一致】；上架时审核人员会复核权限使用 | 可与开发并行 | AGC 受限权限问答（社区转述官方口径）；受限权限清单见 [restricted-permissions](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/restricted-permissions.md) |
| H | 软件著作权 / APP 电子版权 | 软著登记证书或电子版权认证 | 源码材料、申请表 | 中国版权保护中心 / 认证机构 | **10~15 个工作日（加急）~ 30+ 工作日**【社区观测值】 | 可与开发并行 | AGC「应用资质要求」页（见 I） |
| I | **IP-VPN 类《增值电信业务经营许可证》** | 增值电信业务经营许可证（业务种类：国内互联网虚拟专用网业务） | 公司主体；经营范围含"增值电信业务"；注册资本 1000 万（跨省）/100 万（省内）；**股权无外资**；3 名员工社保；网络与信息安全保障措施 | 省通信管理局 / 工信部 | **法定审查期 60 日内**（《电信条例》口径）；**社区实际 20~40 个工作日**【社区观测值】 | 与开发并行（但决定上架时间） | 华为 AGC「应用资质要求」页：https://developer.huawei.com/consumer/cn/devservice/doc/80301 ；许可条件见《电信业务经营许可管理办法》 |
| J | 应用市场对 VPN/代理类应用的审核口径 | 类目资质要求 + 内容合规 | 是否要求 I，取决于类目判定与审核意见 | 华为应用市场审核 | 首轮审核通常 1~7 个工作日【社区观测值】；资质不全会直接驳回 | — | 同上 AGC 资质页；**最终以审核意见为准，建议提审前工单咨询**【待确认】 |

---

## 3. 各环节"能否压缩 / 并行"结论

```
Day 0            开发环境 + 个人账号实名(即时) + 调试证书/Profile(分钟级) + 真机UDID
                 └─► 当天即可跑通 VpnExtensionAbility + tun 原型            ← 关键：这一段零审批
Day 0~1          受限权限 ACL（如需 TASK_KEEPING 等）→ 1 个工作日            ← 可选支线
Day 0~5          企业账号(独立账号) + 企业实名(0~3d) + 内部发布资格(1~2d)      ← 内部的"快通道"
Day 20~60+       IP-VPN 许可证（法定 60 日内；实际 20~40 工作日）             ← 唯一不可压缩的长周期
                 └─► 只有在"公开上架"路线下才进入关键路径
```

- **可并行**：A/B/D/G/H/I 全部可与编码、PoC 并行；互相之间除 E→F 为强依赖外，其余无严格顺序。
- **不可压缩**：I（许可证）受行政机关审查期限约束；E→F 受账号实名审核约束。
- **可完全绕开**：若产品定位为"自用 / 小范围内测 / 企业内部分发"，则 **I、J 不进入关键路径**，整体从"月级"降到"周级以内"。

---

## 4. 申请被拒 / 超时的常见原因（按环节）

| 环节 | 常见原因 | 规避动作 |
|---|---|---|
| ACL 受限权限（G） | 邮件未列明权限清单；无业务必要性说明；以"技术预研"为由申请生产权限 | 邮件中逐条列出权限名 + 每条对应的用户可感知功能 + 不申请的降级方案 |
| 企业实名（D） | 营业执照经营范围不含相关业务；法人信息与工商登记不一致；对公账户户名不符 | 提交前核对工商信息一致性 |
| 企业内部应用分发资格（E） | **复用了已实名的企业账号**（官方明确必须用未实名的隔离账号）；账号归属地非中国大陆 | 单独注册新账号，仅用于内部发布 |
| 应用市场上架（J） | 未提供类目资质；应用被判定为"跨境代理/规避网络管理"类工具；隐私政策与权限声明不符 | 提审前工单咨询类目资质；权限最小化 + 隐私政策逐项对齐 |
| 证书/Profile（B/C/F） | 调试设备超 100 台；Profile 与证书/包名不匹配；重复申请多个组织内部发布证书（上限 1 个） | 统一由一人管理 AGC 证书体系 |

---

## 5. 待确认项与验证方式

| 待确认 | 为什么重要 | 验证方法 |
|---|---|---|
| 华为应用市场对"Xray 类代理客户端"的类目判定与资质要求（是否需要 I，是否直接禁售） | 直接决定"公开上架"是否成立 | 提审前通过 AGC 工单/客服，提交应用功能说明，索取**书面类目资质答复**；保留工单编号作为决策依据 |
| 企业内部应用分发通道是否允许 VPN 类应用 | 决定"小范围分发"这条路是否可用 | 用资格账号走一次内部发布流程，安装到非调试设备验证（不依赖 UDID） |
| 组织内部发布资格的真实审核时长 | 影响内部路线周期 | 实测记录申请提交→通过时间戳，回填本文 |
| VPN 活跃期间是否需要长时任务才能不被冻结 | 影响后台保活方案与权限清单 | 见 R2 第 4 章：`VpnExtensionAbility` 独立进程 + 无长时任务场景下，锁屏 30min 后 `hdc shell hilog` 观察是否触发 `continuousTaskCancel` / 进程冻结 |

---

## 6. 对关键路径的修正建议（给 risk-planner / team-leader）

1. **把"VPN 能力审批"从关键路径上删除**——系统层无审批，改为"用户授权弹窗"的产品设计项（一次性授权 + 引导文案）。
2. **把关键路径换成三段**：① Go/Xray-core → `aarch64-linux-ohos` so 的 PoC（技术不确定性最高）；② 策略决策"公开发行 vs 企业内部/自用"；③ 仅在选"公开发行"时启动 IP-VPN 许可证办理（月级，须立即立项否则拖累发布）。
3. **若目标是尽快可用**：走"个人账号 + 调试安装（≤100 台）"，**当天可产出可跑 tun 的原型**，无需等待任何审批。

---

*本文件为 Interim 版本，R2 全稿（`harmony-platform-constraints.md`）完成后会与本文件对齐并消除重复。所有标注【待确认】的条目将以 R2 的验证实验清单承接。*
