# 许可证原文归档说明

本目录存放**随分发包一起使用的第三方许可证全文**，来源与版本如下。
所有文件已统一为 UTF-8 (无 BOM) + LF 行尾（原文来自 Go module 缓存时是 CRLF，仅改行尾，未改内容）。

| 文件 | 组件 | 上游来源 | 版本 |
|---|---|---|---|
| `MPL-2.0.txt` | Xray-core | `_research_src/Xray-core/LICENSE`（上游仓库 LICENSE） | commit `5ca6f4b7d4dc` |
| `MIT-libXray.txt` | libXray | `_toolchain/libXray-v26.7.28/LICENSE` | tag `v26.7.28` |
| `MIT-tun2socks.txt` | tun2socks | Go module 缓存 `github.com/xjasonlyu/tun2socks/v2@v2.7.0/LICENSE` | `v2.7.0` |
| `Apache-2.0.txt` | gVisor netstack | Go module 缓存 `gvisor.dev/gvisor@v0.0.0-20260701204157-69c2d17aea96/LICENSE` | 同上 pseudo-version |

## 为什么归档在这里

MPL-2.0 要求"以可执行形式分发时提供许可证副本"。把全文放在仓库里是**最低限度**；
更强的做法是打进 HAP 的 `rawfile` 并在应用内展示（见 `doc/release/mpl-compliance.md` 第三节选项 A）。
当前是选项 B（仅仓库 + 应用内链接）。

## 更新方式

组件升级时，从**同版本的上游源码**重新拷一次对应 `LICENSE`，不要手改内容。
