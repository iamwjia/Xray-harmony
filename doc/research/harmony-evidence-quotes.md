# 证据原文摘录（供 risk-planner 的 K1 风险表逐字引用）

> 用途：K1 中每条风险的「可观测信号」都需要指回原文措辞。本文件只做**原文摘录 + 出处 + 证据强度标注**，不做演绎。
> 证据强度三档：**【官方原文】**（文档逐字）/**【官方问答口径】**（华为侧问答或官方客服口径，非规范文档）/**【社区观测值】**（社区实践，样本来源注明）/**【待验证】**（未找到依据）。
> 作者：harmony-platform-analyst · 2026-10-17 · 与 `harmony-platform-constraints.md` v1.1 同源。

---

## A1. `VpnExtensionAbility` 的声明位置与 `type="vpn"` 写法

**出处**：`连接VPN`（OpenHarmony 应用开发文档 / network/net-vpnExtension.md）
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/network/net-vpnExtension.md

**【官方原文】**

```json5
// 举例：在应用的module.json5中定义MyVpnExtAbility。
"extensionAbilities": [
  // ···
  {
    "name": "MyVpnExtAbility",
    "srcEntry": "./ets/vpnability/VPNExtentionAbility.ets",
    "type": "vpn"
  }
],
```

> **注意：**
> 如果DevEco Studio工具提示不能识别"type": "vpn"，需要您手动在SDK的toolchains\modulecheck\module.json文件中，给extensionAbilities对应的type枚举添加"vpn"定义，并清除build缓存和重启DevEco Studio工具。

**是否需要 `extensionAbilities` 之外的额外配置**：文档示例中该条目只有 `name` / `srcEntry` / `type` 三个字段，**未出现** `permissions`、`metadata`、`exported` 等字段；启动侧只需在 ArkTS 中构造 `Want{bundleName, abilityName}` 调 `vpnExtension.startVpnExtensionAbility(want)`。→ 结论：**除 `type:"vpn"` 外无额外声明式配置**（【官方原文】+【文档示例推断，无正面表述】）。
**附带可观测信号**：若 SDK 的 `modulecheck/module.json` 未包含 `"vpn"` 枚举，构建期即报错（这是最早可观测的失败信号）。

---

## A2. `ohos.permission.INTERNET` 的级别

**出处**：`权限列表（对所有应用开放）` / security/AccessToken/permissions-for-all.md
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/permissions-for-all.md

**【官方原文】**

```
## ohos.permission.INTERNET

允许使用Internet网络。

**权限级别**：normal

**授权方式**：系统授权（system_grant）

**起始版本**：9
```

同源原文（VPN 指导）："使用该功能需要[ohos.permission.INTERNET]权限。"

**「首次启用是系统弹窗用户授权、无人工审核」的官方表述**（`连接VPN` 文档"VPN应用的显示体验"节）：

**【官方原文】**

> - 在VPN应用首次启动连接之前，系统会显示VPN连接授权对话框。该对话框会提示用户是否信任该VPN应用并接受VPN连接请求。
> - 当VPN启动连接成功时，状态栏显示一个VPN (钥匙) 图标以提醒用户VPN处于连接状态。

> 如果您的VPN应用未获取用户信任，系统将弹出VPN连接的授权对话框，当获取用户授权后，系统将自动调用并启动您实现的VPN Extension Ability的onCreate方法将被调用。

**证据边界**：文档通篇**未出现**"需要向华为申请 VPN 权限/资质/白名单"的表述；`ohos.permission.INTERNET` 为 normal + system_grant（声明即授权）。→ "无人工审核"是**由文档缺失 + 权限机制**推出的结论，**不是文档正面否定**。若 K1 要求强证据，请以"官方文档未设任何申请/审批环节"表述，而非"官方声明无需审批"。

---

## A3. 系统同时只允许一个 VPN 连接 + 错误码 `2203002`

**出处 1**：`连接VPN`（同上）"启动VPN Extension Ability"节 —— **【官方原文】**

> 目前系统仅支持启动一个VPN连接服务，当VPN已经启动时应用新调用启动接口会收到系统拒绝错误，此时建议您的应用可以提醒用户先断开当前已经激活的VPN应用连接。

**出处 2**：`VPN错误码` / reference/apis-network-kit/errorcode-net-vpn.md
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/errorcode-net-vpn.md —— **【官方原文】**

```
## 2203002 VPN已存在

**错误信息** VPN exist already, please execute destroy first.

**错误描述** VPN连接已存在，请先调用destroy接口销毁VPN连接。

**可能原因** VPN已经被创建。

**处理步骤** 先执行destroy接口，再调用该接口。
```

**给 K1 的准确表述（避免误报）**：
- `2203002` 的官方定义是 **"VPN 连接已存在 / 已被创建"**，出现在 `VpnConnection.create()` 的错误码表中，语义是**本进程/系统内已有 VPN 连接实例**，官方"可能原因"只写"VPN已经被创建"，**没有**区分"同一应用重复创建"与"其他应用已激活"。
- "其他应用已激活时我方会被拒"来自 `连接VPN` 文档的**另一句原文**（启动接口会被系统拒绝错误），**该句未给出错误码**。

→ **结论（分两档写）**：
1. **【官方原文·确定】** 系统只支持 1 个 VPN 连接服务；重复 `create()` → `2203002`（"VPN exist already"）。
2. **【待验证】** 当**其他应用**已激活 VPN 时，我方 `createVpnConnection().create()` 是否同样返回 `2203002`（而非 `startVpnExtensionAbility` 层面的其它错误码）。**验证方式**：装机两个 VPN demo，A 启动成功后 B 启动，记录 `startVpnExtensionAbility` 与 `create()` 两处返回的 `BusinessError.code/message`。

---

## A4. 三方应用无法开机自启

**出处**：`静态订阅公共事件（仅对系统应用开放）` / basic-services/common-event/common-event-static-subscription-sys.md
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/basic-services/common-event/common-event-static-subscription-sys.md

**【官方原文·标题】** 文档标题即为：`# 静态订阅公共事件（仅对系统应用开放）`

**【官方原文·场景】** "例如，应用希望在设备开机时执行一些初始化任务，那么该应用可以静态订阅开机事件，在收到开机事件后会拉起该应用，然后执行初始化任务。"

**【官方原文·配置要求（关键）】** "修改设备的预置配置文件……预置配置文件在设备上的路径为 `/system/variant/phone/base/etc/app/install_list_capability.json`，设备开机启动时会读取该配置文件，在应用安装时会对在文件中配置的 `allowCommonEvent` 公共事件类型进行授权。"

**【官方原文·决定性一句】** "> **说明**：当前仅支持预置应用配置该文件。"

**【官方原文·生命周期】** "`StaticSubscriberExtensionAbility` 在 `onReceiveEvent()` 执行完 `15秒` 后销毁。"

→ 结论：三方应用既无法让设备侧预置授权文件，也受 15 秒生命周期限制 ⇒ **不可用作开机自启**（【官方原文】，强证据）。

---

## A5. `KEEP_BACKGROUND_RUNNING_SYSTEM` 与 ACL

**出处 1**：`受限开放权限` / security/AccessToken/restricted-permissions.md —— **【官方原文】**

```
## ohos.permission.KEEP_BACKGROUND_RUNNING_SYSTEM

允许应用申请特殊类型长时任务，如在手机上申请计算任务类型的长时任务。

**权限级别**：system_basic

**授权方式**：系统授权（system_grant）

**支持设备**：General

**起始版本**：20
```

**【官方原文·ACL 机制】**

> 以下权限的开放范围为普通应用，但需要通过访问控制列表（ACL）的方式跨级别申请。
> normal等级的应用需要将自身的APL等级声明为system_basic及以上，在开发应用安装包时，需要修改应用的HarmonyAppProvision配置文件……并重新进行应用签名。

**出处 2（对照，normal 级）**：`permissions-for-all.md`

```
## ohos.permission.KEEP_BACKGROUND_RUNNING

允许Service Ability在后台持续运行。

**权限级别**：normal

**授权方式**：系统授权（system_grant）

**起始版本**：8
```

**「1 个工作日」口径的证据强度：【官方问答口径 / 社区转述】**
来源：`ost.51cto.com` 问答，转述华为官方口径 —— "申请进入ACL白名单，请提供APP ID发送到 `agconnect@huawei.com`。收到邮件后，AGC运营审核通过后将进行白名单配置，**审核周期一个工作日**。"
链接：https://ost.51cto.com/answer/26103
→ **K1 请按"社区/官方问答口径，未见规范文档承诺 SLA"引用**，不要写成官方承诺。

---

## A6. 分发三条路径与资质周期

### A6-1 企业内部应用分发（**不上架**）

**出处**：`HarmonyOS 企业内部应用发布`（AGC 文档）
https://developer.huawei.com/consumer/cn/doc/app/agc-help-harmonyos-internalrelease-0000001756878768

**【社区转述的官方原文片段】**（该页 JS 渲染，直接抓取为空；以下为搜索得到的正文片段，**引用前建议人工在浏览器复核一次**）：

> 对于不适合或不希望在华为应用市场上公开发布的、面向企业内部或特定人群的HarmonyOS应用，AGC支持您通过指定渠道进行小范围分发。
> 通过此方式分发，必须使用专用的**组织内部发布证书**和**组织内部发布Profile**来编译打包HarmonyOS应用……
> 当前企业内部应用发布**仅支持Stage模型开发的HarmonyOS应用**，暂不支持元服务。
> 准备一个**未实名认证过的、归属地为中国大陆地区**的华为开发者账号……完成**企业内部应用分发资格申请**……完成**企业开发者（企业内部应用分发）实名认证**。
> **每个账号最多申请1个组织内部发布证书。**

**证据强度：介于【官方原文】与【社区转述】之间**——正文措辞来自官方页面但经搜索引擎转述，**K1 引用时标注"AGC 文档（经检索转述，页面需人工复核）"**。

### A6-2 调试安装（自用/内测）

- 官方文档体系：调试证书 + 调试 Profile，需绑定真机 UDID；**"调试设备上限 100 台"** —— **【待核实】**：本次未逐字抓取到"100 台"的官方原文页面，仅社区与开发者共识。**K1 请标"待核实"**，或由 Leader 指定人工在 AGC 证书页面复核。
- 实名认证时长（华为账号体系通用 FAQ，**非 HarmonyOS 专用文档**）：个人 人脸/银行卡即时、证件 1~3 个工作日；企业 对公账户最快 30 分钟、企业证件 0~3 个工作日。来源：https://support.huaweicloud.com/account_faq/zh-cn_topic_100076.html ——**【官方问答口径】**

### A6-3 公开上架

**出处**：AGC `应用资质要求`
https://developer.huawei.com/consumer/cn/devservice/doc/80301

**【官方原文·总则（检索转述）】** "应用(包含游戏)需提供符合适用的法律法规要求的资质文件……由于应用内容包含的业务类型繁多和审核规则不同时期的调整更新，资质说明并未详尽，如有疑问可咨询客服，以最终审核意见为准。"

**IP-VPN 类《增值电信业务经营许可证》三类要求（企业主体 / 注册资本 1000 万（跨省）或 100 万（省内）/ 股权无外资 / 3 名员工社保 / 经营范围含"增值电信业务"）**：来源为**代办/行业解读类页面**（如 miibt.com、搜狐号等），属**【社区观测值】**；法定审查期限"60 日"来自《电信条例》关于增值电信业务经营许可审查期限的规定，**条款号需法务复核**，K1 请标"法规口径，条款号待法务确认"。
→ **不建议**把"3~15 天"或任何具体审批天数写成事实；本项目结论是"上架路径受资质与合规双重制约，周期为月级且存在不可上架风险"。

---

## A7. tun 数据面由谁实现（决定 P-01 实验规模）

**出处 1**：`@ohos.net.vpnExtension` 模块定位 —— **【官方原文】**

> 三方VPN管理模块，支持三方VPN的启动和停止功能。三方VPN是指由第三方提供的VPN服务……**当前提供三方VPN能力主要用于创建虚拟网卡及配置VPN路由信息，连接隧道过程及内部连接的协议需要应用内部自行实现。**

**出处 2**：`VpnConnection.create(config)` 返回值 —— **【官方原文】**

> Promise\<number\>：以 Promise 形式返回获取结果，**返回指定虚拟网卡的文件描述符 fd**。

**出处 3**：`连接VPN` 开发步骤 —— **【官方原文】**

> - 建立一个VPN的网络隧道，以UDP隧道为例……；
> - 通过VpnConnection.protect保护前一步建立的UDP隧道；
> - 构建VPN Config参数……；
> - 通过VpnConnection.create建立VPN网络连接；
> - **处理虚拟网卡的数据，如：读写操作。**

**结论（强证据）**：系统**只**负责创建虚拟网卡 + 下发路由/DNS 配置，**隧道建立、协议实现、tun fd 的读写与转发全部由应用自行实现**。
→ 对 P-01 的含义：PoC 的实验规模 = 「NAPI 加载自编译 so」+「Go 侧封装/解封装协议」+「tun fd 读写」+「socket protect 顺序」四件事**必须在同一个 PoC 里串通**，无法拆成"系统代劳数据面"的简化版本。任意一环失败即整体不成立。

---

## B. 我在本次调研中明确标为「待验证」的断言（**不占编号**，对外只引 P/VD 号）

> 编号归口说明：`VQ-NN` 属 requirements.md 域、`P-NN`/`VD-NN` 属 Z1 风险表域。本文只提供「待验证断言 + 为什么重要 + 验证方法线索 + 责任角色」，编号与判定阈值由对应 owner 定。

| 断言（当前状态） | 为什么重要 | 验证方法线索 | 责任角色 / 拟挂靠 |
|---|---|---|---|
| 其他应用已激活 VPN 时，我方 `create()` 是否返回 `2203002`（**官方只定义"VPN 已被创建"，未区分同应用重复与其他应用占用**） | 决定 P0「VPN 冲突提示」是强档（可归因）还是弱档（通用文案） | 两个 VPN demo 交叉启动：A 启动成功后 B 调 `startVpnExtensionAbility` 与 `create()`，**两处分别记录 `BusinessError.code/message`** | 我出实验结论 → 挂 risk-planner 的 P-13 第二 case |
| ACL 白名单真实审核时长是否确为"1 个工作日" | 决定兜底保活方案（`taskKeeping`）是否可能拖慢排期 | 提交一次真实 ACL 申请，记录提交→通过时间戳 | risk-planner 记账 |
| 调试设备上限"100 台"的官方原文 | 决定"内测分发"覆盖范围 | 人工在 AGC「证书 / Profile」页与官方文档核对 | risk-planner |
| VPN 活跃期间不申请长时任务是否也会被冻结 | 决定「后台存活」是 P0 还是伪需求 | 真机 8h 对照实验（申请 / 不申请长时任务两组）：`hdc shell hilog \| grep -E "continuousTaskCancel\|Vpn"`，并 `ps -ef` 观察 pid 稳定性 | 我（对应 risk-planner 的 VD-05 → P-07） |

**已修正的措辞（按 leader 与 risk-planner 的要求，改回严谨表述）**：
- 「无审批」→ 「**官方文档未设申请/审批环节**（推论：文档无审批描述 + 依赖权限为 normal 级）」。
- 「100 台」→ 标【待核实】。
- 注册资本两档 → 【社区观测值 / 代办解读】；法定 60 日 → 【法规口径，条款号待法务确认】；ACL 1 个工作日 → 【官方问答口径，无 SLA】。


---

*本文件不替代 R2 全稿；R2（`harmony-platform-constraints.md`）承载结论与四态表，本文件承载原文与证据强度。*
