# 工具链获取清单（OHOS Go）

> 任务：E2 ｜ 作者：xray-core-analyst ｜ 日期：2026-10-18
> **本轮未下载、未安装、未自举、未编译任何东西。** 本文只是「要拿什么、从哪拿、多大、什么许可、怎么验」的清单，等用户批准后按 `README.md` 执行。
> 体积均为**估算**（标注 ~），以实际下载为准；许可证以各自仓库 `LICENSE` 为准。

---

## 1. 必需项（缺任一则无法产出 `.so`）

| # | 物 | 来源 | 版本 | 体积（估算） | 许可证 | 校验方式 |
|---|---|---|---|---|---|---|
| M1 | **OHOS Go fork 源码** | `https://github.com/star4277/ohos-go`（tag `v1.26.5-beta1`） | `v1.26.5-beta1` | tarball ~30 MB / 解压 ~90 MB | **BSD-3-Clause**（fork 继承 Go；以 tarball 内 `LICENSE` 为准） | 记录 `git rev-parse HEAD`；或 tarball 的 `SHA256` 自留（上游未公布） |
| M2 | **引导 Go（bootstrap）** | `https://go.dev/dl/`（国内不通时 `https://golang.google.cn/dl/`） | **go1.24.6 ≤ v < go1.26** 的 windows-amd64 或 linux-amd64 | zip ~80 MB / 解压 ~250 MB | BSD-3-Clause | 官方 JSON 索引里的 **`sha256`**（脚本自动比对） |
| M3 | **DevEco Studio / HarmonyOS SDK（含 NDK）** | 已安装（用户本机 API 26） | 用户现装版本 | 已装，无新增下载 | 华为专有 EULA | 检查 `aarch64-unknown-linux-ohos-clang` 可执行 |
| M4 | **磁盘空间** | — | — | 工具链自体 ~350 MB；加源码与模块缓存**建议预留 ≥ 5 GB** | — | `Get-PSDrive` 可用空间检查 |

> M2 的版本上下界不是猜的：自举下限由 fork 的 `src/cmd/dist/buildtool.go` 里 `minBootstrap` 决定，现役为 **go1.24.6+**（依据：`building-native-cores.md:51`）；上限是「不能高到引入与 fork 补丁不兼容的 dist」——实践中用 **go1.24.x 最稳**，go1.25.x 次之。

## 2. 可选项（不做也能跑，做了省事/更稳）

| # | 物 | 用途 | 体积 | 说明 |
|---|---|---|---|---|
| O1 | **WSL2 + Ubuntu 22.04/24.04** | **推荐的构建环境**（Path A）。`make.bash` 是 bash 脚本，Linux 上自举最省事、与参考实现一致 | 镜像 ~500 MB–1 GB | 微软/Ubuntu 条款；需 `wsl --install`（属系统变更，需用户批准） |
| O2 | **Git for Windows** | 拉 fork 源码并记录 commit；本机已具备 Git Bash | 已装 | GPL-2.0 |
| O3 | **国内 Go module proxy**（`https://goproxy.cn`） | 后续编 libXray 时拉依赖 | 无 | 仅影响 `GOPROXY`，不改产物 |
| O4 | **7-Zip / tar** | 解压 tar.gz（Windows 自带 `tar.exe` 可用，通常不需要） | — | Windows 10 1803+ 自带 `tar`，本清单默认用它 |

**明确不在本轮清单内**（等构建链跑通后再要）：`libXray v26.7.28` 源码、`Xray-core v26.3.27`、gvisor/tun2socks adapter、sing-box。这些属 P-02 的第二步，且引入后体积与许可证面（MPL-2.0）都会扩大。

## 3. 本机已核实的既有事实（不是清单，是现状）

均于 2026-10-18 在本机实际列目录确认：

| 事实 | 证据 |
|---|---|
| NDK clang 存在：`…\native\llvm\bin\aarch64-unknown-linux-ohos-clang`（**无 `.exe` 后缀**，带 `aarch64-unknown-linux-ohos-clang++`） | `ls` 输出 |
| 校验工具齐全：`llvm-readelf.exe`、`llvm-nm.exe`、`llvm-objdump.exe`、`llvm-strings.exe` | 同上 |
| sysroot 结构：`native\sysroot\usr\lib\aarch64-linux-ohos\`（153 个条目，含 `libc.so` / `libc.a` / crt 对象） | 同上 |
| 该目录下**未见** `libc++_shared.so` / `libstdc++` | 同上 → 若后续引入 C++ 依赖需另找 clang runtime【待验证】 |
| 本机**无 Go 工具链** | `go version` → command not found |

## 4. 许可证合规提示（只与「分发」有关，不影响内部构建）

- **Go / fork**：BSD-3-Clause，允许闭源分发，但**须保留版权与许可声明**。分发 HAP 时若内含 Go 产物，建议在「关于/开源许可」页列出 Go 与 fork 的版权声明。
- **DevEco SDK**：华为专有许可，只允许用于开发鸿蒙应用，**不得单独再分发其 NDK 二进制**。
- **后续 libXray / Xray-core**：MPL-2.0（文件级 copyleft）。一旦为 OHOS 修改其源文件，**被改文件必须公开**（R1 §1.3）。
- **fork 的供应链风险**：`star4277/ohos-go` 是**个人第三方 fork、beta 版**。→ 必须记录 commit sha 并在本地归档一份（`README.md` §7）。这不是形式主义：一旦上游删库，构建链就断了。

## 5. 申请下载授权时请一并写明（给用户批）

建议按这个顺序批、分批下，避免一次拉太多：

1. **第一批（最小可验证）**：M1 + M2 ≈ **110 MB** → 目标：自举出 `go1.26.5` 工具链并编出 `libcgoping.so`。
2. 第二批（若第一批在 Windows 原生路径失败）：O1 WSL2 Ubuntu → 换 Linux 路径重跑。
3. 第三批（P-02 第二步）：libXray `v26.7.28` + Go module 依赖 ≈ **500 MB–1 GB**。
