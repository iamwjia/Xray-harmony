# PC17 — 扩展进程状态回传

日期：2026-11-22
范围：`platform/VpnStateFile.ets`、`vpnability/VpnExtAbility.ets`、`service/VpnController.waitForState()`、`pages/DevPanel.ets`

## 1. 问题

数据面在扩展进程，控制面在应用进程。**应用进程没有任何直接手段查询扩展进程里的内核状态**：

- 两个进程各有自己的 `KernelService` 单例，内核实例互不相通；
- `tun fd` 只在扩展进程有效，不可能跨进程查询；
- 于是 UI 说"已连接"时，可能扩展进程早就失败了——这就是"UI 状态说谎"。

## 2. 方案：沙箱状态文件

`filesDir/vpn_state.json`：

```json
{ "state": "starting|running|error|stopped", "code": 0, "msg": "...", "at": 1730000000000 }
```

为什么是文件而不是 CommonEvent / 内存共享：

- 同应用两进程共享 `filesDir`，**不需要新权限**；
- 不依赖事件总线是否真的跨进程（这点在模拟器上不容易验证）；
- 不需要把 fd、凭据、节点地址带出扩展进程——`msg` 里刻意不含这些。

代价是轮询：`VpnController.waitForState()` 在**正在连接**这个短窗口里 250ms 轮一次，拿到 `running`/`error` 立即停，不常驻定时器。

## 3. 谁写、谁读

| 时机 | 写什么 |
| --- | --- |
| 扩展进程 `onCreate` | `starting` |
| `onCreate` 发现会话参数缺失 | `error`（"会话参数缺失"） |
| `bootstrap()` 成功（内核 + tun 都就绪） | `running`（"转发层尚未接入"也写进 msg） |
| `bootstrap()` 抛错 | `error` + 系统错误码 |
| `onDestroy` 收尾完成 | `stopped` |

应用进程侧：`VpnStateFile.read()` + `isStale()`。

**过期判定是必须的**：扩展进程被系统杀掉时不会走 `onDestroy`，文件里会永远留着 `running`。所以 `running` 超过 15s 未刷新即视为过期，返回 `error(code=-1, "状态已过期")`。

## 4. 实测

**通道验证（设备侧用 `aa start ... --ps` 拉起扩展，绕过授权弹窗）**：

```
$ cat .../files/vpn_state.json
{"state":"error","code":202,"msg":"code=202 msg=Non-system applications use system APIs","at":1795331930776}
```

**应用进程读回（开发者面板「读取扩展进程回传状态」）**：

```
状态=error code=202 code=202 msg=Non-system applications use system APIs（9 秒前）
```

两条结论：

1. 状态通道打通：扩展进程写、应用进程读，不需要跨进程查询内核；
2. **202 这个阻塞项被再次确认**（`Non-system applications use system APIs`）——以前只能从 hilog 里看到，现在应用自己能看到并显示，这正是"排障线索不该只存在于开发者工具里"。

## 5. 边界

- 状态是**轮询**得到的，存在最坏 250ms 延迟；对 UI 无感，但它不是实时事件；
- 文件写入非原子（直接覆盖写）。最坏情况读到半截 JSON → 解析失败 → 返回 `null` → 调用方按"无状态"处理，不会误判为 running；
- 首页连接路径**仍是应用进程内核**（`KernelService.start`），切换数据面到扩展进程是下一步，不在本轮范围；
- `DevPanel` 里"启动 VpnExtensionAbility"按钮现在走带会话的路径（`probeVpnExt`），但 `startVpnExtensionAbility` 在模拟器上因授权弹窗不 settle，仍需 `aa start ... --ps` 验证。
