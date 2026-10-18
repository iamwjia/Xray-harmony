# PC2 内核构建链实验包（P-02 → P-03 → P-04 可执行版）

> 任务：PC2 ｜ 作者：xray-core-analyst ｜ 编写日期：2026-10-18
> 定位：把 `risks-and-roadmap.md` 的 P-02/P-03/P-04 三张卡片升级为**可照着敲**的实验包。执行者不需要再查资料，只需按 §1→§8 顺序做，并按 §8 留痕。
> 证据等级沿用 R1：**【源码】**=源码 `文件:行号@commit`；**【官方文档】**；**【实践】**=可复现的第三方工程记录；**【待真机验证】**=未取得一手证据。
> 上游依据：R1 `research/xray-core-baseline.md`；参考实现 `_research_src/Hey`（`docs/building-native-cores.md`、`docs/harmonyos-go-tls-wall.md`）；`_research_src/libXray`。

---

## 0. 开工前必读（三个会让实验白做的坑）

### 0.1 ⚠️ `libXray` 的 main 分支已经编不了了，必须钉 tag `v26.7.28`

| 引用点 | `go.mod` 的 go 指令 | 能否用 go1.26.5 fork 编 |
|---|---|---|
| `libXray` **main**（本次核对 commit `4e1f784`，2026-10-13） | **`go 1.27.1`** | ❌ **不能** |
| `libXray` **tag `v26.7.28`** | **`go 1.26.3`** | ✅ 能 |

依据：【源码】`_research_src/libXray/go.mod:3@4e1f784` vs `git show v26.7.28:go.mod:3`。
**行动**：实验一律 `git checkout v26.7.28`（或 `LIBXRAY_PIN=v26.7.28`）。若脚本取 main 会直接报 `module requires go >= 1.27.1`。

### 0.2 ⚠️「锚 GA」的准确含义：锚的是「go 1.26 兼容的核心」，不是 tag 本身

`libXray v26.7.28` 钉的 xray-core 是伪版本 **`v1.260327.1-0.20260728075948-5ca6f4b7d4dc`**（【源码】`git show v26.7.28:go.mod:6`）。

Go 的伪版本规则：`v1.260327.1-0.<时间>-<hash>` = **tag `v1.260327.0` 之后**的某个 commit。而 `v1.260327.0` 正是 `v26.3.27` 的 SemVer 镜像（【官方文档】libXray README "Versioning"；【源码】`git ls-remote --tags` 观察 `v1.260327.0` 与 `v26.3.27` 指向同一 commit `d2758a0`）。

**所以：实际被验证可用的核心 = `5ca6f4b7`（2026-07-28，GA 之后约 4 个月的主线 commit），不是 GA tag 本身。**
- 该 commit 必然要求 `go ≤ 1.26.3`（否则 libXray `go 1.26.3` 的依赖链会被 Go 拒绝构建）——**这是推断，标【待验证】**，验证方式：`git show 5ca6f4b7:go.mod | head -3`。
- 推论（重要）：**核心从 2026-07-28 之后的某一点起把 `go` 指令抬到了 1.27**，此后所有 commit 都编不了。**上游 main 已漂移**：R1 写作时 `HEAD=95461cc`，本次核对 `origin/main=92ccc93`（`git fetch` 显示 forced update）。**任何"用 main 试一下"的想法都会引入不可控变量，禁止。**

### 0.3 ⚠️ 参考实现违反了「一进程一个 Go runtime」，我们不要照抄

`libXray` README 明确警告：**一个进程只能加载一个 Go runtime**（引 Go #18976 / #15956）。
但 `Hey` 在同一进程里加载了 **3 个 Go `.so`**（`libxray` / `libsingbox` / `libheytun2socks`），并在 `docs/building-native-cores.md:198` 自己承认：
> "如果同一进程里先加载过 libsingbox / libheytun2socks …它仍会 `setenv` 一次…**严格说不满足上面的规则**"。

**结论**：参考实现证明"能跑"，但这属于**已知违规下的侥幸**，不是可依赖的设计。
→ **PC2 必须同时验证两条路线并按 §7 决策**：
- 路线 A（推荐）：**把 Xray 内核 + tun2socks 合并进同一次 `c-shared` 构建，产出单一 `.so`**，天然满足"一个 runtime"。
- 路线 B（照抄 Hey）：多个 `.so` 各自编，靠"加载顺序 + 首次 dlopen 前 setenv"规避。**风险：任一新加载的 Go 库在初始化期都可能与 `environ` 争用。**

---

## 1. 工具链自举（一次性，约 8–15 分钟）

### 1.1 前置检查

