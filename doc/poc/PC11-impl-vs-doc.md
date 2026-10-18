# PC11 — 实现 vs 需求 / 设计 / 计划 三维对齐

| 项目 | 内容 |
|---|---|
| 文档 | PC11 · 事实校准 + 文档补丁说明 |
| 作者 | requirements-architect |
| 日期 | 2026-10-18 22:20 |
| 基线 | PC9（commit `afcad51`，20:30 快照）→ **本文件取代其状态结论**（PC9 保留原样并标 `superseded`） |
| 当前 HEAD | `5778e61`（14 个提交） |
| 证据规则 | 每条结论给 `commit + 文件:行` 或实测日志原文；**无证据一律"未验证"**，不把"代码写完"当"已实现" |
| 工具限制 | 本报告未使用 bash；需要 git 复核的命令列在 §7 |

> **口径提醒（沿用 PC9，不退步）**：`✅ 已实现` = 有代码 + 有执行证据（编译/模拟器启动/实测日志之一，且覆盖该 FR 的核心验收点）；`◐ 部分` = 有代码但未验证，或只覆盖子集；无标记 = 未实现。**`running:true` 只表示内核进程活着，不代表隧道可用** —— 所以三条红线（FR-13/14/15）本轮仍不可能是 ✅。

---

## 1. FR-01 ~ FR-44 状态重判（只列发生变化或需要说明的条目）

完整 44 条状态见 §2 汇总；本节只展开"PC9 → 现在"有变化的部分与反例。

