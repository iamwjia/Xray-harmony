# PC14 — 系统分享：当前 SDK 下不可安全实现（含两次实测证据）

日期：2026-11-22
设备：HarmonyOS 模拟器（x86_64），API 26，DevEco 自带 `sdk/default`

## 1. 想做什么

「导出备份」除了保存到文件，还能一键调起**系统分享面板**（发给微信/邮件/网盘），这才是"发给别人"的主路径。

## 2. 结论先说

**当前 SDK 里做不到安全的系统分享。** 已实现、实测、然后**回退**了，原因有两层：

### 2.1 Share Kit 不在这个 SDK 里

- HarmonyOS 的分享面板是 `systemShare`（Share Kit）；
- `ets/kits/` 下没有 `@kit.ShareKit`，`ets/api/` 下没有 `@ohos.systemShare`；
- 全 SDK 搜索 `systemShare` 只命中 LLVM 头文件，与系统能力无关。

没有可用 API，就只能退回 Want 隐式意图。

### 2.2 隐式意图会被无关应用抢走（两次实测）

写法：把文件写进沙箱 → `fileUri.getUriFromPath()` → `want = { action, uri, flags: FLAG_AUTH_READ_URI_PERMISSION }` → `startAbility`。

| 组合 | 实测结果 |
| --- | --- |
| `action = ohos.want.action.sendData` + `type = application/octet-stream` | **日历应用被拉起**，弹出它的隐私授权页（"调用日历权限、读取位置信息…"） |
| `action = ohos.want.action.sendData`，不带 type | **直接进入日历 UI**（月视图），比上一条更糟 |
| `action = ohos.want.action.sendToData` | `16000019 No matching ability is found`，系统弹"暂无可用打开方式 / 前往应用市场" |

也就是说：**同一个 action，取决于匹配到的应用**，可能打开一个和分享毫无关系的应用，且用户会以为是我们干的事。

## 3. 为什么不能"就这样留着"

- 用户点「导出并分享」，跳出来的是日历的授权弹窗——这不是"分享面板没适配"，是**错误行为**；
- 用 `type` 限定只会换个抢走者，不构成可靠修复；
- 加"先弹确认框告诉用户将交给其他应用"也没解决根因：**我们不知道会交给谁**。

## 4. 现在的做法

- 「导出到文件」走系统保存选择器（`DocumentViewPicker.save`），用户自己选落点；
- 页面上写明：「导出后可在『文件』里找到该文件并分享。（系统分享面板需要 Share Kit，当前 SDK 未提供；用隐式意图会被日历类应用抢走）」
- 该说法就是要让下一个人**别再试一遍**。

## 5. 什么时候可以加

满足其一即可接入：

1. 换到带 **Share Kit** 的 SDK（`systemShare.ShareController.show(context, options)`），按官方示例传 `uri`、`title`、`description`；
2. 或者在真机上验证隐式意图能落在**分享面板**（而不是某个具体应用）——需要真机证据，模拟器不可作数。

真机验证步骤（留给下一轮）：
```
1. 装含"导出并分享"的构建
2. 点击后记录：跳转到了哪个应用 / 是否出现多应用选择
3. 若出现选择面板且目标合理（微信、邮件、文件管理），才允许保留该入口
```

## 6. 代码现状

`pages/Backup.ets` 已回退到只有 `doExport()`（保存选择器）：
- 无 `sendData` / `sendToData` / `fileUri` / `wantConstant` 引用；
- 沙箱导出目录那段也一并删掉，避免留下"生成了没人用的文件"。
