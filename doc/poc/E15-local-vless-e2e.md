# E15 — 本地 VLESS 端到端验证

| 项目 | 内容 |
|---|---|
| 日期 | 2026-11-21 |
| 目标 | 在没有第三方节点的前提下，证明「App → 内核 → 出口节点(VLESS) → 目标」这条链路真的成立 |
| 结论 | **成立**：应用侧拿到 200 + 正文，服务端侧同时出现 `accepted tcp:…` 与 `proxy/freedom: connection opened` |
| 边界 | 只证明**协议与转发**成立；本地节点出口仍是宿主网络，**不能**说明用户获得隐私保护 |

---

## 1. 环境

| 项 | 值 |
|---|---|
| 设备 | 模拟器 `127.0.0.1:5555`，系统内地址 `10.0.2.15/24`，默认网关 `10.0.2.2`（QEMU NAT，即宿主） |
| 应用 | `com.tunnelix.app`，x86_64 未签名 HAP（API 26） |
| 服务端 | `_toolchain/e15/xray.exe`（**标准 Windows Go 1.26.3** 编译，Xray 26.7.28），VLESS + TCP，**明文**，`0.0.0.0:10443` |
| 宿主 HTTP 探针 | `python -m http.server 8000 --bind 0.0.0.0`，文件 `probe.txt` = `xray-harmony-host-reachable` |
| 宿主地址 | `127.0.0.1` / `192.168.3.55`（服务端双栈监听，IPv4 均可达） |

> 凭据（UUID）只写在 `_toolchain/`，未进入仓库。

## 2. Step 1：设备到宿主是否真的能建 TCP

设备侧**没有** `curl/wget/nc`（`toybox` 也没有这两个 applet），
所以 `ping 10.0.2.2` 只能证明 ICMP 可达，**不能**证明 8000 端口可连。
为此加了 native 探针 `m10HostProbe`（复用 M9 的 POSIX socket 代码），从**应用进程**里做真实的 connect + HTTP GET：

```
E15 host probe: [tcp=OK][connect_ms=1][http_ms=1]
                [status=HTTP/1.0 200 OK][body=…xray-harmony-host-reachable]
```

**判定**：TCP 建连成功且拿到预期正文 ⇒ 模拟器可以访问宿主的 HTTP 服务。

## 3. Step 2：流量是否真的走了一次 VLESS

自检路径：应用启动时用代码直接构造节点（`10.0.2.2:10443` + UUID），起内核，再用**带口令的 SOCKS5**（`m11SocksProbe`，RFC1929）请求公网地址。

### 应用侧

```
E15 step2 cfg_bytes=508 socks_port=27747
E15 step2 kernel running=true
E15 step2 via-socks: [ms=2219][socks=127.0.0.1:27747][target=checkip.amazonaws.com:80]
                     [status=HTTP/1.1 200 ][body=222.247.206.159][err=-]
E15 step2 kernel stopped
```

### 服务端侧（同一时刻，`_toolchain/e15/server2.out.log`）

```
18:44:42.077486 [Info] proxy/vless/inbound: firstLen = 140
18:44:42.077486 from 127.0.0.1:54074 accepted tcp:checkip.amazonaws.com:80
18:44:42.084009 [Info] proxy/vless/inbound: received request for tcp:checkip.amazonaws.com:80
18:44:42.084530 [Info] app/dispatcher: default route for tcp:checkip.amazonaws.com:80
18:44:42.112402 [Info] proxy/freedom: dialing to tcp:13.251.36.15:80
18:44:42.112402 [Info] transport/internet/tcp: dialing TCP to tcp:13.251.36.15:80
18:44:42.199970 [Info] proxy/freedom: connection opened to tcp:checkip.amazonaws.com:80,
                local endpoint 192.168.3.55:54076, remote endpoint 13.251.36.15:80
```

**为什么这组日志能证明"走了一次 VLESS"**（三条件必须**同时**成立）：

1. `accepted` 只在 **UUID 校验通过之后**才出现；
2. `firstLen` 落在 VLESS 请求头的量级（我们 140/205），而不是 `621`（HTTP 打进来）或 `1460`（TLS ClientHello）；
3. `proxy/freedom: connection opened` —— 服务端**真的把连接打出去了**。

