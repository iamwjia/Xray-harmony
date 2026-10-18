# platform/ — 平台适配层

- **唯一**允许直接 `import @ohos.*` 的 ArkTS 层（NAPI 例外：它是引擎装载通道）。
- 收口日志、文件、安全存储、网络、VPN 扩展等平台能力，向上暴露窄接口。
- 换平台实现只改本层；业务层不得出现平台细节（如 hilog、preferences）。
- 当前只有 `Logger`（hilog 包装）。后续按需加 `SecureStore`、`VpnBridge`、`NetworkMonitor`。
