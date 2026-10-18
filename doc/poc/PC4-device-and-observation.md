# PC4 · 真机执行前置与观测方法包

> 归属：PC4（真机执行侧工具化）· 作者：harmony-platform-analyst · 2026-10-18
> 定位：**拿来就能用**的执行手册。本文不重做平台调研（结论见 `research/harmony-platform-constraints.md` v1.11），只把 K1 §6 的四条纪律与各实验共用的观测手段落成可复制的命令与判定规则。
> 标注约定：**【待真机验证】**= 命令/路径未在真机上确认；**【官方原文】**= 有官方文档依据；其余为工程实践建议。

---

## 0. 四条纪律 → 操作卡（全实验通用，逐条可执行）

| 纪律 | 操作（可直接复制） | 不做会怎样 |
|---|---|---|
| **P1 先证明跑的是新代码** | 见 §2.1「冷启动标准循环」：`clean assembleHap` → `install` → `aa force-stop` → `hilog -r` → `aa start` | 只 clean 不 force-stop → 安装后旧进程仍在内存，跑到旧代码/旧 `VpnConfig`，制造"改了没生效但日志正常"的假象 |
| **P2 先证明判据本身对** | **禁止**用 `/proc/net/route`、`/proc/net/ipv6_route` 判断 VPN 是否接管；改用 §4 出口 IP 归属判定（分协议 + 只比归属） | VPN 路由在**独立策略路由表**，主表看不到是正常的；v4 的 `0.0.0.0/0` 同样不在主表却能走代理 → 用主表判断会把"已接管"判成"未接管" |
| **P3 设备档位是必填字段** | 每张实验卡先跑 §7.1 设备信息采集，填 §7.2 模板；缺档位设备的项标 `阻塞：缺设备` | 老机型上跑"新档位能力"→ 不是漏测，是**从来测不到**；结论会被误读为"平台不支持" |
| **P4 `VpnConfig` 变更会重建连接** | 任何改动（分应用名单 / 白名单↔黑名单 / `bypass` 翻转 / `dnsAddresses` / `routes`）后**必须重新走 §2.1 冷启动循环**再采集数据 | 在"重建中"的窗口采样 → 判定抖动数据；且重建期间的失败会被误判为"配置错误" |

---

## 1. 环境准备清单

### 1.1 工具与版本

| 项 | 要求 | 校验命令 | 说明 |
|---|---|---|---|
| DevEco Studio | **6.1.x Release**（对应 API 23/24 SDK） | 关于页面 / `hvigorw -v` | 与主稿 API 基线一致；若需 API 26 beta 能力另装 beta 工具链 |
| HarmonyOS SDK | 与 DevEco 同版本；`compatibleSdkVersion=12`、`targetSdkVersion` 跟随最新 Release | `hvigorw -v`、`build-profile.json5` | 见 `research/harmony-platform-constraints.md` §1.1 |
| NDK（native） | 随 SDK 安装（`sdk/default/openharmony/native`） | `llvm-readelf -d libxxx.so` 能用 | 交叉编译 `--target=aarch64-linux-ohos` |
| hdc | 与 SDK 同包（`toolchains/hdc.exe`） | `hdc -v` | **不同版本 hdc 与设备不匹配时会出现连上但 shell 无返回** |
| 签名 | 调试证书 + 调试 Profile，**真机 UDID 需绑定**（调试设备上限 100 台【待核实】） | AGC「证书、APP ID 和 Profile」 | 未绑定的设备装不上；错误信息通常是签名校验失败 |
| 节点 | 至少 1 个 **VLESS/TLS 或 VMess** 节点；**建议同时具备 v4 与 v6 双栈出口** | 用 PC 侧客户端先行验证可用 | 节点不可用会污染所有判定（先证节点通，再证客户端通） |
| 网络环境 | 可切换 **仅 v4** / **双栈** / **仅 v6**（Wi-Fi 与蜂窝至少各一种） | §2.6 | IPv6 相关实验（E14/E20/P-23）必须有 v6 环境 |

### 1.2 设备清单（按实验需要）

