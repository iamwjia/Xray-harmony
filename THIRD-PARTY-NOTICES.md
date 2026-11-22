# 第三方组件与许可证声明（Third-Party Notices）

本文件对应 Tunnelix（`com.tunnelix.app`）二进制分发包中包含的第三方组件。
应用内「设置 → 关于 → 开源许可」页面展示的是本文件的摘要版；**本文件与
`doc/release/licenses/` 下的许可证原文才是完整声明**。

生成日期：2026-11-23
对应构建：Xray-core `v1.260327.1-0.20260728075948-5ca6f4b7d4dc`、
libXray 本地固定目录 `libXray-v26.7.28`、tun2socks `v2.7.0`、
gVisor `v0.0.0-20260701204157-69c2d17aea96`。
依据：`_toolchain/merged/go.mod`（合并库的真实依赖清单）。

---

## 一、直接集成、随包分发的组件

| 组件 | 实际版本（来自 go.mod） | 许可证 | 用途 | 是否修改 | 源码/获取地址 |
|---|---|---|---|---|---|
| Xray-core | `v1.260327.1-0.20260728075948-5ca6f4b7d4dc`<br>（pseudo-version，commit `5ca6f4b7d4dc`） | **MPL-2.0** | 代理协议与出站实现（内核） | **未修改**，按上游源码构建 | https://github.com/XTLS/Xray-core |
| libXray | 固定目录 `_toolchain/libXray-v26.7.28`（tag `v26.7.28`） | MIT | Xray-core 的移动端封装与调用桥（CGo 导出） | 未修改 | https://github.com/XTLS/libXray |
| tun2socks | `github.com/xjasonlyu/tun2socks/v2 v2.7.0` | MIT | tun fd → SOCKS5 转发（数据面） | 未修改 | https://github.com/xjasonlyu/tun2socks |
| gVisor netstack | `gvisor.dev/gvisor v0.0.0-20260701204157-69c2d17aea96` | Apache-2.0 | 用户态 TCP/IP 协议栈（tun2socks 依赖） | 未修改 | https://github.com/google/gvisor |
| geoip / geosite 数据 | v2fly 官方发布构建（应用内显示 `v2fly-<日期>`） | 以 v2fly 发布页声明为准 | 分流规则数据 | 未修改，按原样分发 | https://github.com/v2fly/geoip · https://github.com/v2fly/domain-list-community |

> 说明：tun2socks 与 gVisor 通过 `toolchain/build-merged.ps1` 与 Xray-core 一起编进
> 单个 `libxray.so`，导出 `CGoInvoke` / `StartTun2Socks` 两个入口。**它们确实随包分发**，
> 不是"规划集成"。

## 二、间接依赖

上述四个组件的间接依赖（quic-go、gorilla/websocket、docker/go-units 等，共 60+ 项）
由 `_toolchain/merged/go.mod` 的 require 列表给出，均为 MIT / Apache-2.0 / BSD 系许可证。
完整的逐项清单可用下面的命令在构建机上重现：

```powershell
cd _toolchain\merged
& ..\ohos-go-v1.26.5-beta1\bin\go.exe list -m all
```

许可证原文统一随组件源码发布，未在本仓库逐一复制——这一点是**已知简化**：
若审核要求逐项列出，按上面的命令导出后补进 `doc/release/licenses/`。

## 三、许可证原文

| 文件 | 对应组件 |
|---|---|
| `doc/release/licenses/MPL-2.0.txt` | Xray-core（Mozilla Public License 2.0 全文，取自上游 `LICENSE`） |
| `doc/release/licenses/MIT-libXray.txt` | libXray（MIT，Copyright (c) 2023-2025 XTLS） |
| `doc/release/licenses/MIT-tun2socks.txt` | tun2socks（MIT） |
| `doc/release/licenses/Apache-2.0.txt` | gVisor（Apache License 2.0） |

## 四、MPL-2.0 的具体履行方式

MPL-2.0 是**文件级** copyleft：只要求被 MPL 覆盖的文件在分发可执行形式时提供源码，
不要求公开调用方代码。我们的履行方式：

1. **不分发修改后的 MPL 文件**：Xray-core 按上游源码原样编译（`未修改`），
   因此没有新增需要以 MPL-2.0 公开的文件。
2. **告知源码获取方式**（MPL-2.0 §3.2）：应用内「开源许可」页面 + 本文件 + 仓库 README
   三处都给出上游地址与对应版本/commit。
3. **保留声明**：许可证原文随包（`doc/release/licenses/`），应用内页面列出组件、版本、
   许可类型与"是否修改"。
4. **不暗示背书**（MPL-2.0 §5 关于商标）：应用内明确写"独立第三方项目，与 XTLS、
   Xray-core、v2fly 无隶属关系，未获背书"，应用名 `Tunnelix` 与图标为原创。
5. **若日后修改 Xray-core 的 MPL 文件**：相应文件须以 MPL-2.0 公开，并在同一页面标注
   修改点——这一条已写进应用内页面（"若日后修改，相应文件须以 MPL-2.0 公开"）。

> ⚠️ **风险提示（不是合规问题，但是事实）**：MPL-2.0 只约束版权，**不授予专利许可给
> 下游的"额外限制"**；本项目未对 Xray-core 做任何专利主张，也未添加额外限制条款。

## 五、待办（需要决策或补料）

| 项 | 现状 | 需要谁 |
|---|---|---|
| 本应用**自有代码**的许可证 | **未声明**（仓库无 `LICENSE`，模块 `license` 为空） | 需要你定：MPL-2.0 / MIT / Apache-2.0 / 其他 |
| 间接依赖逐项许可证清单 | 只给生成命令，未逐项落盘 | 我可按命令导出后补齐 |
| 应用内是否展示**许可证全文** | 当前只展示摘要 + 上游地址 | 需要你定：全文塞进应用（几十 KB 文本）还是只给链接 |
