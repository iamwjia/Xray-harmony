# PC0 · 无真机可开工：DevEco + 模拟器最小工程骨架指南

> 归属：PC6（PC0 手册）· 作者：harmony-platform-analyst · 2026-10-18
> 适用前提：**只有 DevEco + 模拟器，没有真机**；目标是"半天内让工程跑起来"，**不是**产出 PoC 结论。
> 平台事实依据一律引 `research/harmony-platform-constraints.md`（下称 **R2**），本文只负责工程骨架与模拟器边界。
> 标注：**【待确认】**= 需在本机实测；**【待真机验证】**= 模拟器上无法定论，必须真机。

---

## 0. 先读这一页（半小时能拿到的确定性）

| 你在模拟器上能确定的 | 你不能确定的（哪怕全绿） |
|---|---|
| 工程结构对、编译链通、HAP 能装、应用能启动 | 真机 ABI 下 so 能否加载（模拟器多为 `x86_64`，真机 `arm64-v8a`，**ABI 不同即结论不可外推**） |
| NAPI 调用链通（ArkTS ↔ C） | tun 能不能建、数据面通不通（R2 §3.1.1） |
| `VpnExtensionAbility` 声明语法是否正确、能否被拉起 | VPN 授权弹窗、系统 VPN 服务行为、`protect()` 顺序错误的表现 |
| 日志链路（`hilog`）、安装/卸载/冷启动流程 | 后台存活、长时任务冻结策略、`BEARER_VPN` 承载态 |
| | 任何**性能/功耗/稳定性**数字 |

**本文的成功标准**：M1~M3 全绿 + M4 记录到"模拟器上到底发生了什么"。**M4 不做结论，只做记录。**

**时间预算（半天 ≈ 4~5h）**：M1 ≈ 1~1.5h；M2 ≈ 1~1.5h；M3 ≈ 0.5~1h；M4 ≈ 0.5~1h（旧 SDK 需处理 `type: "vpn"` 的 `modulecheck` 枚举；**SDK 26 实测无需任何 patch**，见 §1.1.1）。

---

## 1. 工程结构清单（只列存在目的，不贴完整代码）

```
MyXrayPoc/
├── AppScope/
│   ├── app.json5                      # 应用级：bundleName / versionCode / versionName / icon / label
│   └── resources/base/...              # 应用级图标与字符串
├── entry/                              # 主 HAP 模块（type: "entry"）
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/EntryAbility.ets        # 应用入口 Ability（UIAbility）
│   │   │   ├── pages/Index.ets                      # 首页：放 M2/M3/M4 的验证按钮
│   │   │   └── vpnability/VpnExtAbility.ets         # M4 才需要：VpnExtensionAbility 实现
│   │   ├── cpp/
│   │   │   ├── CMakeLists.txt                       # native 构建入口（见 §1.2）
│   │   │   ├── napi_init.cpp                        # M2 的最小 NAPI 模块（见 §1.3 要点）
│   │   │   ├── include/                             # 头文件目录（可空）
│   │   │   └── types/libentry/index.d.ts            # 可选：给 ArkTS 的类型提示
│   │   ├── libs/                                    # M3 用：预编译 so 按 ABI 分目录放这里
│   │   │   ├── arm64-v8a/libprebuilt.so
│   │   │   └── x86_64/libprebuilt.so
│   │   ├── module.json5                             # 模块级配置（见 §1.1，关键）
│   │   └── resources/                               # 模块级资源（字符串/图标/页面路由 profile）
│   ├── build-profile.json5                          # 模块级构建配置（见 §1.2 externalNativeOptions）
│   ├── hvigorfile.ts                                # 模块构建脚本（模板生成，勿手改逻辑）
│   └── oh-package.json5                             # 模块依赖声明（name/version/dependencies）
├── build-profile.json5                              # 工程级：签名 signingConfigs / products(SDK 版本) / modules
├── hvigorfile.ts                                    # 工程级构建脚本
├── oh-package.json5                                 # 工程级依赖（三方库在此声明）
└── local.properties                                 # 本机 SDK 路径等（DevEco 生成，勿入库）
```

### 1.1 `entry/src/main/module.json5` 关键字段逐项

| 字段 | 取值示例 | 为什么必须有 | 坑 |
|---|---|---|---|
| `module.name` | `"entry"` | 模块标识，与目录名一致 | 与 `oh-package.json5` 的 name 不一致会导致构建异常 |
| `module.type` | `"entry"` | 主模块类型 | 只能是 `entry` / `feature` / `har` / `shared` 等合法值 |
| `module.deviceTypes` | `["phone","tablet"]` | 声明可安装设备类型 | **漏写会导致模拟器上"设备不兼容"装不上** |
| `module.deliveryWithInstall` | `true` | 随应用安装 | 一般保持 true |
| `module.installationFree` | `false` | 是否免安装（元服务用） | 普通应用 false |
| `module.pages` | `"$profile:main_pages"` | 页面路由表 | 指向 `resources/base/profile/main_pages.json`，漏配则首页空白 |
| `module.abilities[]` | 见下 | 应用入口 | `srcEntry` 必须指向真实存在的 `.ets` |
| `module.abilities[].name` | `"EntryAbility"` | Ability 名（`aa start -a` 用它） | 与实际类名不一致 → `aa start` 报"ability 不存在" |
| `module.abilities[].srcEntry` | `"./ets/entryability/EntryAbility.ets"` | 入口文件路径 | **以 `src/main` 为根**的路径，写错即编译/运行失败 |
| `module.abilities[].exported` | `true` | 允许被外部拉起 | 调试期建议 true（`aa start` / `hdc` 拉起需要） |
| `module.abilities[].icon/label/startWindowIcon/startWindowBackground` | 必填项 | 启动窗口与桌面图标 | 缺 `startWindowIcon` 在部分 SDK 上直接编译报错 |
| `module.requestPermissions[]` | `{"name":"ohos.permission.INTERNET"}` | 联网（M2/M3/M4 都建议先加） | 权限级别 normal，声明即生效（R2 §3.2） |
| `module.extensionAbilities[]` | **M4 才加**，见 §1.1.1 | 承载 VPN 能力 | 见下方"坑" |

#### 1.1.1 `VpnExtensionAbility` 的声明（M4 专用，R2 §3.1 / evidence-quotes A1）

