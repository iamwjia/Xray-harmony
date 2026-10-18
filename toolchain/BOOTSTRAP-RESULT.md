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

## M5��Go `.so` �� OHOS ������ʵ�⣨E7��

> Ŀ�꣺֤�� **Go runtime ���� OHOS Ӧ�ý����ڳ�ʼ����ִ�� cgo ����**��`P-03` ���ļ��裩���� x86_64 ģ�������ɣ����������
> ���ۣ�**✅\ ����**��`buildtag=openharmony` + `cside=cgoping-c-side-ok`������˳���ȳ���������������ߵ�Ӳ����

### 1. ������`toolchain/build-cgoping.ps1 -Arch x86_64`��

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

�ű������ã�`-Arch arm64|x86_64`��version-script��SONAME�����飨���ܹ�ѡ `R_AARCH64_TLSDESC` / `R_X86_64_TLSDESC`����

### 2. װ��Ӧ�ò���ʵ�����ģ���� `127.0.0.1:5555`��API 26��

HAP ��ȷ�ϣ�`libs/x86_64/libcgoping.so`��1,379,976 B��strip ��+ `libentry.so` �� `DT_NEEDED` Ϊ `libcgoping.so`��**���Ǿ���·��**����

`uitest dumpLayout` �� `M5: call Go CGoPing() :: [116,1159][1200,1299]` �� `uitest uiInput click 658 1229`��

```
10-18 12:54:18.371 20363 20363 I A00001/XVPN_POC: M5 clicked
10-18 12:54:18.371 20363 20363 I A00001/XVPN_POC: M5 result={"success":true,"data":{
  "marker":"pong","version":"cgoping/0.1 (e2-minimal)","goos":"linux","goarch":"amd64",
  "buildtag":"openharmony","cside":"cgoping-c-side-ok"}}
```

���̴�`ps` �� PID 20363����**�� SIGSEGV**��

### 3. �ж�

| ��� | ���� |
|---|---|
| `dlopen("libcgoping.so")` �ɹ� | ✅����־��\ dlopen ʧ�ܷ�֧�� |
| `dlsym("CGoPing")` / `dlsym("CGoFree")` | ✅�����óɹ�������ֵ��\ `CGoFree` �ͷź�����ȷ�� |
| Go runtime �� OHOS �����ڳ�ʼ�� | ✅���ܷ���\ `runtime.GOARCH=amd64` ������ʱ��Ϣ�� |
| ȷʵ�� OHOS fork ���� | ✅\ `buildtag=openharmony`��`//go:build openharmony` ̽�룩 |
| C��Go��C ˫������� | ✅\ `cside=cgoping-c-side-ok`��Go ����� C �� `c_side_marker()`�� |
| ���� | ❌\ �� |

⇒\ **`P-03` ǰ�루so ���� + Go runtime ��ʼ�� + cgo ���ã��� OHOS �ϳ�����**

---

## ⚠\️\ M5 �ȳ���������Ӳ���򣨱�"�ܱ�� so"�����׿��ˣ�

### ���� A��`runtime.GOOS` **����**�����ж��Ƿ����� OHOS fork
�� fork �� `openharmony` Ŀ��**�㶨�ϱ�** `GOOS == "linux"`��

```go
// src/internal/goos/gengoos.go
if target == "openharmony" {
    fmt.Fprintf(&buf, "const GOOS = `linux`\n\n")   // �� �������
}

// src/internal/goos/zgoos_openharmony.go
const GOOS = `linux`
const IsOpenharmony = 1
```

⇒\ ���� `goos=linux` **�������������ô�**��Ψһ�ɿ��о��� `//go:build openharmony` �����ǩ̽�루`toolchain/smoke/tag_openharmony.go` �� ����ֵ `buildtag` �ֶΣ���
**��������д�壬�����ȷ��������Ϊ����Ȼ������ȥ�������������ڡ�**

### ���� B��Ԥ���� `.so` ������ SONAME���ұ������ `libs/<abi>/`
ʵ������ʧ�ܣ���������ͬ��

