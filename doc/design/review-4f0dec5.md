# 批量复核（第一批）：`9758e41` → `cdbcc24` → `4f0dec5`

> 复核人：ui-visual-designer ｜ 日期：2026-11-22 ｜ 依据：`doc/design/ui-spec.md` §4/§5/§10/§11（A-01…A-17，脚本 15 项）
> 方式：按约定只做批量复核，不逐条回环。

## 0. 判定汇总

| 提交 | 声称内容 | 复核结论 |
|---|---|---|
| `9758e41` | 6 项 P0/P1 修复 | ✅ 6/6 落实（chip 60、级别分色、字形静音、行级整句、移动置灰、菜单描边） |
| `cdbcc24` | PageHeader + StatusTone + deriveView(label) + 首页文案换词 + 长按复制 | ✅ 全部落实；⚠️ 首页**只改到"状态区"**，其余仍是硬编码（见 §4） |
| `4f0dec5` | DevPanel 进 Settings + Scroll + PageHeader | ✅ 落实；⚠️ Settings **整页未令牌化**（见 §5），别当成已过 |

**净进展**：全仓硬编码色值 `128 行 → 105 行`（Nodes 18→0、NodeRow 0、ViewModel 5→0 已清空）。剩余 6 个文件：`NodeEdit 25 / Settings 25 / RoutingRules 16 / Logs 14 / Licenses 12 / Index 11 / DevPanel 2`。

**一条待批量修**：`NodeRow.ets:192` 行内 `top/bottom: 10` → 8（E-1，视觉无差异，不单独回环）。

---

## 1. 需要二选一的规范冲突（2 条，我给定论）

### C-1 `PageHeader` 的计数单位写死成「个」——**必须在下一批前改成 `countText`**

`PageHeader.ets:55` `Text(\`${this.count} 个\`)`，注释写"计数只传数字，不传带单位的字符串（单位属于展示层，由这里拼）"。

**这个理由不成立**：单位是**每页**的，不是 header 的。下一批就要用它的两个页面会直接错：

| 页面 | 需要的文本 | 现状会渲染成 |
|---|---|---|
| `Logs` | `127 条` | `127 个` ❌ |
| `RoutingRules` | `已启用 3 条`（带前缀，不是纯计数） | `3 个` ❌ |

**定论**：改 `@Prop countText: string`（空串=不显示），由页面拼好传入。理由：单位与前缀都是页面语义，header 只负责排版；这样也不需要为"条/个/项"各加一个 prop。
**验收**：`PageHeader` 内不出现"个"字面量；`grep "个" components/PageHeader.ets` = 0。

### C-2 首页副标题用 `text_tertiary`（规范写的是 `text_secondary`）——**采纳实现，规范改口**

`Index.ets:230` 用 `text_tertiary`（4.83:1，达标）。副标题是**定位语**（装饰性、非信息），压在应用名下面时用三级色更安静，不与状态行抢注意力。
**定论**：规范 §5.1 改为 `body-sm 13/20 text_tertiary`。

---

## 2. 我做出的产品语义判断（2 条）

### S-1 DISCONNECTED 态新增「已就绪：<name>」——**接受，并补进规范**

`ConnectionViewModel.ets:117`：`hasNode ? \`已就绪：${nodeLabel}\` : '当前仅在本机提供代理'`。

规范 §10.4.1 只约束了 CONNECTED 的三档回退，没写 DISCONNECTED 有节点时该说什么。实现给的是"已就绪：香港 01"——**它比"当前仅在本机提供代理"更有用**（用户点连接前就知道要用哪个节点），且不含实现词。
**定论**：接受；§10.4.1 增一档：DISCONNECTED + 有节点 → `已就绪：<name>`。

### S-2 CONNECTING 文案「正在建立连接…」——**接受，不写秒数**

原骨架文案含"最多等待 8 秒"。8s 是 `KernelService.CONNECT_TIMEOUT_MS`（可调），写进文案就变成**对用户的承诺**：调优变了文案要跟着变，超时几分钟用户会以为"坏了"。
**定论**：保持「正在建立连接…」，**但规范补一条禁止项**：连接过程不放倒计时/秒数承诺。若将来要缓解等待焦虑，用进度指示（`LoadingProgress`）而不是数字。

---

## 3. P0 / P1 / P2

### P0（无——本轮没有阻断项）

### P1-1 `state=DISCONNECTED` 调试串仍在首页（`Index.ets:273`）

已令牌化（`fontChip` + `text_tertiary`）但**没删**。规范 §5.1 已裁决删除、移到 DevPanel（`§5.8` 已写明"首页移过来的内容放这里"）。
**为什么算 P1 而不是 P2**：它是"用户可见的实现语"，与 §10.4 的文案红线同类；且下一批 DevPanel 会再动一次，现在删省一次改动。
**验收**：`grep "state=" pages/Index.ets` = 0。

### P1-2 `PageHeader` 计数单位（见 C-1）

