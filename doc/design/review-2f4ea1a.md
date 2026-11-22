# 复核记录：commit `2f4ea1a`（NodeRow + Nodes 令牌化）

> 复核人：ui-visual-designer ｜ 日期：2026-11-22 ｜ 依据：`doc/design/ui-spec.md` §11.7（15 条自检）、§11.8（15 项脚本）
> 复核范围：`components/NodeRow.ets`、`pages/Nodes.ets`、`common/Token.ets`、`base|dark/element/color.json`

## 0. 结论

**通过项**：leader 报的五条实测逐条对上代码，全部成立。

| 实测项 | 代码依据 | 结论 |
|---|---|---|
| 名称独占 ≈226vp | `Text(this.name).width('100%')` 在 `Column` 内，chip 已不在名称行 | ✅ |
| `:port` 恒完整 | `Text(\`:${this.port}\`)` 独立、无 `layoutWeight`；host 单独 `layoutWeight(1)` | ✅ |
| A-15 菜单不吃行点击 | `bindMenu` 浮层 + 整行 `onClick` 只做 pick | ✅ |
| base/dark 26/26 同键 | 两文件 `"name"` 均 26 条 | ✅ |
| 页内硬编码色 = 0 | `grep '#RRGGBB'` 于 Nodes/NodeRow 均 0 | ✅ |

**不通过项**：4 个 P0（见 §2），其中 3 个是规范文档自身的错误（见 §1，已修）。

---

## 1. 规范自身错误（3 处，已回写 ui-spec.md）

| # | 错误 | 影响 | 修正 |
|---|---|---|---|
| E-1 | §11.4 写行内 `padding top/bottom: 10`，同时 §11.8 要求 `grep "padding(10)"` = 0 | 规范自相矛盾，实现者无所适从 | 改 **8**；`minHeight 64` 吸收差额（内容 40+16=56 < 64），视觉零变化 |
| E-2 | §3.3 间距白名单 `{4,8,12,16,20,24,32}` 未给"两行文字之间的行距"留位置，但 §11.4 用了 `Column({space:2})` | `Space.xxs=2` 无合法身份，后续会被当通用间距用 | 新增 **`space-line = 2`**，限定"仅两行文字之间的行距，不得当控件间距"；建议 Token 改名 `lineGap` |
| E-3 | §11.4 写 host "中间省略" | ArkUI `Ellipsis` 只支持尾部省略，中间省略需手工裁字符串（成本不值） | 改"尾部省略"；因 `:port` 已独立成 Text，**尾部省略不影响四要素** |

顺带对齐（不是错，是两处不一致）：Token 的 `titleMd` 行高 22、`body` 行高 20，规范原为 24/22 → 规范改齐 Token，并补规则：`lineHeight < 1.4×fontSize` 只许用于**单行标题/标签**（16/22=1.38、11/16=1.45 合规），**多行正文禁止**。

---

## 2. P0 缺陷（阻断验收）

### P0-1 `maxWidth: 96` 应为 60

`NodeRow.ets:154` `.constraintSize({ maxWidth: 96 })`

宽度推演（文字列 222vp）：

| 固定项 | vp |
|---|---|
| 协议短名（`vless` @12fp） | ~33 |
| `·` | ~7 |
| `:443` | ~26 |
| 4 个间隙（`Row space 6`） | ~24 |
| **小计** | **~90** |

- chip = 60 → host = 222 − 90 − 60 = **72vp ≈ 11 字符**（`hk01.ex…:443`）
- chip = 96 → host = 222 − 90 − 96 = **36vp ≈ 5 字符**（`hk0…:443`）

**96 等于把"地址可读"废掉一半。** 60 正好 = 4 汉字（4×11 + padding 16），与 `font_chip ≤4 字` 的定义自洽。

### P0-2 `importColor()` 用文案子串猜语义

`Nodes.ets:237-246`：`if (m.indexOf('失败') >= 0) → danger; if (m.indexOf('已存在') >= 0) → warning`

两个反例：

1. `r.failed > 0` 的部分成功，文案含"失败 2 条" → 被判 **danger**（应为 warning）；
2. "新增 3 条，已存在 2 条" → 被判 **warning**（部分成功，尚可接受，但判定依据是巧合而非语义）。

**修法**：导入结果回来时按字段算出显式级别（`ok | warn | error`）存一个 `@State importLevel`，颜色读级别，不读文案。这与"UI 状态不说谎"同类：**颜色不许从文案反推**。

### P0-3 装饰字形缺 `accessibilityLevel('no')`

涉及 `‹`（Nodes:252）、`×`/`+`（Nodes:276）、`⋯`（NodeRow:165）、`✓`（NodeRow:93）。

