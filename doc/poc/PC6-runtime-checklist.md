# PC6 · 设备就绪后的运行时验证清单（M1 安装态 → M2/M3 → M4 观察表）

> 作者：harmony-platform-analyst · 2026-10-18 · 只准备不执行（当前无设备）
> 用法：设备一到位，从 §1 顺序往下走，**命令直接复制**。平台背景不在这里重复（见 `PC0-skeleton-on-emulator.md`）；真机纪律见 `PC4-device-and-observation.md`。
> 本次固定值：HAP `D:\projects\xray-harmony\entry\build\default\outputs\default\entry-default-unsigned.hap`｜bundle `com.example.xraypoc`｜Ability `EntryAbility`｜扩展 `MyVpnExtAbility`

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$hap = 'D:\projects\xray-harmony\entry\build\default\outputs\default\entry-default-unsigned.hap'
```

---

## 1. 前置检查（1 分钟）

| 检查 | 命令 | 期望输出 | 不符时 |
|---|---|---|---|
| 设备可见 | `& $hdc list targets` | 一行设备串，如 `7001005458323933328C3F0F25000000`（或 `127.0.0.1:5555` 模拟器） | 输出 `Empty` → **【需人工】启动模拟器 GUI / 连真机并在设备上确认 USB 调试授权** |
| 设备 API = 26 | `& $hdc shell param get const.ohos.apiversion` | `26` | 非 26 → 记录实际值后**停止**（本工程 `compatibleSdkVersion=26.0.0`，低版本装不上） |
| 系统版本（记录用） | `& $hdc shell param get const.ohos.fullname` | 形如 `HarmonyOS x.y.z` | 仅记录 |
| 现有版本（如有旧包） | `& $hdc shell bm dump -n com.example.xraypoc` | 有 `versionName` 输出 = 已装 | 空 = 未装，正常 |
| 签名状态 | 当前产物是 `*-unsigned.hap` | — | **未签名包 `hdc install` 预期失败**；先按 §2 试，失败则 **【需人工】DevEco 登录华为账号 → Signing Configs → 自动签名** 后重新构建出 `*-signed.hap` |

> 签名失败的预期形态：`hdc install` 报签名校验类错误（`signature verification failed` / `code:9568xxx` 一类）。**【待真机验证】具体错误码与文本**——请把原文抄进 §4 记录表，不要改写成"配置问题"。

---

## 2. M1-安装态（5 分钟）

```powershell
# 2.1 安装（覆盖安装用 -r）
& $hdc install -r $hap

# 2.2 卸载（会清沙箱数据）
& $hdc uninstall com.example.xraypoc

# 2.3 重装 = 2.2 + 2.1；若只是代码更新，用 2.1 的 -r 即可

# 2.4 启动
& $hdc shell aa start -a EntryAbility -b com.example.xraypoc

# 2.5 确认已启动（有进程 = 起来了）
& $hdc shell "ps -ef | grep com.example.xraypoc | grep -v grep"

# 2.6 冷启动标准姿势（改过代码/配置后必做）
& $hdc shell aa force-stop com.example.xraypoc
& $hdc shell hilog -r
& $hdc shell aa start -a EntryAbility -b com.example.xraypoc
& $hdc hilog
```

**判定信号**

| 结果 | 判为 | 下一步 |
|---|---|---|
| `install bundle successfully`（或同类成功文案） | ✅ 安装成功 | 走 2.4 |
| 签名类报错 | ⛔ 未签名/Profile 不匹配 | **【需人工】DevEco 登录账号生成调试签名** 后重编 |
| `failed to install ... code:9568xxx`（非签名类） | ❌ 需看原文 | 抄原文进 §4；常见为设备空间不足 / 与已装包签名冲突（先 `uninstall` 再装） |
| `aa start` 报 ability 不存在 | ❌ 名字不符 | 核对 `module.json5` 的 `abilities[].name`（大小写敏感） |
| `ps` 无输出 | ❌ 启动即崩 | `& $hdc hilog` 看崩溃；取 faultlog 见 `PC4 §2.4` |

---

## 3. M2 / M3 运行态（5 分钟）

界面三个按钮：`M2: call NAPI hello()` / `M3: call prebuilt_add(1,2)` / `M4: start VpnExtensionAbility`。

| 里程碑 | 点按钮后应看到 | 关键日志 |
|---|---|---|
| **M2** | 按钮下方文本变为 `hello from native` | `XVPN_POC`：`M2 hello=hello from native` |
| **M3** | 文本变为 `prebuilt_add(1,2)=3`（**返回 3 = 预编译 .so 真的链上并执行了**） | `XVPN_POC`：`M3 prebuiltAdd result=3` |

**看不到时的排查顺序（按序，命中即停）**

```powershell
# ① 只看本工程日志（首选）
& $hdc hilog | Select-String -Pattern 'XVPN_'

