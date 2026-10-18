# PC7 · AppGallery 包体大小限制的事实核查

> 作者：harmony-platform-analyst · 2026-10-18
> 结论先行，证据分层：**已核实的官方原文** 与 **未获取官方依据** 严格分开。凡无官方原文的，一律标【未获取官方依据】，不猜数字。

---

## 0. 结论（一句话）

> **「40MB 级 HAP 在 AppGallery 是否构成障碍」——目前无法给出"是/否"的官方结论**：因为**华为侧的包体上传上限没有任何可抓取的官方原文**（AGC 文档为前端渲染，抓取为空）。
> 但可确认的官方事实是：**上架单元是 App Pack（`.app`），云端分发与端侧安装以 HAP/HSP 为单位**，且**我们没有任何一条已核实的量化限制会被 40MB 触及**（唯一可查到的量化限制"免安装 HAP ≤10MB"仅适用原子化服务，与本产品无关）。
> **因此：不要为 40MB 做架构妥协；也不要写死包体预算——按 leader 裁决"暂不设包体预算"，待 AGC 上限确认后再定。**
> **另有一条比上传上限更影响体验的确定事实**：`compressNativeLibs` 缺省为 **false** ⇒ **libs 不压缩、下载量 ≈ HAP 体积**（实测 HAP 内 so 全为 STORED，比值 1.000），且 `extractNativeLibs` 缺省为 **true** ⇒ 安装时另解压一份。详见 §5。


---

## 1. 已核实的官方原文（OpenHarmony 文档，可逐字引用）

**出处**：`Stage模型应用程序包结构`
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/quick-start/application-package-structure-stage.md

> **【官方原文】**"每个应用中至少包含一个.hap文件，可能包含若干个.hsp文件、也可能不含，一个应用中的所有.hap与.hsp文件合在一起称为**Bundle**……当应用发布上架到应用市场时，需要将Bundle打包为一个.app后缀的文件用于上架，这个.app文件称为**App Pack**（Application Package）……"
> **【官方原文】**"**App Pack是发布上架到应用市场的基本单元**。"
> **【官方原文】**"在应用签名时，是以HAP/HSP/APP为单位进行签名的；**在云端分发、端侧安装时，是以HAP/HSP为单位进行分发和安装的**。"

**判读**：这两句把"上架单元"与"下发单元"分开了。**对体积的真正约束作用在"下发单元（单个 HAP/HSP）"上**，而不是 App Pack 总量——也就是说，**拆分 HAP/HSP 是平台提供的第一顺位体积手段**（把大资源放进独立 HSP/feature HAP）。

**出处**：`打包工具`
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/tools/packing-tool.md

> **【官方原文】**"应用配置 `compressNativeLibs` 为 true 时，会按照 `--compress-level` 设置的压缩等级对 `--lib-path` 指定目录下的文件进行压缩。"
> **【官方原文】**"`--compress-level`：lib库下文件压缩等级，默认值1。可选等级1-9……数值越大压缩率越高、压缩速度越慢。"
> **【官方原文】**（API 22 起）"`--exist-src-path` 指定增量打包时的源HAP包路径……当 `--lib-path-retain` 配置为 true 时，打包工具会直接拷贝源HAP包中的 libs 目录……当 libs 目录中 so 文件压缩耗时比较久时，使用增量打包可以提升打包速度。"

**判读**：**so 默认是可压缩的**（`compressNativeLibs=true` 时），所以"38MB 内核"在 HAP 里通常**不等于 38MB 下载体积**（Go 静态链接产物压缩率通常不低，但**具体压缩率必须实测，本文件不给未标注来源的数字**）。

**出处**：`NDK工程构建概述`（ABI 取值）
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/build-with-ndk-overview.md

> **【官方原文】**"`OHOS_ARCH`：`armeabi-v7a`/`arm64-v8a`/`x86_64`……设置当前Native交叉编译的目标架构。"