```json5
"extensionAbilities": [
  {
    "name": "MyVpnExtAbility",
    "srcEntry": "./ets/vpnability/VpnExtAbility.ets",
    "type": "vpn",
    "exported": false
  }
]
```

- 官方示例里这三项（`name` / `srcEntry` / `type`）即全部必需字段，**不需要** `metadata`、`permissions`、`requestPermissions`（R2 §3.1.1、`harmony-evidence-quotes.md` A1）。
- **旧说法（官方文档原文，保留以便追溯）**："如果 DevEco Studio 工具提示不能识别 `"type": "vpn"`，需要您手动在 SDK 的 `toolchains/modulecheck/module.json` 文件中，给 `extensionAbilities` 对应的 `type` 枚举添加 `"vpn"` 定义，并清除 build 缓存和重启 DevEco Studio 工具。"
- **已修正（实测回写 · 2026-10-18 · 依据 `PC6-skeleton-build-log.md`）**：在 **SDK 26.0.0.105 + hvigor 6.26.8** 上，`"type": "vpn"` **构建期直接通过，无需任何 patch**。`ProcessProfile` / `GeneratePkgModuleJson` / `PackingCheck` 全程无相关 WARN/ERROR；打包后 HAP 内 `module.json` 完整保留：
  ```json
  "extensionAbilities":[{"exported":false,"srcEntry":"./ets/vpnability/VpnExtAbility.ets",
    "name":"MyVpnExtAbility","type":"vpn"}]
  ```
  → 上面那条"必须 hand-patch `modulecheck`"是**旧 SDK 的已知做法**；SDK 26 上**不要**再去改 SDK 目录（改了反而污染安装）。
- **边界（必须一起读）**：**构建期通过 ≠ 运行期能力可用**。这只证明"声明合法、能打包"；`VpnExtensionAbility` 能否被拉起、能否建 tun、授权弹窗是否存在，**仍须真机验证**（见 §2 M4 观察表、§6）。
- 仍需保留的判定纪律：若构建期真报 `type` 非法，先按上面旧原文确认是否旧 SDK，再判"平台不支持"——避免把**构建配置问题**误判成**平台能力问题**（R2 §5「报错=版位不足 / 静默=语义不同」）。


### 1.2 `entry/build-profile.json5`（native 构建的实际开关）

```json5
{
  "apiType": "stageMode",
  "buildOption": {
    "externalNativeOptions": {
      "path": "./src/main/cpp/CMakeLists.txt",
      "arguments": "",
      "cppFlags": "",
      "abiFilters": ["arm64-v8a", "x86_64"]
    }
  },
  "targets": [
    { "name": "default" }
  ]
}
```

| 字段 | 为什么关键 |
|---|---|
| `externalNativeOptions.path` | 指向 `CMakeLists.txt`；不配 = 根本不编 native（表现为"import 'libentry.so' 失败"） |
| `abiFilters` | **决定出哪些 ABI**；模拟器多为 `x86_64`，真机 `arm64-v8a`（R2 §2.2）。两个都写 → 一个 HAP 同时带两个 ABI 目录，运行期按设备 ABI 选 |
| `apiType` | Stage 模型（VPN 相关 API 仅 Stage 可用，R2 §3.1.0） |

> 工程级 `build-profile.json5` 里另有 `products[].compileSdkVersion / compatibleSdkVersion / targetSdkVersion` 与 `signingConfigs`。建议：`compatibleSdkVersion` = 12（R2 §1.1 / §3.1.0）。

### 1.3 `CMakeLists.txt` 关键行（不是完整文件，但每一行都是坑位）

```cmake
cmake_minimum_required(VERSION 3.5.0)
project(xraypoc)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${NATIVERENDER_ROOT_PATH} ${NATIVERENDER_ROOT_PATH}/include)

# 产物名 = 库名：add_library(entry ...) => libentry.so => ArkTS 里 import ... from 'libentry.so'
add_library(entry SHARED napi_init.cpp)

# NAPI 必需：链接系统提供的 napi 实现
target_link_libraries(entry PUBLIC libace_napi.z.so)
```

| 要点 | 说明 |
|---|---|
| 库名 = 导入名 | `add_library(entry ...)` → `libentry.so` → ArkTS `import testNapi from 'libentry.so'`（**加 `lib` 前缀、去 `.so` 后缀的规则不要搞反**） |
| `libace_napi.z.so` | NAPI 的宿主实现，漏链会在加载时报未解析符号 |
| 交叉编译参数 | 由 `ohos.toolchain.cmake` 自动注入（`--target=<arch>-linux-ohos` / `--sysroot`），**不要手写**（R2 §2.2） |
| C++ 运行时 | 同应用内所有 native 库必须用同一种 STL 链接方式（`OHOS_STL=c++_shared` 默认），混用会在加载期崩（R2 §2.2） |

`napi_init.cpp` 的骨架要点（4 件事，不贴全码）：① `napi_property_descriptor` 声明方法 → ② `napi_define_properties` 挂到 `exports` → ③ 声明 `napi_module`（含模块名，**建议与库名一致**）→ ④ `__attribute__((constructor))` 里调 `napi_module_register`（R2 §2.1 的加载时序：import → ModuleManager → 模块注册）。

---

## 2. 四步可验证里程碑

### M1 空工程：能编译、能安装、能启动、不崩

**做什么**
1. DevEco 新建 `Empty Ability` 工程（Stage 模型、ArkTS）；
2. 确认 `module.json5` 有 `deviceTypes`，`pages` 指向的 `main_pages.json` 存在；
3. 启动模拟器（Device Manager → 启动一台 Phone 模拟器）→ 确认 `hdc list targets` 有设备；
4. 用 DevEco 的 **Run**（或下文命令）跑到模拟器。

```powershell
# 命令行方式（与 DevEco Run 等价的最小集）
hvigorw --no-daemon clean assembleHap
hdc list targets
hdc install -r .\entry\build\default\outputs\default\entry-default-signed.hap
hdc shell aa start -a EntryAbility -b <你的 bundleName>
hdc hilog
```

