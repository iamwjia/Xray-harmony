# OHOS Go 工具链自举 + `cgoping.so` 编译验证结果

> 任务：E6｜执行者：solution-architect｜日期：2026-10-18
> 结论：**工具链自举成功，`cgoping.so` 编译成功，readelf 四验全部通过**（导出符号需加 version-script 才满足"只有 CGoPing/CGoFree"）。
> 产物目录：`_toolchain\bootstrap-tmp\`（bootstrap）、`_toolchain\ohos-go-v1.26.5-beta1\`（自建工具链）、`_toolchain\build\`（so 与 map）、`_toolchain\bootstrap-make.log`（构建日志）

---

## Step 1 — 解压 bootstrap ✅

```
PS> Expand-Archive -Path "D:\projects\xray-harmony\_toolchain\downloads\go1.25.14.windows-amd64.zip" -DestinationPath "D:\projects\xray-harmony\_toolchain\bootstrap-tmp" -Force
PS> & "D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go\bin\go.exe" version
go version go1.25.14 windows/amd64
```

输出与期望一致（`go1.25.14` ≥ fork 要求的 `minBootstrap=go1.24.6`）。

## Step 2 — 自举 OHOS 工具链 ✅（`make.bat` 直接可用，**不需要 Git Bash**）

```
PS> $env:GOROOT_BOOTSTRAP = "D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go"
PS> cd D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1\src
PS> .\make.bat *> D:\projects\xray-harmony\_toolchain\bootstrap-make.log
EXITCODE=0
```

日志尾段（真实输出）：

```
Building Go cmd/dist using D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go. (go1.25.14 windows/amd64)
Building Go toolchain1 using D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go.
Building Go bootstrap cmd/go (go_bootstrap) using Go toolchain1.
Building Go toolchain2 using go_bootstrap and Go toolchain1.
Building Go toolchain3 using go_bootstrap and Go toolchain2.
Building packages and commands for windows/amd64.
---
Installed Go for windows/amd64 in D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1
Installed commands in D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1\bin
*** You need to add D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1\bin to your PATH.
```

> **对既有假设的修正**：任务卡里预判"Windows 上 `make.bat` 可能需要 sh/gcc"，实测**不需要**——宿主侧只编 `windows/amd64` 的 Go 工具链，未触及 cgo 交叉编译器；Git Bash 路径**没有用到**。

## Step 3 — 三连验证 ✅

```
PS> & $go version
go version go1.26.5 windows/amd64

PS> & $go env GOOS GOARCH GOROOT
windows
amd64
D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1

PS> & $go tool dist list | Select-String openharmony

openharmony/amd64
openharmony/arm64
```

`openharmony/arm64` 出现在 `dist list` ⇒ fork 的目标端口已生效（这是"能交叉编译到鸿蒙"的前提）。

## Step 4 — 编译 `cgoping.so`（openharmony/arm64）✅

### 4.1 关键卡点：NDK 的 `aarch64-unknown-linux-ohos-clang` 是 **sh 脚本，不是 exe**

```
文件名存在但无 .exe：aarch64-unknown-linux-ohos-clang（171 字节）
内容：#!/bin/sh ... exec $SOURCE/clang -target aarch64-linux-ohos --sysroot=$SOURCE/../../sysroot -D__MUSL__ "$@"
```

Go 在 Windows 上无法直接执行该脚本 ⇒ **必须改用 `clang.exe` 并显式传等价参数**（内容照抄脚本里的四个参数）。

先用最小 C 文件验证 clang 直连可用：

```
& "$ndk\clang.exe" -target aarch64-linux-ohos "--sysroot=$sysroot" -D__MUSL__ -c t.c -o t.o
EXIT=0
llvm-readelf -h t.o → Class: ELF64 / Machine: AArch64
```

### 4.2 实际构建命令（一次成功，`EXIT=0`）

```powershell
$env:GOOS="openharmony"; $env:GOARCH="arm64"; $env:CGO_ENABLED="1"
$env:GOROOT="D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1"
$env:CC = '"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\llvm\bin\clang.exe" -target aarch64-linux-ohos "--sysroot=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\sysroot" -D__MUSL__'
$env:CGO_CFLAGS="-ftls-model=global-dynamic"
$env:CGO_LDFLAGS="-ftls-model=global-dynamic"
cd D:\projects\xray-harmony\toolchain\smoke
& $go build -buildmode=c-shared -o "D:\projects\xray-harmony\_toolchain\build\cgoping.so" cgoping.go
```

产物：`cgoping.so` **2,635,744 字节**、`cgoping.h` 2,397 字节。

## Step 5 — readelf 四验

### 5.1 默认构建（无 version-script）：**三通过、一不通过**

| 检查项 | 结果 | 实测 |
|---|---|---|
| ① `PT_TLS` 存在 | ✅ | `TLS 0x1203e0 ... R 0x8` |
| ② `R_AARCH64_TLSDESC` 重定位存在 | ✅ | `R_AARCH64_TLSDESC` 共 **1 条** |
| ③ 导出符号**只有** `CGoPing`/`CGoFree` | **❌** | `GLOBAL DEFAULT` 已定义函数 **48 个**，其中 **44 个是 cgo 运行时符号**（`_cgo_*`、`x_cgo_*`、`crosscall2` 等），`CGoPing`/`CGoFree` 只是其中两个 |
| ④ `DT_NEEDED` 仅系统库 | ✅ | 只有 `libc.so`（无 glibc、无 `libc++_shared`） |
| 附：ELF 头 | ✅ | `Type: DYN (Shared object file)` / `Machine: AArch64` |

### 5.2 加 version-script 后：**四验全通过** ✅

新增 `_toolchain\build\cgoping.map`：

```
{
  global:
    CGoPing;
    CGoFree;
  local:
    *;
};
```

重建：

```powershell
& $go build -buildmode=c-shared -ldflags "-extldflags=-Wl,--version-script=D:/projects/xray-harmony/_toolchain/build/cgoping.map" -o "...\cgoping-vs.so" cgoping.go
EXIT=0
```

复验结果：

```
=== 导出符号 ===
  47: 000000000011f014  80 FUNC GLOBAL DEFAULT 13 CGoPing
  48: 000000000011f064  88 FUNC GLOBAL DEFAULT 13 CGoFree