| FR | PC9 | 现在 | 证据 | 判定理由（为什么不是更高/更低） |
|---|---|---|---|---|
| FR-01 分享链接导入 | 部分 | **✅** | `ShareLinkParser.ets:45-64`（四协议分发）+ `Nodes.ets:42-63 doImport`；实测 `import ok: vless @ a.example.org:443`（leader 提供） | 导入→入库→列表可见的闭环有实测；但**错误四分类仍未实现**（解析器直出文案）→ 该子项记入 §4 不一致清单，不影响主验收（主验收为"≤3s 生成并可选中"） |
| FR-03 节点 CRUD 与排序 | 部分 | **✅** | 删除 `ConfigService.ets:232-273`（含落盘失败回滚 `:256-262`）；编辑 `:283-320`；排序 `:327-360`；分组 `:363-373`、`NodeStore` schema=3（`NodeStore.ets:23`）；UI `Nodes.ets:78-127/191-263`；实测：改协议 vless→vmess 列表即时刷新、改名 NodeAZ、moveNode 1→0、分组 H 筛选生效、`5778e61` 的 `cfgRev` 修复 | 五类操作（增/删/改/排序/分组）+ 失败回滚都有代码与实测；"订阅恢复不覆盖用户删除"仍无（因无订阅）→ 不影响本 FR |
| FR-04 手动新建/编辑节点 | 未实现 | **◐** | 编辑页 `NodeEdit.ets:38-191`（12 字段、`validate()` `:137`、`updateNode` `:191`）；**未见"新建空节点"入口**（`Nodes.ets` 只有导入与编辑）；REALITY 仅 `raw/xhttp/grpc` 的组合校验未见 | 编辑可用，但"新建 + 组合校验"缺失 → 只能 ◐ |
| FR-05 配置生成与校验 | 部分 | **✅** | `KernelConfigBuilder.ets:26-83`（入站/出站/routing，逐值 `esc()` `:147`）；三模式 JSON 断言 `_toolchain/verify-routing-json.js` 全 PASS（leader 提供） | 生成 + 结构断言有证据；**"规则数超上限即阻止启动"仍未实现**（`routes` 只由 builder 固定生成，用户规则不进内核）→ 该子项转入 FR-07 |
| FR-06 分流三态 | 部分 | **✅** | `KernelConfigBuilder.ets:64-83`（DIRECT/GLOBAL/RULE；`geoReady` 时 `geosite:cn` + `geoip:cn`，否则降级仅内网）；`GeoAssets.ets:85-235`（内置 zip → 解包 → `setAssetPath`）；实测 `start bytes=802 → confirmed running=true`（geo 规则被解析未报错） | 三模式可下发且内核接受 geo 规则；**但"分流结果是否符合预期（国内直连/国外代理）"未做真机出口验证** → 判 ✅ 是因为本条验收点是"三模式生效且配置合法"，不是"分流结果正确"（后者属 FR-07 与 RG 门禁） |
| FR-07 自定义路由规则编辑 | 未实现 | **◐** | geo 规则由 builder 固定生成（`:71-82`）；`RoutingRule` 模型仍在（`AppConfig.ets:81-89`）但**无 UI、`rules` 数组仍不进内核** | geo 侧有实质进展 → 从"未实现"升为 ◐；自定义编辑仍缺 |
| FR-09 节点切换（快速重启内核） | 部分 | **◐** | `KernelService.start/stop` + `Index.ets:127-141`；无"一键切换节点"动作、无切换中提示、无失败回退原节点 | 未变好：仍是"先断开再连接"的手工两步 |
| FR-13 状态一致性（红线1） | 部分 | **◐** | `ConnectionViewModel.deriveView` + `getXrayState.running` 为准；新增 `socksInfo` 展示（`Index.ets:29`） | **明确不升级**：`running:true` ≠ 隧道可用；无 `BEARER_VPN`、无被动停止感知（PC9 结论仍成立） |
| FR-16 中断后恢复 | 部分 | **◐** | 节点/选中项/设置均已持久化（`NodeStore` schema3、`SettingsStore`）；`Index.ets:143-157` ERROR 态按钮文案为「重试」 | 有"重试"入口，但**无"上次连接中断于何时/原因"**、无一键恢复（FR-14 未实现，恢复体验无法闭环） |
| FR-22 连接诊断 | 部分 | **◐** | `KernelService.humanize()`（超时归因、`886e5ad` 补超时文案）+ 首页横幅（`Index.ets:184-186` 迁移失败可见）+ `Settings.ets:134` 写盘失败横幅 | 错误可读性提升，但**无分步诊断页、无原始错误展开** |
| FR-23 日志查看与导出 | 未实现 | **◐** | `Logger.ets:25-38` 新增 `sensitiveError/sensitiveInfo`（`%{private}s`）；`DevPanel.ets:156 maskSensitive`、`:179-180` 长度+private | 脱敏侧有真进展；**无日志页、无级别过滤、无导出** → ◐ |
| FR-31 协议/传输 | 部分 | **◐** | 四协议 + `raw/ws/grpc/mkcp`；**REALITY 仍缺 `publicKey/shortId`**（`KernelConfigBuilder.ets:139-142`）；**`http2` 仍映射到已移除的 `http`**（`:158-160`） | 两条"导入成功但必失败"的坑未修 → 不能升 ✅ |
| FR-35 本地入站安全 | 部分 | **✅** | `SocksGuard.ets:41-79`（端口 20000-40000 随机、128bit hex 口令、CSPRNG）；`KernelConfigBuilder.ets:26-33`（有口令→`auth:"password"`）；`Index.ets:24-29` 每次连接轮换；实测 `socks endpoint rotated: 127.0.0.1:28117 (auth=password)` | 回环 + 随机端口 + 默认鉴权三件齐全且有实测；"关闭鉴权时的风险提示"未实现（口令为空才 noauth，UI 无开关）→ 不影响本条主验收 |
| FR-40 启动超时兜底 | 部分 | **✅** | `KernelService.ets:71-74`（8000/5000ms 常量）、`:166-176 waitUntil` 硬超时；`Index.ets:78-124` 失败即 ERROR + `bestEffortStop()` 收尾 + `buttonLabel()` 给「重试」；实测失败路径立即进 ERROR 不卡 CONNECTING | 内核启动超时闭环成立。**但 `startVpnExtensionAbility` 那条 Promise 仍未接入**（当前连接不走 VPN 扩展）→ 若严格按 FR-40 原文（针对 VPN 启动 API），应记 ◐。**判定：✅（内核启动路径）+ 遗留项写入 §4** |
| FR-44 设置持久化完整性 | 未实现 | **◐** | `ConfigService.ets:103-121`（`persistSettings` + `persistError`）、`:491-514`（写失败回滚内存值）；`Settings.ets:37-46/134-135`（横幅）；`SettingsStore.ets`（独立 KEY） | 代码齐全，**但未见"注入写失败"的实测证据** → 按纪律记 ◐ |
| FR-41 测速/延迟 | 未实现 | 未实现 | 全仓无测速入口 | 未变 |
| FR-42 多配置 profile | 未实现 | 未实现 | 无 profile 概念 | 未变 |
| FR-43 UDP 转发开关 | 未实现 | 未实现 | `KernelConfigBuilder.ets:29/30` 仍硬编码 `"udp":false`，无 UI | 未变 |
| NFR-06 凭据安全 | 未实现 | **◐** | `SecretStore.ets:158-251`（Asset Store add/query/remove，`DEVICE_FIRST_UNLOCKED`）；`ConfigService.ets:396-485`（schema v1→v2 迁移、in-flight 复用、哈希别名）；`NodeStore.ets:23`（schema=3） | 凭据已迁出明文且有失败阻断（`Index.ets:11-20`）；**未做真机迁移实测与"卸载残留"验证** → ◐ |
| NFR-10 兼容性 | 偏离 | 偏离 | `build-profile.json5`：`compatibleSdkVersion = 26.0.0`（需求要求 12） | 未变，仍是文档/配置不一致项 |