### P1-3 Index 状态大字 `fontSize(22)` + `Medium`

`Index.ets:259-260`：规范是 `display` 24/32 **w600**。现状 22/Medium 是旧值，属漏改（同文件其它字号都已走 Token）。
**修法**：`FontSize.display` + `LineHeight.display` + `FontWeight.Bold`。

### P2

| # | 位置 | 问题 |
|---|---|---|
| P2-1 | `Index.ets:255` `Row({space: 6})` | 6 不在白名单（4/8） |
| P2-2 | `PageHeader.ets:80` `padding left 4 / right 8` | 与 §4.1「左右 16」不一致。**建议规范改口**：44 返回键自带 22 视觉留白，`left:4` 是对的，标题起点 48。规范比实现更该改 |
| P2-3 | `PageHeader` 无按下态 | 图标按钮按下时无 `bg_surface_alt` 反馈（§4.9）。次要，等全局按钮组件一起做 |

---

## 4. Index 剩余未令牌化清单（下一批照此收尾，避免以为已完成）

状态区（tone / hint / busy / 诊断行）已令牌化 ✅，以下是**还没动的**：

| 行 | 现状 | 改成 |
|---|---|---|
| 236-240 | 横幅 `fontSize(12)` / `#8D6E63` / `#FFF3E0` / `padding(10)` / `radius 8` | `Banner(warning)`：`bodySm` / `warning` / `warning_subtle` / `Space.md` / `Radius.panel` |
| 247-251 | 横幅 `#B71C1C` / `#FFEBEE` | `Banner(danger)`：`danger` / `danger_subtle` |
| 255 | `Row({space: 6})` | `Space.xs`(4)，状态点与文字 |
| 259-260 | `fontSize(22)` / `Medium` | `display` 24/32 + `Bold` |
| 273 | `state=` 调试串 | **删除**（P1-1） |
| 306 | `Text('当前节点').fontColor('#666666')` / `fontSize(14)` | `body`(14)/`body` + `text_secondary` |
| 317 | `#FAFAFA` | `bg_surface_alt` |
| 弹层 391-407 | `#FFFFFF` / `radius 10`(徽标) / `#99000000` / `#1976D2` / `#333333` / `fontSize(12)` | §5.9：`bg_surface` / `scrim` / `accent` / `text_primary` / `title-lg`+`caption` |

> 弹层另外两条 §5.9 已写死的：卡片 `radius-hero` 16（现 14→已 14? 见 391 附近）、「我已了解」按钮 40→**44**。你下批做 §5.9 时一起。

---

## 5. Settings 现状（别当成已过）

`4f0dec5` 只做了三件事：包 `Scroll`、加「开发者选项」分组、换 `PageHeader`。**页面内 25 处硬编码、4 处 10fp、2 处 11fp 全部还在**（`#FAFAFA` `#1976D2` `#E0E0E0` `#607D8B` `#777777` `#999999` `#666666`）。§5.4 的逐项清单原样有效。

**已确认的结构修复**（`Scroll`）：原来内容超一屏时底部被裁，属"入口存在但点不到"。这条不在我规范里，但你按 A-17 精神处理是对的——**建议把这条升为通用规则**，我已补进 §4.1（内容超一屏必须可滚，不得靠固定 `Column` 裁切）。

---

## 6. 本轮我对规范的回写（我自己动的，不需你回）

| 位置 | 改动 |
|---|---|
| §11.4 | 行内所有文字/字形 `.accessibilityLevel('no')`；**禁止 `accessibilityGroup(true)`**；附 `9758e41` 的 dumpLayout 证据 |
| §11.7 / §8 A-07 | 改写为「子节点静音 + 行级整句」 |
| §8.2（新增） | 可验证性边界：`accessibilityText` 不进 `dumpLayout`；A-07 只能静态核对 + 真机读屏 |
| §11.8 | 第 14 项改为"有 accessibilityText 且**无** group" |
| §11.10 | 记一条"采纳实测，规范改口" |
| §10.4.1 | 增 DISCONNECTED+有节点 → `已就绪：<name>`；增禁止项"连接过程不放秒数承诺" |
| §5.1 | 副标题色改 `text_tertiary`（C-2） |
| §4.1 | 补"内容超一屏必须可滚"；header padding 改口为 `left 4 / right 8`，标题起点 48（P2-2） |

---

## 7. 下一批之前必须改的 2 项（其余可批量）

1. **`PageHeader.count` → `countText`**（C-1）——否则 Logs / RoutingRules 一上手就是错的。
2. **删 `Index.ets:273` 的 `state=`**（P1-1）——文案红线，且 DevPanel 下批要动。

## 8. 我不会打断的

- `NodeRow` 的 `top/bottom: 10`（E-1）：视觉无差异，已记在 §0，批量时一起。
- `Settings` 整页未令牌化：属于"下一批范围"，不算偏离，但请在清单里明确标注，避免读者误判完成度。