**看到什么算过**
- `hvigorw` 输出 `BUILD SUCCESSFUL`；
- `hdc install` 返回成功（无 `failed to install`）；
- 模拟器上应用前台可见，`hilog` 里能看到你的 `EntryAbility` 生命周期日志（`onCreate`/`onWindowStageCreate`）；
- `hdc shell "ps -ef | grep <bundle>"` 有进程。

**常见报错**

| 报错 | 原因 | 处置 |
|---|---|---|
| `hdc list targets` → `Empty` | 模拟器没起来 / hdc 与设备不匹配 | 先启动模拟器；`hdc kill` 后重试；核对 `hdc -v` 与 SDK 版本 |
| `ohpm install failed` / 依赖拉取失败 | 网络/代理 | DevEco 设置里配镜像或代理，重试 `hvigorw` |
| `failed to install ... signature` | 未签名 / 证书与 Profile 不匹配 | DevEco `File → Project Structure → Signing Configs → 自动签名`（见 §5） |
| `aa start` 报 ability 不存在 | `-a` 的名字与 `module.json5` 的 `abilities[].name` 不一致 | 用 `module.json5` 里的 `name` 原值，区分大小写 |
| 应用启动后白屏 | `pages` profile 缺失 / 首页路径错 | 检查 `resources/base/profile/main_pages.json` 与 `Index.ets` 路径 |
| 构建报 `module.json5` 校验失败 | 字段缺失或非法值 | 按 §1.1 / §1.1.1 逐字段核对；**`type:"vpn"` 在 SDK 26 上不会被拒**（§1.1.1 已修正） |
| `api version parameter is illegal! Expected format: <major>[.<minor>][.<patch>]` | `compatibleSdkVersion` 写了旧格式 `"26.0.0(26)"`；hvigor 6.26.8 只接受纯版本号 | 改成 `"26.0.0"`（详见 §2.5 坑 1） |
| `ninja: error: '.../entry/src/libs/<abi>/libprebuilt.so' ... missing` | CMake 里预编译库相对路径少一层 `main` | `../../libs` → `../libs`（详见 §2.5 坑 2） |
| `spawn java ENOENT`（打包阶段 `PackageHap`） | 本机 PATH 无 java | 设 `JAVA_HOME=<DevEco>\jbr` 并把 `%JAVA_HOME%\bin` 前置到 PATH（详见 §2.5 坑 3） |

### M2 ArkTS 调自写 C 函数（NAPI 全链路）

**做什么**
1. 建 `entry/src/main/cpp/napi_init.cpp`，导出一个返回字符串的方法（如 `hello()` → `"hello from native"`）；
2. 配 `CMakeLists.txt`（§1.3）与 `externalNativeOptions`（§1.2），`abiFilters` 先写 `["x86_64"]`（模拟器优先，省构建时间）；
3. `Index.ets` 里 `import testNapi from 'libentry.so'`，按钮点击后显示返回值 + `hilog` 打印。

**看到什么算过**
- 点击按钮显示 `hello from native`；
- `hilog` 有你的 tag 日志；
- `hdc shell` 进入应用沙箱目录能看到 `libs`（可选）。

**常见报错**

| 报错 | 原因 | 处置 |
|---|---|---|
| `Cannot find module 'libentry.so'` | 没配 `externalNativeOptions.path` / `abiFilters` 不含当前 ABI / 库名不一致 | 三处对齐：库名、`abiFilters`、import 名 |
| `Failed to load native module` / `dlopen` 失败 | 依赖库缺失、SONAME 缺失、STL 链接方式混用 | 用 `llvm-readelf -d libentry.so` 看 `DT_NEEDED`；确认只依赖系统库（R2 §2.2） |
| 链接错误 `undefined symbol: napi_*` | 漏 `target_link_libraries(... libace_napi.z.so)` | 补上 |
| 编译期找不到 `napi/native_api.h` | 未用 NDK 头文件路径 | 用 DevEco 模板生成的 CMake（它会带入 NDK 的 include） |
| 导入名与库名不一致的怪现象 | `add_library(xxx)` 决定 `libxxx.so` | 统一命名，不要靠猜 |

### M3 加载**预编译** .so（非 Go，先手写 C）→ 证明 dlopen 路径通

**做什么**
1. 用 NDK 单独编一个 `libprebuilt.so`（导出 `int prebuilt_add(int,int)`，**必须设置 SONAME**）；
2. 按 ABI 放到 `entry/src/main/libs/<abi>/libprebuilt.so`；
3. `CMakeLists.txt` 里用 `add_library(prebuilt SHARED IMPORTED)` + `IMPORTED_LOCATION .../libs/${OHOS_ARCH}/libprebuilt.so` + `target_link_libraries(entry PUBLIC prebuilt)`；
4. ArkTS 侧通过 `entry` 模块转发调用 `prebuilt_add`。

**看到什么算过**
- `prebuilt_add(1,2)` 返回 3；
- `llvm-readelf -d libprebuilt.so | grep SONAME` 有输出（**没 SONAME 会在真机/安装后加载失败**，这是 R2 §2.2 列的硬约束）。

**常见报错**

| 报错 | 原因 | 处置 |
|---|---|---|
| 链接期找不到 `-lprebuilt` | `IMPORTED_LOCATION` 的 `${OHOS_ARCH}` 与实际 ABI 目录名不一致 | 目录名必须是 `arm64-v8a` / `x86_64` |
| 运行期找不到依赖 so | 预构建库的依赖没一起导入 | 所有依赖库都要按 ABI 放齐（R2 §2.2） |
| 真机加载失败但模拟器正常 | **ABI 不同**（这正是本手册最想让你避开误判的地方） | 见 §4 |

> 为什么 M3 用"手写 C 的预编译 so"而不是 Go：本步只验 **dlopen 路径与打包规则**，与 Go 工具链无关；Go 产物接入是 PC2/PC3 的事，且其"无 `ohos` 目标"问题属独立风险（R2 §2.4）。

### M4 声明 `VpnExtensionAbility` 并尝试启动 → **记录模拟器上到底发生什么**

