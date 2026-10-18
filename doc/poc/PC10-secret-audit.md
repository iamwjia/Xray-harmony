# PC10 · 敏感信息审计报告（第二版：工作区 + 提交历史，基线 `a686761`）

> 审计对象：`D:\projects\xray-harmony`（Tunnelix，已公开于 GitHub `iamwjia/Xray-harmony`）
> 审计人：secret-scanner
> 第一版快照：2026-10-18 20:40~21:05（基线 `0f82ef1`）｜**本版复核基线：`a686761`**
> 历史扫描：由 Leader 执行，回灌于 `team-workspace/deliverables/pc10-feedback.md`
> 报告自身不含任何完整凭据：片段一律 `前4****后4`。

---

## 1. 结论摘要

**全仓 + 全提交历史，没有真实凭据。** 工作区 12 条"看似凭据"的命中逐条核验后全部归入**测试占位 / 结构性常量 / 误报**；历史侧 token 类扫描（`AKIA`/`ghp_`/`github_pat_`/`xox`/`sk-`/`AIza`/`BEGIN PRIVATE KEY`）**输出 0 字节**，UUID 类唯一命中是全零占位，全历史文件名无 `*.pem/*.key/*.p12/*.env`，`libxray.so` **从未入库**（不是"删过"而是"从没提交"）。

**本轮唯一需要继续动手的，是一条被漏改的兄弟位置**：`KernelService.ets:210` 仍把**内核原始错误**用 `Logger.error`（`%{public}s`）打进公共日志——而同文件 `:113` 已经改成 `sensitiveError`（`%{private}s` + 截断 400）。这是"同类问题只修了一处"的典型，**级别 Medium**，一行改动。

**三条 Medium 建议已在 `a686761` 全部落地，我逐行复核通过**（CSPRNG 口令、别名改短哈希、日志 private + UI 不回显原文）。复核中另发现 4 条残留（1 条 Medium、3 条 Low/Info），都不是"新引入的风险"，而是"同一模式没扫干净"：
- M6/M7 仍用 `%{public}s` 打 native 原始响应（`DevPanel.ets:128`、`:141`）；
- M8 的原始响应仍直接显示在 UI 文本上（`:153`，日志侧已修、UI 侧没修）；
- `SecretStore.shortHash()` 的失败兜底会把**原始 id 直接当别名**返回，静默退回旧别名语义（`node:<host:port>`）；
- `ConfigService.addNode()` 仍是 public 且能把明文写进节点表（只是现在没人这么调）。

**H-12（疑似真实设备 UDID）已在 `a686761` 换成占位**，`.gitignore` 的三处乱码注释也已修好。**两个真 bug**（`Md.update()` 未 await 导致全节点撞同一别名、`encodeInto()` 返回空导致 secret 存成空）是 Leader 修 CSPRNG 时挖出来的——这两个的价值高于我本轮所有建议，因为它们属于"**静默错误**"：不报错、不崩溃，只是悄悄地让所有节点共用一个凭据。

---

## 2. 扫描范围与覆盖率

### 2.1 已覆盖

| 面 | 对象 | 覆盖方式 |
|---|---|---|
| `entry/src/main/ets/**` | 16 个 `.ets` + 5 个 README | 核心 11 个**全文通读**（`ShareLinkParser` / `NodeStore` / `ConfigService` / `KernelConfigBuilder` / `KernelService` / `SocksGuard` / `SecretStore` / `Logger` / `ConnectionViewModel` / `DevPanel` / `Index`），其余正则全扫 |
| `entry/src/main/cpp/**`、`types/**` | `napi_init.cpp`、`cgo_bridge.cpp`（均全文）、`prebuilt.c`、`CMakeLists.txt`、`libentry/index.d.ts` | 全文通读 |
| `resources/**`、`module.json5` | `string.json` / `color.json` / `main_pages.json` / `module.json5` | 全文通读（仅 `INTERNET` 一条权限；`extensionAbilities.type="vpn"`，无签名材料） |
| `scripts/**`、`toolchain/**` | 2 + 11 个文件 | 正则全扫（路径/密钥/签名关键词） |
| `doc/**` | 21 个 `.md` | 正则全扫：UUID / IPv4 / 邮箱 / 分享链接 / 设备串 / SSID / 手机号 |
| 根目录配置 | `.gitignore`（GBK，逐行）、`build-profile.json5`（`signingConfigs: []`）、`oh-package.json5`、`hvigorfile.ts`、`AppScope/app.json5`、`.clangd` | 全文通读 |
| 高熵/前缀专扫 | 7 类已知凭据前缀 | 全仓正则，9 类文本后缀 |
| **提交历史** | `git log --all -p -G` token 类 + UUID 类、`--diff-filter=D`、`rev-list --all --objects`、`log -- .gitignore` 时间线、`log --format=%ae` | **由 Leader 执行，已回灌**（本版 §5） |

### 2.2 仍未覆盖（**不假装覆盖**）

| 缺口 | 原因 | 补充建议 |
|---|---|---|
| 二进制 `.so` 的字符串内容 | `grep` 能命中但输出是乱码流，无法判读；抽样命中均为 Go 运行时/标准库常量（`6ba7b810-…` UUID 命名空间、`258EAFA5-…` WebSocket GUID、`c48619fe-…`），已单独确认 | **可选**：入库 so 仅 `libprebuilt.so`(4KB)+`libcgoping.so`(1.3MB) 且均为自编，风险极低；如需证据，命令见 §5.9（Leader 已标"未执行"，我认同不必执行） |
| 运行期数据（`AppStorage`/PersistentStorage / Asset Store 实际内容 / 设备备份） | 不入仓库，只有真机能看 | 归 §3.3 A-01/A-04，属产品级隐私面，不是仓库级 |
| `_research_src/`(153MB 第三方源码)、`oh_modules/`、`_toolchain/`、`build/` | 已 ignore / 构建产物；`_toolchain` 内的 `*.pem` 经抽查全部是 Go 标准库测试夹具 | 无（前提已被 §5.4/§5.6 证实：这些都没入库） |
| 历史提交中的**二进制 blob** 差异 | `-G`/`-p` 对二进制只报 "Binary files differ" | 无：§5.4 已证入库 so 只有两个自编产物 |