**判读**：ABI 是**构建期**决定的，一个 HAP 可以含多个 ABI 的 `libs/<abi>/`（我们已实测双 ABI 打包成功）。

---

## 2. 我们自己的实测数据（可复现，非二手）

来源：`doc/poc/PC6-skeleton-build-log.md` §10（真实构建产物）

| 配置 | HAP 体积 | 说明 |
|---|---|---|
| 仅 `arm64-v8a` | **1,346,634 B** | 单 ABI |
| `arm64-v8a` + `x86_64` | **2,916,719 B** | 双 ABI，**≈ 2.17 倍** |

**直接推论（对 40MB 场景很关键）**：如果内核 so 是 38MB 量级，
- **只发 `arm64-v8a`**：只有一份内核 so；
- **同时带 `x86_64`**：**内核 so 会有两份** ⇒ 体积近似翻倍。
⇒ **上线包必须只保留真机 ABI**（x86_64 仅供模拟器验证，绝不能进发布包）。这条不是"优化建议"，而是**避免把 40MB 变成 80MB** 的硬要求。

---

## 3. 【未获取官方依据】必须人工核实的四项

> 说明：华为开发者文档（`developer.huawei.com/consumer/cn/doc/...`）为前端渲染页面，本环境抓取返回空正文；以下四项**没有拿到官方原文**，因此不给数字。

| # | 待核实 | 为什么必须核实 | 人工核查路径 |
|---|---|---|---|
| 1 | **单 HAP / App Pack 的上传体积上限** | 直接决定"40MB 是不是问题" | AGC「发布应用」文档页：`https://developer.huawei.com/consumer/cn/doc/app/agc-help-releaseapkrpk-0000001106463276`；若页面未写，提 AGC 工单问"HarmonyOS HAP / App Pack 上传大小上限及超限提示" |
| 2 | **应用市场是否按 ABI 拆分下发** | 若市场能按设备架构只下发对应 `libs/<abi>/`，则"多 ABI 打包"不增加用户下载量 | 同上工单，问题措辞："多 ABI 的 HAP 上传后，应用市场是否按设备 ABI 只下发可用的 so？" |
| 3 | **是否存在按需下载/动态交付（类似 AAB 的模块按用户需求下载）** | 决定大资源能否延后下载 | 查 AGC「HarmonyOS 应用发布」与「HSP 动态共享包」相关文档；关键词：动态共享包、按需加载、feature HAP |
| 4 | **免安装（原子化服务）HAP ≤10MB** 的官方原文 | 只影响元服务形态；若将来做元服务入口才相关 | 官方"原子化服务/免安装约束"文档。【社区口径】见 51cto 问答，未见官方原文，**不作为依据** |

**关于广泛流传的"单 HAP 最大 4GB"**：该说法在多个第三方问答（segmentfault / 51cto）出现，措辞为"根据 HarmonyOS 的应用软件包规范"。
→ **【未获取官方依据】**：我没有在 OpenHarmony 官方文档（打包工具、包结构、bundleManager 等）中检索到该数值原文。**在拿到官方页面之前，不得把它当作平台约束写进需求或设计**。

---

## 4. 对"要不要写包体预算"的建议

| 选项 | 建议 | 理由 |
|---|---|---|
| 写死"包体预算 ≤X MB" | ❌ 不建议现在写 | 上限未核实，写死会误伤（可能根本不需要拆） |
| 写"软约束 + 触发条件" | ✅ 建议 | 例如："单 HAP 目标 ≤100MB；**若 AGC 上传上限低于该值**，则按 §1 的官方机制拆为 feature HAP / HSP" |
| 现在就做架构级拆分（HSP/feature HAP） | ⚠️ 暂缓 | 40MB 在移动端属常见量级；在拿到上限前做拆分是**为不确定的约束支付确定的复杂度** |
| 上线包剔除 `x86_64` | ✅ **立刻确定为纪律** | 实测双 ABI 体积 ≈2.17×；内核 so 会被复制两份（§2） |