**做什么**
1. 新建 `ets/vpnability/VpnExtAbility.ets`（`export default class MyVpnExtAbility extends VpnExtensionAbility`，在 `onCreate` 里打一行 `hilog`）；
2. 按 §1.1.1 在 `module.json5` 加 `extensionAbilities`（`type: "vpn"`）；
3. 先构建。**SDK 26 上这一步会直接通过**（实测，见 §1.1.1）；**仅当**你用的是旧 SDK 且明确报 `type` 非法时，才按 §1.1.1 的旧原文处理（patch `modulecheck/module.json` + 清缓存 + 重启 DevEco），再构建；
4. 首页放一个按钮，调 `vpnExtension.startVpnExtensionAbility(want)`；
5. 采集日志：`hdc hilog | Select-String -Pattern "Vpn|vpn|XVPN"`。

> **实测回写 2026-10-18 —— M4 在模拟器上的根因已定，本节的"观察"已可收口为结论**：
> - **现象**：`startVpnExtensionAbility` 的 Promise **既不 resolve 也不 reject**（6s 探针仍 `pending-after-6s`），界面永远停在 `(M4 not run)`。
> - **根因**：系统请求已进入 `NetworkVpnManager`，随后去拉起**授权对话框应用** `com.huawei.hmos.vpndialog` 的 `VpnServiceExtAbility`，而该 bundle **在模拟器镜像中不存在**：
>   `ServiceExt: [AMC651]name:com.huawei.hmos.vpndialog VpnServiceExtAbility` → `BMSCommon: bundle not exist` → `AMS: failed: com.huawei.hmos.vpndialog` → `BMSQuery: ExplicitQueryAbility no match` → **我方 Promise 不回调**。
> - **定性**：**环境缺失（镜像缺系统组件），不是"平台不支持 `VpnExtensionAbility`"**；属「无法判定」，标【待真机验证】。
> - 依据：`PC6-skeleton-build-log.md` §11.4/§11.5（同一台模拟器上复现并采集的 `hdc install/aa start/hilog -x` 原文）。

> ⛔ **执行纪律（实测回写 2026-10-18）：模拟器上只跑 M1 / M2 / M3；M4 一律等真机。**
> 理由：模拟器镜像缺 `com.huawei.hmos.vpndialog`，M4 在模拟器上**必然**卡在"无回调"，重试与重装都不会变好；继续在模拟器上排查 M4 是**纯浪费**，且容易把"环境缺失"误写成"平台不支持"。

**看到什么算过（记录，不判定）**
逐项填写下表，**这张表就是 M4 的交付物**：

| 观察项 | 记录 |
|---|---|
| 构建期是否报 `type: "vpn"` 非法 | 是/否（是 → 记下 SDK 版本与报错原文） |
| `startVpnExtensionAbility` 的返回 | 成功 / `BusinessError.code` + `message` |
| 是否弹出"VPN 连接授权"系统弹窗 | 是/否（**模拟器上未必有**） |
| `MyVpnExtAbility.onCreate` 是否被调用 | 是/否（看 `hilog` 你那行 tag） |
| 状态栏是否出现 VPN 钥匙图标 | 是/否 |
| `hdc shell ifconfig` 是否出现 `vpn-tun` | 是/否 |
| 系统日志里是否有 VPN 服务相关错误 | 原文摘录 |

**常见报错与含义（先记录，不要下结论）**

| 现象 | 可能含义 | 注意 |
|---|---|---|
| 构建期 `module.json` 校验失败 | SDK 未收录 `vpn` 枚举（文档已预警） | 属**工程配置问题**，不是平台不支持 |
| `16000001 The specified ability does not exist` | `want` 里 `abilityName`/`bundleName` 与声明不一致 | 先排除配置错 |
| `16000002 Incorrect ability type` | 拉起的不是 `vpn` 类型的扩展 | 同上 |
| `16000061 Operation not supported` | 该能力在当前设备/形态上不支持 | **要在真机上复核**才能定性（模拟器形态可能不同） |
| `2203001` / `2203002` | 用户类型不允许 / VPN 已存在（R2 §3.2） | 说明已走到 `create()` 阶段，比上面几种进得更深 |
| 弹窗出现但 `onCreate` 没进 | 授权流程已启动但扩展未被拉起 | 记录后按 R2 §7 E 系列在真机复核 |

> **M4 的纪律**：模拟器上"没弹窗 / 报不支持 / 静默失败"**都不构成"平台不支持"的结论**。R2 §5 的口径：*能报错的是版位不足，不报错只静默不同的是语义不同*——而模拟器自身也可能缺服务，属第三种情况：**环境不足**。必须标【待真机验证】并给出复核方法（在真机上重跑同一张观察表）。

---

### 2.5 搭建环境必踩的三个坑（实测回写 · 2026-10-18 · 依据 `PC6-skeleton-build-log.md`）

> **重要前提：三条都不是平台缺陷。** 两条是工程配置、一条是环境变量。把它们当成"平台不支持"会让整条可行性判断跑偏。

| # | 现象（真实报错原文） | 真因（配置 / 平台） | 解法 |
|---|---|---|---|
| 1 | `api version parameter is illegal! Expected format: <major>[.<minor>][.<patch>], e.g., "17", "17.2", "17.2.3"` → `BUILD FAILED` | **工程配置**：`compatibleSdkVersion` 写了 DevEco 5 时代的 `"26.0.0(26)"`；**hvigor 6.26.8 只接受纯版本号** | 根 `build-profile.json5` 改为 `"compatibleSdkVersion": "26.0.0"`（`targetSdkVersion` / `compileSdkVersion` 同格式）。修完实测 `minAPIVersion`/`targetAPIVersion` = `260000026`，确认落在 API 26 |
| 2 | `ninja: error: 'D:/.../entry/src/libs/arm64-v8a/libprebuilt.so', needed by '.../obj/arm64-v8a/libentry.so', missing and no known rule to make it` → `00303300 Configuration Error` | **工程配置**：`CMAKE_CURRENT_SOURCE_DIR` 是 `entry/src/main/cpp`，写 `../../libs` 会解析成 `entry/src/libs`（少一层 `main`） | `CMakeLists.txt` 改用 `${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}`，并把 `libprebuilt.so` 放在 `entry/src/main/libs/<abi>/` |
| 3 | `Failed :entry:default@PackageHap` → `spawn java ENOENT`，`BUILD FAILED` | **环境变量**：`PackageHap` 依赖 `java`，本机 PATH 没有 | 设 `JAVA_HOME=<DevEco>\jbr`，并把 `%JAVA_HOME%\bin` 前置到 `PATH`（另需 `NODE_HOME=<DevEco>\tools\node`、`DEVECO_SDK_HOME=<DevEco>\sdk`） |