---

## 2. 全量状态汇总（44 条）

| 状态 | 数量 | 条目 |
|---|---|---|
| ✅ 已实现 | **6** | FR-01、FR-03、FR-05、FR-06、FR-35、FR-40（附条件，见 §1） |
| ◐ 部分 | **10** | FR-04、FR-07、FR-09、FR-13、FR-16、FR-22、FR-23、FR-31、FR-44、NFR-06 |
| 未实现 | **28** | FR-02、FR-08、FR-10、FR-11、FR-12、FR-14、FR-15、FR-17~21、FR-24~30、FR-32~34、FR-36~39、FR-41~43 |

> 与 PC9 对比：✅ 0→6，◐ 11→10（净升级 6 条、其中 FR-44 由未实现升 ◐、FR-35 由部分升 ✅ 等）。

---

## 3. 新增能力中"需求未覆盖"的部分（是否需要新 FR）

| # | 新能力 | 是否需要新 FR | 建议 |
|---|---|---|---|
| 1 | **geo 资源手动联网更新 + 离线文件导入**（`GeoAssets.updateFromNetwork` `:249-292`、`pickAndImport` `:363-436`） | **需要** | 立 **FR-45**：geo 资源更新须**仅由用户显式发起**、更新前告知体积、失败保留旧资源、支持离线导入；验收点含"应用在用户未操作时不得联网下载 geo"（这是一条隐私/信任约束，不能只靠注释） |
| 2 | **节点分组与筛选**（`NodeStore` schema3 `group`、`Nodes.ets:191-263` 筛选行） | **需要（小）** | 立 **FR-46**：节点分组可命名/可筛选；分组名长度上限与空组清理规则须可验收 |
| 3 | **日志 public/private 分级**（`Logger.ets:25-38`） | **需要（安全项）** | 立 **FR-47**：任何可能含凭据/服务器地址的日志必须以 private 输出；验收=导出/抓取日志中不出现 UUID/密码/域名（可正则机检） |
| 4 | 凭据 schema v1→v2 迁移与失败阻断（`ConfigService.ets:396-442`） | 不需要新编号 | 已被 **NFR-06 + FR-04** 覆盖，建议在 NFR-06 补一句"迁移失败必须阻断连接" |