| 项 | 要求 | 检查命令 | 期望输出 |
|---|---|---|---|
| 构建机 OS | **Linux x86_64**（WSL2 / 容器 / 构建机）。**不要用 Windows 原生**——`make.bash` 是 bash 脚本，且 cgo 交叉链接链路在 Windows 上未验证 | `uname -sm` | `Linux x86_64` |
| 引导 Go（bootstrap） | **go1.24.6+**（fork 的 `src/cmd/dist/buildtool.go` 里 `minBootstrap` 决定） | `$GOROOT_BOOTSTRAP/bin/go version` | `go version go1.24.x` 或更高 |
| DevEco Studio / HarmonyOS SDK | 需要其 `native/llvm/bin/aarch64-unknown-linux-ohos-clang` | `ls $DEVECO_SDK_HOME/default/openharmony/native/llvm/bin/ \| grep ohos-clang` | 看到 `aarch64-unknown-linux-ohos-clang` |
| 磁盘 | ≥ 3 GB（fork 源码 + 工具链 + 模块缓存） | `df -h ~` | 可用 > 3G |
| 网络 | 能访问 github.com 与 Go module proxy | `git ls-remote https://github.com/star4277/ohos-go.git \| head -1` | 有输出 |

依据：bootstrap 版本要求见【实践】`building-native-cores.md:51`；CC 路径见【实践】`building-native-cores.md:63-67`。

### 1.2 步骤序列（可直接复制）

**S1 取 fork 源码**
```bash
mkdir -p ~/hey-ohos-build && cd ~/hey-ohos-build
git clone --branch v1.26.5-beta1 https://github.com/star4277/ohos-go.git ohos-go-1.26.5
cd ohos-go-1.26.5 && git rev-parse HEAD      # ← 记进 §8 记录模板（fork commit）
```
- 输入：网络 + 磁盘
- 输出：`~/hey-ohos-build/ohos-go-1.26.5/`，含 `src/`、`VERSION` 文件
- 验证：`cat VERSION` 应含 `1.26.5`（异常：`1.24.x` → 分支取错，重取 `--branch v1.26.5-beta1`）

**S2 自举编译工具链**
```bash
cd ~/hey-ohos-build/ohos-go-1.26.5/src
GOROOT_BOOTSTRAP=/usr/local/go GOTOOLCHAIN=local ./make.bash
```
- 输入：`GOROOT_BOOTSTRAP` 指向满足版本的**标准** Go（不是 fork 自己）
- 输出：`~/hey-ohos-build/ohos-go-1.26.5/bin/{go,gofmt}`，末尾打印 `Installed Go for linux/amd64`
- 耗时：普通笔记本 **6–12 分钟**（单次；增量重跑会快）
- 常见失败点：
  | 现象 | 根因 | 处置 |
  |---|---|---|
  | `go: cannot find GOROOT directory` / bootstrap 版本过低 | `GOROOT_BOOTSTRAP` 未设或版本 < go1.24.6 | 换 go1.24.6+ |
  | `flag provided but not defined: -complete` 之类 bootstrap 报错 | bootstrap 版本**过高**（跨了不兼容版本） | 用 go1.24.x/1.25.x 而不是最新 |
  | 编译中途 OOM | 并行度高 | `GOFLAGS= GOMAXPROCS=2 ./make.bash` |
  | `GOTOOLCHAIN` 触发自动下载 | 忘了 `GOTOOLCHAIN=local` | 必须带 |
  ⚠️ **不要放在仓库的 `build/` 下**：`hvigor clean` 会删掉它（【实践】`building-native-cores.md:57`、`:204`）

**S3 验证工具链（三条，全绿才算成功）**
```bash
export GOROOT=$HOME/hey-ohos-build/ohos-go-1.26.5
export PATH=$GOROOT/bin:$PATH
go version                                  # ① 期望：go version go1.26.5 linux/amd64
go tool dist list | grep openharmony        # ② 期望：openharmony/arm64（必须出现）
go env GOOS GOARCH CGO_ENABLED              # ③ 期望：linux amd64 1
```
- **异常 ②**（无 `openharmony/arm64`）：fork 的端口补丁没生效 → 确认分支为 `v1.26.5-beta1`，或 `grep -r openharmony $GOROOT/src/internal/syslist | head` 应能命中。
- **异常 ①**（版本不是 1.26.5）：PATH 里还有另一个 go → `which -a go` 清理。

### 1.3 产物位置约定

| 物 | 建议路径 | 理由 |
|---|---|---|
| 工具链 | `~/hey-ohos-build/ohos-go-1.26.5` | 仓库外，`hvigor clean` 不碰 |
| 源码钉版目录 | `~/hey-ohos-build/src-xray`、`~/hey-ohos-build/src-libxray-v26.7.28` | 同上；且能避免 `go mod` 污染仓库 |
| `.so` 产物 | `<repo>/entry/src/main/cpp/prebuilt/arm64-v8a/` | CMake 从这里拷进 HAP（【实践】`building-native-cores.md:12`） |