=== TLSDESC 条数 === 1
=== PT_TLS === TLS 0x11f8a0 ... R 0x8
=== NEEDED === Shared library: [libc.so]
```

⇒ 四项全过，**`cgoping-vs.so` 为本步的正式验收产物**。

---

## 结论与要点

1. **工具链可用**：`make.bat` 在 Windows 原生自举成功（18 分钟内），宿主 `go1.26.5 windows/amd64`，`dist list` 含 `openharmony/arm64`。
2. **交叉编译可用**：`GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1` + NDK `clang.exe`（显式 `-target`/`--sysroot`/`-D__MUSL__`）+ `-ftls-model=global-dynamic` 一次产出 `DYN`/`AArch64` 共享库。
3. **TLS 链路已验证**：`PT_TLS` 段 + `R_AARCH64_TLSDESC` 重定位同时存在，这正是绕过 musl IE-TLS 限制的关键证据。
4. **依赖干净**：`DT_NEEDED` 仅 `libc.so`，没有把宿主库或 glibc 带进产物。
5. **导出符号默认过宽（重要）**：不加约束时 44 个 cgo 运行时符号对外可见。**结论：正式产物必须加 version-script**（与 libXray 的 `global: CGoInvoke; CGoFree; local: *;` 做法一致），否则符号面过大、且可能与宿主符号冲突。

## 卡点与规避（写进后续脚本）

| 卡点 | 现象 | 规避 |
|---|---|---|
| **NDK wrapper 是 sh 脚本** | 直接把它当 `CC` 会在 Windows 上失败（无法执行 sh） | 用 `clang.exe` + 显式 `-target aarch64-linux-ohos --sysroot=<ndk>/sysroot -D__MUSL__`（四个参数照抄脚本） |
| **PowerShell 环境变量不跨调用保留** | 单独一次 `go build` 报 `go: no Go source files` | 环境变量与 `go build` **必须在同一次调用内**设置并执行（已写进建议脚本） |
| **默认导出 44 个 cgo 符号** | 四验第 3 项不通过 | 加 `-ldflags "-extldflags=-Wl,--version-script=<map>"` |

## 下一步

1. 把 Step 4/5 的命令固化进 `toolchain\build-cgoping.ps1`（含 version-script、环境变量一次性设置），避免重复手工操作。
2. 真机侧未做（本步不涉及）：`hdc file send cgoping-vs.so` + NAPI 加载 + 调 `CGoPing` 属后续 `P-03` 范围。
3. 下一步真正的构建目标是 **libXray（`v26.7.28`，禁止 main）**：本步已验证的 `CC`/`-ftls-model`/version-script 三件套可直接复用，但需额外处理（a）Xray JSON 配置解析依赖的包体积、（b）`readelf` 校验 `DT_NEEDED` 不得引入 `libc++_shared` 之外的非系统库。
4. 无【需人工】项：本步所有阻塞点均已自行解决。

## 产物清单

| 文件 | 说明 |
|---|---|
| `_toolchain\ohos-go-v1.26.5-beta1\bin\go.exe` | 自建 OHOS Go 工具链（go1.26.5） |
| `_toolchain\bootstrap-make.log` | 自举完整日志 |
| `_toolchain\build\cgoping.so` / `.h` | 默认构建产物（符号面过宽，作对照） |
| `_toolchain\build\cgoping-vs.so` | **加 version-script 的正式验收产物** |
| `_toolchain\build\cgoping.map` | 导出符号约束脚本 |

---

## M5：Go `.so` 在 OHOS 进程内实测（E7）

> 目标：证明 **Go runtime 能在 OHOS 应用进程内初始化并执行 cgo 调用**（`P-03` 核心假设），用 x86_64 模拟器即可，无需真机。
> 结论：**鉁匼 成立**（`buildtag=openharmony` + `cside=cgoping-c-side-ok`），并顺带踩出两条会坑死后来者的硬规则。

### 1. 构建（`toolchain/build-cgoping.ps1 -Arch x86_64`）

```
Arch   : x86_64  (GOARCH=amd64, ABI=x86_64, triple=x86_64-linux-ohos)
Validation (llvm-readelf):
  [PASS] ELF type / machine           Type=DYN (Shared object file) Machine=Advanced Micro Devices X86-64
  [PASS] PT_TLS present               TLS segment found
  [PASS] R_X86_64_TLSDESC count       1
  [PASS] exported == 2                CGoPing,CGoFree
  [PASS] NEEDED only libc.so          libc.so
