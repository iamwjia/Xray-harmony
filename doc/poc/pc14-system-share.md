# PC14 — 系统分享：Share Kit 可用（前次结论已推翻）

日期：2026-11-22
设备：HarmonyOS 模拟器（x86_64），API 26
状态：**superseded** —— 本文第 1 节记录的"当前 SDK 没有 Share Kit"是错的，原因与更正见该节。

## 1. 我错在哪（保留记录，不删）

第一次找 Share Kit 时只搜了 `sdk/default/openharmony/ets`：

```
ls ets/kits | grep -i share        -> 只有 BasicServicesKit / dataShare / fileshare
grep -rln systemShare ...          -> 只命中 LLVM 头文件
```

于是写下"SDK 没有 Share Kit，只能退回 Want 隐式意图"。错在只看了开源的 openharmony SDK，没看同一层的 `hms`（Huawei 闭源能力）：

```
sdk/default/hms/ets/kits/@kit.ShareKit.d.ts
sdk/default/hms/ets/api/@hms.collaboration.systemShare.d.ts
sdk/default/hms/ets/api/@hms.collaboration.harmonyShare.d.ts
```

`@kit.ShareKit` 导出 `systemShare` 与 `harmonyShare`。图库、WPS 的分享走的正是它。

教训：查平台能力不能只扫一个 SDK 根。`sdk/default` 下同时有 `openharmony`（开源底座）与 `hms`（闭源 Kit），很多"系统级"能力只在后者。

## 2. 隐式意图为什么确实不能用（这段仍然有效）

在"没有 Share Kit"的错误前提下试过 Want 隐式意图，实测三次：

| 写法 | 结果 |
| --- | --- |
| `sendData` + `type=application/octet-stream` | 拉起日历应用的隐私授权页 |
| `sendData`，不带 type | 直接进入日历月视图 |
| `sendToData` | `16000019 No matching ability`，提示"暂无可用打开方式" |

结论不变：隐式意图让系统自己匹配能力，会被无关应用接走，不能用来做分享。分享只应走 Share Kit。

## 3. 正确实现（已落地）

```ts
const record: systemShare.SharedRecord = {
  utd: utd.UniformDataType.FILE,          // general.file：任意文件
  uri: fileUri.getUriFromPath(path),      // 沙箱文件 -> file:// URI
  title: fileName,
  description: '加密备份，需口令解开'
};
const controller = new systemShare.ShareController(new systemShare.SharedData(record));
controller.show(ctx, {
  selectionMode: systemShare.SelectionMode.SINGLE,
  previewMode: systemShare.SharePreviewMode.DETAIL
});
```

流程：生成密文 → 写入 `context.filesDir/exports/` → 打开分享面板。
失败时（设备无分享面板）不谎报成功：提示文件名与体积，并指向「导出到文件」。

## 4. 实测

```
bundle export: nodes=4 rules=0 missingCreds=0
面板内容：分享 | tunnelix-backup-1795328686063.tunnelixbak
              加密备份，需口令解开 | 华为分享
页面提示：已发送到分享面板（约 2.1 KB）。请把口令另发一条消息。
```

模拟器上目标较少（只有华为分享），真机会出现微信/邮件等更多目标。

## 5. 遗留

- `excludedAbilities` / `ShareAbilityType` 未使用（当前无需排除通道）；
- 未注册 `shareCompleted` 回调（无统计需求，也不宜为统计多要能力）；
- 真机需复核：面板是否显示应用名与缩略图（模拟器上为默认图标）。
