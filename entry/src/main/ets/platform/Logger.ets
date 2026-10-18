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
}