SONAME: [libcgoping.so]
```

脚本已内置：`-Arch arm64|x86_64`、version-script、SONAME、四验（按架构选 `R_AARCH64_TLSDESC` / `R_X86_64_TLSDESC`）。

### 2. 装进应用并真实点击（模拟器 `127.0.0.1:5555`，API 26）

HAP 内确认：`libs/x86_64/libcgoping.so`（1,379,976 B，strip 后）+ `libentry.so` 的 `DT_NEEDED` 为 `libcgoping.so`（**不是绝对路径**）。

`uitest dumpLayout` → `M5: call Go CGoPing() :: [116,1159][1200,1299]` → `uitest uiInput click 658 1229`：

```
10-18 12:54:18.371 20363 20363 I A00001/XVPN_POC: M5 clicked
10-18 12:54:18.371 20363 20363 I A00001/XVPN_POC: M5 result={"success":true,"data":{
  "marker":"pong","version":"cgoping/0.1 (e2-minimal)","goos":"linux","goarch":"amd64",
  "buildtag":"openharmony","cside":"cgoping-c-side-ok"}}
```

进程存活（`ps` 有 PID 20363），**无 SIGSEGV**。

### 3. 判定

| 检查 | 结论 |
|---|---|
| `dlopen("libcgoping.so")` 成功 | 鉁叄ㄈ罩疚轡 dlopen 失败分支） |
| `dlsym("CGoPing")` / `dlsym("CGoFree")` | 鉁叄ǖ饔贸晒Α⒎祷刂当籠 `CGoFree` 释放后仍正确） |
| Go runtime �� OHOS �����ڳ�ʼ�� | ✅���ܷ���\ `runtime.GOARCH=amd64` ������ʱ��Ϣ�� |
| 确实用 OHOS fork 编译 | 鉁匼 `buildtag=openharmony`（`//go:build openharmony` 探针） |
| C→Go→C 双向调用链 | 鉁匼 `cside=cgoping-c-side-ok`（Go 侧调用 C 侧 `c_side_marker()`） |
| 崩溃 | 鉂孿 无 |

鈬抃 **`P-03` 前半（so 加载 + Go runtime 初始化 + cgo 调用）在 OHOS 上成立。**

---

## 鈿燶锔廫 M5 踩出来的两条硬规则（比"能编出 so"更容易坑人）

### 规则 A：`runtime.GOOS` **不能**用来判断是否用了 OHOS fork
该 fork 对 `openharmony` 目标**恒定上报** `GOOS == "linux"`：

```go
// src/internal/goos/gengoos.go
if target == "openharmony" {
    fmt.Fprintf(&buf, "const GOOS = `linux`\n\n")   // ← 刻意如此
}

// src/internal/goos/zgoos_openharmony.go
const GOOS = `linux`
const IsOpenharmony = 1
```

鈬抃 看到 `goos=linux` **不代表工具链用错**。唯一可靠判据是 `//go:build openharmony` 编译标签探针（`toolchain/smoke/tag_openharmony.go` → 返回值 `buildtag` 字段）。
**这条若不写清，会把正确构建误判为错误，然后让人去换工具链白折腾。**

### 规则 B：预构建 `.so` 必须设 SONAME，且必须放在 `libs/<abi>/`
实测两次失败，各自现象不同：

1. **不设 SONAME**：链接器把**构建期绝对路径**写进 `libentry.so` 的 `DT_NEEDED`，安装后启动即失败：
   ```
   W MMG: key:default/entry First: failed Error loading shared library
   D:/projects/xray-harmony/entry/src/main/cpp/../libs/x86_64/libcgoping.so:
   (needed by /data/storage/el1/bundle/libs/x86_64/libentry.so)
   ```
   鈬抃 加 `CGO_LDFLAGS=... -Wl,-soname,libcgoping.so` 后正常（`DT_NEEDED` 变为 `libcgoping.so`）。
