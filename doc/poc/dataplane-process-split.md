# 数据面进程划分：内核搬进 VPN 扩展进程

| 项目 | 内容 |
|---|---|
| 日期 | 2026-11-22 |
| 决定 | **扩展进程 = 数据面（内核 + 转发）；UI 进程 = 控制与展示** |
| 当前状态 | 架构与代码骨架已落地并编译通过；转发层未接入；未在真机验证 |

## 1. 为什么必须拆

`tun fd` 只在创建它的进程内有效。原来内核跑在 UI 进程，而 tun 由扩展进程创建，
两者不在同一个进程里，fd 就没法用。

两条路：

| 方案 | 代价 |
|---|---|
| 把 fd 跨进程传给 UI 进程 | 需要 fd 传递机制，且内核仍与 tun 分离，异常时两侧状态更难对齐 |
| **把内核搬进扩展进程**（采用） | 扩展进程要加载内核 .so（内存翻倍），但数据面完整地活在一个进程里 |

选后者：数据面自洽比省内存更重要——出问题时只需要看一个进程的日志。

## 2. 进程职责

```
UI 进程（EntryAbility / 页面）
  ├─ 读配置真源（节点、规则、设置）
  ├─ 生成内核配置（唯一的生成点）
  ├─ 决定 SOCKS 端口与口令
  └─ startVpnExtensionAbility(带会话参数)  ──┐
                                             │  Want.parameters["tunnelix.session"]
                                             ▼
扩展进程（VpnExtAbility）
  ├─ 解析会话参数（VpnSession.fromWant）
  ├─ 先起内核（SOCKS 监听 loopback）
  ├─ 再建 tun（create → fd）
  └─ 转发层（tun fd → 协议栈 → SOCKS）  ← 未实现
```

**顺序是硬要求**：先内核后 tun。反过来的话，tun 一建立系统就开始往里送流量，
而此刻 SOCKS 还没监听，这批流量被直接丢弃——表现是「连上的一瞬间所有应用断网」。

## 3. 参数为什么这样传

- **配置整串**从 UI 进程传过去，而不是让扩展自己拼：配置怎么写只有一处，
  否则两个进程各拼一份，规则会悄悄不一致；
- **SOCKS 端口与口令**也要传，转发层要用它指回本地入站；
- **凭据不单独传**：它已经在配置串里；
- 缺参数时扩展**拒绝建 tun**——建了也无人转发，只会把设备流量吸进黑洞。

## 4. 已知代价与风险

| 项 | 说明 |
|---|---|
| 内存 | 两个进程各自加载内核 .so（热态约 38MB/进程），升级为合并库后更大 |
| 状态可见性 | UI 进程无法直接查询扩展进程的内核状态；需要落盘/共享通道才能显示真实状态 |
| DNS | 当前 `dnsAddresses` 给的是公共地址，隧道内解析未实现 → DNS 会绕过代理（泄漏点） |
| 转发 | 未接入。tun 建立后无人读 fd 时**没有网络**，日志里会明确写出这一点 |
| 单实例 | 内核是进程级单例，跨进程后要避免"两边各起一个内核" |

## 5. 真机验证清单（按顺序）

1. 扩展进程能否加载内核 .so 并启动（日志：`kernel running in extension process`）；
2. `create()` 是否弹授权、是否返回 fd（日志：`tun established fd=...`）；
3. 授权被拒 / 已被其他 VPN 占用时的错误归因是否正确（2203001 / 2203002）；
4. 销毁顺序：先停内核再销毁 tun（否则留下"网卡在、转发死"的状态）；
5. 转发接入后：tun 内流量是否真的经 SOCKS 出网（服务端日志佐证）。

## 6. 仿真环境实际能验证到什么（已实测，修正了"必须真机"的笼统说法）

原始判断是「扩展路径必须真机」。实测发现**大部分可以在模拟器上验证**，
做法是绕开系统授权弹窗，直接用 `aa start` 拉起扩展 ability 并带上会话参数：

```sh
# 设备侧脚本，避免宿主机 shell 的嵌套引号问题
SESSION=$(cat /data/local/tmp/session-test.json)
aa start -a MyVpnExtAbility -b com.tunnelix.app --ps tunnelix.session "$SESSION"
```

实测输出（模拟器 API 26 / x86_64）：

```
XVPN_EXT: onCreate abilityName=MyVpnExtAbility
XVPN_EXT: session: socksPort=12345 routing=rule configBytes=207
XVPN_EXT: starting kernel in extension process
XVPN_EXT: kernel running in extension process        ← 架构假设成立
XVPN_EXT: bootstrap failed: code=202 msg=Non-system applications use system APIs
```

**已证实的**：