**结论**：建议新增 **FR-45 / FR-46 / FR-47**（按 FR-41~44 格式）。本轮**未直接写入** `requirements.md`——因为需你确认编号后再追加，避免与你的编号规划冲突（见 §6 待确认）。

---

## 4. 双向不一致清单

### 4.1 需求有、实现没有（或只做一半）

| # | 需求 | 实现现状 | 建议 |
|---|---|---|---|
| U-1 | FR-31：REALITY 参数完整 / `http/h2/h3` 拒绝 | 缺 `publicKey/shortId`；`http2` 仍生成 `"http"` | **改代码**（高优先，属"导入成功但必失败"） |
| U-2 | FR-13/14/15 三条红线 | 无隧道可用性探测、无中断原因记录 | **改代码**（依赖 VPN 链路，但 FR-14 可先做） |
| U-3 | FR-17 首连明示四要素 | 无模态、无四要素文案 | **改代码**（纯 UI，成本低，合规相关） |
| U-4 | FR-29 许可与来源声明（MPL） | 关于页仅一行内核版本 | **改代码**（法务阻塞上架） |
| U-5 | FR-05 子项：规则数超限阻止启动 | 用户规则不进内核，无上限校验 | **改代码**（随 FR-07） |
| U-6 | FR-01 子项：失败四分类 | 解析器直出文案 | **改代码**（小） |
| U-7 | NFR-10：`compatibleSdkVersion=12` | 配置为 26.0.0 | **改文档或改配置**：若确为调试便利，需在 NFR-10 写明"开发期 =26，发布前回落 12"并给门禁；否则改配置 |
| U-8 | FR-40 原文（VPN 启动 API 超时） | 仅覆盖内核启动超时 | **改代码**（随 FR-10） |

### 4.2 实现有、需求没有

| # | 实现 | 建议 |
|---|---|---|
| I-1 | geo 联网/离线更新（含"不后台自动下载"约束） | 新增 FR-45 |
| I-2 | 节点分组与筛选 | 新增 FR-46 |
| I-3 | 日志 public/private 分级 | 新增 FR-47 |
| I-4 | 凭据迁移失败即阻断连接 | 并入 NFR-06 条文（不新增编号） |
| I-5 | `bestEffortStop` 失败后收尾（防端口占用挡住重试） | 属 FR-40 实现细节，已在 §1 备注，不新增 |

### 4.3 设计偏离（改文档，不改代码）

| # | 偏离 | 原因（实测） | 处理 |
|---|---|---|---|
| D-1 | `libxray.so` **不在 `DT_NEEDED`**，改为运行时 `dlopen` | 若链接依赖，动态加载器在启动即加载它，Go runtime 随即快照 `environ`；此后设置的 `xray.location.asset` 读不到 → 实测报 `stat /system/bin/geosite.dat`。现用 `-Wl,--as-needed` 延迟到首次 `dlopen`（`56267fb`） | **改 design**：在 §2.9（预构建库约束）S-1 旁补"延迟加载要求"，并说明它同时是 geo 资源可用的前提 |
| D-2 | 配置生成用**手拼字符串 + 逐值转义**，不是"结构化对象 + JSON.stringify" | ArkTS 严格模式禁无类型对象字面量（`arkts-no-untyped-obj-literals`），对象字面量方案在本工程不可编译 | **改 design**：把"生成策略"的表述改为"字符串构造 + `esc()` 逐值转义"，并写明该校验手段（三模式 JSON 断言脚本） |

---

## 5. 计划/风险维度的进度更新（给 K1 文档的补丁要点）