2. **试图从应用私有目录 `dlopen` 绝对路径**（先把 so 放 rawfile 再释放到 `files/native/`）：
   ```
   M5 dlopen FAILED: [arg:/data/storage/el2/base/haps/entry/files/native/libcgoping.so]
   Error loading shared library ...: No error information
   ```
   鈬抃 **沙箱/挂载限制：应用 files 目录下的 .so 不可 dlopen**（`No error information` 是典型的无执行权限/被拒表现）。
   鈬抃 唯一可行位置是随包分发的 `libs/<abi>/`（`/data/storage/el1/bundle/libs/<abi>/`）。

> 附带结论：**hvigor 只打包参与 CMake 链接图的 .so**。未链接的预构建库即使放在 `libs/<abi>/` 也不会进 HAP（实测 HAP 内只有 `libc++_shared.so`/`libentry.so`/`libprebuilt.so`）。要让它进包，必须 `add_library(... SHARED IMPORTED)` + `target_link_libraries`（本项目的 `prebuilt` 与 `cgoping` 均如此）。运行时仍可用 `dlopen`+`dlsym` 调用，证据语义不受影响。

## M5 产出清单

| 文件 | 说明 |
|---|---|
| `toolchain/build-cgoping.ps1` | 一键构建 + 四验（含 SONAME、version-script、两坑注释） |
| `toolchain/smoke/go.mod` / `tag_openharmony.go` / `tag_default.go` | fork 判别探针（build tag） |
| `entry/src/main/libs/x86_64/libcgoping.so` | x86_64 产物（SONAME 已设） |
| `entry/src/main/cpp/cgo_bridge.cpp` | NAPI 绑定：dlopen + dlsym + 调用 + `CGoFree` |
| `entry/src/main/cpp/napi_init.cpp` / `CMakeLists.txt` | 注册 `m5CGoPing`、挂载 `cgoping` 参与打包 |
| `entry/src/main/ets/pages/Index.ets` | 第 4 个按钮 `M5: call Go CGoPing()` |

---

## 结论边界（必读，防止把结论说过头）

- M5 的证据来自 **x86_64 模拟器（API 26）**，据此可确认：**Go runtime 能在 OHOS 应用进程内初始化并完成 cgo 调用**（含 C→Go→C 双向）。
- **arm64 真机仍未验证**：`P-03` 只算**局部证实**。真机需重跑同一链路（arm64 `libcgoping.so` + 同一点击动作），并额外关注 fork 的 TLSDESC/信号处理在真实 ABI 下的表现。
- 因此本结论**不能**外推为「Xray-core 在 OHOS 真机可用」——那需要 `P-02`（编 libXray）+ 真机加载调用才能定论。

## 附：三条工具层注意事项

1. **不能用 `runtime.GOOS` 判断是否用了 OHOS fork**（fork 对 openharmony 目标恒为 `linux`）——只能用 `//go:build openharmony` 编译标签探针。
2. **NDK 的 `aarch64-unknown-linux-ohos-clang` / `x86_64-unknown-linux-ohos-clang` 是 171 字节的 `#!/bin/sh` 脚本**，Windows 不能执行；必须改用 `clang.exe` + `-target <triple> --sysroot=<ndk>/sysroot -D__MUSL__`。
3. **`hdc hilog` 是流式的**（会一直跟着设备日志刷），要看已产生的缓冲用 `hdc shell hilog -x`（或先 `hilog -r` 清空再复现）。

---

## P-02：libXray 在 OHOS 进程内加载与响应（E9）

> 目标：把已验证的「Go → OHOS `.so`」链路用在**真内核**上——编 `libXray v26.7.28`（含 xray-core `v1.260327.1`），amd64 在模拟器加载并验证 `CGoInvoke` 有响应。
> 结论：**✅ 成立**——`CGoInvoke` 返回合法 JSON（`{"success":false,"data":null,"error":"unknown method"}`），证明内核可被加载、Go runtime 完成初始化、xray-core 的调用分发器被执行。

### 1. 源码与钉版

```
repo   : https://github.com/XTLS/libXray.git
tag    : v26.7.28  (同时带 tag v1.260728.0)
commit : 80263da83e96b2972455b0a94b13ee1a10e51391
go.mod : go 1.26.3 ; require github.com/xtls/xray-core v1.260327.1-0.20260728075948-5ca6f4b7d4dc
本地路径: _toolchain/libXray-v26.7.28（不入库）
```

> **踩坑：默认 `GOPROXY=https://proxy.golang.org` 在本机不可达**，`go mod download` 报
> `dial tcp 142.250.73.81:443: connectex: A connection attempt failed ...`（连接超时）。
> 解决：`GOPROXY=https://goproxy.cn,direct` + `GOSUMDB=sum.golang.google.cn` + `GOFLAGS=-mod=mod`，之后 `go mod download` 退出码 0。