### 2.3 并发编辑声明

第一版扫描期间仓库正在被改（`SecretStore.ets` 首扫不存在、`KernelConfigBuilder` 签名 5→6 参、`NodeStore` SCHEMA 1→2）。本版已按 `a686761` 全量复核受影响文件（`SecretStore` / `SocksGuard` / `Logger` / `KernelService` / `DevPanel` / `ConfigService` / `NodeStore` / `Index` / `Nodes` / `PC6-runtime-checklist` / `.gitignore`），**§3.1 的 12 条命中在新代码下无变化**（占位与常量都还在，仍然是占位与常量）。

---

## 3. 命中清单

### 3.1 硬编码面（12 条，**全部非真实凭据**，`a686761` 复核无变化）

| # | 位置 | 脱敏片段 | 判定 | 级别 | 处置 |
|---|---|---|---|---|---|
| H-01 | `service/ShareLinkParser.ets:290` | `vless://0000****0000@example.com:443` | **测试占位**（全零 UUID + `example.com`，RFC 4122 弃用址） | Info | 无需处置。可选：改用 `your-uuid-here` 更自证是占位 |
| H-02 | 同上 `:291` | `vmess://eyJ2****In0=` | **测试占位**（base64 解开是 `add=example.net, id=全零`） | Info | 同上 |
| H-03 | 同上 `:292` | `trojan://pass****word@example.org:443` | **测试占位**（密码字面量就是 `password`） | Info | 同上 |
| H-04 | 同上 `:293` | `ss://YWVz****cGFzc3dvcmQ=@example.io:8388` | **测试占位**（解开是 `aes-256-gcm:password`） | Info | 同上 |
| H-05 | 同上 `:31` | base64 字母表 | **结构性常量** | Info | 无需处置。**CI 规则需把"纯字母序/字典序串"列入白名单**，否则每次扫描都报它 |
| H-06 | `Logger.ets:9`、`DevPanel.ets:10`、`VpnExtAbility.ets:5`、`EntryAbility.ets:6` | `DOMAIN = 0x0001` | **结构性常量**（hilog domain） | Info | 无需处置 |
| H-07 | `service/KernelConfigBuilder.ets:19` | `DEFAULT_SOCKS_PORT = 18080` | **结构性常量**（端口） | Info | 保留为调试兜底；实跑走 `SocksGuard` 轮换 |
| H-08 | `service/SocksGuard.ets:22/23/25/27` | `PORT_MIN=20000` / `PORT_MAX=40000` / `SECRET_HEX_LEN=32` / `SOCKS_USER='tun****ix'` | **结构性常量**（用户名非秘密，文件头已注明） | Info | 无需处置 |
| H-09 | `_toolchain/**/crypto/**/{example-key,platform_root_key,policy_*}.pem` | `-----BEGIN EC PRIVATE KEY-----` | **误报**：Go 标准库测试夹具 + `_toolchain/` 已 ignore（§5.4 证实未入库） | Info | 无需处置 |
| H-10 | `entry/src/main/libs/**/libxray.so`（命中 `6ba7****30c8`、`258E****5B11`、`c486****7e21`） | 见左 | **误报**：UUID/DNS 命名空间 + WebSocket 握手 GUID，Go 标准库固定值 | Info | 无需处置；`libxray.so` 已证实**从未入库** |
| H-11 | `scripts/build-hap.ps1`、`toolchain/*.ps1`、`BOOTSTRAP-RESULT.md`（多处） | `C:\Program Files\Huawei\DevEco Studio\...`、`D:\projects\xray-harmony\...` | **误报（非凭据）**：本机绝对路径，不含密钥 | Info | 建议改 `$env:DEVECO_SDK_HOME` / `$PSScriptRoot`。理由不是"泄漏密码"，而是公开仓库不该暴露开发机目录布局，且换机即坏 |
| H-12 | `doc/poc/PC6-runtime-checklist.md`（原 `:10`/`:17`） | 原为 `7001****0000` | **疑似真实设备标识 → 已处置**：`a686761` 已改为"真机为一串十六进制序列号，模拟器为 `127.0.0.1:5555`" | Info（**已关闭**） | 无需再动作。注意：设备标识不是凭据，**不能靠轮换消除**；已改为不写真实值，只控增量 |

> **H-10 附注（§5.4 已确认）**：`.gitignore` 规则链是 `*.so` → `!entry/src/main/libs/**/*.so` → `entry/src/main/libs/**/libxray.so` 再排除。实际入库：`arm64-v8a/{libcgoping,libprebuilt}.so`、`x86_64/{libcgoping,libprebuilt}.so` 共 4 个，均自编；`libxray.so` 两个 ABI 均在 `!!` 忽略态，且 `git log --all -- '*libxray.so'` 为 0 字节。**符合预期，无需改动**——但规则链脆弱（`!` 反选 + 单文件再排除），见 §6 R-01。

### 3.2 日志泄密面（v2 更新）