# ② 按 tag 过滤（参数语义以 hilog -h 为准）
& $hdc shell hilog -h
& $hdc hilog -T XVPN_POC
```

| 现象 | 结论 | 查什么 |
|---|---|---|
| 无 `XVPN_BOOT` | 应用没起来 / 装的是旧包 | §1 `bm dump` 的 `versionName`；重跑 §2.6 |
| 有 `XVPN_BOOT`，点 M2 后无 `XVPN_POC` 且界面显示 `M2 failed` | **so 未加载**（ABI 不匹配 / 依赖缺失 / SONAME） | 界面上的 `code/message`；`& $hdc shell "ps -ef \| grep com.example.xraypoc"` 看是否崩溃重启；`llvm-readelf -d libentry.so` 查 `DT_NEEDED` |
| M2 正常、M3 显示 `M3 failed` | **预编译库问题** | 确认 HAP 内 `libs/arm64-v8a/libprebuilt.so` 存在；未见则回到构建（`PC6-skeleton-build-log.md` §4.4） |
| 界面文本不更新但日志有输出 | UI 刷新问题（非 native 问题） | 记录后跳过，不影响 M2/M3 判定 |

> **ABI 提醒**：当前产物只含 `arm64-v8a`。若在 **x86_64 模拟器**上跑，M2/M3 会因"该 ABI 无 so"失败——这是**预期**，不是代码缺陷；不要在 x86_64 上得出"NAPI 不可用"的结论。

---

## 4. M4 观察表（最重要，逐项可记）

> **纪律**：模拟器与真机**各记一张表，不得合并**；模拟器上的负结论**不得**写成"平台不支持"（可能是环境不足），一律标【待真机验证】。
> **构建期已确定**：`type:"vpn"` 在 SDK 26 上构建期通过（无需 patch），本项若再次报错才需记录。

### 4.1 观察项 → 具体命令 / 看哪里 / 记录字段

| # | 观察项 | 具体命令 / 看哪里 | 记录字段 |
|---|---|---|---|
| 1 | `startVpnExtensionAbility` 的返回 | 界面 `M4` 下方文本（成功/`start failed: <code> <message>`）；日志 `XVPN_POC` 的 `M4 start ok` / `M4 start failed code=... msg=...` | `ok` 或 `code=` + `message`（逐字抄） |
| 2 | 是否弹出 VPN 授权对话框 | 目视（首次调用时） | 是/否；出现时机（点击后约多少秒） |
| 3 | `MyVpnExtAbility.onCreate` 是否被调用 | `& $hdc hilog \| Select-String 'XVPN_EXT'` | 有 `onCreate` 行 = 进；无 = 未进 |
| 4 | 状态栏是否出现 VPN 钥匙图标 | 目视（右上角状态栏） | 是/否；出现/消失时刻 |
| 5 | `vpn-tun` 是否存在 | `& $hdc shell ifconfig`（或 `& $hdc shell ip addr`） \| 找 `vpn-tun` | 有/无；若有，抄 IP 段 |
| 6 | 系统日志摘录 | `& $hdc hilog \| Select-String -Pattern 'Vpn\|vpn' \| Tee-Object -FilePath .\m4_log.txt` | 贴 3~10 行原文；特别关注错误码 `16000001/16000002/16000061/2203001/2203002` |
| 7 | 构建期是否报 `type:"vpn"` 非法 | 构建输出（已知 SDK 26 通过） | 是/否（是 → 记 SDK 版本 + 报错原文） |

### 4.2 记录表（复制两份：`模拟器` / `真机`）

```
设备类型：模拟器 / 真机            设备型号：
系统版本 const.ohos.fullname：      API Level：
构建标识（versionName / 构建时间）：
网络环境（Wi-Fi / 蜂窝，v4 / 双栈）：

1) start 返回：            （ok 或 code + message）
2) 授权弹窗：  是/否       出现时刻：
3) XVPN_EXT onCreate： 是/否
4) 状态栏钥匙图标： 是/否   时刻：
5) vpn-tun： 有/无         地址：
6) 系统日志摘录（原文 3~10 行）：
7) 构建期报错： 是/否（若"是"抄原文）：
结论三态：通过 / 不通过 / 无法判定
（若"无法判定"，写清缺什么：缺设备 / 缺环境 / 缺观测手段）
```

### 4.3 观察项与常见错误码的对应（便于第一时间定性）

| 现象 | 含义 | 是否可判"平台不支持" |
|---|---|---|
| `16000001` | `want` 里的 ability 不存在（配置问题） | ❌ 不可，先查 `module.json5` |
| `16000002` | ability 类型不符（拉起的不是 vpn 扩展） | ❌ 不可，先查 `type` |
| `16000061` | 该能力在当前设备/形态不支持 | ⚠️ **模拟器上必须真机复核**；真机才可作为证据 |
| `2203001` | 用户类型不允许（GUEST 等） | ❌ 不可，换正式用户 |
| `2203002` | VPN 已存在（已有连接） | ❌ 不可，先断开其它 VPN 再试 |
| 弹窗出现但无 `onCreate` | 授权流程启动但扩展未拉起 | ⚠️【待真机验证】 |
| 完全无任何反应、无日志 | 应用/扩展都没被拉起 | ❌ 先按 §2.6 冷启动、确认装的是新包 |

---

## 5. 「需人工」标注规则（一句话）

> 凡卡在 **登录账号 / 点授权弹窗 / 启动模拟器 GUI / 设备配对** 的，统一写 `【需人工】<具体动作>`，**不要陪用户折腾环境**，也不要去删 IDE 缓存（`.idea/`）或改 IDE 设置。

示例写法：
- `【需人工】DevEco 登录华为账号 → Project Structure → Signing Configs → 自动签名，然后重新构建`
- `【需人工】启动模拟器（DevEco Device Manager）并在设备上确认调试授权`
- `【需人工】在真机上点一次"允许"VPN 授权弹窗`

---

## 6. 执行记录（设备到位后填）

| 日期 | 设备 | M1 安装 | M2 | M3 | M4 结论 | 卡点 / 需人工项 |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

---

*本清单只索引"设备到位后的下一步动作"；平台事实与判据边界见 `PC0-skeleton-on-emulator.md` §6/§9 与 `PC4-device-and-observation.md`。所有【待真机验证】项须以真机实测回填。*