### 2. 编译（`-buildmode=c-shared`，带 version-script + SONAME）

```powershell
$env:GOOS="openharmony"; $env:GOARCH="amd64"; $env:CGO_ENABLED="1"
$env:CC='"...\clang.exe" -target x86_64-linux-ohos "--sysroot=...\sysroot" -D__MUSL__'
$env:CGO_CFLAGS ='-ftls-model=global-dynamic'
$env:CGO_LDFLAGS='-ftls-model=global-dynamic -Wl,-soname,libxray.so'
go build -trimpath -buildvcs=false -buildmode=c-shared `
  -ldflags "-extldflags=-Wl,--version-script=<...>/libxray.map" `
  -o ...\libxray.so ./cgo_bridge
```

`libxray.map`：`global: CGoInvoke; CGoFree; local: *;`

首次编译（`EXIT=0`）产物：`libxray.so` **71,317,112 B**（未 strip，含符号与 DWARF）。

### 3. 四验（`llvm-readelf`）

| 检查 | 结果 |
|---|---|
| ELF 头 | ✅ `Type: DYN (Shared object file)` / `Machine: Advanced Micro Devices X86-64` |
| `PT_TLS` | ✅ `TLS 0x1f506c0 ... R 0x8` |
| `R_X86_64_TLSDESC` | ✅ 1 条 |
| 导出符号 | ✅ **仅 `CGoInvoke` + `CGoFree`**（version-script 生效） |
| `DT_NEEDED` | ✅ 仅 `libc.so`；`SONAME: libxray.so` |

### 4. 接入应用

- `entry/src/main/libs/x86_64/libxray.so` ← 构建产物；
- `CMakeLists.txt`：`add_library(xraycore SHARED IMPORTED)` + `target_link_libraries(entry PUBLIC xraycore)`（同 M5 规则：**不参与链接图的 .so 不会进 HAP**）；
- `cgo_bridge.cpp` 新增 `M6CGoInvoke`：`dlopen("libxray.so")` → `dlsym("CGoInvoke")` → 用**故意非法**的信封调用（`{"apiVersion":1,"method":"__p02_probe__","payload":{}}`）→ `CGoFree` 释放；
- `Index.ets` 第 5 个按钮 **`M6: load libxray + CGoInvoke`**。

HAP 内确认：`libs/x86_64/libxray.so` **38,069,288 B**（strip 后）；HAP 总大小 **42,421,112 B**。

### 5. 实跑（模拟器 127.0.0.1:5555，API 26）

```
I A00001/XVPN_POC: M6 clicked
I A00001/XVPN_POC: M6 result=[elapsed_ms=0] {"success":false,"data":null,"error":"unknown method"}
```

进程存活（PID 26110），**无 SIGSEGV**。

判定：返回**合法 JSON**（`success:false` + 结构化 `error`）⇒ **Xray 内核在 OHOS 进程内可加载并响应调用**，`P-02` 核心证据成立。
**注意**：这不是「能代理上网」——无节点、无出站连接，只验证「加载 + 分发器执行」。

### 6. 采集到的数字（未采集项如实标注）

| 指标 | 值 | 说明 |
|---|---|---|
| `libxray.so`（构建产物，未 strip） | **71,317,112 B** | — |
| `libxray.so`（HAP 内，strip 后） | **38,069,288 B** | hvigor 自动 strip |
| HAP 总大小 | **42,421,112 B** | 含 libentry/libprebuilt/libcgoping/libc++_shared |
| 安装耗时（`hdc install -r`） | **2 s** | 模拟器，非真机 |
| 冷启动到 UI 可用（代理指标） | **≈1.28 s** | `aa start` → `uitest dumpLayout` 成功；含 dumpLayout 自身开销，**非严格首帧** |
| 进程内存（`VmRSS` / `VmHWM`） | **173,200 kB / 174,044 kB**（≈169/170 MB） | 整个应用进程，含 38 MB 映射的 `libxray.so` + Go runtime + ArkTS |
| `CGoInvoke` 单次调用耗时 | **< 1 ms**（`elapsed_ms=0`） | 见下方观察 1 |

### 7. 两条必须记录的观察

1. **本架构下没有独立的「dlopen 耗时」**：`.so` 必须参与链接图才能进 HAP，因此它同时是 `libentry.so` 的 `DT_NEEDED`，**在应用启动时即被加载**；运行期 `dlopen("libxray.so")` 只是取已加载句柄。⇒ **内核真实加载成本在冷启动，不在点击按钮时**；1.28 s 冷启动中该部分未拆分（【未采集】细分）。
2. **Native 侧 `OH_LOG_INFO` 未出现在 `hilog -x` 中**（只看到 ArkTS 的 `XVPN_POC` 行，M5 时亦然）。⇒ 阶段归因（dlopen/dlsym/call）**不能依赖 native 日志**；本次改为把 `elapsed_ms` 拼进返回值才拿到耗时。**后续 PoC 需阶段归因时，应把状态写进返回值或改用可达的日志通道。**