| # | 位置 | 现状（基线 `a686761`） | 判定 | 级别 | 处置 |
|---|---|---|---|---|---|
| **L-01'** | `service/KernelService.ets:210` | **未修**：`Logger.error(\`kernel probe failed during start: ${lastProbeError}\`)`；`lastProbeError` 来自 `resp.error` 或 `unparsable: ${raw}`，**就是内核原始响应**，此处仍是 `%{public}s` | **潜在泄密面（与 L-01 同类，漏改的兄弟位置）** | **Medium** | 改成 `Logger.sensitiveError('kernel probe failed during start: ' + KernelService.truncate(lastProbeError, 400))`。**判据**：`grep -n 'Logger.error' KernelService.ets`，参数里不得再出现 `raw` / `lastProbeError` / 内核错误变量 |
| L-01a | `KernelService.ets:113` | **已修**：`Logger.sensitiveError(... truncate(e,400))` | 合格 | — | 保留 |
| L-01b | `KernelService.ets` 兜底 `return`（原 `:123`） | **已修**：`内核错误（详细原因已写入日志）`，不再拼 `e` | 合格 | — | 保留 |
| L-01c | UI 侧 `Index.ets:60-66`（`toReadable`） | **已修**：只取 `ke.message`（人话）；我核了 `KernelError.raw` 的**全部引用**，只有构造函数赋值、**无任何读取点** —— 不做回显比"遮蔽后再显示"更彻底 | 合格 | — | 保留 |
| **L-02a** | `pages/DevPanel.ets:128`（M6）、`:141`（M7） | **未修**：`hilog.info(..., 'M6/M7 result=%{public}s', ret)`；`ret` 是 native 返回的**内核原始响应**（M6 是 `__p02_probe__` 的完整 JSON；M7 是 version/state/ports 原始串） | 与 L-01 同类，漏改 | **Medium** | 照抄 M8 已改好的写法：`(len=%{public}d)=%{private}s` + `ret.length` |
| **L-02b** | `pages/DevPanel.ets:153` | **未修**：`this.m8Result = ret;` —— 内核原始响应**直接显示在 UI 文本上**（日志侧已 private，UI 侧没改） | 与 L-01c 同一原则的漏改 | **Medium** | UI 只显示长度/verdict 摘要，原文只进 private 日志。判据同 L-01c：UI 文本不得出现内核返回的 JSON |
| L-03 | `platform/Logger.ets:14/18/22`（常规）+ `:33/:37`（新增 private） | **部分已修**：新增 `sensitiveError/sensitiveInfo`（`%{private}s`）；但三个常规出口仍 `%{public}s`，且**无统一 `mask()`** | 设计缺陷仍在 | **Medium（降一档）** | `%{private}s` 是**调用方每次自己选**——等于把"要不要脱敏"下放给每个调用点，L-01'/L-02a 就是这个模式的必然产物。建议二选一：①lint 规则：`Logger.info/error` 不得接收含 `raw\|error\|resp\|config\|payload` 字样的变量；②`Logger` 内建 `mask()`（UUID 形态 / `user:pass@` / 32+hex / IPv4）自动遮蔽，`sensitive*` 作强档 |
| L-04 | `cpp/cgo_bridge.cpp:659/670/683` | **未修**：`M9 run=%{public}s`、`via-proxy ip=%{public}s`、`direct ip=%{public}s` —— **把设备出口公网 IP 打进 public 日志** | 真实隐私泄漏（仅手动点 M9 触发） | Low | 删掉 `ip=` 输出，只留 `verdict=DIFF_IP/SAME_IP`；判据本身不需要打印 IP 值 |
| L-05 | `platform/SecretStore.ets` | **已修**：别名改 `node:<SHA-256 前 8 字节 hex>`，日志只剩无意义 hex；`legacyAliasForNode()` 仅供迁移，注释明确"新代码不要用" | 合格（把我原来只算 Info 的建议一并落地了） | Info（**已关闭**） | 保留；残留见 L-05' |
| **L-05'** | `SecretStore.ets:60-64`、`:66-70` | **残留**：`shortHash` 在两种失败下 `return v`（原始 nodeId）→ 别名变成 `node:<protocol@host:port>`，**静默退回旧别名语义**；而 `resolveCredential()` 先查哈希别名、命中即返回，**永远不会走到 re-key 分支**，这个"退回"是永久性的 | 静默降级（不是凭据泄漏，但把已修的问题悄悄改回去） | **Low** | 兜底别 `return v`：应 `return 'raw:' + v`（或抛错让调用方阻断），让别名形态**永远**不等于 legacy 形态；并在 `aliasForNode` 出口加断言"结果必须是 16 位小写 hex"。理由：`e3b0c442…` 守卫只覆盖"输入为空"，**没覆盖"哈希抛异常"这条同类路径** |
| L-06 | `service/SocksGuard.ets:49` | 只打端口 + `(auth=password)`，注释明确"口令进日志就等于没有口令" | 合格（**主动防御范例**） | Info | 保留，建议当 §6 日志规范的正面样例 |
| L-07 | `ConfigService.ets:162/179/189`、`Nodes.ets:57` | 只打 `protocol@host:port` | 合格（与 Leader 首轮结论一致，复核无变化） | Info | 无需处置 |
| L-08 | `ShareLinkParser.ets:117-118` | 错误串 `'不支持的协议：' + proto`，无 `://` 时取 `raw.substring(0,12)` | 理论风险（可能截到粘贴内容开头字符，如裸 UUID） | Low | 取 12 字符前先判是否纯 `[a-z0-9+.-]`，否则回 `'无法识别的链接'`（1 行） |
| **L-09（新）** | 直接 `import { hilog }` 的 4 个文件：`Logger.ets`（应保留）、`EntryAbility.ets`、`DevPanel.ets`、`VpnExtAbility.ets` | 绕过统一日志出口，`Logger` 里将来加的 `mask()` 管不到它们 | 结构性缺陷 | Low | 加 ESLint/自定义规则：除 `platform/Logger.ets` 外禁止 import `@kit.PerformanceAnalysisKit`。**这是 §6 R-04 能真正生效的前提** |

### 3.3 架构性风险（A-01 已可关闭；另新开两条）