---

## 2. 交叉编译（P-02 主体）

### 2.1 环境变量全量清单

```bash
# ── ① 目标与工具链（必填）──────────────────────────────
export GOROOT=$HOME/hey-ohos-build/ohos-go-1.26.5
export PATH=$GOROOT/bin:$PATH
export GOTOOLCHAIN=local              # 禁止自动下载别的 Go 版本，否则前功尽弃
export GOOS=openharmony               # 关键：不是 android、不是 linux
export GOARCH=arm64
export CGO_ENABLED=1                  # c-shared 必须开 cgo

# ── ② C 交叉编译器（必填，二选一）──────────────────────
export OHOS_NATIVE_HOME=${DEVECO_SDK_HOME:-$HOME/DevEco/sdk}/default/openharmony/native
export CC=$OHOS_NATIVE_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang
export CXX=$CC++
# 备选：直接用三元组驱动（不依赖 DevEco 变量）
# export CC=aarch64-unknown-linux-ohos-clang

# ── ③ TLS 模型（必填，核心中的核心）────────────────────
export CGO_CFLAGS="-ftls-model=global-dynamic"

# ── ④ 可选但建议 ────────────────────────────────────────
export CGO_LDFLAGS="-Wl,--build-id=none"   # 便于产物比对（可选）
export GOFLAGS="-mod=mod"                   # 避免 vendor 干扰
# 显式给 sysroot（一般由 OHOS clang 自带，出问题时才需要）
# export CGO_CFLAGS="$CGO_CFLAGS --sysroot=$OHOS_NATIVE_HOME/sysroot"
```

| 变量 | 为什么必须 | 依据 |
|---|---|---|
| `GOOS=openharmony` | 决定 Go runtime 的 TLS 实现走 TLSDESC；用 android → bionic 固定槽 → 外来线程 SIGSEGV；用 linux → IE-TLS → musl 拒绝 dlopen | R1 §2.4.2；【实践】`building-native-cores.md:27-31` |
| `CGO_CFLAGS=-ftls-model=global-dynamic` | 把其余 TLS 变量压到通用动态模型，配合 fork 的 `tls_g` TLSDESC | 【实践】`building-native-cores.md:81` |
| `GOTOOLCHAIN=local` | 否则 go 发现 `go.mod` 要求更高版本会去下载官方 Go，静默换掉 fork | R1 §1.2 推论；执行侧纪律 |
| **不加 `-tags netgo`** | openharmony 的 net 端口需要 cgo，加了报 `_C_getifaddrs undefined` | 【实践】`building-native-cores.md:82`、`:205` |
| `CC` 指向 OHOS clang | musl + OHOS sysroot；用 glibc clang 会链错 libc | 【实践】`building-native-cores.md:63-67` |

### 2.2 构建命令（libXray 路线）

```bash
# 取钉死版本（不要 main！见 §0.1）
cd ~/hey-ohos-build && git clone https://github.com/XTLS/libXray.git src-libxray
cd src-libxray && git checkout v26.7.28 && git rev-parse HEAD    # ← 记进 §8

# 关键：确认 go.mod 的 go 指令 ≤ 1.26
head -3 go.mod        # 期望：go 1.26.3（若见 1.27.x → 版本取错，回 §0.1）

# 编 c-shared（cgo_bridge 已是 package main）
go build -trimpath -buildvcs=false \
  -buildmode=c-shared \
  -o "$OLDPWD/prebuilt/arm64-v8a/libxray.so" \
  ./cgo_bridge
```
- 产物：`libxray.so` + 同目录自动生成的 `libxray.h`
- **预期耗时**：首次（无模块缓存）**3–8 分钟**；有缓存 **40–90 秒**
- **`.h` 不可信**：cgo 生成的头文件列出所有 `//export` 符号，**不管 version-script 有没有隐藏**；判断导出集只认 `llvm-nm -D`（【实践】`building-native-cores.md:179`）

### 2.3 产物命名与放置规则

| 规则 | 说明 |
|---|---|
| 名字固定为 `lib<name>.so` | CMake 的 `target_link_libraries` / `dlopen` 依赖该命名 |
| ABI 目录固定 `arm64-v8a` | HarmonyOS 真机 = arm64；**x86_64 模拟器加载会失败**（见 §4 第 2 类） |
| 必须与 `libentry.so` 一起被 CMake 安装到 HAP 的 libs 目录 | 否则运行期 `dlopen` 找不到（见 §4 第 1 类） |
| 三个 Go 库若同时需要 | 优先合并为**单次构建的单一 `.so`**（§0.3 路线 A） |

---