**可复制的最小环境准备（三条坑一次全避）**

```powershell
$dev = 'C:\Program Files\Huawei\DevEco Studio'
$env:NODE_HOME="$dev\tools\node"; $env:DEVECO_SDK_HOME="$dev\sdk"; $env:JAVA_HOME="$dev\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
Set-Location 'D:\projects\xray-harmony'
& "$dev\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default assembleHap --no-daemon
```

**两条判读提醒**
- PowerShell 里即使出现 `Exit Code: 1`，只要输出里有 `BUILD SUCCESSFUL` 就算成功——hvigor 把 WARN 写 stderr，PowerShell 会当成 `NativeCommandError`。
- 空 `signingConfigs` 只产生 `Will skip sign 'hos_hap'` 的 WARN，产出 `*-unsigned.hap`，属预期中间态（签名见 §5）。

**日志判读提醒（实测回写 2026-10-18）**
- `hdc hilog` 是**流式**的：它只输出**从此刻起**新产生的日志，**不打印历史缓冲**。
- 想看**已经发生**的事（如崩溃前、启动前那几行），用 **`hdc shell hilog -x`**（导出当前缓冲）。
- 典型误判：先跑操作、再开 `hdc hilog` → 看不到刚发生的关键行，误判为"没打日志/没执行"；正确做法是**先 `hilog -x` 取缓冲**，或**先开 `hdc hilog` 再操作**。

### 2.6 字段层级陷阱：**加错层级不会报错，只会静默失效**

