# 安全审计（2026-11-22）

> 范围：本仓库全部 ArkTS / C++ / 构建脚本 + 依赖与分发面。
> 方式：自研静态扫描（`scripts/security-scan.js`，已接入 `verify.ps1`）+ 人工复核关键路径。
> 结论：**未发现高危问题**；有 3 项加固建议（已全部落地）、3 项需要外部工具或真机才能覆盖的边界。

---

## 1. 已核查的安全设计（不是"没查"，是"确认成立"）

| 关注点 | 现状 | 依据 |
|---|---|---|
| **凭据存储** | 节点凭据走 `SecretStore`（HUKS 封装），节点表里只存 `credentialRef` 别名 | `platform/SecretStore.ets`、`service/ConfigService.ets` 迁移逻辑 |
| **凭据落盘** | 备份导出强制加密（PBKDF2 200k + AES-256-GCM），口令不持久化、不写日志 | `platform/BundleCrypto.ets`、`service/ConfigBundle.ets` |
| **日志脱敏** | 所有日志经 `Logger.redact`（UUID / 分享链接 / 键值凭据 / 节点地址 / 裸 IP 五类规则），并有单测 | `platform/Logger.ets`、`tests/log-redaction.test.js` |
| **明文 HTTP** | 订阅地址允许用户填 `http://`（这是用户的网络环境决定的），应用自身**没有任何明文请求端点** | 扫描规则 `plaintext-http` |
| **C++ 侧** | 仅 cgo/NAPI 桥接层，无 `strcpy/sprintf/system` 等无边界或注入面函数 | 扫描规则 `unsafe-c` |
| **剪贴板** | 复制分享链接时给出"含凭据、等同密码"的警告级提示 | `pages/Nodes.ets` `copyShareLink` |
| **清空数据** | 先删凭据再清表，删除失败会回报条数（不假装成功） | `ConfigService.clearAllData` |

## 2. 自研扫描的规则与局限

`scripts/security-scan.js` 的 8 条规则：硬编码凭据、明文端点、绕过脱敏的 `console.*`、
unsafe C 函数、`credentialRef` 值外泄、备份未加密、`.gitignore` 覆盖、闸门接入完整性。

**两轮修正的教训（值得记住）**：

- 第一版把 `url.startsWith('http://')` 判成"明文端点" → 7 条 FAIL 里 5 条是这个误报；
- 第一版把 `Logger.warn('v1 plaintext credentialRef detected')` 判成"凭据外泄" → 而那句恰恰是**发现明文凭据的告警**。

> 安全扫描器误报率高，就会被当成噪音整体忽略——**规则宁可少，不可吵**。现在判据是
> "真的把值带到落盘/日志"（模板插值 / `JSON.stringify` 直传）与"真的当端点用"（非 startsWith 等判断语境）。

**自研查不到的三件事**：依赖漏洞（CVE）、编译期数据流（taint 分析）、运行时行为。

## 3. 外部静态扫描工具评估

| 工具 | 能查什么 | 对本项目的适配 | 建议 |
|---|---|---|---|
| **DevEco Code Linter**（官方，IDE 内） | ArkTS 规范、API 误用、性能反模式 | 原生支持 `.ets`，零配置 | ✅ **必开**：IDE 每次改完跑一遍（无法进 CI，属人工环节） |
| **semgrep** | 自定义模式匹配、跨文件简单数据流 | 无 ArkTS grammar，只能按"文本级"规则跑（等同加强版 grep） | ◐ 可选：把自研 8 条规则迁成 semgrep YAML，好处是规则可复用、有社区规则集 |
| **gitleaks** | 密钥/令牌（含 **git 历史**） | 语言无关，支持自定义规则 | ✅ **建议接入 CI**：能扫历史提交，这是自研扫描（只看工作区）覆盖不到的 |
| **trufflehog** | 同上 + 活体验证（会发请求） | 活体验证对离线仓库不适用 | ❌ 不必要 |
| **osv-scanner / dependency-check** | 依赖 CVE | 可查 `oh-package.json5` 与 npm 依赖；但对 `libxray.so`（自编译 Go 产物）无版本信息 | ✅ **建议**：对 ohpm 依赖跑一次；Xray 版本需人工跟踪上游安全公告 |
| **CodeQL** | 深度数据流 | **无 ArkTS 支持**，C++ 部分可跑但本项目 C++ 只有一个桥接层 | ❌ 投入产出不划算 |
| **cppcheck / clang-tidy** | C/C++ 空指针、越界、未初始化 | 本项目 C++ 仅 `cgo_bridge.cpp` + `napi_init.cpp` | ✅ **建议**：对 `entry/src/main/cpp` 跑 `cppcheck --enable=warning,performance` |

**推荐落地顺序**：DevEco Code Linter（人工，已可用）→ gitleaks（CI，覆盖历史）→ cppcheck（native 层）→ semgrep（规则复用，可选）。

## 4. 本轮已加固

1. `.gitignore` 补 `*.jks` / `*.p12` / `*.keystore` / `*.cer` / `signature/`——上架签名材料绝不能入库；
2. `scripts/security-scan.js` 接入 `verify.ps1`（6 道 → 7 道闸门），扫描不过即构建失败；
3. 规则去噪（见 §2）。

## 5. 仍需外部条件才能验证的边界

| 项 | 为什么现在验不了 | 判据 |
|---|---|---|
| 真机上 HUKS 加密强度与密钥不可导出 | 模拟器 HUKS 行为与真机不同 | 真机 `hidumper` 查密钥属性，确认 `EXPORTABLE=false` |
| VPN 数据面是否真的全量走 tun | 卡在系统授权（`202`） | 真机连上后对比出口 IP + 抓包 |
| 依赖 CVE | 需外部漏洞库与网络 | `osv-scanner --lockfile=oh-package.json5` 跑一次，结果归档 |