## 3. 产物校验（不过关就不要进 P-03）

`llvm-nm` / `llvm-readelf` 在 `$OHOS_NATIVE_HOME/llvm/bin/` 下（【实践】`building-native-cores.md:177`）。先 `export PATH=$OHOS_NATIVE_HOME/llvm/bin:$PATH`。

| # | 命令 | 期望输出 | 异常输出 → 含义与处置 |
|---|---|---|---|
| 1 | `strings -a $SO \| grep -m1 'GOOS=openharmony'` | `GOOS=openharmony` | **空** → 用错工具链/`GOOS`（编成了 android 或 linux）。回 §2.1 逐项核对；这是**最高频错误** |
| 2 | `strings -a $SO \| grep -m1 -o 'go1\.26\.[0-9]*'` | `go1.26.5` | `go1.27.x` → 用了非 fork 的官方 Go；`空` → 剥离过深，改用 `go version -m $SO` 复核 |
| 3 | `llvm-readelf -l $SO \| grep -i TLS` | 出现 `TLS` 段（`PT_TLS`） | **空** → 典型的 `GOOS=android` 产物（bionic 固定槽，无 PT_TLS）→ **必崩，禁止进下一步** |
| 4 | `llvm-readelf -r $SO \| grep -i TLSDESC` | 出现 `R_AARCH64_TLSDESC` | **空** → TLS 模型错（IE/LE）；补 `-ftls-model=global-dynamic` 重编 |
| 5 | `llvm-nm -D $SO \| grep ' T .*CGo'` | **恰好两行**：`CGoFree`、`CGoInvoke` | **多出** `CGoQueryStats`/`CGoSetTunFd`/`CGoRunXrayFromJSON` 等 → **导出面泄漏**（缺 version-script 或版本不对）。多余符号=对外攻击面，必须收敛 |
| 6 | `llvm-readelf -d $SO \| grep NEEDED` | 建议：`libc.so`（musl）等系统库；**不应出现** `libgo*`、`libc++_shared.so`（除非确实用了 C++） | 出现 `libc++_shared.so` 且 HAP 未打包它 → 加载期 `library not found`；出现绝对路径 → 构建机泄漏 |
| 7 | `strings -a $SO \| grep -m1 -o 'xray-core@v[^ ]*'` | 与 §8 记录的钉版一致（如 `xray-core@v1.260327.1-0.20260728075948-...`） | 与预期不符 → 模块缓存被别的版本污染：`go clean -modcache` 后重编 |
| 8 | `du -h $SO` | 记录数值（libXray 量级 **约 15–30 MB**，标【待实测】） | 显著偏大 → 忘了 `-trimpath`/`-ldflags=-s -w`；偏小到几 MB → 依赖没链进去 |

**判定线**：1–5 **全部通过**才算 P-02 通过；6–8 记录留痕即可（6 出现异常需处置）。

**参考实现同款检查**（可作为对照）：
```bash
llvm-nm -D "$SO" | grep ' T .*CGo'      # Hey 的 libxray.so 只有 CGoFree / CGoInvoke
```
【实践】`building-native-cores.md:157-175`。

---

## 4. P-03：NAPI 侧加载验证（dlopen）

### 4.1 加载代码骨架（关键调用，不写完整实现）

```cpp
// napi_init.cpp 片段：只给关键调用与错误处理骨架
static void* g_handle = nullptr;

static napi_value LoadCore(napi_env env, napi_callback_info info) {
  if (g_handle) return Ok(env, true);                 // 已加载
  // ⚠️ 需要传给 Go 的环境变量必须在这里（dlopen 之前）设置，见 §6-B
  setenv("XRAY_LOCATION_ASSET", assetDir.c_str(), 1); // 只能在首次加载前！

  g_handle = dlopen("libxray.so", RTLD_NOW | RTLD_LOCAL);
  if (!g_handle) {
    const char* e = dlerror();                        // ← 必须立刻取，后续调用会清空
    LOGE("dlopen libxray.so failed: %s", e ? e : "(null)");
    return Throw(env, e ? e : "dlopen failed");
  }
  auto invoke = (CGoInvokeFn)dlsym(g_handle, "CGoInvoke");
  auto freeFn = (CGoFreeFn)dlsym(g_handle, "CGoFree");
  if (!invoke || !freeFn) {
    LOGE("dlsym failed: %s", dlerror() ? dlerror() : "null symbol");
    dlclose(g_handle); g_handle = nullptr;
    return Throw(env, "missing CGoInvoke/CGoFree");
  }
  return Ok(env, true);
}
```
要点：
- `dlerror()` **必须紧跟失败调用后立即取出**（它会被后续调用清空），且 `dlsym` 的失败判定要用「先清 `dlerror()` 再 `dlsym` 再查 `dlerror()`」的标准写法，不要只判返回值。
- `RTLD_NOW`（立即解析，失败早暴露）优先于 `RTLD_LAZY`；`RTLD_GLOBAL` 是否需要【待真机验证】——若 `.so` 依赖同一进程内其它库的符号才需要，否则用 `LOCAL` 更安全。
- **`setenv` 的位置是本实验最容易写错的一行**，见 §6-B。

