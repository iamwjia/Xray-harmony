# pages/ — UI 层

- 只做展示与用户交互，**不写业务规则**、不直接调平台 API（除路由/窗口）。
- 所有状态展示必须来自 `viewmodel/*ViewModel.deriveView()`，不得自行判断"看起来已连接"。
- 页面间跳转只用 `router`，页面不做数据持久化。
- 当前页面：`Index`（首页）、`Nodes`（节点列表）、`Settings`（设置）、`DevPanel`（PoC 探针，仅开发用）。
