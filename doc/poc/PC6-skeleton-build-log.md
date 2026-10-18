# PC6 · 最小工程骨架实际构建记录（E1）

> 作者：harmony-platform-analyst · 2026-10-18
> 目标：**不是文档，是可构建的工程**。本记录只写**真实执行过的命令与真实输出**，含 3 个真实报错与修法。
> 工程位置：`D:\projects\xray-harmony`（仓库根，未移动/删除 `doc/`、`_research_src/`、`.git/`、`README.md`、`.gitignore`）

---

## 0. 结果摘要（先看这个）

| 项 | 结果 | 证据 |
|---|---|---|
| **M1 构建出 HAP** | ✅ **通过** | `entry/build/default/outputs/default/entry-default-unsigned.hap`（1,346,569 字节）；冷构建 `BUILD SUCCESSFUL in 5 s 380 ms`，`34 tasks: 34 executed, 0 up-to-date` |
| **M2 NAPI 桩（ArkTS ↔ C）** | ✅ **代码通过编译并进包**（运行期待设备） | `libs/arm64-v8a/libentry.so`（50,712 B）在 HAP 内；ArkTS `CompileArkTS` 通过 |
| **M3 预编译 .so 链接** | ✅ **链接与打包通过**（运行期待设备） | HAP 内 `libs/arm64-v8a/libprebuilt.so`；`libentry.so` 的 `DT_NEEDED` 含 `libprebuilt.so` |
| **M4 `VpnExtensionAbility` 声明** | ✅ **构建期校验通过（关键发现，见 §5）** | HAP 内 `module.json` 保留 `"extensionAbilities":[{"type":"vpn",...}]`，**未报 `modulecheck` 校验失败，也无需 patch SDK** |
| **签名** | ⏸ 未配置（按指示） | 构建日志 WARN：`Will skip sign 'hos_hap'. No signingConfigs profile is configured` |
| **安装/启动/运行时** | ⏸ 等设备（模拟器/真机） | 记录见 §7「下一步需要人工做什么」 |

**当前 ABI：仅 `arm64-v8a`**（真机）。`x86_64` 未配置——模拟器要用时在 `entry/build-profile.json5` 的 `abiFilters` 加一项即可（§6）。

---

## 1. 环境实测值（本次真实读到的，不是假设）

| 项 | 实测值 | 来源 |
|---|---|---|
| DevEco build | `DS-261.23567.138.36.2600851` | `<DevEco>\build.txt` |
| SDK | `apiVersion: 26`、`platformVersion: 26.0.0`、`version: 26.0.0.105`、`releaseType: Release` | `<DevEco>\sdk\default\openharmony\ets\oh-uni-package.json` |
| hvigor 引擎 / 插件 | `@ohos/hvigor 6.26.8`、`@ohos/hvigor-ohos-plugin 6.26.8` | `<DevEco>\tools\hvigor\*\package.json` |
| node | DevEco 内置：`<DevEco>\tools\node` | `hvigorw.bat` 需要 `node` 或 `NODE_HOME` |
| java | DevEco 内置 JBR：`<DevEco>\jbr` | 打包阶段 `PackageHap` 需要（见 §4 报错 3） |
| NDK clang | `<DevEco>\sdk\default\openharmony\native\llvm\bin\clang.exe` | `aarch64-unknown-linux-ohos-clang` 在该目录**无 `.exe` 后缀**，用 `clang.exe --target=...` 更稳 |
| hdc | `<DevEco>\sdk\default\openharmony\toolchains\hdc.exe` | 本机当前无设备连接 |

> `<DevEco>` = `C:\Program Files\Huawei\DevEco Studio`

---

## 2. 构建前必须设的三个环境变量（否则一定失败）

```powershell
$dev = 'C:\Program Files\Huawei\DevEco Studio'
$env:NODE_HOME        = "$dev\tools\node"
$env:DEVECO_SDK_HOME  = "$dev\sdk"
$env:JAVA_HOME        = "$dev\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
Set-Location 'D:\projects\xray-harmony'
```

| 缺哪个会怎样 | 现象 |
|---|---|
| 缺 `NODE_HOME` 且 PATH 无 node | `hvigorw.bat` 直接 `ERROR: NODE_HOME is not set and no 'node' command could be found in your PATH` |
| 缺 `DEVECO_SDK_HOME` | 找不到 SDK / 无法解析 API 版本 |
| 缺 `JAVA_HOME` | 走到打包阶段才炸：`spawn java ENOENT`（§4 报错 3） |