现状 = 外层有 `accessibilityText` + 内层字形仍可读 → 读屏念"‹ 返回"。**这是 A-07 的反向缺陷：有标签但会重复念。** 四处都要加（脚本第 13 项）。

### P0-4 行缺 `accessibilityGroup(true)`

`NodeRow.ets:189-190` 有 `accessibilityLevel('yes')` + `accessibilityText(rowA11y())`，但 chip 上还有 `accessibilityText(this.group)`（NodeRow:155）→ 会与整行**双读**（"香港01，vless…，已选中，香港"）。

**修法**：行根加 `.accessibilityGroup(true)`，让整行按一句播报；chip 的 `accessibilityText` 保留（分组已含在 rowA11y 里，两者不冲突的前提是 group 生效）。

---

## 3. P1 缺陷

| # | 位置 | 问题 | 修法 |
|---|---|---|---|
| P1-1 | `NodeRow.ets:122` `Row({space: 6})` | 6 不在间距白名单 | 改 4 或 8；另建议把 `·` 合并进协议 Text，省一个间隙（6vp 直接还给 host） |
| P1-2 | `NodeRow.ets:54-58` 菜单 | 上移/下移恒可点，首/末项未置灰；`moveNode` 返回 false 后**静默无反馈** | 首/末项 `text_tertiary` + 不可点 |
| P1-3 | `NodeRow.ets:53-64` 菜单浮层 | 无描边 | 加 **1vp `border_subtle`**：本规格不用阴影，层级靠"描边 + 亮度差"；深色下 `bg_surface` 浮层压在 `bg_surface` 卡片上会融成一片 |
| P1-4 | `Nodes.ets:248-294` `@Builder header()` | 页头内联在页面里 | 抽 `components/PageHeader.ets`。否则 Index / NodeEdit / RoutingRules / Logs 会各抄一份——正是当初要防的重复 |

---

## 4. P2 缺陷

| # | 位置 | 问题 |
|---|---|---|
| P2-1 | `Nodes.ets:355-368` chip | 可点 `Text` 无按下态（§4.9 要求 `bg_surface_alt` 或 `accent_pressed` 反馈） |
| P2-2 | `NodeRow.ets:23` `showGroupChip` | 死属性：Nodes 未传、恒 true |
| P2-3 | `Nodes.ets:293` header padding `left:4 / right:8` | 与 §4.1「页面左右 16」不一致（视觉差异约 12vp，标题起点 52 vs 64）。建议统一：header padding 0 + 44 按钮，标题起点 = 48 |

---

## 5. 两处偏离的裁定

### 5.1 用 `Text('\u2713')` / `Text('\u22ef')` 代替 `SymbolGlyph` → **接受**

理由：`sys.symbol.*` 名称不保证可解析，缺资源 = 白块，比字形更糟；视觉等效（20vp、同色）且不引资源。

**条件（4 条）**：
1. 所有装饰字形 `.accessibilityLevel('no')`（见 P0-3）；
2. 字形尺寸/字重进 Token（`IconSize.check=20` 已进；`✓` 用 `FontWeight.Bold` 补视觉重量，代码已做）；
3. 系统字体放大 1.3× 后不得溢出 24vp 槽（A-13 复测）；
4. **`‹`（U+2039）是标点不是箭头**，视觉偏小偏高，需比其他图标大 2vp（22）才等重，或直接换 `←`。

### 5.2 自定义 `@Builder` 菜单代替 `MenuItem` → **接受**

理由：`MenuItem` 无法只给"删除"上 `danger`，只能整菜单一色。

**条件（3 条）**：
1. 浮层加 1vp `border_subtle` 描边（见 P1-3）；
2. 首/末项置灰（见 P1-2）；
3. 项高 44、`minWidth 160`、删除红 —— 已符合，保持。

### 5.3 方案 B（chip 降级纯文字）暂不启用 → **同意，但触发条件写死**

**触发条件**：出现 **≥5 字分组名且 host 被截到 <8 字符**时才启用。不到这一步不提前付"分组不再是标签"的代价。

---

## 6. 复核待办（下次 diff 我看这 6 条）

1. chip `maxWidth` 是否 60；4 字组名下 host 是否 ≥10 字符；
2. `importColor` 是否改为读显式级别（`grep "indexOf('失败')"` = 0）；
3. 四处装饰字形是否都有 `accessibilityLevel('no')`；
4. `NodeRow` 根是否 `accessibilityGroup(true)`，读屏是否一句读完；
5. 菜单浮层是否有描边、首末项是否置灰；
6. `Row({space:6})` 是否已回白名单。