| 档位 | 用途 | 典型现象（老机型/新机型差异） |
|---|---|---|
| **API 12~14 设备**（NEXT 5.0） | 基线实验：tun 建立、fd 读写、分应用（≤64）、IPv6 默认漏 | `generateVpnId`/`protectProcessNet`/`onAuthorizationResult` **方法不存在**（`undefined`/`TypeError`） |
| **API 20+ 设备**（6.0） | 多 VPN（`generateVpnId`）、`destroy(vpnId)` | 老设备上调用即抛错，误判为"多 VPN 不支持" |
| **API 22+ 设备** | `protectProcessNet`、`avPlaybackAndRecord`/`specialScenarioProcessing` 长时任务 | 老设备缺方法 |
| **API 23+ 设备**（6.1） | 分应用名单 **256** 上限（E21-b/E12）、`taskKeeping` 手机可用性 | 老设备上配 100 个可能报错/静默截断 → 会被误判为"平台只支持 64" |
| **支持应用分身/多用户的设备** | E22（分身/多用户匹配语义） | 不支持分身的机型上测不出该场景 |

> **纪律**：上表任一档位缺失时，对应实验项状态写 `阻塞：缺设备`，**不得写"待执行"**，也不得用模拟器替代（模拟器 `x86_64` 在 ABI、`BEARER_VPN` 承载、分身/多用户、长时任务冻结策略上均可能与真机不同）。

---

## 2. `hdc` 命令速查表

> 全部为 **PC 侧命令**（Windows PowerShell / Git Bash 通用）。`<bundle>` 替换为实际包名（示例：`com.example.xrayharmony`）。

### 2.0 连接与设备确认

| 用途 | 命令 | 常见坑 |
|---|---|---|
| 列出设备 | `hdc list targets` | 显示 `Empty` = 未连接/未授权：重插 USB、设备侧信任弹窗、`hdc kill` 后重试 |
| 版本 | `hdc -v` | 与 SDK 不匹配时常见"能 list 不能 shell" |
| 进入交互 shell | `hdc shell` | 退出 `exit`；长命令建议用 `hdc shell "<cmd>"` 一次性执行 |
| 设备型号/版本 | 见 §7.1 | — |

### 2.1 冷启动标准循环（P1，每次改代码/改配置后必跑）

```powershell
# 1) 构建（不要用增量，确保产物是新的）
hvigorw --no-daemon clean assembleHap

# 2) 安装（覆盖安装；路径按实际产物调整）
hdc install -r .\entry\build\default\outputs\default\entry-default-signed.hap

# 3) 强制停止旧进程（关键：只 clean 不 force-stop 会跑到旧进程）
hdc shell aa force-stop com.example.xrayharmony

# 4) 确认进程已消失（输出为空 = 已停干净）
hdc shell "ps -ef | grep com.example.xrayharmony | grep -v grep"

# 5) 清空日志缓冲（让本轮日志从零开始）
hdc shell hilog -r

# 6) 冷启动
hdc shell aa start -a EntryAbility -b com.example.xrayharmony

# 7) 实时看日志（另开一个终端窗口）
hdc hilog
```

**常见坑**
- 步骤 4 仍有输出 → 有残留进程（含 `VpnExtensionAbility` 独立进程），重复 `aa force-stop` 或用 §3 的 `kill`。
- 步骤 2 报 `failed to install` → 常见原因：签名/Profile 不含该设备 UDID、包名冲突、`hvigorw` 没跑成功（先看构建输出）。
- 步骤 6 拉起后界面空白 → 先看 `hdc hilog` 有无 `Error`，再看是否有崩溃（§2.4）。

### 2.2 包管理与版本核对

| 用途 | 命令 | 常见坑 |
|---|---|---|
| 卸载 | `hdc uninstall com.example.xrayharmony` | 卸载会**清空应用沙箱**（含 ASSET 凭据），需要"首次授权流程"的实验要重跑 |
| 安装 | `hdc install -r xxx.hap` | `-r` = 覆盖安装；不加 `-r` 可能因已存在而失败 |
| 查看已装信息 | `hdc shell bm dump -n com.example.xrayharmony` | 输出很长，先 `> dump.txt` 再本地搜 `versionName`/`apiVersion` |
| 查看调试签名/设备绑定 | AGC 控制台 | 设备 UDID 变更（换机）后必须重新生成 Profile |

### 2.3 进程观测（VPN 扩展是否独立存活）

