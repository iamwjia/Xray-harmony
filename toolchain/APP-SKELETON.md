# APP-SKELETON：从 PoC 探针到可发育的 App 骨架

> 任务：E13｜作者：solution-architect｜日期：2026-10-18
> 目标：把首页的 4 个测试按钮换成**真实 App 的第一版骨架**，按 `doc/design.md` 四层架构落目录；
> 判据不是"功能完整"，而是**结构正确**——以后每加一个功能都知道该放哪层。

---

## 1. 目录与职责（四层落地）

```
entry/src/main/ets/
├── pages/         UI 层：只展示与交互，不写业务规则
│   ├── Index.ets      首页（连接开关 + 当前节点 + 连接状态）
│   ├── Nodes.ets      节点列表（本地假数据 + 选中切换）
│   ├── Settings.ets   设置（日志级别 / 关于）
│   └── DevPanel.ets   开发者面板（原 PoC 探针 M2/M3/M4/M5/M6/M7/M8，全部保留）
├── viewmodel/     状态机与 UI 投影：状态单向派生，禁止 UI 自置位
│   └── ConnectionViewModel.ets
├── model/         配置域模型（L-A）：唯一可编辑真源 + schema 版本 + 序列化
│   └── AppConfig.ets
├── service/       应用服务层：用例编排（配置读写、将来的内核驱动/订阅）
│   └── ConfigService.ets
└── platform/      平台适配层：唯一允许直接 import @ohos.* 的 ArkTS 层
    └── Logger.ets
```

每个目录都有 `README.md` 写明「职责 / 边界 / 不该放什么」。

## 2. 数据流（单向）

```
用户操作
  → pages（只发意图）
      → viewmodel（状态机：合法迁移 + deriveView）
      → service（用例：读/写 L-A、将来生成 L-B 内核配置）
          → model（L-A 数据）
          → platform（日志 / 存储 / 网络 / VPN）
```

关键约束：
- **UI 只读 `deriveView()`**，不自己判断"看起来连上了"（对应 `FR-13`）；
- **状态只能由 `requestConnect / requestDisconnect / onKernelConnected / onKernelError` 改变**，非法迁移被拒绝并返回 false；
- **`model/` 不出现任何 `@ohos.*` 与内核 JSON 字段**（L-B 由 service 生成，不落盘、不回写，见 design §4.7）。

## 3. 状态机（占位实现）

| 状态 | 允许迁移到 | 说明 |
|---|---|---|
| `DISCONNECTED` | `CONNECTING` | 初始态 |
| `CONNECTING` | `CONNECTED` / `ERROR` / `DISCONNECTED` | 用户可取消 |
| `CONNECTED` | `DISCONNECTED` / `ERROR` | — |
| `ERROR` | `DISCONNECTED` / `CONNECTING` | 展示 `lastError` |

**占位说明（必须知道）**：当前 `requestConnect()` 只做迁移，0.8s 后由页面内的 `setTimeout` 调用 `onKernelConnected()` **模拟**服务回报。
真实实现里这个回调必须来自 `service/KernelService`（`runXrayFromJson` 返回 + `getXrayState` 确认 + 用户态健康探测），页面里那段 `setTimeout` 要删掉。
**保留它的唯一理由**：让骨架能演示状态流转；它由 UI 触发"模拟回调"，形式上仍是「服务回报 → 状态改变」，不是 UI 直接置位。

## 4. 本次实测（模拟器，x86_64）

| 项 | 结果 |
|---|---|
| 构建 | `BUILD OK abi=x86_64 hap=15,895,448 bytes build=11s`（arm64 默认配置同样通过，见下） |
| 首页渲染 | `未连接 / state=DISCONNECTED / 当前节点：示例节点 A（占位）` |
| 点「连接」 | `已连接 / state=CONNECTED`（经 `CONNECTING` 迁移，非直接置位） |
| 节点页 | 3 条假数据渲染，`已选中` 标记正确 |
| 选节点 B → 返回 | 首页显示 `示例节点 B（占位）`，状态仍为 `CONNECTED`（跨页面保留） |
| 设置页 | 日志级别四项 + 关于信息正常 |
| 开发者面板 | M2/M3/M4/M5/M6/M7/M8 按钮与结果区完整保留 |

## 5. 下一步（按优先级）

1. **`service/KernelService`**：把 `m8Invoke` 包装成类型化接口（`start(config)` / `stop()` / `state()`），由它回调 viewmodel，**删掉页面里的 `setTimeout` 模拟**；
2. **`service/KernelConfigBuilder`**：L-A → L-B（内核 JSON）的纯函数生成器（design §4.4），并为它写「同输入同输出」的测试；
3. **持久化**：`platform/SecureStore`（ASSET）+ `RDB` 落地 L-A，`ConfigService` 改为从存储加载；
4. **凭据引用**：`XrayNode.credentialRef` 已预留，接安全存储后填实，**明文不进 model**；
5. **连接状态接线**：`onKernelConnected` 只能由「内核 running + 用户态探测」驱动（design §3.7 两维状态）。

## 6. 已知缺口（明确不做，避免误读）

| 缺口 | 原因 |
|---|---|
| 无真实连接 | 未接 tun/VpnExtension，属真机阶段 |
| 无订阅网络请求 | 按任务约束不引入 |
| 无持久化 | 仅内存单例；重启即回到默认假数据 |
| 无分应用/DNS/路由 UI | 属后续迭代，模型已预留 `rules/settings` |
| 无国际化/无障碍 | V1 范围 |
| M4 探针保留但默认不自动执行 | 真机上每次启动都会弹 VPN 授权，会被当成 bug |
