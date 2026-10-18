# viewmodel/ — 状态机与 UI 投影

- 定义状态枚举与**合法迁移表**（`Disconnected / Connecting / Connected / Error`）。
- 对外只暴露两类方法：UI 意图（`requestConnect` / `requestDisconnect`）与服务回报（`onKernelConnected` / `onKernelError`）。
- `deriveView()` 把状态**单向派生**为展示信息（文案/颜色/忙碌），页面只读它。
- 禁止在 UI 里置位状态；禁止乐观置位（对应 `FR-13` 状态一致性）。
