# 全范围代码 review（2026-11-23）

范围：`entry/src/main/ets/**`，46 个 `.ets`，12,464 行（另有 `vpnability`、`entryability` 两个入口文件）。
方式：先做机器可判的横切扫描（定时器/句柄/异常/引用/编码），再逐个读业务核心（ConfigService、
ConfigBundle、KernelConfigBuilder、ShareLinkParser、ProbeStore、BundleCrypto）与三个最重的页面。

结论先说：**没有发现"数据被静默改坏"级别的缺陷，但找到了一个会让界面说假话的高危 bug、
一个保存失败后凭据状态不一致的高危 bug**，以及若干中低危问题。已修 4 项，余下 3 项给出判断依据与建议。

---

## 一、已修（本轮）

### R-1（高）探针结果的颜色串行，一行失败会让别的行"变红"

- 位置：`pages/Nodes.ets`（原 `probeLevel: this.probeResultLevel`，传给列表里每一行）
- 现象：`probeResultLevel` 是**页面级**状态，表示"本页最近一次探针"的结果；但 `probeTextFor(id)`
  是**每行**的。于是：测 A 行失败（level=2）后，B 行只要磁盘上存着「32 ms」，它的 chip 会因为
  全局 level=2 被染成 `danger` 红底红字 —— **成功的结果显示成失败色**。反向同理（失败显示成功色）。
- 判定依据：这和本项目自己立的规则直接冲突——"颜色跟着措辞走，迟早会说谎"（`Nodes.ets` 内注释原文）。
- 修法：新增 `probeLevelFor(id)`，级别跟着这一行自己的结果走（内存值优先，其次落盘记录）。
- 验证：编译通过；**未在真机上制造"A 失败 + B 成功"的组合截图**，这一条属于逻辑修正，视觉待确认。

### R-2（高）保存节点时，节点表写失败不会回滚凭据

- 位置：`service/ConfigService.ets` `updateNode()`
- 现象：用户改了凭据 → 先 `SecretStore.put`（**覆盖**同一别名）→ 再 `NodeStore.save`。
  若 save 失败：代码回滚了内存里的节点表并提示"保存失败"，**但磁盘上的凭据已经是新的**。
  下次连接 = 旧配置 + 新凭据，内核报handshake 失败，而用户记忆里"刚才保存失败了，应该没变"。
- 修法：put 之前先把旧凭据读出来；save 失败时把旧值写回（尽力而为），
  若回滚也失败则记 `error` 日志明说"凭据可能已被替换"。
- 未做：`addNodeSecure()` 同样存在"put 成功但 addNode 返回 false（重复节点）→ 孤儿密钥"，
  危害低（别名确定性、无引用），只记录不改。

### R-3（中）首页连接计时器在页面不可见/销毁后仍在跑

- 位置：`pages/Index.ets`
- 现象：`setInterval(..., 1000)` 只在"未连接"时 `stopTick`，没有 `onPageHide` / `aboutToDisappear`。
  退到后台后仍然每秒 tick（纯展示用的时长/流量），且页面销毁后定时器仍持有 `this`。
- 修法：加 `onPageHide()` 与 `aboutToDisappear()` 都调 `stopTick()`；同时把 `refreshStatusStrip`
  里"已连接才 startTick 且只在 connectedAt===0 时启动"改成**无条件 startTick**（它自身幂等）——
  否则隐藏时停表、回来时 `connectedAt` 仍 >0，计时器永远不再启动，连接时长会停在隐藏那一刻。
  这一步是上一步的必要配套，漏了就是引入新 bug。

### R-4（低）备份文件解出来结构不完整时，报错信息对用户无意义

- 位置：`service/ConfigBundle.ets` `importFromText()`
- 现象：`JSON.parse` 成功但缺 `nodes`/`rules`（手改过的文件、别家工具产物）时，
  直接 `payload.nodes.length` 抛 TypeError，用户看到
  "恢复失败：Cannot read property 'length' of undefined"。
- 修法：解密后校验 `Array.isArray(payload.nodes/rules)`，给一句人话错误。

---

### R-5（中，已修）shadowsocks 出站静默忽略"传输"设置

- 位置：`service/KernelConfigBuilder.ets` `buildOutbound()` 的 `shadowsocks` 分支
- 现象：vless/vmess/trojan 三个分支都拼了 `streamSettings`，**只有 ss 分支没拼**。
  用户在编辑页给 ss 节点选了 WS，配置生成时被悄悄丢掉 —— "设置了不生效"且没有任何提示。
