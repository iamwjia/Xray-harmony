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

## 二、记录未改（需产品或验证支撑）

### R-5（中）shadowsocks 出站静默忽略"传输"设置

- 位置：`service/KernelConfigBuilder.ets` `buildOutbound()` 的 `shadowsocks` 分支
- 现象：vless/vmess/trojan 三个分支都拼了 `streamSettings`，**只有 ss 分支没拼**。
  用户在编辑页给 ss 节点选了 WS，配置生成时被悄悄丢掉 —— "设置了不生效"且没有任何提示。
- 为什么不直接改：Xray 的 shadowsocks 出站是否支持 `streamSettings`（ss over ws 是否成立）
  我没有在真机上验证过；擅自补上可能导致这类节点**从"传输不生效"变成"内核起不来"**，
  后者更糟。两个选项：
  1. 补 `streamSettings`（若上游支持，语义正确）；
  2. 保持现状但在编辑页对"ss + 传输≠TCP"给出提示，说明该组合不会生效。
- 需要你定：要我按 1 做（并在真机/内核日志上验证一次），还是按 2 做。

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

## 五、给下一步的建议顺序

1. R-2 / R-1 的**真机复验**（构造"A 失败 B 成功"和"模拟落盘失败"两个场景）。
2. R-5 定方案（ss + 传输）。
3. 单独一轮审 `VpnExtAbility` 的跨进程配置传递与凭据生命周期。
4. 上架前把 R-7（DevPanel 开关）和 R-6（清空数据的别名清理）一起收掉。