### 8. 结论边界

- 本次证据来自 **x86_64 模拟器**：证明「**Xray 内核可被 OHOS 应用加载并响应 `CGoInvoke`**」。
- **仍未验证**：arm64 真机加载、真实节点出站、tun 数据面（属 `J-01` 范围）。
- 故 `P-02` 记为**核心证据成立、真机部分待验**；**不能**据此宣布「可以代理上网」。

### 9. M7（补测）：调用真实方法，证明 xray-core 已初始化并可服务

M6 的 `unknown method` 只证明**分发层**被执行（且 `elapsed_ms=0` 说明未进入内核逻辑）。因此补测三个**真实存在**的方法：

请求：`{"apiVersion":1,"method":"xrayVersion"}` / `"getXrayState"` / `"getFreePorts","payload":{"count":1}`

实跑结果（hilog 原文）：

```
I A00001/XVPN_POC: M7 clicked
I A00001/XVPN_POC: M7 result=[version_ms=0][state_ms=0][ports_ms=1]
  version={"success":true,"data":{"version":"26.7.28"},"error":""}
  state={"success":true,"data":{"running":false},"error":""}
  ports={"success":true,"data":{"ports":[41861]},"error":""}
```

判定（按 Leader 给的判据表）：

| 结果 | 含义 | 本次 |
|---|---|---|
| `success:true` 且有真实数据 | **xray-core 真的被初始化并可服务** | ✅ **版本 `26.7.28` + 空闲端口 `41861`** |
| `getFreePorts` 返回端口 | 内核侧**实际执行了 socket 绑定**（不是常量返回） | ✅ 耗时 1 ms |
| `getXrayState` | `running:false` = 尚未启动实例（预期，本步不启动内核） | ✅ |

**⇒ P-02 完整成立**：`.so` 加载 → Go runtime 初始化 → libXray 逻辑执行 → xray-core 被调用并返回真实数据。

**关于 `version_ms=0` / `state_ms=0` 的说明（不是计时错误）**：这三个方法里前两个是**常量/标志位读取**（`XrayVersion()` 返回编译期版本号、`GetXrayState()` 读一个 bool），耗时低于 1 ms 计时精度；只有 `getFreePorts` 做真实 socket 绑定，测到 **1 ms**。真正的「内核实例化」发生在 `runXray` / `runXrayFromJson`，本步**刻意不调用**（无节点、无配置，属 `J-01` 范围）。

### 10. 体积事实（产品化门槛，非优化项）

| 项 | 值 |
|---|---|
| `libxray.so`（未 strip） | **71,317,112 B**（≈68 MiB） |
| `libxray.so`（HAP 内，hvigor strip 后） | **38,069,288 B**（≈36.3 MiB） |
| HAP 总大小 | **42,421,112 B**（≈40.5 MiB） |

- 单是内核就占了 HAP 的 **~90%**；对移动应用是硬门槛。
- 可能的裁剪方向（**尚未验证，不写结论**）：①只 import 需要的协议/传输（不用 `main/distro/all` 的全量注册）；②`-ldflags="-s -w"` 进一步去符号/调试信息；③裁掉未使用的 DNS/geodata 相关包。**任何裁剪都必须重跑本节的验证，否则产物不再代表 Xray 的真实能力。**

### 11. 由「链接图才能进包」推导出的版本策略后果（Leader 裁决）

实测链条：
1. hvigor **只打包参与 CMake 链接图的 `.so`**（未链接时即使放在 `libs/<abi>/` 也不进 HAP）；
2. 一旦进链接图，它就成为 `libentry.so` 的 `DT_NEEDED` ⇒ **启动时即被加载**，无法懒加载；
3. 应用私有目录的 `.so` 不可 `dlopen`（见 M5 规则 B-2）。

⇒ **「包内 A/B 双内核版本」方案不成立**：两个版本都进链接图 = 两份都随启动加载（38 MB × 2 常驻映射），用确定的内存开销换很小的回滚灵活性，不划算。
**结论（Leader 2026-10-18 裁决）：改为「单一内核版本 + 应用商店版本回滚」**，`D-18` 的 A/B 双版本作废；内核安全更新时效 = 商店发版时效。

---

## 体积与 ABI 策略（E10）

> 目标：把「模拟器包」与「真机包」分开，别让真机包背 x86_64 专用的 38 MB 内核。
> 结论：**仅 arm64 的发布包 = 38,656,796 B（≈36.9 MiB），双 ABI 包 = 79,485,000 B（≈75.8 MiB），分包省下 40,828,204 B（51.4%）**。

### 1. arm64 版 `libxray.so`（新增，六项验证全绿）