- 依据（**读源码确认，不是猜**）：`app/proxyman/outbound/handler.go` 把出站的
  `streamSettings` 解析成 `h.streamSettings`（第 88 行），由 `h.Dial() → internet.Dial(ctx, dest,
  h.streamSettings)`（第 275 行）套用，**与协议无关**；`proxy/shadowsocks/client.go` 的
  `Client.Process` 正是通过传入的 `dialer internet.Dialer` 出网。所以 ss + ws / ss + tls 是成立的，
  之前漏拼属于实现遗漏，不是上游限制。
- 已做：ss 分支补 `"streamSettings":' + stream + '`，与另外三个协议一致。
- 已加回归：`tests/config-builder.test.js` 新增「四个协议都要带 streamSettings」——
  **行为级**（抽取 ss 分支真实函数体喂参数跑，断言 `streamSettings` 存在且 network 透传）
  + 另外三个协议的源码级断言。并按"闸门必须能报错"的要求做了反向验证：
  把 ss 分支的拼接去掉后，该组断言如预期 FAIL 两条。
  顺带发现：那次故意打断时第一次误打到 trojan 分支（字符串匹配到更早的相同片段），
  断言也如实报出了 `trojan 出站带 streamSettings FAIL`——说明这些断言各自独立生效。

## 二、记录未改（需产品或验证支撑）

### R-6（低）`clearAllData` 用 `credentialRef` 当别名删密钥，覆盖不全

- 位置：`service/ConfigService.ets` `clearAllData()`
- 现象：只删 `nodes[i].credentialRef` 指向的别名；若该值仍是 v1 明文（迁移未完成），
  等于拿明文去 remove（无意义），而 `legacyAliasForNode()` 那种旧别名不会被清理。
- 影响：残留密钥**仍然可寻址**但无人引用，与 `removeNode` 里的判断一致（"危害小 ≠ 已销毁"），
  且清空数据属于低频操作。建议后续统一走一个 `aliasForNode()` + `legacyAliasForNode()` 双删。

### R-7（低）开发者面板随发布版一起去用户手里

- 位置：`pages/Settings.ets` → `pages/DevPanel`（"开发者选项 · 失败探针与内核状态"）
- 现象：DevPanel 能注入非法配置、导出备份自检、直连探测宿主。
  本机自测工具，无越权能力，但上架审核与"这软件看着像半成品"的产品印象是成本。
- 建议：用 `BuildProfile` 的 debug 标记控制入口可见性（一行判断），发布版隐藏。

---

## 三、检查过但未发现问题的部分（正面结论，附带判据）

| 检查项 | 方法 | 结果 |
|---|---|---|
| 文件句柄泄漏 | 逐个核对 `fileIo.openSync` 与 `closeSync` 是否 try/finally | 8 处全配对 ✅ |
| 未处理的 Promise | 扫所有 `.then(` 是否配 `.catch` | 页面侧 20+ 处全覆盖 ✅ |
| 内部数组被页面原地改 | 核对 `getNodes()/getRules()` 的调用点 | 页面都 `.slice()` 后再用 ✅ |
| 编码 / NUL 字节 | 全量 Python 校验 UTF-8 | 46 文件全部合法 ✅ |
| 加密参数 | PBKDF2-SHA256 + AES-256-GCM，每次随机 salt/nonce，16 字节 tag | 参数合理 ✅ |
| 端口校验 | `splitHostPort` 正则 + `1..65535` 范围 | vless/vmess/trojan/ss 都过同一校验 ✅ |
| JSON 注入 | 所有动态值走 `JSON.stringify` 转义 | 无手拼字符串 ✅ |
| 落盘缓存 | `ProbeStore` 有内存缓存，`ForEach` 每行读不走磁盘 | ✅ |
| 定时器清理 | `Index` 之外还有 3 处 `setTimeout(400ms)` 只用来复位刷新态 | 自清，可接受（页面销毁时会有一次无效赋值） |

---

## 四、这份 review 没有覆盖到的（明确边界）

- **没有跑真机**：所有运行时行为（内核启动、VPN 授权、HUKS、分享面板）仍是模拟器口径。
- **没有审 `vpnability/VpnExtAbility.ets` 的进程间数据流**（181 行，配置由应用进程传入扩展进程），
  这块和"凭据不进日志/不进文件"直接相关，值得单独一轮。
- **没有审 native 侧**（`libxray` / `libcgoping` 是预编译产物，不在本轮范围）。
- 性能只做了静态判断（`visibleNodes()` 每次渲染重算 + `ForEach` 非 `LazyForEach`）。
  节点数 < 200 时无感；上千节点需要换成 `LazyForEach` + 预过滤，这是**未实测的推断**。

---

## 五、第二轮：VPN 扩展进程与凭据生命周期（R-5 之后按优先级做的 B）

