/**
 * service/KernelConfigBuilder.ets — L-A → L-B（内核 JSON）生成器
 *
 * 职责：把「用户意图」翻译成 Xray 配置 JSON。**纯函数**：同一输入必得同一输出，
 *       便于灰度、回滚与问题复现（design §4.4）。
 *
 * 本任务（E14）范围：只生成「socks 入站 + freedom 出站」的最小配置，
 * 用于验证 UI → 内核的驱动链路。**节点接入另开任务**，届时只在这里把
 * freedom 出站替换为节点出站，UI 与状态机不需要改。
 *
 * 约束：
 *   - 生成物不落盘（design §4.7：L-B 是生成物，不回写）；
 *   - 这里**不读安全存储**，因此不含任何凭据。
 */

export class KernelConfigBuilder {
  /** 本地 SOCKS 端口：与 M8 探针验证过的配置保持一致 */
  static readonly DEFAULT_SOCKS_PORT: number = 18080;

  /**
   * 最小配置：socks 入站（noauth，仅回环）+ freedom 出站。
   * @param socksPort 本地监听端口
   */
  static buildMinimal(socksPort: number = KernelConfigBuilder.DEFAULT_SOCKS_PORT): string {
    const cfg: string = '{"log":{"loglevel":"warning"},' +
      '"inbounds":[{"tag":"socks-in","listen":"127.0.0.1","port":' + socksPort.toString() + ',' +
      '"protocol":"socks","settings":{"auth":"noauth","udp":false}}],' +
      '"outbounds":[{"tag":"direct","protocol":"freedom"}]}';
    return cfg;
  }
}