### 4.2 失败定位顺序（从最可能开始，逐级排除）

| 序 | 现象（dlerror / logcat） | 最可能原因 | 确认方法 | 处置 |
|---|---|---|---|---|
| 1 | `dlopen failed: library "libxray.so" not found` | **`.so` 没被打进 HAP**（CMake 未安装 / `abiFilters` 未含 arm64-v8a） | 解 HAP：`unzip -l app.hap \| grep libxray` | 修 CMake `install(TARGETS ...)` 与 `build-profile.json5` 的 abiFilters |
| 2 | `... is 64-bit instead of 32-bit` / `ELFCLASS` 不符 / `invalid ELF header` | 在 **x86_64 模拟器**上跑 arm64 产物 | `uname -m`、`llvm-readelf -h $SO \| grep Machine` | 换真机，或另编 x86_64 版（本实验只针对真机 arm64） |
| 3 | `cannot locate symbol ...` / `library "libc++_shared.so" not found` | `DT_NEEDED` 里有个 HAP 内不存在的依赖 | §3-#6 的 `NEEDED` 列表与 HAP 内 libs 列表对照 | 把缺失库一并打包；或去掉不必要的 C++ 依赖重编 |
| 4 | `unsupported relocation` / `cannot apply relocation` / 加载后立刻 abort | 产物不是 TLSDESC（§3-#3/#4 异常） | 回看 §3 检查 3、4 | 重编；检查 `-ftls-model` 与工具链 |
| 5 | `dlopen` 成功，但 `dlsym("CGoInvoke")` 返回 NULL、`dlerror` = `undefined symbol` | version-script 把符号隐藏了 / 库版本不对 | `llvm-nm -D $SO \| grep CGo`（§3-#5） | 用钉版源码重编 |
| 6 | `dlopen` 返回非 NULL，**随后进程崩**（不在 `dlopen` 调用栈内） | 见 §6 三类 SIGSEGV | 抓 hilog 崩溃栈看是否在 Go 线程 | 按 §6 归因 |

> 判据：**P-03 通过 = 「`dlopen` 成功」+「`dlsym` 拿到 2 个符号」+「加载后 30 秒内不崩」三件事同时成立。**

---

## 5. P-04：`CGoInvoke` 冒烟 → 异步回调 → 压测（三级递进）

请求信封（【实践】`building-native-cores.md:99`）：
```json
{"apiVersion":1,"method":"<method>","payload":{...}}
```
返回信封：`{"success":bool,"data":...,"error":"..."}`（**原始 JSON，非 base64**）。
可用 method（示例，实际以钉版 `invoke_model.go` 为准）：`runXrayFromJson` / `stopXray` / `ping` / `pingBatch` / `xrayVersion` / `getFreePorts` / `countGeoData`。

### L1 同步冒烟（10 次，最快的"活着"证明）
- 调用：`{"apiVersion":1,"method":"xrayVersion","payload":{}}`
- **通过线**：10/10 返回非 NULL 且 `success:true`，`data` 含版本号
- **失败线**：返回 NULL、或 `success:false`、或崩溃 → 立刻转 §7 分支 A/D
- 目的：验证「外来线程（ArkTS 线程）→ cgo → Go」这条**最容易 SIGSEGV** 的路径

### L2 异步与回调（一次完整生命周期）
- 步骤：`runXrayFromJson`（起本地 SOCKS 入站）→ `ping`（对一个已知可达目标）→ `stopXray`
- **通过线**（全满足）：
  1. `runXrayFromJson` 返回 `success:true`，且本地端口可连（在 ArkTS 侧 `connect` 一次验证）
  2. `ping` 返回带延迟数值
  3. 回调从**非 UI 线程**送达（记录 `tid`；若在主线程回调且阻塞 > 16 ms，判**部分通过**，需改线程模型）
  4. `stopXray` 后端口释放、再 `run` 能成功（可重复 start/stop 3 轮）
- **失败线**：任一轮 `stop` 后无法再 `run`（句柄/端口泄漏）、或回调丢失、或 `CGoFree` 未被调用（内存只增不减）