| 用途 | 命令 | 说明 |
|---|---|---|
| 列出本应用进程 | `hdc shell "ps -ef \| grep com.example.xrayharmony \| grep -v grep"` | 会看到多个进程（主进程 + 扩展）；**记录 pid 与启动时间**，用于判断"是否被重启" |
| 查看进程树/父子关系 | `hdc shell "ps -ef \| grep -E 'xrayharmony\|vpn'"` | 【待真机验证】不同版本 `ps` 参数支持不同，必要时先 `hdc shell ps --help` |
| 观察某个 pid 是否稳定 | 连续执行上面命令并对比 pid | **pid 变化 = 进程被系统重启**（正是 P-07/E9 要抓的信号） |

### 2.4 日志与崩溃

| 用途 | 命令 | 常见坑 |
|---|---|---|
| 实时日志 | `hdc hilog` | 刷屏；配合 `grep` 或 tag 过滤 |
| 按 tag 过滤 | `hdc hilog -T XVPN` 【待真机验证：`-T` 参数在部分版本为 `-T <tag>`，先 `hdc shell hilog -h` 确认】 | tag 必须与代码里 `hilog.info(domain, TAG, ...)` 的 TAG 完全一致（大小写敏感） |
| 清空缓冲 | `hdc shell hilog -r` | 采集前必做，否则混入上一轮日志 |
| 提高缓冲（长时间跑） | `hdc shell hilog -G 16M` 【待真机验证】 | 8 小时实验建议先扩缓冲 |
| 崩溃栈（应用级） | `hdc file recv /data/log/faultlog/faultlogger .\faultlog` 【待真机验证：路径与权限】 | 无权限时先 `hdc shell ls /data/log/faultlog` 确认可读性 |
| 崩溃栈（临时） | `hdc file recv /data/log/faultlog/temp .\faultlog_tmp` 【待真机验证】 | 同上 |
| Native crash（C/C++/Go） | 同 faultlogger；文件内看 `SIGSEGV/SIGABRT` + 栈帧 | Go 崩溃常见 `SIGURG`/`fatal error: unexpected signal`，正是 PoC 要抓的形态 |

### 2.5 网络状态观测（**判据正确性关键**）

| 用途 | 命令 | 说明 |
|---|---|---|
| 接口与地址 | `hdc shell ifconfig` 或 `hdc shell ip addr` | tun 接口名固定为 **`vpn-tun`**（官方原文），出现即说明虚拟网卡已建 |
| 策略路由（**判断 VPN 是否接管的正解之一**） | `hdc shell ip rule` + `hdc shell ip route show table all` | VPN 路由在独立策略路由表；`ip rule` 里出现指向 vpn 表的规则才是证据 |
| **禁止** | `cat /proc/net/route`、`/proc/net/ipv6_route` | 主表不反映 VPN 接管，会误判（纪律 P2） |
| 连接与监听 | `hdc shell netstat -anp` 【待真机验证：部分版本无 netstat，可试 `ss -anp`】 | 用于看本地监听端口（形态 B）与目标连接 |
| 端到端出口判定 | 见 §4 | 唯一可信的"是否走代理"判据 |

### 2.6 网络环境切换（IPv6 相关实验必用）

| 目标环境 | 操作 | 校验 |
|---|---|---|
| 仅 v4 | 关闭 Wi-Fi 蜂窝数据；或在路由器/APN 侧关闭 v6 | §4 的 v6 请求应**解析/连接失败** |
| 双栈 | 开启 Wi-Fi（路由器下发 v6） | §4 的 v4/v6 均能出结果 |
| 仅 v6 | 【待真机验证】视网络环境而定（部分 APN 可设 v6-only） | 若无法构造 v6-only，则 E14/E20 的"v6 漏"判定改用 IPv6 目标可达性 |

### 2.7 文件与端口

| 用途 | 命令 | 说明 |
|---|---|---|
| 推文件到设备 | `hdc file send .\node.json /data/local/tmp/node.json` | 调试期把节点配置塞进设备（注意：**生产实现不得走此路径**） |
| 取设备文件 | `hdc file recv /data/local/tmp/dump.txt .\dump.txt` | 导出 `ps`/`ip rule` 输出做留档 |
| 端口转发（PC→设备） | `hdc fport tcp:18080 tcp:1080` | 形态 B 的 loopback 代理若监听 `1080`，可**从 PC 侧**直接验证（避免"应用内自测"的循环论证） |
| 反向转发（设备→PC） | `hdc rport tcp:1080 tcp:1080` 【待真机验证：hdc 版本支持情况】 | 需要设备侧访问 PC 服务时用 |