| # | 对象 | 状态（基线 `a686761`） | 级别 | 处置 |
|---|---|---|---|---|
| **A-01** | `NodeStore.credentialRef` 明文落盘 | **代码侧已完成，建议关闭**（逐行复核见 §3.4 附注）：SCHEMA 2；`NodeStore.save` 只写别名；`addNodeSecure` 先写 Asset 后写节点表；`ensureSecureMigration` 先全部 `put` 成功再写 v2；旧别名 re-key；`put` 拒空 secret；`get` 把空 secret 当 missing | 关闭（原 High） | 见 §7-Q2 的 3 条措辞建议与残留 |
| **A-04（新）** | 迁移的**触发时机**：`ensureSecureMigration()` 只在 `pages/Index.ets:83`（连接前）被调 | v1 用户若只打开 App 看节点列表、**从不点连接**，明文凭据会一直留在盘上 | **Low** | 把迁移挂到 `EntryAbility.onCreate` 做一次，把明文驻留窗口从"首次连接"压到"首次启动"。判据：冷启动（不连接）后落盘内容中 `credentialRef` 必须全部是 `node:…` |
| A-02 | `SocksGuard` 口令随机源 | **已修**：`Math.random()` → `cryptoFramework.createRandom().generateRandomSync()`，端口同步改 CSPRNG | 关闭（原 Medium） | 保留。**小注（Info）**：`randomUint32()` 里 `b[0]<<24` 在 JS 产出有符号 int32、再取绝对值 `% 20000`，有极轻微取模偏置；因端口**本就不是安全边界**（`risks-and-roadmap.md:372` 同口径），无需修，建议注释点明"随机端口只降碰撞、不防猜" |
| **A-05（新）** | `ConfigService.addNode()` 仍是 **public**，会把传入的 `credentialRef` 原样落盘 | 现在唯一调用方是 `addNodeSecure()`（已核），但接口敞开 = 下一个人可能直接用它写明文 | **Low** | 降为 `private`（`addNodeSecure` 内部调用），或入口加断言"`credentialRef` 必须以 `node:` 开头，否则拒绝" |
| A-03 | `Subscription.urlRef`（订阅地址可能含 token） | 目前只存引用；`AppConfig.ets:74` 已写明将来要加密 | Info | 订阅功能落地时**必须**复用 `SecretStore`，否则订阅 token 会成为第二个明文面 |

### 3.4 复核 `a686761` 三条修复（Leader 要求的第一问）

| 建议 | 声明 | 我的复核 | 判定 |
|---|---|---|---|
| ① CSPRNG | `Math.random()` → `createRandom().generateRandomSync()` | `SocksGuard.ets:54`（端口）、`:71`（口令）均改用 `cryptoFramework.createRandom()`；`randomHex` 取 `ceil(32/2)=16` 字节 → 32 hex = 128bit，**长度与原来一致，无弱化** | **通过** |
| ② 别名短哈希 | `node:` + SHA-256 前 8 字节 hex + 旧别名自动 re-key | `SecretStore.ets:32-34` 哈希别名、`:37-39` legacy 别名（仅迁移用）；`ConfigService.resolveCredential()`：先查新别名 → 未命中查 legacy → 命中则 `put` 新别名 + 改 `credentialRef` + `NodeStore.save` + `remove(legacy)`，**顺序正确**（先写新的再删旧的，不会丢凭据）；`e3b0c44298fc1c14` 守卫在 `:60`，我核对过它确实是 SHA-256("") 的前 8 字节，取 `min(8,len)` 字节转 16 hex，判据正确 | **通过**（残留见 L-05'） |
| ③ 日志 private + UI 不回显 | 新增 `sensitiveError/sensitiveInfo`；原文截断 400 只进日志；UI 只给分类文案；DevPanel M8 private + 带长度 | `KernelService:113`、兜底 return、`Index.toReadable` **均正确**；`DevPanel:155` M8 改 `(len=%{public}d)=%{private}s` **正确**。**但** M6/M7（`:128`/`:141`）与 M8 的 UI 赋值（`:153`）未同步 | **部分通过**（L-01'/L-02a/L-02b 为残留） |

**复核中额外确认的两点（都对实现有利，值得记下来）**：

1. **部分迁移是幂等的**：假设节点 1..k 写入 Asset Store 成功、第 k+1 个 `put` 失败 → `ensureSecureMigration` 直接 `return false`，**不写节点表**（明文原样保留，不丢数据）；重试时前 k 个别名撞 `24000003` → 走 `remove + add` 覆盖。`pendingCredentialMigration` 失败时保持 `true`，不会误报"已完成"。这个"先全部成功、后落盘"的顺序是**正确设计**，比"逐个迁移逐个落盘"安全得多。
2. **`addNodeSecure` 的失败路径是阻断式的**：`put` 失败 → 不打节点表、返回 false → `Nodes.ets:58` 提示"凭据写入安全存储失败"。不存在"凭据没存上但节点加进去了"的半成品状态。

---

## 4. 处置优先级（v2）

| 顺序 | 级别 | 条目 | 为什么这个位置 | 成本 |
|---|---|---|---|---|
| 1 | **Medium** | **L-01'**（`KernelService:210`） | 唯一"已修模式的漏改点"，且落在**最可能承载内核原文**的变量上 | 1 行 |
| 2 | **Medium** | L-02a（M6/M7 `%{public}s`）、L-02b（M8 UI 回显） | 同一次"修 DevPanel"没扫干净；照抄已改好的 `:155` 即可 | 3 行 |
| 3 | **Medium** | L-03（`Logger` 无统一 `mask()` + 无 lint 约束） | 它是 L-01'/L-02a 的**根因**：把"要不要脱敏"下放给每个调用点，就一定会漏 | 半天（含 lint） |
| 4 | **Low** | L-05'（哈希兜底 `return v`）、A-04（迁移触发时机）、A-05（`addNode` public）、L-08、L-09 | 都属**同一种病**：失败路径悄悄变回旧行为 / 接口敞开 | 各 1~5 行 |
| 5 | **Low** | L-04（cpp 打出口 IP） | 只在手动点 M9 时触发 | 3 行 |
| — | **关闭** | A-01、A-02、H-12、L-05 | 已复核通过 | — |

> 逐条提醒：**本次没有任何条目需要"到平台撤销并重发"**——因为没有发现真实凭据。历史侧的个人邮箱**明确不建议改写历史**，理由见 §5.5 长注。

---

## 5. 需要 Leader 执行的命令（v2：已执行，结论回填）

> 第一版交给 Leader 的 10 组只读命令**已执行完毕**，回灌见 `team-workspace/deliverables/pc10-feedback.md`。本版逐项核对结论，标出**仍需你判断 / 可选执行**的项。