1. **���� SONAME**����������**�����ھ���·��**д�� `libentry.so` �� `DT_NEEDED`����װ��������ʧ�ܣ�
   ```
   W MMG: key:default/entry First: failed Error loading shared library
   D:/projects/xray-harmony/entry/src/main/cpp/../libs/x86_64/libcgoping.so:
   (needed by /data/storage/el1/bundle/libs/x86_64/libentry.so)
   ```
   ⇒\ �� `CGO_LDFLAGS=... -Wl,-soname,libcgoping.so` ��������`DT_NEEDED` ��Ϊ `libcgoping.so`����
2. **��ͼ��Ӧ��˽��Ŀ¼ `dlopen` ����·��**���Ȱ� so �� rawfile ���ͷŵ� `files/native/`����
   ```
   M5 dlopen FAILED: [arg:/data/storage/el2/base/haps/entry/files/native/libcgoping.so]
   Error loading shared library ...: No error information
   ```
   ⇒\ **ɳ��/�������ƣ�Ӧ�� files Ŀ¼�µ� .so ���� dlopen**��`No error information` �ǵ��͵���ִ��Ȩ��/���ܱ��֣���
   ⇒\ Ψһ����λ��������ַ��� `libs/<abi>/`��`/data/storage/el1/bundle/libs/<abi>/`����

> �������ۣ�**hvigor ֻ������� CMake ����ͼ�� .so**��δ���ӵ�Ԥ�����⼴ʹ���� `libs/<abi>/` Ҳ����� HAP��ʵ�� HAP ��ֻ�� `libc++_shared.so`/`libentry.so`/`libprebuilt.so`����Ҫ�������������� `add_library(... SHARED IMPORTED)` + `target_link_libraries`������Ŀ�� `prebuilt` �� `cgoping` ����ˣ�������ʱ�Կ��� `dlopen`+`dlsym` ���ã�֤�����岻��Ӱ�졣

## M5 �����嵥

| �ļ� | ˵�� |
|---|---|
| `toolchain/build-cgoping.ps1` | һ������ + ���飨�� SONAME��version-script������ע�ͣ� |
| `toolchain/smoke/go.mod` / `tag_openharmony.go` / `tag_default.go` | fork �б�̽�루build tag�� |
| `entry/src/main/libs/x86_64/libcgoping.so` | x86_64 ���SONAME ���裩 |
| `entry/src/main/cpp/cgo_bridge.cpp` | NAPI �󶨣�dlopen + dlsym + ���� + `CGoFree` |
| `entry/src/main/cpp/napi_init.cpp` / `CMakeLists.txt` | ע�� `m5CGoPing`������ `cgoping` ������ |
| `entry/src/main/ets/pages/Index.ets` | �� 4 ����ť `M5: call Go CGoPing()` |

---

## ���۱߽磨�ض�����ֹ�ѽ���˵��ͷ��

- M5 ��֤������ **x86_64 ģ������API 26��**���ݴ˿�ȷ�ϣ�**Go runtime ���� OHOS Ӧ�ý����ڳ�ʼ������� cgo ����**���� C��Go��C ˫�򣩡�
- **arm64 �����δ��֤**��`P-03` ֻ��**�ֲ�֤ʵ**�����������ͬһ��·��arm64 `libcgoping.so` + ͬһ������������������ע fork �� TLSDESC/�źŴ�������ʵ ABI �µı��֡�
- ��˱�����**����**����Ϊ��Xray-core �� OHOS ������á���������Ҫ `P-02`���� libXray��+ ������ص��ò��ܶ��ۡ�

## �����������߲�ע������

1. **������ `runtime.GOOS` �ж��Ƿ����� OHOS fork**��fork �� openharmony Ŀ���Ϊ `linux`������ֻ���� `//go:build openharmony` �����ǩ̽�롣
2. **NDK �� `aarch64-unknown-linux-ohos-clang` / `x86_64-unknown-linux-ohos-clang` �� 171 �ֽڵ� `#!/bin/sh` �ű�**��Windows ����ִ�У�������� `clang.exe` + `-target <triple> --sysroot=<ndk>/sysroot -D__MUSL__`��
3. **`hdc hilog` ����ʽ��**����һֱ�����豸��־ˢ����Ҫ���Ѳ����Ļ����� `hdc shell hilog -x`������ `hilog -r` ����ٸ��֣���

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