---

## 5. `compressNativeLibs` 的实际取值（决定下载量，比上传上限更影响体验）

### 5.1 官方原文（配置项与缺省值）

**出处**：`module.json5配置文件`
https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/quick-start/module-configuration-file.md

> **【官方原文】**`compressNativeLibs`："在打包hap时，该标签标识libs库是否以压缩存储的方式打包到HAP。- true：libs库以压缩方式存储。- false：libs库以不压缩方式存储。" 缺省说明原文：**"该标签可缺省，在打包hap时缺省值为 false。"**
> **【官方原文】**`extractNativeLibs`（API 20+）："标识应用安装时，libs库是否解压到应用安装目录。**当 `compressNativeLibs` 和 `extractNativeLibs` 都配置为 false 时，应用以不解压 libs 库的方式进行安装；其他场景，应用以解压 libs 库的方式进行安装**。" 缺省说明原文："该标签可缺省，**缺省值为 true**。"

### 5.2 本工程的实际情况（**未显式配置 ⇒ 走缺省**）

- `entry/src/main/module.json5` 中**既没有 `compressNativeLibs`，也没有 `extractNativeLibs`**（已检索确认）。
- 因此按官方缺省：**`compressNativeLibs = false`（不压缩）、`extractNativeLibs = true`（安装时解压）**。

### 5.3 实测佐证（HAP 内 so 全部 STORED）

对一个含内核 so 的实际构建产物解包核对（zip 条目 `Length` vs `CompressedLength`）：

| 条目 | 未压缩大小 | 压缩后大小 | 比值 |
|---|---|---|---|
| `libs/x86_64/libxray.so` | 38,069,288 | 38,069,288 | **1.000** |
| `libs/x86_64/libcgoping.so` | 1,380,360 | 1,380,360 | 1.000 |
| `libs/arm64-v8a/libc++_shared.so` | 1,262,504 | 1,262,504 | 1.000 |
| 其余 `libentry.so` / `libprebuilt.so` | — | — | 1.000 |

⇒ **所有 so 在 HAP 内均以 STORED（不压缩）方式存储**，与"缺省 `false`"完全一致。

### 5.4 由此推出两个**确定**的体积结论

| 结论 | 依据 |
|---|---|
| **下载量 ≈ HAP 体积本身**：38MB 的内核 so 在 HAP 里就是 38MB，**不会因为打包而变小** | 缺省 `compressNativeLibs=false` + 实测比值 1.000 |
| **安装后大概率再占一份**：缺省 `extractNativeLibs=true` ⇒ 安装时把 libs 解压到安装目录 ⇒ **存储占用 ≈ 包体 + 解压后 libs**（是否保留原始安装包需真机核实，标【待真机验证】） | 官方原文"其他场景，应用以解压 libs 库的方式进行安装" |

> **所以"38MB 内核 ≠ 38MB 下载量"这句话要改口径**：**在当前缺省配置下，它就是 ≈38MB 下载量**；只有当显式设置 `compressNativeLibs: true` 时才可能变小（**压缩率必须实测，本文件不估算**）。

### 5.5 给设计与需求的取舍（只给事实与选项，不替设计决定）

| 选项 | 效果 | 代价 / 待验证 |
|---|---|---|
| 维持缺省（`compressNativeLibs=false`） | 下载量 = 包体；安装后额外解压 | 简单、无加载风险 |
| 显式 `compressNativeLibs: true` | 下载量可能下降（**压缩率待实测**） | 安装前需解压，可能影响首次启动耗时【待实测】 |
| `extractNativeLibs: false`（API 20+，需同时 `compressNativeLibs=false`） | 安装时不解压 ⇒ 省一份存储 | 需验证 so 加载方式/性能是否受影响【待实测】 |
| 拆分 feature HAP / HSP | 把内核从主包挪出，减小首装下载 | 增加工程复杂度；商店是否按需下载【未获取官方依据】 |