| 组 | 检查 | 结论（`0f82ef1` 时点） | 我的核对意见 |
|---|---|---|---|
| 5.1 | remote / `.git/config` 内嵌 token / hooks | remote 无 `<user>:<token>@`；无 `[credential]`、无 `insteadOf`；14 个 `.sample` hook、**无激活 hook** | **通过**。顺带：目前**没有任何 pre-commit 拦截**，这是 §6 R-02 的落地前提，不是问题 |
| 5.2 | 全历史 token 扫描 | **0 字节** | **通过** —— 本次审计最关键的正面证据 |
| 5.2 | 全历史 UUID 扫描 | 唯一值 = 全零占位（`ShareLinkParser`，`+` 行） | **通过**。判据说明：`+` 行=提交时带入、`-` 行=删过但仍留在历史。这里只有 `+` 且是全零，无问题 |
| 5.3 | 曾提交后删除的文件 | 仅 `_commit_msg2.txt`（`9df72f9` 删除它本身） | **通过**。可选补做 `git show 9df72f9^:_commit_msg2.txt`；**我的判断：不值得做**——提交信息草稿，且若当时真有凭据，§5.2 已经会报出来 |
| 5.4 | 入库产物 | 追踪 92 文件；命中仅 4 个 `lib{cgoping,prebuilt}.so`；`libxray.so` `git log --all` **0 字节 = 从未入库** | **通过，并回答了我第一版 H-10 附注的疑问**：不是"删过"，是"从没提交"，所以历史里也不存在它 |
| 5.5 | 提交者身份 | 全部提交仅 `Jia Wang <iam****@163.com>`；另有 **2 条** `Co-authored-by: Copilot <…@users.noreply.github.com>` | **同意 Low + 不改历史**（长注见下） |
| 5.6 | 忽略/未跟踪 | 未跟踪仅 `?? doc/poc/PC10-secret-audit.md`（我的报告） | **通过** |
| 5.7 | `.gitignore` 补丁时间线 | `*.so` 与 libxray 排除规则均在，且 libxray 从未提交 | **通过** —— "先提交后补规则"这条最强的历史泄漏线索**不成立** |
| 5.8 | 全历史文件名 | 仅 `SecretStore.ets`（误命中 `secret` 关键词） | **通过**。无 `*.pem/*.key/*.p12/*.env` 历史 |
| 5.9 | 入库 so 的 `llvm-strings` | **未执行** | **我同意不必执行**：入库 so 只有 2 个自编产物（4KB + 1.3MB），`libprebuilt.c` 源码在库里可对账，§5.2 已扫过历史。将来若有人把第三方 so 入库，这条才重新有必要 |

### 5.5 长注：作者邮箱怎么定级、为什么我同意"不改历史"

- **级别 Low，理由是"改不了"而不是"不严重"**：提交者邮箱随 `git clone` 分发到每个克隆副本；删除/改写历史的代价是让所有 fork / PR / 已发 commit 引用全部失效——本项目是公开仓库，已有外部交互。用 `filter-repo` 追这一点，破坏性远大于收益。
- **也认可"用户说过不改作者信息"这个前提**：这不是技术判断能推翻的事，作者本人意愿优先。
- **2 条 Copilot trailer 不是问题**：`Co-authored-by: Copilot <…@users.noreply.github.com>` 用的是 GitHub **noreply** 地址，本身不含个人邮箱，**无需处置**（这一条可以放心，不必再追）。
- **能做的只有"控增量"**：①`git config --global user.email "<id>+<login>@users.noreply.github.com"`；②README 加一句"提交邮箱为 noreply"。
- **一句诚实的话**：这条风险在本仓**无法"修复"，只能"停止扩大"**。任何声称"已修复"的处置都是假的。

### 仍需你判断的一项

- **L-01' / L-02a / L-02b 是否本轮就修**：都是 1~3 行，且都属于"同一模式漏改"。我倾向**本轮一并修掉**——它们的存在会让"日志已加固"这个结论在下一轮审计里被打回，而修的成本低于解释成本。

---

## 6. 长期机制建议（v2：含本轮两个真 bug 的教训）