> **形态 B/loopback 的正确验证姿势**：用 `hdc fport` 从 PC 打设备端口，比"应用内自己连自己"更可信，因为后者可能走的是应用内直连而非监听端口。

---

## 3. 五档"死亡方式"操作卡（P-19 / P-25 / P-26 共用）

> K1 要求**五种死亡方式分开测、结论分开记录**。下表把每种方式的操作固定下来，保证不同人做出来的实验可比。

| # | 死亡方式 | 操作（可直接复制） | 可控性 | 注意 |
|---|---|---|---|---|
| D1 | 用户划掉任务卡 | 手动：最近任务 → 上滑划掉 | 中 | 无法脚本化，需人工计时；建议另一人负责 `hilog` 打点 |
| D2 | `kill` 主进程 | `hdc shell "ps -ef \| grep com.example.xrayharmony \| grep -v grep"` → 取 pid → `hdc shell kill -9 <pid>` | **高（推荐做主判据）** | `-9` 不可捕获；先确认杀的是主进程而非扩展进程 |
| D3 | 低内存回收 | 【待真机验证】构造内存压力（反复申请大内存的调试入口，或安装压力测试应用） | 低 | 触发时机不可控；记录"是否真的发生了回收"比记录结论更重要 |
| D4 | 息屏后台被杀 | 手动按电源键息屏 → 保持 30min / 2h → 亮屏检查 | 中 | 与长时任务档位强相关（E9 对照组：申请/不申请长时任务） |
| D5 | 崩溃 | **必须先在调试版内置"故意崩溃"隐藏入口**（ArkTS `throw` / C++ `abort()` / Go 侧 `panic`），入口触发即崩溃；再执行：`hdc shell aa force-stop` 前**不要**先停应用 → 触发崩溃 → 立即采集 faultlog（§2.4） | 高 | 崩溃路径**可能不走 `onDestroy`**，清理时机最不可控 → 不单列这一档，孤儿隧道会被判成"不存在"；本档必须独立记录结论，不得与 D2 合并 |

**统一记录格式（每档每次都记）**

| 字段 | 取值示例 |
|---|---|
| 死亡方式 | D2 / D5 |
| T0（终止时刻） | `hilog` 时间戳或 `hdc shell date +%s%3N` |
| 扩展进程是否存活 | `ps` 输出 pid / 已消失 |
| tun 是否消失 | `hdc shell ip addr` 是否还有 `vpn-tun` |
| 状态栏 VPN 图标 | 消失 / 仍在 |
| 首个"直连成功"时刻 T1 | §4 探测脚本的首次成功时间戳 |
| 泄漏窗口 W = T1 − T0 | 毫秒 |
| 对外出口归属变化 | 本地运营商 → 机房 / 未变 |

---

## 4. 出口 IP 判定（P2 纪律的落地）

### 4.1 为什么不能"看首页/看 IP 字符串"

- 双栈站会因 **Happy Eyeballs** 优先走 v6，看首页结果无法判断 v4 是否被接管。
- IP 字符串每次都不同（CDN/负载均衡），**比字符串必然误判**。
- 正解：**分协议端点 + 只比归属（ASN/组织）**。

### 4.2 端点

| 协议 | 端点 | 返回 |
|---|---|---|
| 仅 v4 | `https://api-ipv4.ip.sb/ip` | 纯文本 IPv4 |
| 仅 v6 | `https://api-ipv6.ip.sb/ip` | 纯文本 IPv6（无 v6 时**失败属预期**） |
| 归属信息 | `https://api.ip.sb/geoip`（JSON，含 `asn` / `organization` / `country`） | 用于取 ASN/组织 |

### 4.3 判定规则（**唯一判据**）

| 观测 | 判定 |
|---|---|
| v4 端点返回的归属 = **本地运营商** | **泄漏**（流量没走代理） |
| v4 端点返回的归属 = **机房/云服务商**（与节点同组织） | **已走代理** |
| v6 端点**失败**（DNS 无 AAAA 或连接超时） | **IPv6 未纳入**（符合 `isIPv6Accepted` 默认 false 的预期） |
| v6 端点成功且归属 = **本地运营商** | **v6 直连泄漏**（这正是"v4 阻断 / v6 通"的形态） |
| v6 端点成功且归属 = 机房 | v6 已纳入隧道 |

> **记录必须写"归属结论"，不要只贴 IP**。示例：`v4: ASN 4134(China Telecom) → 泄漏`、`v4: ASN 14061(DigitalOcean) → 走代理`。