范围：`vpnability/VpnExtAbility.ets`（181 行）、`service/VpnSession.ets`、`service/VpnController.ets`、
`platform/VpnStateFile.ets` 的调用面。

### V-1（高，已修）启动中任一环节失败，内核不会停

- 位置：`VpnExtAbility.bootstrap()`
- 现象：`kernel.start()` 成功之后，`createVpnConnection()` / `conn.create()` 抛异常时，代码只往
  状态文件写 `error` 就结束了 —— **内核还在本进程里跑着，SOCKS 端口也被占着**。
  下一次连接会以"端口占用"这种与真实原因无关的形式失败，而用户与日志都指向错误方向。
  原代码对"转发失败"这一个分支做了 tun 回滚，但**没停内核**；对更早的失败则完全没有回滚。
- 修法：内核起来之后的所有步骤包在 try 里，失败统一走 `rollback()`：转发 → tun → 内核，
  三步各自独立 try（前一步失败不能连带后面的清理也不做）。`bootstrap` 再抛出，
  由 `onCreate` 的 catch 统一写 `error` 状态——状态文案保持一处，不分散。

### V-2（中，已修）明文凭据在整个会话期间驻留在扩展进程内存

- 位置：`VpnExtAbility` + `VpnSession.configJson`
- 现象：内核配置串（含 UUID / 密码 / ss method:password）从 Want 解出来后存在 `this.session` 上，
  **直到进程销毁都不清**。而内核启动后已经持有自己的副本，扩展侧没有任何代码再用它。
- 修法：`dropSessionSecrets()` —— 转发层就绪后立刻把 `configJson` 与 `socksPass` 置空。
- 说明边界：这不改变"凭据经 Want 参数跨进程传递"这个事实（见 V-3），只是缩短内存驻留时间。

### V-3（中，已修）Want 参数没有大小保护

- 位置：`VpnController.start()`
- 现象：配置串随节点数/规则数增长，整串塞进 `Want.parameters`。超大配置时
  `startVpnExtensionAbility` 会失败，而返回的错误码看不出"参数太大"。
- 修法：发之前检查长度，超 `MAX_SESSION_CHARS`（64K 字符，保守值）就直接抛
  "配置过大（N KB），无法通过启动参数传给 VPN 扩展"。
- **未验证**：Want 参数的真实上限没有公开数字，64K 是我取的保守阈值；实测配置约 4–8KB。

### V-4（低，记录）凭据以明文经过 Want 参数

- 现状：`configJson` 含真实凭据，经 `Want.parameters` 从 UI 进程传到扩展进程，不落盘。
- 风险评估：两个 ability 同属本应用，Want 参数不落盘、不经网络；主要暴露面是
  系统侧对 ability 启动参数的记录/快照（具体行为取决于系统版本，未取证）。
- 备选方案及否决理由：
  1. **写沙箱文件传**：等于把明文凭据落盘，比现在更差；
  2. **只传节点 id，扩展进程自己读配置并解凭据**：需要扩展进程能读 HUKS/Asset Store，
     而扩展进程的权限与生命周期受限（且不得引用部分 Kit），风险更高；
  3. **自建 IPC（wantAgent 回调 / 本地 socket）**：控制面与数据面已经有两个通道
     （状态文件 + Want），再加一个通道会让"谁是真相源"变模糊。
- 结论：维持现状，作为已知取舍记录；若后续真机取证发现系统会记录 Want 参数，再改方案 2。

### V-5（低，记录）onDestroy 的 shutdown 是异步的

- 现象：`onDestroy()` 里 `this.shutdown().then(...)`，方法本身同步返回；系统不保证等它完成。
- 影响：极端情况下 tun/内核清理被打断，残留由下一次启动的 `rollback`/端口占用暴露。
- 现状可接受（shutdown 内每步都有超时），记录不修。

### 第二轮没有覆盖的

- `Forwarding.start(tunFd, ...)` 的实现（tun 侧读写循环、UDP、背压）本轮**只看接口**，没读实现。
- 真机行为：`202 Non-system applications use system APIs` 仍是当前唯一硬门，
  上述改动全部只做到"编译 + 逻辑自洽"，**运行时未验证**。

---

## 六、给下一步的建议顺序

1. R-2 / R-1 的**真机复验**（构造"A 失败 B 成功"和"模拟落盘失败"两个场景）。
2. R-5 定方案（ss + 传输）。
3. 单独一轮审 `VpnExtAbility` 的跨进程配置传递与凭据生命周期。
4. 上架前把 R-7（DevPanel 开关）和 R-6（清空数据的别名清理）一起收掉。

---

