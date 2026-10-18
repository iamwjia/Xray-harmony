# service/ — 应用服务层

- 承载用例：配置读写、节点选择、后续的「生成内核配置 / 启动内核 / 订阅更新」。
- 依赖 `model/` 与 `platform/`，**不依赖 UI**（页面通过 viewmodel 间接使用）。
- 本层是把「用户意图」翻译成「平台动作」的地方；内核 JSON 只在这里生成。
- 当前只有 `ConfigService`（内存单例 + 假数据）。持久化、内核驱动均未实现，见 `toolchain/APP-SKELETON.md`。