| P / R / 门禁 | PC9 时 | 现在 | 证据 |
|---|---|---|---|
| K1 `P-01`（so 加载） | 未完成 | **已达成**（M6/M7 探针可用 + `libxray` 可 `CGoInvoke`） | `DevPanel.ets:123-147`、`KernelService.start` 实测 running=true |
| K1 `P-02`（构建链） | 未完成 | 部分（`--as-needed` + `setAssetPath` 已落地；性能基线仍无） | `cgo_bridge.cpp` `setAssetPath`、`CMakeLists.txt` `--as-needed` |
| K1 `P-03`（tun 链/J-01） | 未开始 | **仍未开始**（无 `createVpnConnection`） | `VpnExtAbility.ets:16-23` 仍是骨架 |
| 风险 R-06（IPv6 默认泄漏） | 存在 | **未缓解**（无 VPN 配置，v6 尚未接管） | 无 `VpnConfig` |
| 风险 R-13（`routes` 不可增量） | 存在 | 未缓解；FR-39 未实现 | `KernelConfigBuilder` 只生成 routing，不生成 routes |
| 门禁 `RG-02`（v6 不泄漏） | 未验证 | 仍不可验证（依赖 P-03） | — |
| 凭证明文风险（NFR-06） | 已发生（明文落盘） | **已缓解**（Asset Store + 迁移 + 失败阻断）；残留：删除节点不擦除历史 secret（`ConfigService.ets:227-230` 注释已如实说明） | 同 NFR-06 证据 |

---

## 6. 待你确认 / 我无法确认的项

| # | 事项 | 为什么不能定 |
|---|---|---|
| Q-1 | 是否新增 **FR-45/46/47** | 编号规划属你与 Z1 的职责；我给了内容但没写入，避免撞号 |
| Q-2 | FR-40 是否维持 ✅ | 我按"内核启动超时闭环"判 ✅，但原文指向 `startVpnExtensionAbility`。二者要区分，需你在 ID 标记口径上拍一下 |
| Q-3 | NFR-10 的 `compatibleSdkVersion=26` | 无法判断是"调试期临时值"还是"产品决策"；需你或架构侧确认后再决定改文档还是改配置 |
| Q-4 | FR-06 是否维持 ✅ | 依据是"三模式配置合法 + 内核接受"，**不含分流结果正确性验证**（需真机出口 IP 对比）；若你的 ✅ 口径要求结果正确，应降为 ◐ |
| Q-5 | geo 资源版本升级流程（`GEO_VERSION` 常量需手工改，`GeoAssets.ets:55-58`） | 这是"发版即更新"还是"允许远程改版本号"？涉及是否引入远程配置通道（安全面） |

---

## 7. 需要你（或执行者）用 git 复核的命令清单

```bash
git -C D:/projects/xray-harmony log --oneline afcad51..5778e61
git -C D:/projects/xray-harmony show --stat 357a91b 12011f6 5778e61
git -C D:/projects/xray-harmony show --stat be97988 0f82ef1 a686761 c35837a 886e5ad
git -C D:/projects/xray-harmony show --stat 56267fb f20baff 7f2c65d
git -C D:/projects/xray-harmony diff afcad51..5778e61 -- entry/src/main/ets/service/KernelConfigBuilder.ets
llvm-readelf -d entry/libs/arm64-v8a/libxray.so | grep -E "SONAME|NEEDED"
```

---

## 8. 本轮已做的文档补丁 & 未做的

**已做**
1. `doc/requirements.md`：FR 表主键单元加状态标记（`✅` / `◐`，未实现不加）+ 表下「实现状态（2026-10-18）」小节（只列 ✅/◐ + 证据）+ 变迁记录一行。
2. `doc/design.md`：补记两条设计偏离（D-1 `--as-needed` 延迟加载、D-2 字符串构造 JSON），标注"偏离原因 = 实测约束"，不删原设计文字。

**未做（等确认）**
- FR-45/46/47 的正式写入（Q-1）；
- `risks-and-roadmap.md` 的里程碑/风险进度表补丁（本文件 §5 已给全部要点，等 Q-2/Q-3 定调后一次改，避免改两遍）。

---

## 9. 关于 PC9

PC9 是 20:30 快照，**状态结论已被本文件取代**；其方法论（三值口径、证据规则、四域分析、MVP 缺口清单、冲突项）仍然有效，**不删除**。建议在 PC9 顶部加一行：`superseded by PC11（2026-10-18 22:20），状态结论以 PC11 为准`。