来自 SDK 自带 schema（`<DevEco>\tools\hvigor\hvigor-ohos-plugin\res\schemas\`）的三条事实（实测回写 · 2026-10-18）：

1. `ohos-project-build-profile-schema.json`：`app.products.items.required = ["name", "compatibleSdkVersion"]`；
2. 同文件：`targetSdkVersion` 原文 **"It defaults to the same value as compileSdkVersion unless otherwise specified."**；`compileSdkVersion` 原文 **"For HarmonyOS, it defaults to the SDK version bundled with DevEco Studio unless otherwise specified"** ⇒ 不显式写，IDE 与 CLI 可能得出不同默认值；
3. `ohos-module-build-profile-schema.json` **完全不含 `targetSdkVersion`**（顶层只有 `targets`/`buildOption`/`buildOptionSet`/`apiType`/`entryModules`/`showInServiceCenter`/`buildModeBinder`）。

> ⇒ **把 `targetSdkVersion` 写进 `entry/build-profile.json5` 能通过 schema 校验，但永远不会生效——这是"假修"**。它和 R2 §5 的「静默 vs 报错」是同一个坑的另一种形态：**字段加错层级不会报错，只会静默失效**。
> 排查口诀：**版本三元组只在工程级 `app.products[]`；模块级只放 `targets`/`buildOption`。**

---

## 3. 模拟器能力边界（本手册最重要的一节）


### 3.1 ✅ 模拟器上可靠可用（结论可外推）

| 能力 | 依据 | 备注 |
|---|---|---|
| ArkTS / ArkUI 编译与运行 | R2 §1.1 | 与真机同一套 IDE/编译器 |
| HAP 构建链（hvigor/ohpm）、目录结构与 `module.json5` 校验规则 | R2 §1.2 | 校验规则与真机一致（`type: "vpn"` 在 SDK 26 上构建期直接通过，见 §1.1.1） |
| NAPI 调用链（ArkTS ↔ C/C++，含参数/返回值/线程回调） | R2 §2.1 | 只要 so 的 ABI 与模拟器一致即可 |
| `hilog`、安装/卸载/冷启动流程、`aa start` / `aa force-stop` | PC4 §2 | 命令与真机同一套 |
| 资源与页面路由、权限声明（normal 级） | R2 §3.2 | 权限校验逻辑一致 |

### 3.2 ⚠️ 模拟器上"能跑但结论不可外推"

| 项 | 为什么不能外推 | 正确用法 |
|---|---|---|
| **ABI**（模拟器常为 `x86_64`，真机 `arm64-v8a`） | 加载成功只证明"该 ABI 的 so 可用"，不代表真机能加载 | 模拟器上用 `x86_64` 版 so 验"流程通"；真机必须用 `arm64-v8a` 版重验（§4） |
| 预编译库依赖与 SONAME | 与 ABI 无关的规则（SONAME 缺失、依赖没带齐）在两边都会失败，但**报错文本可能不同** | 用 `llvm-readelf -d` 做静态检查（不依赖设备） |
| 内存/CPU/功耗/吞吐 | 模拟器是宿主机上跑的系统镜像 | **只记基线，不设判定线**（PoC 铁律） |
| 系统版本/API Level | 模拟器镜像版本可能与目标机型不同（新版镜像可能带新 API，**看起来"支持"其实是环境偏新**） | 记录模拟器 API Level（PC4 §7.1 的 `const.ohos.apiversion`），与目标机型对齐后再谈结论 |
| 长时任务与后台冻结 | 冻结/回收策略依赖真实调度与功耗模型 | 只能在真机验（R2 §4.1、PC4 §3 D4） |
| `BEARER_VPN` / `netCapabilitiesChange` 承载态 | 依赖真实网络栈与 VPN 服务状态 | 真机验（R2 §9.5.2） |

### 3.3 ❌ 模拟器上"基本不可用 / 高度不确定"（**必须用一个最小实验确认，不许直接断言**）

| 能力 | 为什么可疑 | **最小确认实验** | 若结果是"不可用"该怎么写 |
|---|---|---|---|
| 系统 VPN / tun（`VpnExtensionAbility` + `create()` + `vpn-tun`） | 模拟器可能未集成 VPN 服务，或未提供授权弹窗 | 就是 **M4**：声明 + 拉起 + 看 `onCreate`、弹窗、`ifconfig` 的 `vpn-tun`、`create()` 错误码 | 写"**模拟器上未观察到 VPN 能力（记录错误码 X）**，不代表真机不支持"，标【待真机验证】 |
| VPN 数据面（tun fd 读写、路由分流） | 依赖 `create()` 成功 | M4 通过后再加一个"读 tun fd 计数"的日志 | 同上；**不得据此判断"性能"或"拓扑"** |
| 应用分身 / 多用户 | 模拟器支持度不确定 | 设置里看是否有"应用分身"入口；有则按 R2 E22 步骤试 | 标【待确认】 |
| `protectProcessNet`(API 22+) / `onAuthorizationResult`(26.0.0) / `taskKeeping`(21+) | 依模拟器镜像 API Level | 先查 `const.ohos.apiversion`，再看方法是否存在（`typeof x === 'function'`） | 版本不足 → "版位不足"，不是"平台不支持" |
| 开机自启 | 平台本身对三方不可用（R2 §4.4） | 无需在模拟器验 | 直接按 R2 结论（这是**平台事实**，与模拟器无关） |

---

## 4. 构建产物与 ABI 对照表

### 4.1 怎么出、放在哪

| 目标 | 怎么出 | 产物位置 | 备注 |
|---|---|---|---|
| 模拟器（多为 x86_64） | `abiFilters: ["x86_64"]`（或两者都写） | `entry/build/default/intermediates/libs/x86_64/libentry.so` → 打进 HAP 的 `libs/x86_64/` | 构建更快，先跑通流程 |
| 真机（arm64-v8a） | `abiFilters: ["arm64-v8a"]` | 同上，`.../arm64-v8a/` → HAP 的 `libs/arm64-v8a/` | **真机结论只认可这一份** |
| 两者同包 | `abiFilters: ["arm64-v8a","x86_64"]` | HAP 内两个 ABI 目录并存，运行期按设备选 | 体积翻倍，但一份包通吃；PoC 期推荐 |

> 交叉编译参数由工具链注入：`--target={arch}-linux-ohos`、`--sysroot={ndk}/sysroot`（R2 §2.2）；`OHOS_ARCH ∈ {armeabi-v7a, arm64-v8a, x86_64}`。

### 4.2 怎么确认"加载的到底是哪个 ABI"（避免最常见的误判）

**方法 1（推荐，运行期自证）**：ArkTS 侧读运行设备 ABI 并打印

```ts
import deviceInfo from '@ohos.deviceInfo';
// 在按钮点击或 aboutToAppear 里
console.info(`XVPN_BOOT abiList=${JSON.stringify(deviceInfo.abiList)} api=${deviceInfo.sdkApiVersion}`);
```

**方法 2（静态核对 HAP 里有哪些 ABI）**：

```powershell
# HAP 就是 zip：列出 libs 下的 so
tar -tf .\entry\build\default\outputs\default\entry-default-signed.hap | Select-String "libs/"
```

**方法 3（设备侧 ABI 列表）**：`hdc shell param get const.product.cpu.abilist` 【待确认：参数名以设备为准】

**判定规则（照这个写结论就不会错）**

| 观察 | 正确结论 | 错误结论（禁止） |
|---|---|---|
| 模拟器 ABI = `x86_64`，只带了 `arm64-v8a` 的 so，加载失败 | "**包内缺对应 ABI**" | ❌"平台不支持加载 so" |
| HAP 内同时有 `arm64-v8a` 与 `x86_64`，模拟器加载成功 | "打包与加载链路通（x86_64 侧）" | ❌"真机也会成功" |
| 模拟器加载成功 → 换真机（`arm64-v8a`）加载失败 | "**arm64 侧未验证/有问题**" | ❌"模拟器的结论错了"（其实是结论越界） |

---

## 5. 签名与安装（模拟器）

> **实测回写 2026-10-18（本条修正本节的前提假设，原文保留）**：本文早前假定"未签名包 `hdc install` 必失败、必须先配签名"——**该假设在模拟器上不成立**：
> - 实测：在 `127.0.0.1:5555` 的**模拟器（开发者模式，API 26）**上，**未签名 HAP 可直接安装并启动**（`install bundle successfully`）；
> - 推测原因：该模拟器镜像**未强制签名校验**；
> - **真机是否同样宽松【待真机验证】**（真机通常强制签名）；
> - 因此：**签名是"真机/上架链路"的必需项，不是模拟器链路的前置项**。本节下方的手动签名步骤在真机上仍然必需，不要因为模拟器能装就跳过。
> - 依据：`PC6-skeleton-build-log.md` §11.1。

### 5.1 最短路径（推荐给"只想半天跑起来"的人）

1. DevEco 登录华为账号（**仅自动签名需要**）；
2. `File → Project Structure → Signing Configs` → 勾选 **Automatically generate signature**；
3. 直接 `Run`。
> 自动签名会生成调试证书 + 调试 Profile 并绑定当前设备。**换设备（含换模拟器镜像）后可能需要重新生成**。

### 5.2 手动签名（要理解原理时看）

| 物料 | 作用 | 注意 |
|---|---|---|
| 调试证书 `.cer` | 证明开发者身份 | 由 AGC 或 DevEco 生成 |
| 调试 Profile `.p7b` | 限定"哪些设备 / 哪些权限"可跑 | **含设备 UDID 列表**（真机需绑定；调试设备上限 100 台，**【待真机验证】** 具体口径） |
| 私钥 `.p12` | 签名用 | 与 `.cer` 成对 |

### 5.3 安装命令

```powershell
hdc install -r .\entry\build\default\outputs\default\entry-default-signed.hap
hdc uninstall <你的 bundleName>
hdc shell bm dump -n <你的 bundleName>     # 核对装上的版本
hdc shell aa force-stop <你的 bundleName>  # 冷启动前必做（PC4 §2.1）
```

### 5.4 最常见的三类签名/安装报错

| # | 现象（文本大意） | 原因 | 处置 |
|---|---|---|---|
| 1 | `failed to install ... signature verification failed` / 提示未签名 | 用的是未签名 HAP（`unsigned` 产物）或签名配置没生效 | 用 `*-signed.hap`；检查 Signing Configs 是否绑定到当前 product |
| 2 | `... profile ... device not in profile` / 设备不在 Profile 内 | 调试 Profile 未包含该设备 UDID（**真机换机必踩**） | AGC 重新生成 Profile 并重新签名；模拟器通常不受此限【待确认】 |
| 3 | `... certificate/profile mismatch` 或证书过期 | 证书与 Profile 不是同一套 / 证书过期 | 重新自动签名；确认 `bundleName` 与 AGC 上一致 |

> 具体错误码会随版本变化，**以实际报错文本为准**；处置顺序建议：①换 `-signed.hap` ②重新自动签名 ③核对 `bundleName` 与设备/UDID。

---

## 6. 明确"模拟器上不能得出的结论"清单

> 原则：**模拟器全绿 ≠ 实验通过**。以下实验项在模拟器上只能验"代码路径"，不能出结论。

| 实验项 | 它在问什么 | 为什么模拟器不行 | 必须真机的理由 |
|---|---|---|---|
| **`B-0` 对照基线**（同进程 `protect` 是否有效） | 若同进程 `protect` 也无效 ⇒ A1/A3 均不成立 ⇒ 平台级否决 | 依赖 `VpnConnection.create()` 成功 + 真实路由/策略路由 | 模拟器可能建不出 tun，"无效"会与"没建出来"混淆，直接导致**错杀整个产品路线** |
| **`P-01` 真 tun + stub 协议（L0→L5）** | tun fd 读写 + `protect` 顺序 + 数据面通 | ABI 差异 + 无真实网络栈/VPN 服务 | `protect` 顺序错的表现是"能连不能通"，模拟器无真实出站，测不出来（PC3 / R2 §2.4 P5） |
| **`P-20` tun2socks 链路** | 用户态转发正确性 | 依赖 tun 数据面 | 同 P-01 |
| **`P-27` 拓扑定路（对象/句柄可达）** | 放行自身/进程粒度是否成立 | 依赖真实进程模型与分应用名单生效 | PC1 的 gate-0a 结论必须真机 |
| **`J-01` 合流门禁** | 五段（加载/数据面/统计/v6/恢复）是否全通 | 含 D1 划掉、D2 `kill -9`、D5 崩溃三种死亡方式 | 死亡方式与系统回收策略强依赖真机（PC4 §3） |
| **`P-25` 孤儿隧道** | 进程死后是否留孤儿 | 同上 | 模拟器回收策略不同 |
| **`P-19` 状态感知时延** | `BEARER_VPN` / 承载变化 | 模拟器承载态可能不变 | 时延档位（≤5s）只能在真机取数 |
| **`P-23` IPv6 四条件** | v6 是否真纳入隧道 | 需可构造 v6 环境 | 模拟器网络多为宿主机 NAT，v6 行为不可信 |
| 任何**性能/功耗/内存**数字 | — | 宿主机上跑的系统镜像 | PoC 只记基线，不设判定线 |

**一句话纪律**：**模拟器只回答"我的代码/配置对不对"，不回答"平台行不行"。**

---

## 7. 附：本手册引用的平台事实索引

| 事实 | 出处 |
|---|---|
| `type: "vpn"` 声明写法 | R2 §3.1、§3.1.1；`research/harmony-evidence-quotes.md` A1 |
| `type: "vpn"` 在 **SDK 26 上无需 patch**（构建期实测通过） | 本文 §1.1.1、§9；原始记录 `doc/poc/PC6-skeleton-build-log.md` §5 |
| 系统只建网卡/下发路由，隧道与 fd 读写由应用实现 | R2 §3.1.1 |
| NAPI 加载时序（import → ModuleManager → 模块注册） | R2 §2.1 |
| ABI 集合、`--target=*-linux-ohos`、STL 一致性、SONAME 与预构建库约束 | R2 §2.2 |
| 权限 `INTERNET` 为 normal、声明即生效 | R2 §3.2 |
| VPN 能力下限 API 11 / 商用 12；`protectProcessNet` 22；`onAuthorizationResult` 26；`taskKeeping` 21 | R2 §3.1.0、§4.1 |
| 手机不可起 native 子进程、`AppServiceExtensionAbility` 仅 2in1 | R2 §4.3 |
| 三方不可开机自启 | R2 §4.4 |
| `BEARER_VPN` 语义（12+，仅表示承载） | R2 §9.5.2 |
| 四纪律（冷启动 / 判据 / 档位 / 重建）与 `hdc` 命令 | PC4 §0、§2 |

---

## 8. 【待确认】/【待真机验证】清单

| # | 待确认 | 怎么确认 |
|---|---|---|
| C1 | 你的模拟器实际 ABI | `deviceInfo.abiList`（§4.2 方法 1） |
| C2 | 模拟器镜像 API Level | `hdc shell param get const.ohos.apiversion` |
| C3 | ~~当前 SDK 是否已收录 `extensionAbilities.type = "vpn"`~~ → **已由实测关闭**：SDK 26.0.0.105 构建期直接通过（§1.1.1、§9） | — |
| C4 | 模拟器是否提供 VPN 授权弹窗与 `vpn-tun` | M4 观察表 |
| C5 | `hdc shell param get const.product.cpu.abilist` 参数名有效性 | 实跑，返回空则改用方法 1/2 |
| C6 | 模拟器安装是否要求 Profile 绑定设备 | 直接 `hdc install` 试；失败看报错文本 |
| **V1** | 真机 `arm64-v8a` 下 so 加载、tun 建立、数据面 | **必须真机**（PC4 §3、§5） |
| **V2** | 后台存活/长时任务/冻结策略 | **必须真机**（PC4 §3 D4） |
| **V3** | `B-0`/`P-01`/`P-20`/`P-27`/`J-01` 任何结论 | **必须真机**（§6） |

---

## 9. 实测固化信息（SDK 26 环境事实 · 2026-10-18）

> 来源：`doc/poc/PC6-skeleton-build-log.md`（原始记录，含真实命令与输出）。本节只做"可引用的固化结论"，便于后续任何人在同一环境上对齐判断。

### 9.1 环境版本（实测读到，非假设）

| 项 | 实测值 |
|---|---|
| DevEco build | `DS-261.23567.138.36.2600851` |
| SDK | `apiVersion 26` / `platformVersion 26.0.0` / `version 26.0.0.105` / `Release` |
| hvigor 引擎与插件 | `@ohos/hvigor 6.26.8`、`@ohos/hvigor-ohos-plugin 6.26.8` |
| hdc | **3.2.0f**（`<DevEco>\sdk\default\openharmony\toolchains\hdc.exe`，探测时无设备连接） |
| node / java | DevEco 内置 `tools\node`、`jbr`（须显式设 `NODE_HOME` / `JAVA_HOME`） |
| NDK clang | `<DevEco>\sdk\default\openharmony\native\llvm\bin\clang.exe`（`aarch64-unknown-linux-ohos-clang` 在该目录**无 `.exe`**，用 `clang.exe --target=...` 更稳） |

### 9.2 构建结果与产物

| 项 | 实测值 |
|---|---|
| 命令 | `hvigorw.bat --mode module -p product=default assembleHap --no-daemon` |
| 冷构建结果 | `BUILD SUCCESSFUL in 5 s 380 ms`，`34 tasks: 34 executed, 0 up-to-date` |
| 增量构建结果 | `BUILD SUCCESSFUL in 4 s 768 ms`，`33 tasks: 22 executed, 11 up-to-date` |
| 产物 | `entry\build\default\outputs\default\entry-default-unsigned.hap`，**1,346,634 B**（未签名，"另议"状态） |
| 产物内 API 字段 | `minAPIVersion=260000026`、`targetAPIVersion=260000026`、`compileSdkVersion=26.0.0.105` ⇒ **与设备 HarmonyOS 7 / API 26 对齐（环境对齐已确认）** |

### 9.3 HAP 内部结构（实测）

| 条目 | 大小 |
|---|---|
| `module.json` | 1,685 B（含 `extensionAbilities[].type="vpn"`、`requestPermissions[INTERNET]`） |
| `libs/arm64-v8a/libentry.so` | 50,712 B（M2 NAPI 模块） |
| `libs/arm64-v8a/libprebuilt.so` | 4,120 B（M3 预编译库，strip 后） |
| `libs/arm64-v8a/libc++_shared.so` | 1,262,504 B（`OHOS_STL=c++_shared` 默认；占包体 ~93%） |
| `ets/modules.abc` | 18,652 B |

### 9.4 `DT_NEEDED` 实测（证明 M3 真的链上，不是"配了没生效"）

```
libentry.so:
  (NEEDED)  libace_napi.z.so
  (NEEDED)  libprebuilt.so      ← M3 链接成立
  (NEEDED)  libc++_shared.so
  (NEEDED)  libc.so
  (SONAME)  libentry.so