```
Arch   : arm64  (GOARCH=arm64, ABI=arm64-v8a, triple=aarch64-linux-ohos)
Validation (llvm-readelf):
  [PASS] ELF type / machine         Type=DYN (Shared object file) Machine=AArch64
  [PASS] PT_TLS present             TLS segment found
  [PASS] R_AARCH64_TLSDESC count    1
  [PASS] exported == 2              CGoInvoke,CGoFree
  [PASS] NEEDED only libc.so        libc.so
  [PASS] SONAME                     libxray.so
OK  arm64 -> entry\src\main\libs\arm64-v8a\libxray.so  (69,068,464 bytes)
```

编译耗时 19 s（依赖已在 module cache）。新增 `toolchain/build-libxray.ps1 -Arch arm64|x86_64`，一条命令完成「编译 + version-script + SONAME + 六项验证」。

顺带补齐 **arm64 版 `libcgoping.so`**（2,633,368 B），让真机包功能与模拟器包一致。

### 2. ABI 分包（默认真机，按需模拟器）

- `entry/build-profile.json5` 的 `abiFilters` **默认只有 `arm64-v8a`**（真机/发布）；
- 新增 `scripts/build-hap.ps1 -Abi arm64|x86_64|both`：构建前改写 `abiFilters`，构建后**无论成败都恢复 arm64 默认值**，避免"忘了改回来"把 38 MB 带进发布包；
- 脚本在构建前会 **touch `CMakeLists.txt`** 强制重新 configure —— 见 §4 的坑。

### 3. 真实体积对照表（解包 `libs/` 统计，非估算）

| 配置 | HAP 总大小 | arm64 `libxray.so` | x86_64 `libxray.so` | `libs/` 合计 |
|---|---|---|---|---|
| **双 ABI**（arm64 + x86_64） | **79,485,000 B**（≈75.8 MiB） | 35,740,808 B | 38,069,288 B | 79,221,944 B |
| **仅 arm64（发布用）** | **38,656,796 B**（≈36.9 MiB） | 35,740,808 B | — | 38,394,368 B |

其余 so（arm64 单 ABI 包内）：`libc++_shared.so` 1,262,504 / `libcgoping.so` 1,309,832 / `libentry.so` 77,104 / `libprebuilt.so` 4,120。

- **省下 40,828,204 B（51.4%）**；x86_64 内核（38.07 MB）对真机完全没有价值。
- 值得注意：**arm64 版的 `libxray.so` 比 x86_64 版小 2.33 MB**（35.74 vs 38.07 MB），ARM64 指令编码更紧凑。
- **发版用哪个**：`hap-arm64-only.hap`（`-Abi arm64`，默认配置）。双 ABI 包只用于模拟器调试。

### 4. 一个必须记录的坑：CMake 的 `EXISTS()` 在 configure 期求值

首次做「both」构建时，HAP 里 **arm64 目录没有 `libxray.so`**（只有 x86_64 有），`libentry.so` 的 `DT_NEEDED` 也没有 `libxray.so` —— 因为该 ABI 的 CMake configure 发生在「arm64 内核还没编出来」之前，`if(EXISTS ...)` 结果被缓存了。
⇒ **新增某个 ABI 的预构建 so 后，必须强制重新 configure**（touch `CMakeLists.txt` 或清理 `entry/build`）；`build-hap.ps1` 已自动 touch，避免复发。

### 5. 验收细节（按任务要求）

- **把仅 arm64 的包装到 x86_64 模拟器 → 失败，且是预期**（不是缺陷）：
  ```
  error: failed to install bundle. code:9568347
  error: install parse native so failed. In the module named entry,
  the Abi type supported by the device does not match the Abi type configured in the C++ project.
  ```
- **双 ABI 包回归通过**（装回模拟器后 M7 仍成功）：
  ```
  M7 result=[version_ms=0][state_ms=0][ports_ms=2]
    version={"success":true,"data":{"version":"26.7.28"},"error":""}
    state={"success":true,"data":{"running":false},"error":""}
    ports={"success":true,"data":{"ports":[34373]},"error":""}
  ```
- M2/M3/M5/M6/M7 按钮与逻辑均未改动。

### 6. 关于「体积能不能更小」的准确判断（防止误读）

**ABI 分包解决的是「翻倍」问题，不是「38 MB」本身。**
- arm64 真机同样必须携带 `libxray.so`（35.74 MB strip 后），这是 Xray 全量内核的**固有体重**（同类客户端 `libv2ray.so` 同量级），不是我们写胖了；
- 想再小只能裁协议/传输，那要改 `xray-core` 的 import 列表 ⇒ **MPL-2.0 §3.1 公开被改文件 + 永久分叉维护 + 牺牲节点兼容性**，代价远大于收益，**本次不做**；
- 「36.9 MiB 是否可接受」取决于应用市场的包体上限，属产品决策，不是技术问题。

---

## P-01 前置：真实出站验证（E11，节点缺失下的「转发链路」验证）