> **判据收紧（2026-11-21，独立复核后修订）**：
> **只看到 `accepted` 不足以判"转发成功"**。陷阱 3 就是反例：`accepted tcp:10.0.2.2:8000`
> 之后紧跟 `blocked target … blackholing`，握手与路由都成立，出站却被 SSRF 防护拦掉。
> 因此最低判据必须包含第三行 `proxy/freedom: connection opened …`；
> 只有 `accepted` 时只能判「**握手成功、出站被拦**」。

### 负对照（独立复核补充，同端口 10443）

| 场景 | 服务端日志 | 客户端 |
|---|---|---|
| **错误 UUID** | `firstLen = 205` → `rejected proxy/vless/encoding: invalid request user id: 1111…` | 503 |
| **正确 UUID** | `firstLen = 205` → `accepted …` → `connection opened` | 200，`body=222.247.206.159` |

⇒ 证明 `accepted` 确实与 UUID 校验强相关，不是"任何连接都会打"。
另外两组指纹可用于快速归因：`firstLen = 621` = 非 VLESS 客户端（HTTP 打进来）；`firstLen = 1460` = TLS ClientHello（安全层配错）。

App 侧 200 与 服务端侧 `accepted` 是**同一时刻**的同一个请求，缺任一条都不成立。

## 4. 三个"看起来成功、其实没走代理"的陷阱（都实际踩到了）

| # | 现象 | 原因 |
|---|---|---|
| 1 | App 侧拿到 200，**服务端一行日志都没有** | 用 RULE 模式，目标 `10.0.2.2` 属 `10.0.0.0/8`，被内网直连规则命中，**根本没进节点**。→ 自检改用 GLOBAL。**这条同时反向证明 RULE 的私网直连规则是生效的** |
| 2 | 服务端 `firstLen = 1460` + `invalid request version` | `XrayNode.security` 默认是 `TLS`，自检节点没显式设 `NONE`，于是发了 TLS ClientHello 到明文端口。→ 显式 `security = NONE` |
| 3 | 服务端 `accepted` 之后紧跟 `proxy/freedom: blocked target …, blackholing` | freedom 出站默认**阻断私网/回环目标**（SSRF 防护）。→ 目标改为公网地址，链路才通 |

第 2 条顺带暴露一个产品风险：**节点对象的默认安全层是 TLS**。分享链接里 `security` 缺省会被解析成 `none`，所以导入路径没问题；但任何"代码里直接构造节点"的地方都必须显式设置，否则会产生与"配置错了"一模一样的现象。

## 5. 能证明什么 / 不能证明什么
**能证明**

- 模拟器应用进程能连宿主端口（TCP + HTTP 200）；
- 内核能在真实节点配置下启动并接受 SOCKS5（**带口令**）请求；
- 流量确实经 VLESS 协议到达服务端，并被服务端转发出去（服务端日志三条件同时成立）；
- RULE 模式的内网直连规则生效（陷阱 1 的反向证据）。

**不能证明**

- **不能**证明"IP 变了"：本地节点出口就是宿主网络，`222.247.206.159` 是宿主公网出口，换任何本地节点都一样；
- **不能**证明隐私保护：这是自建节点 + 明文 VLESS + 无鉴权外的任何防护，与真实服务商节点无关；
- **不能**证明 UDP / QUIC / 分流规则在真实网站上的行为；
- **不能**替代真机验证：VPN 扩展、tun 接管、其他应用流量是否被代理，全部未涉及。

## 6. 复现步骤

1. 宿主：`_toolchain/e15/xray.exe run -c _toolchain/e15/server.json`（VLESS 明文，`0.0.0.0:10443`）；
2. 宿主：`python -m http.server 8000 --bind 0.0.0.0 --directory _toolchain/e15/www`；
3. 设备：装 HAP → `hdc install -r …`（**单独执行**，约 3 分钟；期间并行其它 hdc 命令会导致掉线）；
4. 观察 `hilog -x | grep 'E15'`（应用侧）与 `_toolchain/e15/server2.out.log`（服务端侧）。

> 自检代码（`E15_PROBE_ON_BOOT` / `E15_STEP2_ON_BOOT`）在得出结论后已删除，
> 只保留两个 native 探针 `m10HostProbe` / `m11SocksProbe` 供后续诊断复用。