libprebuilt.so:
  (NEEDED)  libc.so
  (SONAME)  libprebuilt.so      ← SONAME 必须存在，否则安装后加载失败
```

### 9.5 当前 ABI 边界（禁止外推）

- **当前只构建 `arm64-v8a`**（`entry/build-profile.json5` → `externalNativeOptions.abiFilters`）。
- **能得出**：`arm64-v8a` 的编译 / 链接 / 打包链路通。
- **不能得出**：① 运行期能否 `dlopen`（需设备）；② `x86_64`（模拟器）是否同样可行；③ 任何性能数据。
- 模拟器要用时：`abiFilters` 加 `"x86_64"` **并且**用 `--target=x86_64-linux-ohos` 重编一份 `libprebuilt.so` 放到 `entry/src/main/libs/x86_64/`（漏这步会因"该 ABI 无预编译库"失败）。

### 9.6 已由实测关闭的旧结论（保可追溯）

| 旧结论 | 状态 | 新结论 |
|---|---|---|
| `type:"vpn"` 必须手改 SDK `toolchains/modulecheck/module.json` | **已修正（仅适用旧 SDK）** | SDK 26.0.0.105 构建期直接通过，**不要改 SDK 目录** |
| `compatibleSdkVersion` 可写 `"5.0.0(12)"` 这类带 API 的格式 | **已修正** | hvigor 6.26.8 只接受纯版本号（`"26.0.0"`） |
| 未签名 HAP 一定装不上、签名是安装硬前置 | **已修正（模拟器范围内）** | 模拟器（开发者模式 / API 26）未签名 HAP **可装可启动**（`install bundle successfully`）；**真机仍通常需签名**，【待真机验证】。见 §5 开头注 |
| M4「点按钮没反应」需要继续排查 | **已定性（模拟器）** | 根因：镜像**缺 `com.huawei.hmos.vpndialog`**（系统日志 `bundle not exist` → `failed` → 我方 Promise 不回调）⇒ **环境缺失，非平台不支持**；模拟器上不再排查 M4，一律等真机。见 §2 M4 段 |

---

## 10. 修订记录

| 日期 | 改了什么 | 依据（实测） |
|---|---|---|
| 2026-10-18 | ① §2 M4 段：补**根因结论**（镜像缺 `com.huawei.hmos.vpndialog`）+ 系统日志链 + **「模拟器只跑 M1/M2/M3，M4 等真机」执行纪律**；② §2.5 判读提醒：补 **`hdc hilog` 是流式的、看历史缓冲用 `hdc shell hilog -x`**；③ §5 开头：未签名包可装（模拟器）——原「必先签名」假设标 `superseded`；④ §9.6 表格补三行「旧结论 → 新结论」 | `poc/PC6-skeleton-build-log.md` §11.1（安装成功）/§11.4（M4 现象）/§11.5（根因诊断与 `hilog -x` 采集） |

> 注：本文其余内容仍以 R2（`research/harmony-platform-constraints.md`）为准；本节只回写**模拟器实测**得到的事实，不改变任何平台能力结论。

---

## 10. 修订记录

| 日期 | 版本 | 修订内容 | 依据 |
|---|---|---|---|
| 2026-10-18 | v1.0 | 初版（模拟器骨架指南） | PC6 任务 |
| 2026-10-18 | v1.1 | **实测回写**：①§1.1.1 修正 `type:"vpn"` 需 patch 的过时结论（SDK 26 无需 patch，保留旧说法并标"已修正"）；②新增 §2.5 三条真实报错（api version / ninja 路径 / spawn java ENOENT）、§2.6 字段层级陷阱（加错层级静默失效）；③新增 §9 实测固化信息（版本/产物/HAP 内容/`DT_NEEDED`/ABI 边界）；④同步更新 §0 时间预算、§2 M1 与 M4 报错表、§3.1、§7 索引、§8 的 C3 项 | `doc/poc/PC6-skeleton-build-log.md`（E1 原始构建记录） |

---

*本手册与 PC4 同一口径：**命令可直接复制、结论必须标依据、不确定必须标出**。M1~M3 全绿说明"你会用这套工具链了"；M4 的观察表是**交给真机阶段的输入**，不是结论。*