> 目标：从「内核能初始化」推进到「内核能转发流量」。
> 结论：**转发链路成立**（SOCKS 握手成功、经内核取到 HTTP 200），**但「出网经节点」这一层无法验证——仓库内无可用节点，已标 `【需要人工：提供一个可用节点】`**。

### 1. 测试设计（这一层不需要节点）

- 入站：`socks` 监听 `127.0.0.1:18080`（noauth）
- 出站：`freedom`（**故意不用节点**：先把「内核转发链路」与「节点出口」两层拆开）
- 驱动：`runXrayFromJson` 起实例 → `getXrayState` 确认 → **native 侧手写 SOCKS5**（`0x05` 握手 → CONNECT 域名 → `GET /`）→ 与直连同址对照 → `stopXray`

新增两个 native 能力（避免每测一个方法就改一次 native）：
- `m8Invoke(method, payloadJSON)`：通用 `CGoInvoke` 桥；
- `m9ProxyProbe()`：一键完成「起实例 + SOCKS 探针 + 直连对照 + 停实例」。

### 2. 实跑结果（hilog 原文）

```
M8 clicked
M8 result=[verdict=SAME_IP(forwarding-only)]
  run={"success":true,"data":{},"error":""}
  state={"success":true,"data":{"running":true},"error":""}
  via_proxy_status=HTTP/1.1 200  via_proxy_ip=113.246.178.167
  socks_err=-
  direct_status=HTTP/1.1 200   direct_ip=113.246.178.167
  stop={"success":true,"data":{},"error":""}
```

### 3. 三层判据（分开写，不合并）

| 层 | 问题 | 本次结论 |
|---|---|---|
| ① 内核运行 | `getXrayState.running` 是否为 true | ✅ **true**（`runXrayFromJson` 返回 `success:true`） |
| ② 转发链路 | SOCKS 握手 + CONNECT 是否成功、经内核能否取到 HTTP 响应 | ✅ **成功**：`socks_err=-`、经代理拿到 `HTTP/1.1 200` 与正文 |
| ③ 出网经节点 | 经代理出口 IP 是否 ≠ 直连 IP | ❌ **未验证**（本步用 `freedom`，两者同为 `113.246.178.167`，**预期相同**） |

**⇒ 可以说的**：`Xray 内核在 OHOS 进程内可启动、可监听 SOCKS、可按配置转发并返回真实响应`。
**⇒ 不能说的**：`流量经节点出网` / `具备隐私保护效果`——那需要 ③，本步未做。

### 4. 待补：`【需要人工：提供一个可用节点】`

仓库与环境里没有任何节点凭据（`_toolchain/`、环境变量、配置文件中均无 `vless/vmess/trojan/ss` 链接）。接上节点只需**把 outbound 从 `freedom` 换成节点配置，代码一行不改**。

提供方可按此格式给测试节点（机房/地域即可，无需生产节点）：
`协议 + 地址:端口 + 凭据（UUID/密码）+ 传输与安全层（ws+tls / reality 等）+ 是否需要 SNI/flow`

到位后复跑本探针，判定表：
- 经代理 IP ≠ 直连 IP，且为机房 ISP ⇒ **才可写「内核可代理出网」**；
- 连不上但 `running:true` 且内核日志有出站握手 ⇒ 内核在跑，问题在节点/网络；
- `runXrayFromJson` 返回错误 ⇒ 记原文，区分「配置非法」与「运行失败」。

### 5. 顺带记录：HAP 压缩（`compressNativeLibs`）后的体积口径

本期 `module.json5` 由平台侧开启 `compressNativeLibs`，实测（x86_64 单 ABI 包）：

| 指标 | 值 |
|---|---|
| `libs/` 未压缩合计 | 40,850,184 B（≈39.0 MiB） |
| **HAP（下载体积）** | **15,799,538 B（≈15.1 MiB）** |

**注意口径**：压缩只减小**下载体积**；安装时仍会解压（`extractNativeLibs` 缺省 true）⇒ **安装占用仍约 39 MiB**。**不能写成「体积减半」**，应写「下载 15.1 MiB / 安装约 39 MiB」。

### 6. 收尾说明与一条观测规则

**收尾状态**：E11 标记完成，范围 =「转发链路验证」。**「出网经节点」那半依赖人工提供节点，另行开任务复跑**，不在本任务挂起。

**规则（本次诊断弯路提炼，与「`/proc` 路由表不能判断 VPN 接管」同类）**：
> **出口 IP 探针必须同时记录 HTTP 状态行**，否则「空正文」会被误读成「网络不通」，从而把一次**选错测试站点**误判成**平台网络限制**。
> 一般化表述：**不要用一个测不出目标量的观测手段去证明/证伪它**——`ping` 通只说明 ICMP 可达，不能说明 TCP/HTTP 可用；`curl 成功` 也不能说明流量走了代理。