---

## 6. 对"要不要写包体预算"的建议（按 leader 2026-10-18 裁决修订）

### 6.0 关键实验：`compressNativeLibs` A/B 实测（2026-10-18，结论：**应开启**）

同一工程、同一内核 so，仅改 `module.json5` 的 `"compressNativeLibs"` 一项，各打一次包（`assembleHap --no-daemon`）：

| 配置 | HAP 体积 | `libs/arm64-v8a/libxray.so` 条目 | 压缩比 |
|---|---|---|---|
| 缺省（`false`，不压缩） | **38,656,796 B（≈36.9 MiB）** | 35,740,808 → 35,740,808（STORED） | **1.000** |
| `"compressNativeLibs": true` | **14,542,619 B（≈13.9 MiB）** | 35,740,808 → 13,206,202 | **0.369** |

**其他条目同批受益**：`libc++_shared.so` 1,262,504 → 445,030（0.352）；`libentry.so` 77,104 → 32,498（0.421）。

> ⚠️ **最容易误读的一点（必须写进任何引用处）**：
> `extractNativeLibs` 缺省为 **`true`** ⇒ **安装时仍会把 libs 解压到安装目录**。
> 所以准确表述是：**下载量 13.9MB，但安装后占用仍约 36MB**。
> **"开了压缩，占用也变一半"是错的**——压缩只省**下载/上传**，不省**安装后存储**（除非另行设置 `extractNativeLibs: false`，那是另一个待验证的设计选项）。

**判定（按 leader 事先给定的判据）**：
> "若压缩后 HAP 明显变小（比如 40MB → 25MB）⇒ **应把 `compressNativeLibs: true` 定为发布配置**"

实测 **36.9MB → 13.9MB（−62%）**，**远强于判据**：**⇒ `compressNativeLibs: true` 已定为发布配置**（2026-10-18 写入 `entry/src/main/module.json5` 并提交，见 §6.0.1）。
代价：安装时解压（`extractNativeLibs` 缺省 `true` 已是解压路径），**首次启动耗时【待实测】**；但**下载量减少 ~23MB** 是确定收益。

### 6.0.1 落地状态（2026-10-18）

- `entry/src/main/module.json5` 已永久加入 `"compressNativeLibs": true`（附行内注释说明"下载变小 ≠ 占用变小"）。
- 落地后重建验证：`BUILD SUCCESSFUL in 5 s 79 ms`，HAP = **14,542,619 B**，`libxray.so` 压缩比 **0.369**（与实验值一致）。
- **遗留待验证（不许当"应该没影响"）**：**压缩包的首次启动耗时 vs 未压缩包**，需真机对比（同设备、同节点、冷启动各 ≥10 次取中位数）。


### 6.1 包体预算与发布纪律

| 选项 | 结论 | 依据（**纪律必须有数字，否则下次有人会觉得"顺手改掉也行"**） |
|---|---|---|
| 写死"包体预算 ≤X MB" | ❌ **不写** | 上限未核实；没有依据的软约束会在评审时被当成依据 |
| **暂不设包体预算** | ✅ **本版采纳** | 待 AGC 上限确认后再定；现有证据未显示 40MB 触及任何已知限制 |
| **发布纪律 ①：上线包不得含 `x86_64`** | ✅ **必须** | 内核 so 会被复制两份：**单 ABI 未压缩 38,656,796 B → 双 ABI 约 79.5MB**（按 +35.7MB 估算；骨架包实测双/单 = **2.17×**：1,346,634 → 2,916,719 B）。误带 = 单内核多 ~36MB，属事故 |
| **发布纪律 ②：`compressNativeLibs: true`** | ✅ **已落地** | A/B 实测：**38,656,796 B → 14,542,619 B（−62%）**，`libxray.so` 压缩比 0.369。代价：首次启动耗时**待实测**；且**不改安装占用**（见 §6.0 警告） |
| 现在就做 HSP/feature HAP 拆分 | ⚠️ 暂缓 | 开启压缩后下载量已 13.9MB，无明显拆分必要 |



