# PC19 — 数据面收敛到扩展进程（消除双内核）

日期：2026-11-22
范围：`service/VpnSessionFactory.ets`（新增）、`VpnController.stop()`、`pages/Index.ets`、`pages/DevPanel.ets`

## 1. 之前的问题

首页连接走的是**应用进程内核**（`KernelService.start`），而真正的数据面在**扩展进程**（`VpnExtAbility`）。两条路并行：

- 首页显示「已连接」时，应用进程确实有一个内核在跑，但**没有任何 tun**——用户看到的"连上了"与"流量是否走代理"无关；
- 开发者面板另有一套启动逻辑，两边配置各拼一份，一处改了另一处不知道；
- `tun fd` 只在扩展进程有效，应用进程那个内核永远拿不到它。

## 2. 改法

1. **会话只在一个地方组装**：新增 `VpnSessionFactory.build(cfg)`，首页与开发者面板都调它。
   以前两处各拼一份配置，本质上是在赌"两边不会分叉"。
2. **首页不再启动应用进程内核**：改为 `VpnController.start(...)` 请求扩展进程，然后**以状态文件为准**判断结果。
3. **断开改为请求扩展停止**：`VpnController.stop()` → `stopVpnExtensionAbility`，真正收尾（停转发 → 停内核 → 销 tun）在扩展进程的 `onDestroy`。
4. **不 await 启动调用**：首次连接会弹系统授权对话框，用户不点之前该 promise 不 settle，但扩展进程可能已经起来并写了状态。所以"启动成功"的判据是**状态文件**，不是调用是否返回。

## 3. 实测（模拟器）

```
session built: socksPort=36785 routing=rule configBytes=984
vpn start not settled within 15000ms (authorization dialog may be pending)
首页：连接异常 | 等待扩展进程响应超时 | 重试
```

关键证据：**整个过程中应用进程没有出现 `KernelService.start`**——首页确实不再自己起内核了。

首页从"假装已连接"变成"如实报超时"，这正是本次要修的东西。

## 4. 边界

- 模拟器上没有 VPN 授权弹窗组件，`startVpnExtensionAbility` 永不 settle，扩展进程也起不来，因此**"成功连接"这条路径本轮无法验证**（与 PC18 同一个 202/授权门）；
- 断开路径同理未实测；
- 真机验证时应看到：授权弹窗 → 允许 → 状态文件 `running` → 首页显示「已连接」+「系统 VPN：已接管」。