### 4.4 避免 Happy Eyeballs 误判的三条硬规则

1. **强制单协议端点**：只打 `api-ipv4.ip.sb` / `api-ipv6.ip.sb`，**不要**打 `ip.sb` 首页或任何双栈端点。
2. **一次只测一个协议**：同一轮里只发起一种协议的请求（不要并发 v4+v6），否则 v6 成功会掩盖 v4 失败，反之亦然。
3. **每次测量前清连接缓存**：走 §2.1 冷启动循环 + 切换网络后重测；避免 DNS 缓存与连接复用导致的旧结果。

### 4.5 执行步骤（人工/脚本二选一）

**A. 应用内诊断页（推荐，最贴近真实路径）**
1. 诊断页放两个按钮：「测 v4 出口」「测 v6 出口」，分别请求对应端点并显示原始返回 + 归属解析结果；
2. 每次点击前提示"请确保 VPN 处于已连接状态"，并把结果写入 `hilog`（见 §6 的 `XVPN_IP`）；
3. 连测 3 次，取一致结果（防止单次抖动）。

**B. PC 侧间接验证（用于交叉核对）**
```powershell
# 若代理在设备上有本地监听端口，可用端口转发从 PC 侧验证
hdc fport tcp:18080 tcp:1080
# PC 侧走设备代理请求（示例：curl 走 socks5）
curl -4 --socks5-hostname 127.0.0.1:18080 https://api-ipv4.ip.sb/ip
curl -6 --socks5-hostname 127.0.0.1:18080 https://api-ipv6.ip.sb/ip
```
> 注意：此方法验证的是"代理端口可用"，**不等于"系统级 tun 已接管"**；tun 是否接管仍以 **设备内** 的协议端点结果为准。

### 4.6 常见误判与排错

| 现象 | 最可能原因 | 排查 |
|---|---|---|
| v4 与 v6 都返回本地运营商 | VPN 未接管 / tun 未建 / 路由未下发 | `hdc shell ip addr` 看 `vpn-tun`；`ip rule` 看规则；§6 的 `XVPN_TUN` 日志 |
| 只有 v6 返回本地运营商 | `isIPv6Accepted=false`（默认）→ v6 不进 tun | 这是**预期行为**，记录为"IPv6 未纳入" |
| 结果时好时坏 | 连接重建中（P4）/ 长时任务被取消 / 进程被重启 | 对齐 `hilog` 时间戳与 pid 变化 |
| 全部请求超时（含直连） | 代理自身流量被路由进 tun（protect 顺序错） | 见 §6 判定树 R5 |

---

## 5. 设备档位矩阵（P3 纪律的落地）

> **读表口径（先读这句再看表）**：**能报错的是「版位不足」，不报错只静默不同的是「语义不同」**——后者最容易把"测不到"判成"平台不支持"。
>
> 可推广到所有平台能力探测：**报错说明你撞到了边界，静默说明你根本没撞到**。因此本表「老机型会看到什么现象」一列，凡是写"不报错/静默"的行，都**不能靠运行时报错发现**，只能靠预先分配设备 + 受控失败对照（见 §8）来证伪。


