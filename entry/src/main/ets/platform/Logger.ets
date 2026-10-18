import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * platform/Logger.ets — 日志出口（平台适配层）
 *
 * 职责：把 hilog 包成统一入口，后续换实现（分级过滤 / 落盘 / 脱敏）只改这里。
 * 边界：**不做业务判断**，不在这里决定"要不要记"，只负责输出。
 */
const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_APP';

export class Logger {
  static info(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', msg);
  }

  static warn(msg: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', msg);
  }

  static error(msg: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', msg);
  }

  /**
   * 记录**可能含敏感内容**的文本（内核原始错误、第三方响应等）。
   *
   * 用 `%{private}s`：hilog 默认只显示 `<private>`，只有打开隐私日志能力时才展开。
   * 这类文本的来源不可控——内核报错可能回显配置片段，第三方响应可能带 token，
   * 用 public 打出去等于把它们永久写进设备日志。
   */
  static sensitiveError(msg: string): void {
    hilog.error(DOMAIN, TAG, '%{private}s', msg);
  }

  static sensitiveInfo(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{private}s', msg);
  }
}