### L3 压测（1 万次，验稳定性与泄漏）
- 循环：偶数次 `xrayVersion`、奇数次 `ping`（轻量、无外部依赖优先）；若 ping 有网络依赖，则 9:1 混合
- 每 1000 次采样一次进程 RSS，记录到 §8 模板
- **通过线**：
  1. 崩溃次数 **= 0**
  2. RSS 线性回归斜率 ≈ 0（增长 **< 5%**，且不随次数单调上升）
  3. 每次返回的字符串都经 `CGoFree` 释放（用计数器核对 invoke/free 次数相等）
  4. 总耗时记入基线（**不设绝对阈值**，见下）
- **失败线**：任一崩溃 / RSS 单调上升 / invoke 次数 ≠ free 次数
- ⚠️ **耗时与 RSS 的绝对值不设判据**：本实验只产出**基线数字**，供 Q1 的性能需求回填。理由是 R1 §5.3 已定「回填前不得引用任何未测指标」。

---

## 6. 三类 SIGSEGV 的区分方法（现场快速归因）

| 特征 | **A. 冷 cgo 入口（TLS 墙）** | **B. `dlopen` 后 `setenv`（environ 争用）** | **C. 外来线程调 cgo（同一堵墙的另一面）** |
|---|---|---|---|
| 触发时机 | **第一次**从 ArkTS/VPN 扩展线程调 cgo | `dlopen` 之后、Go 库**初始化线程仍在跑**期间发生 `setenv`/`setenv` 类操作 | 在**非 Go 创建**的线程上调 cgo（VPN 扩展线程、worker 线程） |
| 崩溃栈形态 | `#00/#01 libxray.so` 两帧即断，后续帧不可解；地址像野指针（如 `0x0001xxxx...`） | 栈落在 **libc（musl）** 或 Go 初始化线程，**不在** `dlopen` 调用栈内 | 与 A 类似，但**只在特定线程**复现（UI 线程可能不复现） |
| 是否与线程相关 | 是（同进程内换线程才复现） | 否（与线程无关，与**时序**有关） | 是（关键在"线程是谁创建的"） |
| 判据（先查这个） | `llvm-readelf -l $SO \| grep TLS` **为空** 或 `-r` 无 TLSDESC → 就是 A | 满足：①有 Go 库已 `dlopen`；②代码里在之后调过 `setenv` → 就是 B | 有 PT_TLS+TLSDESC 但**仍**只在特定线程崩 → 查是否该线程未经过 Go 的 `needm` 路径，通常仍需回 A 的修法 |
| 规避 | `GOOS=openharmony` + `-ftls-model=global-dynamic` 重编（R1 §2.4.2） | **所有环境变量在首次 `dlopen` 之前设完**；运行期参数一律走调用参数（JSON/实参） | 同 A；并尽量让 cgo 调用收敛到固定线程 |
| 参考机制 | R1 §2.4.2；【实践】`harmonyos-go-tls-wall.md` §3-§5 | 【实践】`building-native-cores.md:183-198`（Go 只在初始化时拷贝一次 `environ`；初始化线程会读到被 `setenv` realloc 掉的旧数组 → 野指针） | 同 A |

**现场归因流程（60 秒版）**：
1. 抓 hilog 崩溃段，看 `Signal:` 与 `Process name`（是否 `:vpn` 这类扩展进程）。
2. 数栈帧：`libxray.so` 只有 1–2 帧且无 libc 帧 → **A 或 C**。
3. 查 §3 检查 3/4（PT_TLS / TLSDESC）：缺失 → **确认 A**。
4. 两者都在，但崩在 libc / Go 初始化线程、且时间点紧跟 `setenv` → **B**。
5. 两者都在、崩在固定业务线程 → **C**。

---

## 7. 失败分支处置（决策树）