| 能力 | 最低 API | 需要什么档位设备 | **老机型上会看到什么**（区分"不支持" vs "测不到"） |
|---|---|---|---|
| `VpnExtensionAbility` / `@ohos.net.vpnExtension` | **11**（商用 Release 12） | API 12+ 任意 | API <11 无该模块 → 编译期或运行期 `undefined` |
| `isBlocking` / `isIPv4Accepted` / `isIPv6Accepted` / `trustedApplications` | 11 | API 12+ | **不会报错**：字段能传、`create()` 正常返回，但新语义不生效（例如名单上限仍按 64、`isBlocking` 的边界行为不同）→ **现象是"静默不同"而非"报错"**，只能靠本表预先分配设备，不能靠运行时报错发现 |
| 分应用名单 **64** 上限 | 11 | API 12~22 | **无差异表现**（12~22 都按 64）；**超过 64 时**表现为 `create()` 报 `2200001` **或静默截断**（见 E21），且**日志里不会有任何提示** → 必须用 E21 的"第 N+1 个应用流量是否真走 VPN"来判定 |
| 分应用名单 **256** 上限 | **23** | API 23+ | **老机型配 100+ 个会报错或静默截断** → 千万别判成"平台只支持 64" |
| `generateVpnId()` / `destroy(vpnId)`（多 VPN） | **20** | API 20+ | 老机型 `generateVpnId is not a function` / `undefined` |
| `protectProcessNet()` | **22** | API 22+ | 同上 |
| `createVpnObserver()` / `onAuthorizationResult()` | **26.0.0** | API 26+（beta 线） | 老机型无此方法；**不得作为基线依赖** |
| 长时任务 `taskKeeping`（手机） | **21** | API 21+ 且具 `KEEP_BACKGROUND_RUNNING_SYSTEM`（ACL） | API<21：`BackgroundMode` 无该枚举 → 传字符串被忽略或返回参数错误；API≥21 但未获 ACL → 申请直接失败（权限校验），**日志里是权限错误不是"不支持"** |
| 长时任务 `voip` | 13 | API 13+ | API<13：枚举值 `undefined`，传字符串 → `startBackgroundRunning` 返回参数错误 |
| 长时任务 `avPlaybackAndRecord` / `specialScenarioProcessing` | 22 | API 22+ | API<22：枚举不存在（`undefined`）；传字符串 → 参数错误 |
| `NetBearType.BEARER_VPN` / `netCapabilitiesChange` | **12** | API 12+ | API<12：`bearerTypes` 里永远不含 `BEARER_VPN`（枚举值缺失）→ **表现为"VPN 明明连着却感知不到"**，易误判为"状态感知不可用" |
| `connection.setAppHttpProxy` | 11 | API 12+ | API<11：方法不存在 → 调用即 `TypeError: not a function` |
| Native 子进程（`native_child_process.h`） | 12 | **仅 PC/2in1、Tablet** | 手机上返回 `NCP_ERR_NOT_SUPPORTED` → 不是 bug，是设备限制 |
| `childProcessManager.startChildProcess` | 11 | 仅 Tablet/PC/2in1 | 手机返回 `16000061` |
| `AppServiceExtensionAbility` | 20 | **仅 2in1** + ACL 企业权限 | 手机上不可用 |
| `bundleManager.getApplicationLabel` | 26.0.0 | API 26+ | 老机型不可用（且本身需 ACL，实务不可用） |
| `getBundleInfo(bundleName)` | 14 | 任意（但三方需 `GET_BUNDLE_INFO_PRIVILEGED`） | 权限不足 → `201 Permission denied` |

> **状态三分（K1 要求）**：`待执行` / `阻塞：缺设备` / `已完成`。**缺设备不是"待执行"**，两者混同会让进度看起来比实际好。

---

## 6. 建议的 hilog 观测点

### 6.1 建议 tag 与字段（统一命名，便于 grep 与事后分析）

| tag | 打印时机 | 必带字段 | 用途 |
|---|---|---|---|
| `XVPN_BOOT` | 应用/扩展启动 | `stage`、`pid`、`ability`、`apiLevel`、`mono` | 判断"跑的是新代码"（配合 P1 的构建号/时间戳） |
| `XVPN_NAPI` | NAPI 加载 native so | `soName`、`symbol`、`ret`、`errno` | so 是否加载成功（P1 类失败） |
| `XVPN_CORE` | 内核启停 | `coreVer`、`state`、`err` | 内核是否跑起来 |
| `XVPN_PROTECT` | 调 `protect(fd)` | `fd`、`ret`、`err` | **protect 是否在 create 之前**（顺序错会导致全超时） |
| `XVPN_TUN` | `create(VpnConfig)` 前后 | `tunFd`、`addr`、`mtu`、`dns`、`routeCnt`、`trustCnt`、`blockCnt`、`ipv6Accepted`、`blocking` | tun 是否建立、配置是否**真的**生效 |
| `XVPN_FLOW` | 数据面周期统计（每 5s） | `tunRd`、`tunWr`、`sockTx`、`sockRx`、`dropQ` | 4 个计数器组合定位"卡在哪一层" |
| `XVPN_DNS` | DNS 查询/应答 | `qname`、`qtype`、`src`（tun/lo/ext）、`ans`、`ms` | DNS 是否进 tun、是否泄漏到原网卡 |
| `XVPN_IP` | 出口判定 | `proto`(v4/v6)、`endpoint`、`ip`、`asn`、`org`、`verdict`(proxy/local/fail) | §4 判定的日志留痕 |
| `XVPN_LIFE` | 生命周期 | `evt`(onCreate/onDestroy/suspend/resume)、`reason` | 与 D1~D5 死亡方式对齐 |
| `XVPN_HEALTH` | 健康探测 | `fdWr`(ok/errno)、`hbRtt`、`state` | 一阶（fd 写）/二阶（心跳）判定 |
| `XVPN_CAP` | 承载态变化 | `bearer`（是否含 `BEARER_VPN`）、`netId` | 仅表示"系统承载"，**不等于隧道健康** |