---

## 3. 工程结构（本次实际创建的文件，不含构建产物）

```
D:\projects\xray-harmony\
├── AppScope/
│   ├── app.json5                                   # bundleName=com.example.xraypoc / versionCode / icon / label
│   └── resources/base/element/string.json          # app_name
│   └── resources/base/media/app_icon.png           # 占位图标（70B 1x1 PNG，仅为能构建）
├── entry/
│   ├── build-profile.json5                         # ★ externalNativeOptions: abiFilters=["arm64-v8a"]
│   ├── hvigorfile.ts                               # hapTasks
│   ├── oh-package.json5                            # ★ dependencies: "libentry.so": "file:./src/main/cpp/types/libentry"
│   └── src/main/
│       ├── module.json5                            # ★ abilities + extensionAbilities(type:"vpn") + INTERNET
│       ├── ets/entryability/EntryAbility.ets        # 打印 XVPN_BOOT 生命周期日志
│       ├── ets/pages/Index.ets                     # M2 / M3 / M4 三个按钮
│       ├── ets/vpnability/VpnExtAbility.ets         # M4：最小 VpnExtensionAbility（仅打日志）
│       ├── cpp/CMakeLists.txt                      # ★ add_library(entry SHARED ...) + IMPORTED prebuilt
│       ├── cpp/napi_init.cpp                       # ★ hello() / prebuiltAdd() 两个导出 + napi_module_register
│       ├── cpp/prebuilt/prebuilt.c                 # M3 预编译库源码（手写 C，非 Go）
│       ├── cpp/types/libentry/index.d.ts           # 给 ArkTS 的类型声明（消除 ArkTS 类型校验问题）
│       ├── cpp/types/libentry/oh-package.json5     # 声明 name=libentry.so / types
│       ├── libs/arm64-v8a/libprebuilt.so           # ★ 由 NDK clang 交叉编译产出（11,696 B）
│       └── resources/base/{element,media,profile}  # string/color/main_pages/startIcon
├── build-profile.json5                             # ★ products: compatibleSdkVersion/targetSdkVersion="26.0.0"
├── hvigorfile.ts                                   # appTasks
├── oh-package.json5                                # modelVersion 6.0.0，无三方依赖（离线可构建）
└── hvigor/hvigor-config.json5                      # modelVersion 6.0.0
```

### 3.1 关键配置字段（逐项说明，均为本次实际生效值）

| 文件 | 字段 | 本次取值 | 说明 |
|---|---|---|---|
| `build-profile.json5`（根） | `products[].compatibleSdkVersion` | `"26.0.0"` | **不能写 `"26.0.0(26)"`**（会报错，见 §4 报错 1）；与设备 API 26 对齐 |
| 同上 | `products[].targetSdkVersion` | `"26.0.0"` | 同上 |
| 同上 | `app.signingConfigs` | `[]` | 空 → 产出 **unsigned** HAP，构建日志有 WARN，属预期中间态 |
| `entry/build-profile.json5` | `apiType` | `"stageMode"` | VPN 相关 API 仅 Stage 模型可用（R2 §3.1.0） |
| 同上 | `buildOption.externalNativeOptions.path` | `"./src/main/cpp/CMakeLists.txt"` | 不配 = 根本不编 native |
| 同上 | `buildOption.externalNativeOptions.abiFilters` | `["arm64-v8a"]` | **当前只出真机 ABI**；模拟器需加 `"x86_64"` |
| `entry/src/main/module.json5` | `deviceTypes` | `["phone","tablet","2in1"]` | 漏写会"设备不兼容" |
| 同上 | `abilities[].srcEntry` | `"./ets/entryability/EntryAbility.ets"` | 以 `src/main` 为根 |
| 同上 | `extensionAbilities[0].type` | `"vpn"` | **本次构建期被 SDK 26 直接接受**（§5） |
| 同上 | `extensionAbilities[0].srcEntry` | `"./ets/vpnability/VpnExtAbility.ets"` | 同上 |
| 同上 | `requestPermissions` | `[{name:"ohos.permission.INTERNET"}]` | normal 级，声明即生效（R2 §3.2） |
| `entry/oh-package.json5` | `dependencies["libentry.so"]` | `"file:./src/main/cpp/types/libentry"` | 让 ArkTS 拿到 `.d.ts`；**这是"import 'libentry.so' 有类型"的关键** |
| `CMakeLists.txt` | `add_library(entry SHARED napi_init.cpp)` | 库名 `entry` → `libentry.so` | `import ... from 'libentry.so'` 与库名必须对应 |
| 同上 | `PREBUILT_DIR` | `${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}` | **`../libs` 不是 `../../libs`**（见 §4 报错 2） |
| `napi_init.cpp` | `napi_module.nm_modname` | `"entry"` | 与库名保持一致 |