| 阶段失败 | 首选动作 | 次选 | 不要做 |
|---|---|---|---|
| **编译失败**：`module requires go >= 1.27.x` | 回 §0.1 钉 `v26.7.28`（或对应 go≤1.26 的 tag） | 降 `libXray`/core 到更早 tag | ❌ 用官方 Go 1.27 编（会丢 TLSDESC，白编） |
| **编译失败**：`_C_getifaddrs undefined` | 去掉 `-tags netgo` | 检查 `CGO_ENABLED=1` | ❌ 加 `netgo` 绕过 |
| **编译失败**：bootstrap 报错 | 换 go1.24.6~1.25.x 的 bootstrap | 用容器固定环境 | ❌ 升到最新 Go 当 bootstrap |
| **校验失败**：无 `PT_TLS` | 确认 `GOOS=openharmony`；用 `go version -m $SO` 看 GOOS | 重装 fork 工具链 | ❌ 直接上真机试（必崩，浪费真机时间） |
| **校验失败**：TLS 有但无 TLSDESC | 补 `-ftls-model=global-dynamic` 重编 | 检查 fork 是否含 arm64 TLSDESC 补丁 | ❌ 手工打 TLS patch |
| **校验失败**：导出符号 > 2 | 换回带 version-script 的钉版 | 自行加 version-script | ❌ 放任多导出（攻击面 + 升级不可控） |
| **加载失败**：`library not found` | 查 HAP 内是否含该 `.so`（§4 第 1 类） | 换绝对路径 `dlopen` 验证 | ❌ 改 `LD_LIBRARY_PATH`（沙箱无效） |
| **加载失败**：`unsupported relocation` | 回 §3 重编 | 换 fork 版本 | ❌ 混用不同工具链编的库 |
| **加载成功但 dlsym 为空** | 用 `llvm-nm -D` 核对导出集 | 换钉版源码 | ❌ 猜符号名 |
| **回调崩（B 类）** | 把 `setenv` 全部前移到首次 `dlopen` 前 | 运行期参数改走 JSON | ❌ 在回调里 `setenv` |
| **回调崩（A/C 类）** | 重编（TLSDESC）；确认没有混入 android 产物 | **换 Go fork 版本**（`star4277/ohos-go` 的其它 tag 或 openharmony-sig 树 + 前移补丁） | ❌ 在 C 侧加信号处理"兜住" |
| **压测泄漏** | 核对 invoke/free 计数；`CGoFree` 必须用，不能 `std::free` | 换 `-ldflags=-s -w` 重编对照 | ❌ 提高 GC 频率掩盖 |
| **同一进程需两个 Go 库** | **合并单次构建成单一 `.so`**（§0.3 路线 A） | 照抄 Hey 分库 + 严控加载顺序（记录为已知风险） | ❌ 认为"Hey 能跑所以没问题" |

---

## 8. 记录模板（每条必填，作为 R-01 缓解措施的留痕）

复制下表到实验记录文件（建议 `<repo>/doc/xray-harmony/poc/records/PC2-<日期>.md`），**每换一次工具链或 flags 就新增一行**。

```markdown
# PC2 实验记录 <日期>

## A. 环境
| 项 | 值 |
|---|---|
| 构建机 OS / 架构 | Linux x86_64（WSL2 / 容器 / 物理机） |
| bootstrap Go | go1.24.x（<实际版本>，`$GOROOT_BOOTSTRAP`） |
| OHOS Go fork | repo=star4277/ohos-go tag=v1.26.5-beta1 **commit=<git rev-parse HEAD>** |
| `go version` | go version go1.26.5 linux/amd64 |
| `go tool dist list \| grep openharmony` | openharmony/arm64 （是/否） |
| DevEco / SDK 版本 | <版本号> |
| OHOS_NATIVE_HOME | <路径> |
| 真机型号 / HarmonyOS 版本 / API | <如 ALN-AL80 / 6.1.0.x / API 23> |

## B. 源码钉版
| 组件 | tag | commit | go.mod 的 go 指令 |
|---|---|---|---|
| libXray | v26.7.28 | <sha> | 1.26.3 |
| xray-core（由 libXray 决定） | 伪版本 `v1.260327.1-0.20260728075948-5ca6f4b7d4dc` | 5ca6f4b7d4dc | ≤1.26.3（待核） |

## C. 全量构建 flags（必须原样可复现）
```
GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 \
CC=$OHOS_NATIVE_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang \
CXX=$CC++ \
CGO_CFLAGS="-ftls-model=global-dynamic" \
CGO_LDFLAGS="<...>" \
GOTOOLCHAIN=local \
go build -trimpath -buildvcs=false -buildmode=c-shared -o <out> ./cgo_bridge
```

## D. Patch 清单（有则必列，无则写「无」）
| # | 目标文件 | 补丁内容（一句话） | 是否需按 MPL-2.0 §3.1 公开 |
|---|---|---|---|
| 1 | <如 tun2socks_adapter/.../isSocketFD> | 恒返回 false（HarmonyOS VPN fd 拒 Fstat） | 是/否 |

## E. 产物校验（§3 八条逐条填）
| # | 命令 | 实际输出 | 期望 | 通过 |
|---|---|---|---|---|
| 1 | strings GOOS | | GOOS=openharmony | ☐ |
| 2 | strings go1.26.x | | go1.26.5 | ☐ |
| 3 | readelf -l TLS | | 有 PT_TLS | ☐ |
| 4 | readelf -r TLSDESC | | 有 R_AARCH64_TLSDESC | ☐ |
| 5 | nm -D ' T .*CGo' | | 恰 2 个 | ☐ |
| 6 | readelf -d NEEDED | | 无异常依赖 | ☐ |
| 7 | strings xray-core@ | | 与 §B 一致 | ☐ |
| 8 | du -h | | 记录 | ☐ |

## F. P-03 加载验证
| 项 | 结果 |
|---|---|
| dlopen 结果 / dlerror | |
| dlsym CGoInvoke / CGoFree | |
| 加载后 30s 内是否崩 | |
| 失败类别（§4.2 序 1-6） | |

## G. P-04 三级判据
| 级 | 通过线 | 实测 | 结论 |
|---|---|---|---|
| L1 冒烟 10 次 | 10/10 success | | |
| L2 起/停/回调 3 轮 | 全满足 | | |
| L3 压测 10000 次 | 0 崩 · RSS 增长<5% · invoke=free | | |

## H. 基线数字（供 Q1 回填，禁止当判据）
| 指标 | 数值 | 采集方式 |
|---|---|---|
| 空闲 RSS | | L3 第 0 次采样 |
| L3 结束 RSS | | 第 10000 次 |
| 单次 CGoInvoke P50/P99 | | 计时器 |
| 冷启动 → 可接受连接 | | ArkTS 侧打点 |

## I. 结论与后续
- 判定：P-02 ☐通过 ☐失败；P-03 ☐通过 ☐失败；P-04 ☐通过 ☐失败
- 阻塞项 / 待验证项：
- 需要的下一步：
```