**打印规范**：单行 `key=value` 用空格分隔（便于 `grep` + `awk`）；禁止打印订阅 URL/token/节点密码；时间统一用 `hilog` 自带时间戳（不要自己打本地时间，避免时区混乱）。

### 6.2 「连不上」判定树（按日志顺序自上而下，命中即停）

| 序号 | 现象 | 结论 | 下一步 |
|---|---|---|---|
| R0 | 无 `XVPN_BOOT` | 应用没起来 / 装的还是旧包 | 重跑 §2.1；核对 `bm dump` 的 `versionName` |
| R1 | 有 BOOT，无 `XVPN_NAPI` 成功 | **so 未加载**（ABI 不匹配 / 依赖缺失 / `SONAME` 问题） | `llvm-readelf -d` 查 `DT_NEEDED`；确认 `libs/arm64-v8a/` |
| R2 | NAPI 成功，无 `XVPN_CORE state=running` | **内核没跑**（Go runtime 初始化失败/崩溃） | 取 faultlog 看 `SIGSEGV/SIGABRT`；试 `GODEBUG=asyncpreemptoff=1` |
| R3 | CORE running，无 `XVPN_TUN tunFd=` | **tun 没起来**（`create()` 报错） | 看 `err`：`2203001`（用户类型）/`2203002`（已存在）/`2200001`（参数） |
| R4 | 有 tunFd，`XVPN_FLOW tunRd=0` 持续 | **没有流量进 tun**（路由/分应用名单/策略路由问题） | `ip rule`、`ip route show table all`；检查 `routes`、`trustedApplications` |
| R5 | tunRd>0 但 `sockTx` 不增 / 全部超时 | **代理自身出站被捞回**（protect 顺序错） | 确认 `XVPN_PROTECT ret=0` 在 `XVPN_TUN` **之前** |
| R6 | sockTx 正常但域名失败 | **DNS 失败** | `XVPN_DNS src=`：无记录=查询未进 tun（routes 未覆盖 DNS 网段）；`src=ext`=泄漏 |
| R7 | 一切正常但只有 v6 直连 | `isIPv6Accepted=false`（默认） | 预期行为，记录"IPv6 未纳入" |

### 6.3 采集命令模板

```powershell
# 清缓冲 → 冷启动 → 采集到文件（采集 60s 后 Ctrl+C）
hdc shell hilog -r
hdc shell aa force-stop com.example.xrayharmony
hdc shell aa start -a EntryAbility -b com.example.xrayharmony
hdc hilog | Select-String -Pattern "XVPN_" | Tee-Object -FilePath .\log_run01.txt
```

> 只要 `XVPN_` 前缀统一，就能一条命令捞全链路日志；**不要**用零散 tag（事后无法整体回放）。

---

## 7. 记录模板

### 7.1 设备信息采集（每条都先跑这段）

```powershell
hdc -v
hdc list targets
hdc shell param get const.product.model
hdc shell param get const.product.brand
hdc shell param get const.ohos.fullname
hdc shell param get const.ohos.apiversion
hdc shell param get const.build.characteristics
hdc shell param get const.product.software.version
```
> 【待真机验证】参数名以设备实际为准；任一返回空时可先 `hdc shell param get` 帮助或改用 `hdc shell "cat /system/build.prop"`（部分版本可读）。

### 7.2 实验记录表（**每行一次实验**，不要合并）

