# PC18 — 转发接线（tun2socks）：代码就位，卡在 202

日期：2026-11-22
范围：`_toolchain/merged/main.go`、`entry/src/main/cpp/cgo_bridge.cpp`、`napi_init.cpp`、`service/Forwarding.ets`、`vpnability/VpnExtAbility.ets`、`toolchain/build-merged.ps1`

## 1. 做了什么

把 `tun fd` 交给 tun2socks，让设备侧流量真正进 SOCKS：

| 层 | 改动 |
| --- | --- |
| Go（合并库） | `StartTun2Socks(fd, "socks5://user:pass@127.0.0.1:port")` 真正实现：`engine.Insert(&Key{Device:"fd://N", Proxy:...})` + `engine.Start()`；新增 `StopTun2Socks()`；补 `CGoInvoke` / `CGoFree` 兼容别名 |
| C++（NAPI） | 新增 `startForwarding(fd, socksUrl)` / `stopForwarding()`，dlopen 合并库并 dlsym，返回 JSON（不靠异常传错误码） |
| ArkTS | 新增 `service/Forwarding.ets`：拼 socks URL、解析结果、**日志只记端口与 fd，不记 url**（含口令） |
| 扩展进程 | tun 建好后启动转发；**启动失败则销毁 tun 并把状态写成 error**——没人读的 tun 会把流量吞进黑洞；`shutdown()` 顺序改为「先停转发 → 再停内核 → 最后销毁 tun」 |

顺序这件事在代码注释里写死了：反过来先关 tun，转发层会读到一个已关闭的 fd。

## 2. 实测发现的真问题（这轮最有价值的部分）

部署合并库（`libmerged.so` 覆盖 `libs/<abi>/libxray.so`）后，扩展进程立刻报：

```
kernel raw error: dlsym: do_dlsym failed: Symbol not found: CGoFree, version: null
so=/data/storage/el1/bundle/libs/x86_64/libxray.so
```

原因：NAPI 桥接早就按 `CGoInvoke` / `CGoFree` 写死了 dlsym，而合并库只导出 `Invoke` / `FreeString`。

修法不是在 C++ 里加两套名字，而是在**库侧给兼容别名**（`CGoInvoke → Invoke`、`CGoFree → FreeString`），调用方一行不动。

修完后：

```
XVPN_EXT: kernel running in extension process
XVPN_EXT: bootstrap failed: code=202 msg=Non-system applications use system APIs
状态文件：{"state":"error","code":202,...}
```

**即：合并库可用、内核能在扩展进程起、状态回传能看到；卡点前移到 `conn.create()` 的 202。**

## 3. 结论：转发代码就位，但跑不到

`Forwarding.start()` 在 tun 创建成功之后才调用，而 202 正好在 `conn.create()` 上。所以：

- **本轮不能宣称"转发可用"**，只能宣称"转发已接线、编译通过、失败路径已处理"；
- 202 不解决，转发永远走不到执行点。这条与 `doc/risks-and-roadmap.md` 里的真机验证项是同一件事。

## 4. 部署注意（不写进仓库）

`libs/**/libxray.so` 与 `_toolchain/` 都在 `.gitignore` 里，所以**合并库不进仓库**。换机器/换 ABI 必须：

```
powershell -ExecutionPolicy Bypass -File .\toolchain\build-merged.ps1 -Arch arm64     # 或 x86_64
copy _toolchain\merged\build-<arch>\libmerged.so entry\src\main\libs\<abi>\libxray.so
```

漏了这一步的现象就是上面那条 `Symbol not found: CGoFree`——比"链接期报错"更难查，因为它在运行期。

## 5. 真机验证清单（等设备）

1. 装机，连一次，看状态文件是否 `running` 且 msg 为「内核、tun 与转发层均就绪」；
2. `adb shell` 侧访问任意外网域名，确认走代理（服务端 `connection opened` 才是判据，`accepted` 不算）；
3. 断开后确认：转发先停、tun 销毁、状态文件 `stopped`；
4. 失败注入：把 socks 端口改错，确认进入 `error` 且 **tun 已被销毁**（不残留黑洞）。