---

## 9. 版本钉死矩阵（写进任何脚本头部，防止隐式漂移）

| 层 | 钉死值 | 漂移风险 | 检测手段 |
|---|---|---|---|
| OHOS Go fork | `star4277/ohos-go` `v1.26.5-beta1` | beta 版、个人 fork，可能停更或被 force-push | 记录 commit sha；**本地留副本**（`~/hey-ohos-build` 归档） |
| libXray | `v26.7.28`（**不是 main**） | main 已是 `go 1.27.1`，直接编不了 | 构建前 `head -3 go.mod` 断言 go ≤ 1.26 |
| xray-core | 由 libXray 的 `go.mod` 决定（伪版本）；**禁止手动升级** | 上游 2026-07-28 后抬到 go1.27 | `strings $SO \| grep xray-core@` |
| DevEco / OHOS SDK | 记录具体版本 | NDK clang/sysroot 随版本变 | 记录 `$OHOS_NATIVE_HOME` 路径与 `clang --version` |
| HarmonyOS 真机 | 记录型号 + 版本 + API | 系统 OTA 会改变外来线程 TLS 初值（R1 §2.4.3 F-2） | 每次都记；OTA 后**必须重跑 §3 校验与 P-03** |

---

## 10. 依据索引

| 结论 | 依据 |
|---|---|
| fork / `GOOS=openharmony` / TLSDESC / 三种编法对比 | 【实践】`_research_src/Hey/docs/building-native-cores.md:23-37`；`harmonyos-go-tls-wall.md` §3-§5；R1 §2.4.2 |
| bootstrap 需 go1.24.6+；`make.bash` 步骤 | 【实践】`building-native-cores.md:45-53` |
| `-ftls-model=global-dynamic`、禁 `netgo` | 【实践】`building-native-cores.md:74-82` |
| 工具链别放 `repo/build/` | 【实践】`building-native-cores.md:57`、`:204` |
| 产物校验 5 条 + `.h` 不可信 | 【实践】`building-native-cores.md:153-179` |
| `CGoInvoke` 信封 / `CGoFree` 必须用 / 仅 2 导出 | 【实践】`building-native-cores.md:98-101`；【源码】`_research_src/libXray/cgo_bridge/main.go:13-25@4e1f784` |
| `dlopen` 后禁 `setenv` 的两层原因 | 【实践】`building-native-cores.md:183-198` |
| libXray main 已 `go 1.27.1` | 【源码】`_research_src/libXray/go.mod:3@4e1f784` |
| libXray `v26.7.28` 为 `go 1.26.3`、钉 core 伪版本 | 【源码】`git show v26.7.28:go.mod:3,6` |
| xray-core GA 的 go 指令 / HEAD 的 go 1.27 | R1 §1.2；【源码】`go.mod:3@v26.3.27`、`@95461cc` |
| tun2socks 的 Fstat 补丁是 required（否则 `log.Fatal`） | 【实践】`building-native-cores.md:132` |
| 一进程一 Go runtime（Go #18976/#15956）与参考实现的违规 | 【官方文档】libXray README WARNING；【实践】`building-native-cores.md:198` |

---

## 附：本实验包刻意不做的事

- **不写完整实现代码**（NAPI 桥、ArkTS 侧只给关键调用与判据）。
- **不给性能绝对阈值**：RSS/耗时只产出基线，阈值由需求文档在回填后确定（R1 §5.3 回填规则）。
- **不覆盖 `proxy/tun` 直连路线**：该路线需新增 `//go:build openharmony` 实现并承担 MPL-2.0 开源义务（R1 §5.4.1），属独立 PoC（P-03 的对照分支），不在本包强制范围。