| 字段 | 填写要求 |
|---|---|
| 实验项 | 例如 `E9-A`（有长时任务）/ `E21-b`（65 项） |
| 日期时间 | `YYYY-MM-DD HH:mm` |
| 设备型号 / 品牌 | §7.1 输出 |
| 系统版本（`const.ohos.fullname`） | 例如 `HarmonyOS 6.1.0.xxx` |
| **API Level** | 数字（12 / 20 / 23 …） |
| **是否新档位设备** | 是 / 否（对照 §5 判断该实验项是否要求新档位） |
| 设备状态三分 | `已完成` / `待执行` / `阻塞：缺设备` |
| 构建标识 | commit / 构建时间 / `versionName`（证明跑的是新代码） |
| 节点 | 协议 + 出口归属（机房 ASN） |
| 网络环境 | 仅 v4 / 双栈 / 仅 v6（Wi-Fi / 蜂窝） |
| 长时任务 | 未申请 / `dataTransfer` / `taskKeeping` |
| 死亡方式（若适用） | D1~D5 |
| 观测值 | 关键日志行（原样粘贴）+ 计数器（`tunRd/tunWr/sockTx`）+ §4 归属结论 |
| 结论 | 一句话（可判定：通过 / 不通过 / 无法判定） |
| 异常与备注 | 崩溃栈路径、`ip rule` 输出文件路径 |
| 执行人 | — |

### 7.3 结论三态（禁止模糊表述）

- **通过**：给出判定依据的数字（如"泄漏窗口 P50=120ms / P95=340ms，样本 22"）。
- **不通过**：给出失败现象 + 命中的判定树编号（R1~R7）。
- **无法判定**：写清卡在哪（缺设备 / 缺 v6 环境 / 节点不可用），并**保留原始日志文件路径**。

> **纪律：「无法判定」必须写明缺什么，三选一并具体化**——`缺设备`（写明需要哪个 API 档位 / 是否支持应用分身）/ `缺环境`（写明需要仅 v6、还是双栈、还是可切网）/ `缺观测手段`（写明缺哪个信号，如"取不到 faultlog"）。
> **"无法判定"不是垃圾桶**：未写明缺失项的"无法判定"一律退回，重记为 `待执行`，避免把"没做"伪装成"做了但判不了"。


---

## 8. 常见坑清单（按出现频率排序）

1. **改了没生效**：只 `clean` 没 `aa force-stop` → 跑到旧进程（P1）。
2. **用主路由表判断 VPN**：`/proc/net/route` 看不到 VPN 属正常，误判为"未接管"（P2）。
3. **看双栈首页判断泄漏**：Happy Eyeballs 优先 v6，看首页必误判（§4.4）。
4. **老机型跑新档位实验**：不是漏测，是从来测不到；结论会被误读为平台不支持（P3）。
5. **重建窗口采样**：改 `VpnConfig` 后没等重建完成就采数，数据抖动（P4）。
6. **protect 与 create 顺序颠倒**：现象是"能连不能通"，极易误判为协议 bug（R5）。
7. **DNS 未进 tun**：`routes` 没覆盖 DNS 地址所在网段 → 域名全失败、IP 直连可用（R6）。
8. **应用内自测代替真实路径**：应用自己连自己的监听端口，可能走的是直连逻辑（§2.7）。
9. **hilog 未清缓冲**：上一轮日志混入，看起来"每一步都成功"（§2.4）。
10. **模拟器跑真机项**：ABI/承载态/分身/长时任务策略均可能不同 → 一律不采信。

---

## 9. 【待真机验证】清单（用前先确认，别当事实）

| # | 待确认项 | 确认方式 |
|---|---|---|
| V1 | `hilog` 的 tag/级别过滤参数（`-T`/`-L`/`-G`）在当前版本的实际语义 | `hdc shell hilog -h` |
| V2 | faultlog 目录可读性与路径（`/data/log/faultlog/faultlogger`、`/temp`） | `hdc shell ls /data/log/faultlog` |
| V3 | `netstat` / `ss` 是否存在及其参数 | `hdc shell which netstat`；`hdc shell ss -h` |
| V4 | `hdc rport` 是否被当前 hdc 版本支持 | `hdc -h` 查子命令 |
| V5 | `ps` 的可用参数（`-ef` 是否被支持） | `hdc shell ps --help` |
| V6 | 设备参数名（`const.ohos.apiversion` 等）是否返回有效值 | §7.1 实跑 |
| V7 | 是否能构造"仅 v6"网络环境 | §2.6 |
| V8 | 低内存回收（D3）的可控触发方式 | 观察 `hilog` 是否有 lmkd/回收事件，记录真实触发条件 |

---

*本工具包与 `research/harmony-platform-constraints.md`（v1.11）同源：平台结论以该文为准，本文只负责"怎么在真机上把它测出来"。命令若与设备实际行为不符，以设备实测为准并回填 §9。*