| 项 | 结果 |
|---|---|
| 扩展进程独立拉起 | ✅（pid 与 UI 进程不同） |
| `Want` 参数传递 + 会话解析 | ✅ `socksPort=12345 routing=rule configBytes=207` |
| **内核在扩展进程里加载并启动** | ✅ 这是本架构最关键的假设 |
| 缺参数时拒绝建 tun | ✅ `missing session parameters, refusing to establish tun` |
| 错误可读性 | ✅ 修复前是 `[object Object]`，现在是 `code=... msg=...` |

**仍然只能在真机验证的**：`create()` 能否拿到 tun fd。原因是它必须在
「经 `startVpnExtensionAbility` 授权的会话」里调用，而这步在模拟器上卡在缺失的
系统授权组件（`com.huawei.hmos.vpndialog`）上。

**待查（重要）**：`code=202 Non-system applications use system APIs`。
`@ohos.net.vpnExtension` 的 d.ts 里**没有** `@systemapi` 标记，release notes 也未提权限限制，
所以 202 更可能是「本次不是授权会话」而不是「第三方不能用」。
需要确认：三方应用走正式 `startVpnExtensionAbility` 流程时是否会得到同样错误。
这条直接决定产品可行性，必须在真机优先验证。

**2026-11-23 复查（把上面的推测变成了结论的一半）**

**0. 系统侧日志给出的完整因果链（模拟器 API 26，真实路径点「连接」）**

```
NETMANAGER_EXT: StartVpnExtensionAbility SelfAppName = Tunnelix 0
NETMANAGER_EXT: GetCachedWant: get cachedwant success
ServiceExt:      name:com.huawei.hmos.vpndialog VpnServiceExtAbility, userId:-1
BMSCommon:       bundle not exist -n com.huawei.hmos.vpndialog
BMSQuery:        ExplicitQueryExtension size:0 -e VpnServiceExtAbility
AMS:             [SAU91]failed: com.huawei.hmos.vpndialog
NETMANAGER_EXT:  connectAbility failed 2097152
```

读法：我们的 `startVpnExtensionAbility` **成功到达系统**（`CacheCurrentWant` 说明 want 已被缓存）；
系统随后去拉起**授权对话框组件** `com.huawei.hmos.vpndialog/VpnServiceExtAbility`；
该包在模拟器镜像里不存在 → `bundle not exist` → `connectAbility failed`。

**所以「为什么没弹授权框」有确切答案：弹窗是系统组件画的，不是应用画的；
模拟器镜像没有这个组件，用户自然什么都看不到**（`bm dump -a` 共 66 个包，有
`amsdialog`/`commondialog`/`notificationdialog`/`pasteboarddialog`/`powerdialog`，**独缺 vpndialog**）。

1. 走**真实路径**（点首页「连接」→ `VpnController.start` → `startVpnExtensionAbility`）实测：
   界面停在"连接中…"，**没有出现任何系统授权弹窗**；15s 后 UI 报
   "系统未响应 VPN 授权请求（没有出现授权弹窗）"；`vpn_state.json` **根本没被创建**；
   日志里没有 `XVPN_EXT` 输出（扩展进程从未被拉起）。
   → 真实路径**没走到 `create()`**，压根没有 202。
2. 因此 202 的性质定为：**「绕过授权、直接 `aa start` 拉起扩展后再调 `create()`」的后果**，
   不是"第三方应用不能建 VPN"的证据。规格层证据：d.ts 全文 0 处 `@systemapi`、
   该 API 无 `@permission` 标注、模块头注释写明这是"提供给第三方应用的 VPN 能力"。
3. 仍未验证：**真机走完整授权流程后 `create()` 是否返回 fd**。
   残余风险很具体——`ohos.permission.MANAGE_VPN` 在 SDK 的 `PermissionDefinitions.json` 里是
   `availableLevel: system_basic` + `availableType: SYSTEM`，第三方应用申请不到；
   若某个实现要求它，那就是真·硬限制。公开 API 没有标注它，且定位是第三方 VPN，
   但这只能说明"应该不需要"，不能证明"一定不需要"。
4. 判定方法（真机 10 分钟）：装 HAP → 点连接 → 看①是否弹授权框 ②允许后 `vpn_state.json`
   是否 `running` ③`hilog | grep XVPN_EXT` 是否出现 `tun established fd=`。三条都过才算通。
5. 连带影响（对其它协议的判断）：这条限制**与协议/传输无关**。`create()` 发生在"创建 tun 网卡"
   这一步，此时 ss/vless/vmess/trojan 都还没参与；所以不是"只有 ss+WS 有问题"，
   而是**所有协议的 tun 接管都被同一个授权链路挡住**。内核层（SOCKS 入站 + 出站）不受影响，
   在扩展进程里已经成功启动过。