---

## 4. 真实命令与真实输出（含 3 个报错与修法）

### 4.1 最终可用命令（可复制）

```powershell
$dev = 'C:\Program Files\Huawei\DevEco Studio'
$env:NODE_HOME="$dev\tools\node"; $env:DEVECO_SDK_HOME="$dev\sdk"; $env:JAVA_HOME="$dev\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
Set-Location 'D:\projects\xray-harmony'
& "$dev\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default assembleHap --no-daemon
```

> 说明：用的是 **DevEco 自带的全局 `hvigorw.bat`**，不需要项目内 wrapper，也不需要联网（`oh-package.json5` 无三方依赖）。

### 4.2 冷构建成功输出（删掉 `build/`、`.cxx/`、`.hvigor/` 后重跑，**34/34 任务全部执行**）

```
> hvigor Finished :entry:clean... after 1 ms
> hvigor Finished :entry:default@PreBuild... after 77 ms
> hvigor Finished :entry:default@ConfigureCmake... after 18 ms
> hvigor Finished :entry:default@ProcessProfile... after 120 ms
> hvigor Finished :entry:default@CompileResource... after 167 ms
> hvigor Finished :entry:default@BuildNativeWithCmake... after 1 s 933 ms
> hvigor WARN: When performing compilation for the arm64-v8a architecture:
clang++: warning: argument unused during compilation: '--gcc-toolchain=...' [-Wunused-command-line-argument]
> hvigor Finished :entry:default@BuildNativeWithNinja... after 635 ms
> hvigor Finished :entry:default@ProcessLibs... after 19 ms
> hvigor Finished :entry:default@DoNativeStrip... after 119 ms
> hvigor Finished :entry:default@CacheNativeLibs... after 5 ms
> hvigor Finished :entry:default@CompileArkTS... after 2 s 585 ms
> hvigor Finished :entry:default@GeneratePkgModuleJson... after 3 ms
> hvigor Finished :entry:default@ProcessCompiledResources... after 1 ms
> hvigor Finished :entry:default@PackageHap... after 285 ms
> hvigor Finished :entry:default@PackingCheck... after 6 ms
> hvigor WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured in current project.
> hvigor Finished :entry:default@SignHap... after 1 ms
> hvigor Finished :entry:default@CollectDebugSymbol... after 1 ms
> hvigor Finished :entry:default@assembleHap... after 1 ms
> hvigor BUILD SUCCESSFUL in 5 s 380 ms

34 tasks in total: 34 executed, 0 up-to-date
```

> **PowerShell 里 `Exit Code: 1` 是假信号**：hvigor 把 WARN 写到 stderr，PowerShell 将其当作 `NativeCommandError`。判定以输出中的 `BUILD SUCCESSFUL` 与产物文件为准。

### 4.3 报错 1：API 版本格式（首次构建就撞到）

**真实输出（原文）**
```
> hvigor ERROR: Error Code: 00308018 Unknown Error
api version parameter is illegal! Expected format: <major>[.<minor>][.<patch>], e.g., "17", "17.2", "17.2.3"
> hvigor ERROR: BUILD FAILED in 1 s 305 ms
```
**原因**：我最初按 DevEco 5 的写法填了 `"compatibleSdkVersion": "26.0.0(26)"`；**hvigor 6.26.8 只接受纯数字版本号**。
**修法**：根 `build-profile.json5` 改为 `"compatibleSdkVersion": "26.0.0"`、`"targetSdkVersion": "26.0.0"`。
**副作用验证**：打包后 `module.json` 里 `minAPIVersion: 260000026`、`compileSdkVersion: "26.0.0.105"` ⇒ 版本确实按 API 26 生效。

### 4.4 报错 2：预编译库路径差一级