| # | 建议 | 拦得住 | **拦不住**（必须知道） |
|---|---|---|---|
| R-01 | **`.gitignore` 白名单化**：`*.so` 全 ignore，只对已审核的 so 用 `git add -f` 显式加入；补齐 `*.p12 *.p7b *.cer *.pem *.key *.jks *.keystore *.pfx signature/ .env.* *.provisionprofile`、`local.properties` | 新克隆/build 产物误提交；**签名材料首次入库**（p12 入库=私钥泄漏，只能重签证书，无法"删掉就好"） | 已提交过的文件（规则对历史无效）；无后缀私钥（`deploy_key`）；`git add -f` / IDE 的 `add .` 绕过。**现状提醒**：当前规则链靠"`!` 反选 + 单文件再排除"工作，脆弱难读——本轮 §5.4 就是因为这条规则才必须专门查一次"到底谁入库了" |
| R-02 | **pre-commit 跑 `gitleaks protect --staged`**（或 `trufflehog filesystem --only-verified`） | 提交瞬间的已知前缀凭据（AKIA/ghp_/私钥头/Bearer），把"发现→修复"压到 0 | **无前缀的真实凭据**——本项目的 UUID/密码正是这一类，和 `00000000-…` 占位长得一样；已 push 的旧提交；`gitleaks:allow` 一掩了事。现实提醒：目前 `.git/hooks` 只有 14 个 `.sample`，**完全没有拦截** |
| R-03 | **CI 跑 `gitleaks detect --log-opts="--all"`（扫历史）** | 本地 hook 结构性拦不住的两类：`-n` 提交、force-push 残留；以及历史里的旧提交 | 运行期泄漏（日志/Asset Store 内容）；二进制内凭据（需额外 strings 扫描） |
| R-04 | **日志双保险**：①`Logger` 内建 `mask()`（UUID 形态 / `user:pass@` / 32+hex / IPv4 / 出口 IP）；②**禁止 `platform/Logger.ets` 以外 import `@kit.PerformanceAnalysisKit`**（当前 4 个文件直接 import，`mask()` 管不到） | **本项目最现实的泄漏路径**：内核原始错误、整份 config、`user:pass@host` | ①native 侧（`OH_LOG_*`）需单独实现同一套遮蔽，ESLint 管不到 C++；②新写的 `console.log`（需再加一条规则）；③**"忘记用 sensitive 系列"**——这正是 L-01'/L-02a 的成因，所以必须配 lint，不能靠自觉 |
| R-05 | **提交身份去标识化**：noreply 邮箱 + README 声明 | 后续提交不再泄漏真实邮箱 | 历史邮箱（已分发，见 §5.5，**不做历史改写**）；手写 trailer |
| R-06 | **占位符规范**：文档/自检统一 `your-uuid-here` / `<device-serial>` / `example.com`，禁止从真机/真订阅复制粘贴 | H-12 这类"示例带真值"；也让扫描误报量下降（`example.com` 可白名单） | 手抄真值到 issue/PR 评论（仓库外） |
| R-07 | **凭据生命周期**：Asset Store 条目记 `created_at`，提供"重新导入/撤销"入口 | 用户怀疑泄漏时可自助轮换 | 服务端撤销（在用户自己的服务端） |
| **R-08（新，来自本轮两个 bug）** | **"哨兵值"防御**：对**已知的退化输出**做显式检测并拒绝使用。已落地范例：`SecretStore.ets:60` 检 `e3b0c44298fc1c14`（SHA-256("") 前 8 字节）→ 拒绝当别名；`:158` 拒空 secret 落库；`:207` 把读到的空 secret 当 missing。**建议推广**：所有"哈希/编码/摘要"类 API 首次接入都写一条"输入为空时的输出指纹"守卫 | **静默的数据退化**——`Md.update()` 未 await → `SHA-256("")` → **全部节点撞同一别名**（每个都能连，只是连的是别人的凭据）；`encodeInto()` 返空 → **secret 存成空**（UI 显示"已保存"）。这两个都**不崩溃、不报错、日志正常**，只有哨兵值能抓 | ①**非空但错**的输出（如哈希了错误输入）——哨兵只能抓"空/全零输入"这类特征值；②第三方 API 换版本后换了退化值（哨兵失效，需跟着更新）。**它的价值是"针对已知失败模式的回归防线"，不是通用正确性保证** |
| **R-09（新）** | **"写后读回"自检**：凡有"编码→存储→解码"环节的写入（secret、配置、节点表），写完立即读回比对，不等价按失败处理（`SecretStore.get` 对空 secret 的处理已是此思路，建议延伸到 `NodeStore.save`） | 编码层静默丢数据（正是 `encodeInto` 那个 bug 的表现） | 读回一致但"存错了地方"（如写到另一个别名）——需 R-08 的别名断言配合 |
| **R-10（新，已升格）** | **同源缺陷的"搜索半径"纪律**（原为"兄弟位置清单"，`fa9d956` 后按 Leader 建议改写成可执行判据）：每次修复后**必须回答四个维度**——①**同 API**：还有谁在调同一个 API？②**同模式**：还有谁在用同一个写法（如"把 native 返回值直接赋给 @State"）？③**同文件类型**：`.ets` / `.cpp` / `.ps1` 各自的同类点在哪？④**同数据流向**：这条数据还会流到哪些终点（hilog / UI 文本 / Toast / 文件）？——四个维度逐个列清单，逐个确认"改还是不改"，不允许用"我 grep 过了"代替 | **同类漏改**——本轮 4 条残留里 3 条这么来的（L-01'/L-02a/L-02b）；`fa9d956` 之后又复现一次（附录 A 的 R-a：M8 的**日志轴**改了、**UI 轴**漏了，而 `grep 'hilog'` 扫不到 `this.m8Result = ret`）。**这个维度缺失正是"grep 过了就没有了"最典型的失效方式** | ①**形态相同但语义不同**的地方（同样打日志，一个含凭据一个不含）——需要人判断"这算不算同类"，判据给不了答案；②**跨语言**（`cgo_bridge.cpp` 的 `OH_LOG_*` vs ArkTS 的 `Logger`）需要额外的语言维度清单，否则第四维度（数据流向）容易只在一侧做完 |

> 一句话取舍（v2 微调）：**R-04 治"真实存在的路径"，R-08/R-09 治"静默错误"，R-01~R-03/R-05/R-06 治"仓库外带"**。本轮最大收获是 R-08：两个 bug 都不是"泄漏"，但都能让用户在**毫无察觉**的情况下把凭据用错——这类问题比泄漏更难发现，因为它不留下任何异常痕迹。

---

## 7. 回答 Leader 的三问

### Q1｜按 `a686761` 复核三条修复 → **§3.4 已逐行复核：①通过 ②通过 ③部分通过**

- ① CSPRNG **通过**（`SocksGuard.ets:54/71`，长度未弱化）
- ② 别名短哈希 **通过**（re-key 顺序正确、`e3b0c442…` 判据正确）；残留 L-05'（兜底退回原始 id）
- ③ 日志 private + UI 不回显 **部分通过**：`KernelService` 三处与 `Index.toReadable` 都对；**漏了 3 处** —— `KernelService:210`（Medium）、`DevPanel:128/141`（Medium）、`DevPanel:153` 的 UI 回显（Medium）

### Q2｜A-01 能否标为"已完成" → **可标"代码侧已完成"，我据此关闭 A-01；但不建议写"风险已彻底消除"**

**可关闭的依据**（不是看日志，是看代码路径 + 你的实测）：
1. **写入路径**：`addNodeSecure` 先 `SecretStore.put`、失败即返回 false 不打节点表（`ConfigService.ets:283-294`）；`Nodes.ets:58` 是唯一导入入口，走的正是它；
2. **迁移路径**：`ensureSecureMigration` **先全部 put 成功、最后才 `NodeStore.save`**，部分失败不落盘、可重试且幂等（§3.4 附注 1）；`NodeStore.SCHEMA=2` 让新写入的 `credentialRef` 只能是别名；
3. **读取路径**：`resolveCredential` 取不到就返回 null，`Index.ets:83-90` 直接阻断连接并提示"请重新导入该节点"，**不存在"拿空串硬连"**；
4. **实测**：`nodeStore load ok: 1 node(s) schema=2 migrated=true`，且是**重启后读盘**得到的——这是关键，它证明落盘内容已是 schema 2，而不是内存推断。

