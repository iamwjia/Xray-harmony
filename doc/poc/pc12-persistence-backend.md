# PC12 — 持久化后端：PersistentStorage 的恢复路径不成立，改用 preferences

日期：2026-11-22
范围：`entry/src/main/ets/platform/KvStore.ets`、四个 Store、`ConfigService.loadFromDisk()`、`EntryAbility.onWindowStageCreate`
设备：HarmonyOS 模拟器（x86_64），API 26

## 1. 现象

首次连接的一次性明示（`settings.onboardingDone`）在**每次重启后重新出现**。用户点过一次「我已了解」，重启又弹。

排查时先分清「没写进去」和「写了没读回来」，所以 `SettingsStore.load()` 打印了 `rawLen`：

```
09:18:20 settingsStore save ok: routing=rule log=INFO     ← 写了
09:18:33(重启) settingsStore load: rawLen=0               ← 读回来是空
```

## 2. 证据

设备上的文件确实存着数据（不是没落盘）：

```
hdc shell cat /data/app/el2/100/base/com.tunnelix.app/haps/entry/files/persistent_storage
<string key="tunnelix_settings_v1">"{...\"onboardingDone\":true}"</string>
<string key="tunnelix_subs_v1">"{... 两条订阅 ...}"</string>
<string key="tunnelix_nodes_v1">""</string>
```

同一份文件里：`settings` 有值但读回 0、`subs` 有值（因为启动时不读它，所以没被覆盖）、`nodes` 已经是空串。

这解释了一条更严重的隐情：**读空之后只要有任何一次写回，磁盘上的真实数据就被固化成空**。节点表就是这么被清掉的——不是用户删的。

同时排除了时序假设：把恢复挪到 `onWindowStageCreate`（UI 上下文已就绪、`loadContent` 之前）仍然 `rawLen=0`。所以不是"调得太早"，是 `PersistentStorage.persistProp(key, '')` 在这套运行时上的恢复路径本身不成立。

## 3. 方案

新增 `platform/KvStore.ets`，直接走 `@ohos.data.preferences` 的**同步** API：

- `init(context)`：`preferences.getPreferencesSync(context, { name: 'tunnelix_store' })`，只做一次；
- `read(key)`：`getSync(key, '')`，未 init 或异常返回空串并**记错误日志**；
- `write(key, value)`：`putSync` + `flushSync()`，返回布尔，调用方不得假装成功。

四个 Store（Node / Settings / Rules / Subscription）把 `AppStorage.get` / `AppStorage.setOrCreate` 换成 `KvStore.read` / `write`，`ensure()` 保留为空实现以兼容旧调用点。`AppStorage` 只剩下 `cfgRev`（UI 刷新通知），不再承担数据存储。

初始化与恢复的位置：`EntryAbility.onWindowStageCreate` → `KvStore.init(this.context)` → `ConfigService.getInstance().loadFromDisk()` → 凭据迁移 → `loadContent`。

`loadFromDisk()` 是幂等方法，构造函数不再读盘——构造函数在 `onCreate` 阶段就会被 `ensureSecureMigration()` 触发，那时读到的必然是空。

## 4. 验证（均为强制停止后重启，非进程内内存复用）

| 项 | 结果 |
| --- | --- |
| 明示确认后重启 | `settingsStore load: rawLen=73` → `onboarding=true`，弹层不再出现，点「连接」直接进入 `state=CONNECTED` |
| 导入 1 个节点后重启 | `nodeStore load: rawLen=369` → `1 node(s) schema=3 migrated=true` |
| 落盘文件 | `haps/entry/preferences/tunnelix_store`（258 B → 369 B 随节点增长） |
| 初始化失败路径 | `KvStore` 未 init 时读返回空串并记 error，写返回 false——不会被当成成功 |

## 5. 遗留

- 旧的 `files/persistent_storage` 不再读取。目前只在模拟器上有测试数据，未做一次性的旧数据搬迁；如果要保历史数据，需要在 `KvStore.init` 后加一次 legacy 导入（读旧文件 → 写新库 → 标记已迁移）。
- `KvStore` 是同步 IO，写放大可忽略（每次操作一条 JSON），但**不要在渲染循环里写**。
- 扩展进程（`VpnExtAbility`）不读这些 Store，配置通过 Want 传入，因此不需要 init；若将来要在扩展进程里读写，必须先 `KvStore.init`。