**给文档的措辞（本版定稿，可直接抄）**

> **包体**：**暂不设包体预算**（待 AGC 上传上限确认后回填）。
> **发布纪律 1：上线包不得包含 `x86_64`**——内核 so 会被复制两份（误带则单内核多约 36MB）。
> **发布纪律 2：开启 `compressNativeLibs: true`**——实测 HAP 从 36.9MB 降到 13.9MB（−62%，`libxray.so` 压缩比 0.369）；`extractNativeLibs` 保持缺省 `true`（安装时解压），**首次启动耗时需实测**。
> **体积基线（实测）**：strip 后内核 so 35.7MB；开启压缩后**下载体积 13.9MB**；安装后占用仍约为「解压后 libs + 包体」，具体是否保留原始安装包【待真机验证】。


---

## 7. 实测体积快照（2026-10-18 16:0x，工作区 `entry/src/main/libs/`）

> 说明：这两个 `.so` 由**内核集成那条线**产出，我只读取不修改；体积会随构建 flags（是否 strip / 优化等级）变化，**下表是"当下这一版"而非最终值**。

| 文件 | 大小 | 备注 |
|---|---|---|
| `arm64-v8a/libxray.so` | **69,068,464 B（≈65.9 MiB）** | 真机主线用的内核 so |
| `x86_64/libxray.so` | **71,317,112 B（≈68.0 MiB）** | 仅模拟器；**不得进发布包** |
| `arm64-v8a/libprebuilt.so` | 11,696 B | PC6 骨架桩 |
| `x86_64/libprebuilt.so` | 9,840 B | 同上 |

**两个必须点出来的事实**

1. **未 strip 时内核 so 是 69MB**（x86_64 版 71MB），**strip 后 35.7MB**（见下方实测）。若同时打进两个 ABI，**单内核就 ≈140MB（未 strip）**——这比"40MB 是否超限"的问题严重得多。⇒ §6 的"上线包不得含 `x86_64`"**不是优化，是必需**。
2. 同一份内核在不同构建下体积差异明显（本次核查早前见过另一版 HAP 内 `libxray.so` 为 38,069,288 B），说明**当前产物很可能未 strip 或构建 flags 不同**。⇒ **"包体到底多大"必须以 Release + strip 后的产物为准，标【待实测】**；本文件不给最终数字。

**建议的下一步（已执行，结果为实测）**

```powershell
# 只读取工作区文件、输出到临时目录，不污染他人构建
llvm-strip.exe --strip-all entry/src/main/libs/arm64-v8a/libxray.so -o %TEMP%\libxray.stripped.so
```

**实测结果（2026-10-18）**：

| 版本 | 大小 |
|---|---|
| 工作区原始 `arm64-v8a/libxray.so` | 69,068,464 B（≈65.9 MiB） |
| `--strip-all` 之后 | **35,740,808 B（≈34.1 MiB）** |

⇒ **strip 让内核 so 减少约 48%**。**"单内核 ~35MB（strip 后）"这个量级是实测成立的**，与 leader 的"40MB 量级"判断一致；而**未 strip 的 69MB 不能作为包体基线**。
→ 结论：**包体基线应取 strip 后的 35.7MB（arm64 单 ABI）**；若误带 x86_64，则再叠加一份（约 +36MB，合计 ≈72MB）。

---

## 8. 本次核查的方法与局限（便于复核）



- ✅ 可抓取：OpenHarmony 官方文档（gitee 源）——本节所有"官方原文"均出自此。
- ❌ 不可抓取：`developer.huawei.com/consumer/cn/doc/...`（前端渲染，返回空正文），因此**所有 AGC/应用市场侧的数字均未获取**。
- 🔁 复核建议：由人工在浏览器打开 §3 的两个链接，把页面上的相关句子**截图存档**，再回填本文的 §3 与 §5。