**为什么建议不要写"已彻底消除"**（三条，都不是"代码没写完"）：
1. **"落盘覆盖"不等于"物理擦除"**：`AppStorage`/PersistentStorage 的覆盖写是否在文件系统层留下旧块（journal、快照、备份），静态扫描无法证明。**建议措辞**："新写入与迁移后的节点表不再含明文凭据"+ 一句面向用户的"如曾用早期版本导入节点，建议重新导入一次以彻底翻新凭据"。
2. **明文曾经落过盘，就应假定可能被备份/抓取过**：这是"泄漏面一旦存在就按已泄漏处理"的原则。它不影响"仓库干净"这个结论（运行期数据从不进 git），但**不能由代码修复来证否**。
3. 残留 A-04（迁移只在"连接前"触发）：只浏览不连接的用户，明文字节仍驻留到首次连接为止。

> 一句话：**A-01 从"设计缺陷"降级为"已修 + 3 条边界残留"**，我同意关闭；但措辞请用"代码侧已完成"，不要用"风险已消除"。

### Q3｜两个防御是否值得写进 §6 → **值得，已写成 R-08 / R-09，并额外加了 R-10**

理由：`Md.update()` 未 await（全节点撞同一别名）与 `encodeInto()` 返空（secret 存成空）都是**静默错误**——不崩溃、不报错、日志一片正常，用户看到的是"保存成功"。这类问题在**安全审计里几乎抓不到**（它们不产生任何可疑字符串），只能靠"对已知退化输出设哨兵"（R-08）与"写后读回"（R-09）来兜。另加 **R-10（兄弟位置清单纪律）**，因为本轮 4 条残留里 3 条都是"同类问题只修一处"——这和那两个 bug 是同一类病根：**只处理眼前这一处，不扫同类**。

---

## 8. 我做了什么 / 没做什么

- **做了**：全仓 6 类模式 × 9 类文本后缀扫描；11 个核心文件逐行通读；`.gitignore` 逐行核（GBK 编码下用 grep 逐行读）；每条命中做"占位/常量/真值"三分类；**按 `a686761` 全量复核 10 个受影响文件**并逐行给判据；核对 `KernelError.raw` 的全部引用点以确认 UI 不回显；核对迁移/导入/解析三条路径的失败行为与幂等性；对 Leader 回灌的 10 组历史结论逐项核对并说明"为何可信"。
- **没做**：**没有修改任何业务代码**（含本次发现的 4 条残留——按约定处置由 Leader 执行）；没执行任何命令（bash/powershell 均被禁，历史扫描由 Leader 执行）；没验证设备侧实际行为（模拟器与真机差异归 PC4/PC6）。
- **不写"已修复"**：本报告只给"建议 + 判据 + 复核结论"；唯一说"已完成"的是 Leader 已实际提交并实测过的项（A-01/A-02/H-12/L-05/L-01a-c），每条都注明了依据与边界。

---

# 附录 A · 第三版复核记录（`fa9d956` + `357a91b`）

> 复核时间：2026-10-18 20:52｜复核人：secret-scanner
> 复核对象：Leader 在 `fa9d956` 的四条修复 + A-04 位置变更 + `357a91b` 新增的节点删除功能
> 结论：**四处修复 + A-04 全部通过，A-05 一并关闭**；**另发现 5 条新残留**（其中 2 条是"同一模式在别的轴上又漏了一次"）。

## A.1 逐条复核

| 项 | 声明 | 复核结果 | 判定 |
|---|---|---|---|
| 1 | `KernelService:210` 探针失败路径改 `sensitiveError` + 截断 400 | `KernelService.ets:210` 确为 `Logger.sensitiveError(... truncate(lastProbeError, 400))`；同文件已无其它 `Logger.error` 携带内核原文（`:244` 携带的是 `Error.message`，见 A.3-R-e） | **通过** |
| 2 | `DevPanel` M6/M7 native 原始响应 → 长度 + `%{private}s` | `DevPanel.ets:128`、`:141` 均已改为 `'…(len=%{public}d)=%{private}s', ret.length, ret` | **通过**（日志轴） |
| 3 | `DevPanel` M8 UI 回显 → `maskSensitive()`（UUID 占位 + 截断 300） | 新增 `maskSensitive()`（`:153-158`），`m8Result` 改走它（`:165`）。**"调试面板不是豁免区"这个判断我认同**——面板是给人看的，`Text()` 里的字面量和屏幕截图一样会外流 | **通过**（详见 A.3-R-b） |
| 4 | `SecretStore.shortHash` 兜底 `return v` → `'raw:'+id` | `SecretStore.ets:63`（空输入分支）与 `:71`（异常分支）**都**改成 `return \`raw:${v}\``，注释还写清了"直接返回 v 会退回旧别名、而 re-key 永远走不到，这个退回是永久的" —— 我原话的核心被准确保留了 | **通过** |
| 5 | A-04：迁移挪到 `EntryAbility.onCreate` | `EntryAbility.ets:14-19` 在 `onCreate` 调 `ensureSecureMigration()`，捕获异常并记日志；注释写明"只用不连的用户明文会一直留在节点表里"（这正是 A-04 的立论） | **通过**（残留见 A.3-R-c） |
| 6 | A-05：`ConfigService.addNode()` 改 private | `ConfigService.ets:184` 已是 `private addNode(node: XrayNode)`，唯一调用点是 `:344`（`addNodeSecure` 内） | **通过 → A-05 关闭** |

> 附带确认：`SecretStore.aliasForNode` 仍只对 `nodeId` 哈希，`legacyAliasForNode` 仍仅供迁移读取；`resolveCredential` 的 re-key 逻辑未受影响。**A-01 的"代码侧已完成"结论在 `fa9d956` 下依然成立。**

## A.2 `357a91b` 新增删除功能的安全面（Leader 指定单看）

**结论：删除路径本身没有 public 泄漏。** 逐条核过：