**真实输出（原文，节选）**
```
> hvigor WARN: ninja: error: 'D:/projects/xray-harmony/entry/src/libs/arm64-v8a/libprebuilt.so',
  needed by 'D:/projects/xray-harmony/entry/build/default/intermediates/cmake/default/obj/arm64-v8a/libentry.so',
  missing and no known rule to make it
> hvigor ERROR: Failed :entry:default@BuildNativeWithNinja...
> hvigor ERROR: 00303300 Configuration Error
```
**原因**：`CMAKE_CURRENT_SOURCE_DIR` = `entry/src/main/cpp`，我写了 `../../libs` → 解析成 `entry/src/libs`（少一层 `main`）。
**修法**：改为 `${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}`（实际位置 `entry/src/main/libs/arm64-v8a/`）。

### 4.5 报错 3：打包阶段缺 java

**真实输出（原文，节选）**
```
> hvigor ERROR: Failed :entry:default@PackageHap...
> hvigor ERROR: Error Code: 00308018 Unknown Error
spawn java ENOENT
> hvigor ERROR: BUILD FAILED in 5 s 861 ms
```
**原因**：`PackageHap` 依赖 `java`，本机 PATH 里没有；DevEco 自带 JBR 在 `<DevEco>\jbr`。
**修法**：设 `JAVA_HOME=<DevEco>\jbr` 并把 `%JAVA_HOME%\bin` 前置到 PATH。

> 前 2 个错误是**工程配置**问题，第 3 个是**环境变量**问题——都不是平台能力问题。这三个报错原样记录，供后续任何人重现时对照。

---

## 5. 关键发现：`type: "vpn"` 在 SDK 26 上**构建期直接通过**

- 官方文档曾提示："如果 DevEco 提示不能识别 `"type": "vpn"`，需手改 SDK 的 `toolchains/modulecheck/module.json` 枚举"（`research/harmony-evidence-quotes.md` A1）。
- **实测：SDK 26.0.0.105 不需要任何 patch**。`module.json5` 里写 `"type": "vpn"` 后，`ProcessProfile` / `GeneratePkgModuleJson` / `PackingCheck` 全部通过，无任何相关 WARN/ERROR。
- 证据：打包后的 `module.json`（HAP 内）保留完整条目：
```json
"extensionAbilities":[{"exported":false,"srcEntry":"./ets/vpnability/VpnExtAbility.ets",
  "name":"MyVpnExtAbility","description":"$string:VpnExtAbility_desc",
  "label":"$string:VpnExtAbility_label","type":"vpn"}]
```
- **结论（可写进 PC4 §5 档位矩阵的第一条实测数据）**：
  1. `type:"vpn"` 的构建期校验在 **API 26 SDK 上已收录**，"需要 patch modulecheck"这条仅适用于旧 SDK；
  2. **构建通过 ≠ 能力可用**：这只证明"声明合法"，`VpnExtensionAbility` 能否被拉起、能否建 tun，必须真机验（M4 运行时部分仍为【待真机验证】）。

---

## 6. ABI 说明（当前构建的是哪个，别外推）

| 项 | 当前状态 |
|---|---|
| 已配置 ABI | **`arm64-v8a` 仅此一项**（`entry/build-profile.json5` 的 `abiFilters`） |
| 产物内 libs | `libs/arm64-v8a/` 下有 `libentry.so`、`libprebuilt.so`、`libc++_shared.so` |
| **能得出的结论** | 该工程在 `arm64-v8a` 上**构建/链接/打包**链路通 |
| **不能得出的结论** | ① 运行期能否 `dlopen`（需设备）② `x86_64`（模拟器）是否同样可行 ③ 任何性能数据 |
| 模拟器需要时怎么加 | `abiFilters` 改为 `["arm64-v8a","x86_64"]`，并**重新用 `--target=x86_64-linux-ohos` 编一份 `libprebuilt.so`** 放到 `entry/src/main/libs/x86_64/`（缺这一步会因"该 ABI 无预编译库"而失败） |

### 6.1 预编译库（M3）是怎么产出的（可复现命令）

```powershell
$sdk='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
$clang="$sdk\llvm\bin\clang.exe"
$out='D:\projects\xray-harmony\entry\src\main\libs\arm64-v8a'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$args=@('--target=aarch64-linux-ohos',"--sysroot=$sdk\sysroot",'-shared','-fPIC','-O2',
        '-Wl,-soname,libprebuilt.so','-o',"$out\libprebuilt.so",
        'D:\projects\xray-harmony\entry\src\main\cpp\prebuilt\prebuilt.c')
& $clang @args
```

**校验（两条都必须过）**
```powershell
& "$sdk\llvm\bin\llvm-readelf.exe" -d "$out\libprebuilt.so" | Select-String 'SONAME|NEEDED'
# 期望：SONAME: [libprebuilt.so]；NEEDED 仅 libc.so
```
实测输出：
```
(NEEDED)  Shared library: [libc.so]
(SONAME)  Library soname: [libprebuilt.so]
```

**`libentry.so` 的依赖（证明 M3 真的链上了）**
```
(NEEDED)  Shared library: [libace_napi.z.so]
(NEEDED)  Shared library: [libprebuilt.so]      ← M3 链接成立
(NEEDED)  Shared library: [libc++_shared.so]
(NEEDED)  Shared library: [libc.so]
(SONAME)  Library soname: [libentry.so]
```

### 6.2 产物核对（HAP 内）

| 条目 | 大小 | 含义 |
|---|---|---|
| `module.json` | 1,685 B | 含 `extensionAbilities[type=vpn]`、`requestPermissions[INTERNET]` |
| `libs/arm64-v8a/libentry.so` | 50,712 B | M2 NAPI 模块 |
| `libs/arm64-v8a/libprebuilt.so` | 4,120 B | M3 预编译库（strip 后） |
| `libs/arm64-v8a/libc++_shared.so` | 1,262,504 B | NDK 的 C++ 运行时（`OHOS_STL=c++_shared` 默认） |
| `ets/modules.abc` | 18,652 B | ArkTS 编译产物 |

> 说明：`libc++_shared.so` 占了 HAP 体积的 93%。若后续在意体积，可改 `OHOS_STL=c++_static`（需全应用统一，见 R2 §2.2）。

---

## 7. 下一步需要人工做什么（按顺序）

| # | 事项 | 谁做 | 为什么必须人工 |
|---|---|---|---|
| 1 | **启动模拟器或连接真机**，确认 `hdc list targets` 有设备 | 用户（人工） | 模拟器是 GUI（`<DevEco>\tools\emulator\Emulator.exe`）；真机需 USB 调试授权 |
| 2 | **配置调试签名**（DevEco 登录华为账号 → `Project Structure → Signing Configs → 自动签名`） | 用户（人工，**必须登录账号**） | 签名需要华为开发者账号；我不能代登录 |
| 3 | 装包并跑 M1 安装态：`hdc install -r entry-default-signed.hap` + `hdc shell aa start -a EntryAbility -b com.example.xraypoc` | 可由我执行（设备到位后） | 需 #1、#2 完成 |
| 4 | 跑 M2/M3：点两个按钮，看返回值与 `hilog`（tag `XVPN_POC`） | 可由我执行（设备到位后） | 需 #3 |
| 5 | 跑 M4 观察表：`startVpnExtensionAbility` 的返回码 / 是否弹授权框 / `onCreate` 是否进 / `ifconfig` 是否有 `vpn-tun` | 可由我执行（真机优先） | **模拟器结论不可外推**（PC4 §3） |
| 6 | 若目标是模拟器验证：加 `x86_64` ABI + 重编 `libprebuilt.so`（§6） | 可由我执行 | 需先确认模拟器 ABI（`deviceInfo.abiList`） |

**签名卡住的判定标准（给用户的明确信号）**：出现以下任一即说明"必须人工登录账号"，不要继续折腾：
- DevEco 提示需要登录 / `Signing Configs` 里无法自动生成证书；
- `hdc install` 报签名校验失败（`signature verification failed` 一类）。

---

## 8. 本次未做（明确边界，避免误读）

- ❌ 未安装到设备、未启动应用、未验证 M2/M3 运行期（无设备）
- ❌ 未配置签名（按指示跳过，产物是 `entry-default-unsigned.hap`）
- ❌ 未构建 `x86_64`
- ❌ 未写任何业务代码（无订阅、无分流、无内核、无 tun 调用）——`VpnExtAbility.ets` 只打了两行日志
- ❌ 未改 `doc/`、`_research_src/`、`.git/`、`README.md`；`.gitignore` **只追加**了构建产物规则（`build/`、`.hvigor/`、`oh_modules/`、`*.hap`、`entry/.cxx/`、`local.properties`、`.preview/`）

---

*本记录的所有命令与输出均来自本机实际执行（2026-10-18）。三处报错均可复现：删掉对应修正即可重现。*