| 检查点 | 结果 |
|---|---|
| `removeNode` 的日志 | `ConfigService.ets:220/224/238/246/248` —— 只打 `id`（=`protocol@host:port`，与既有 L-07 放行口径一致）或**哈希别名**（`node:<16 hex>`）。**无明文凭据、无 secret** |
| UI 侧（`Nodes.ets:62-70`） | 只回"已删除/删除失败（详见日志）"；catch 分支打的是 `Error.message`，不含凭据 |
| 先删表还是先删密钥 | **先落盘、后删密钥**，落盘失败回滚内存（`:227-241`）。方向正确：宁可留一个孤儿 secret，也不能出现"界面删了、重启又回来" |
| `24000002`（not found） | `SecretStore.remove` 视为幂等成功 —— 对"v1 明文节点从未进过 Asset Store"这种情况是对的 |

## A.3 新残留（5 条）

| # | 位置 | 问题 | 级别 | 处置 |
|---|---|---|---|---|
| **R-a** | `DevPanel.ets:127`（M6）、`:140`（M7） | **同类问题在"UI 轴"上又漏了一次**：日志已改 private，但 `this.m6Result = ret` / `this.m7Result = ret` 仍是**内核原文直接上屏**，没走 `maskSensitive()`。M8 改了 UI、M6/M7 的 UI 没改 | **Low**（风险低于 M8：M6 是 unknown-method 错误、M7 是 version/state/ports，都不太可能回显配置；但形态完全同构） | 改成 `this.m6Result = this.maskSensitive(ret)`（两行）。**这也正好说明 R-10 该按位置清单做——它不会自动覆盖"另一个轴"** |
| **R-b** | `DevPanel.ets:153-158` | `maskSensitive` **只遮 UUID 形态**。trojan 的密码、ss 的 `method:password` **不是 UUID**，会原样上屏；配置里 `"password":"…"` 同样能透 | **Low** | 补两条替换：`/"(pass\|password\|id)"\s*:\s*"[^"]*"/g` → `"$1":"****"`，以及截断前先把 `user:pass@` 形态遮蔽。更省事的替代：M8 面板**只显示 `len` + `verdict=`**，不显示原文（信息量差别很小，风险归零） |
| **R-c** | `SecretStore.ets:176`（`remove` + `add` 覆盖）＋ `EntryAbility.ets:14` 与 `Index.ets:83` 两处并发调用 | **覆盖写不是原子的**：别名冲突时走 `remove → add`，中间有一个"密钥不存在"的窗口。而迁移现在有**两个入口**（启动时 + 连接前），两者之间**没有 in-flight 保护**（无 `migrating` 标志、无 promise 复用）。窄窗口内若 `resolveCredential` 命中该窗口 → 返回 `null` → 用户看到"节点凭据不可用，请重新导入该节点"，而节点其实完好 | **Low**（不是泄漏，是**假失败**；窗口极窄，但用户看到的是"凭据丢了"，会真的去重导） | ①优先：覆盖改用 `asset.update(attr)`（消除非原子窗口）；②退一步：加 in-flight promise 复用（`private migrationTask: Promise<boolean> \| null`），让第二次调用直接 `return this.migrationTask` |
| **R-d** | `ConfigService.ets:207-208` 注释 | **注释与事实不符**：写着"残留的 secret 不可寻址（别名已不在节点表里）"。事实是别名由 `aliasForNode(id)` **可重算**，而 `id` 是确定性的 `protocol@address:port`（`ShareLinkParser.finalize`）——所以那条 secret **仍然可寻址**，只是没人会主动去取。真正后果是：①不会被自动读到；②用户若重新导入同一节点，`put` 会覆盖它。**"危害小"这个结论成立，但理由写错了**——而错误的理由会教出"删除即销毁"的错觉，磁盘上那份凭据其实还在 | **Info**（结论对、解释错，最容易误导下一个人） | 改注释为"别名可由 id 重算，因此残留 secret 仍可寻址；因不会被主动读取、且同一节点重导时会覆盖，故危害可控"。若要更彻底：`remove` 失败时记一条"待清理 alias"清单，下次启动重试 |
| **R-e** | `KernelService.ets:244`、`EntryAbility.ets:18` | 仍用 `Logger.error` / `hilog.error` + `%{public}s` 打**异常 message**。当前这些 message 都是我们自己的文案（最多带 Asset Store 的 `code/msg`），**不含内核原文**，所以风险低；但它属于 L-03 同一类"异常文本默认 public" | **Info** | 与 L-03 一起处理：给异常文本统一走 `sensitiveError`，或在 `Logger` 内建 `mask()` 后不必逐处区分 |

## A.4 对 Leader 两个提议的回应

1. **R-10 建议升格为"同源缺陷的搜索半径"** —— **我同意，并已按你的措辞改写 §6 R-10**（见下）。补一句为什么你的版本比我的强：我的原话（"当场 grep 出同模式的全部调用点"）只在**同一个轴**上成立；而本轮 R-a 恰恰证明它不够——M8 的**日志轴**改了、**UI 轴**漏了，`grep 'hilog'` 扫不到 `this.m8Result = ret`。所以判据必须写成"**同 API / 同模式 / 同文件类型 / 同数据流向**"四个维度分别问一遍，而不只是"搜同样的关键字"。
2. **A-01 措辞纪律** —— 已按此写进 §7-Q2；本附录继续遵守：`fa9d956` 之后我仍只写"节点表不再含明文"，不写"风险已彻底消除"。

## A.5 结项判断

- `fa9d956` 的四处修复 + A-04 + A-05：**全部通过**，无一条需要返工；
- 新残留 5 条：**2 条 Low 属"修就能好"的小改**（R-a 两行、R-b 两条正则），2 条 Low/Info 是**设计层的小修正**（R-c 原子性 / R-d 注释准确性），1 条 Info 归入 L-03；
- **不构成阻塞**：没有 Medium 以上、没有真实凭据、没有新增泄漏路径。**PC10 可结项**；上述 5 条建议作为"下一轮代码卫生"的输入，不必为它们单独开任务。

> 最后一句方法论（值得留在报告里）：本轮 4 条残留里有 3 条是同一病根 —— **"修了一个位置"被当成了"修了一类问题"**。而两次都不是"没修对"，是"没修全"。所以真正的判据不是"改对了吗"，而是"**还有几个一样的位置**"：问的时候必须给出维度（API / 模式 / 文件类型 / 数据流向），否则答案永远是"我 grep 过了，没有了"。
