import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * platform/Logger.ets — 日志出口（平台适配层）
 *
 * 职责：统一出口 + 内存环形缓冲 + 脱敏，供「运行日志」页面查看与导出（FR-23）。
 * 边界：**不做业务判断**，不在这里决定"要不要记"，只负责记录与过滤。
 *
 * 三条设计取舍：
 *   1. **只写 hilog + 内存缓冲，不做持续落盘**：每条日志同步写文件在 UI 线程上是
 *      性能陷阱（一次连接会打几十条）。导出时才生成文件，用户拿到的是当前缓冲快照。
 *   2. **缓冲有上限（500 条）**：不设上限等于把内存泄漏写在脸上。
 *   3. **进缓冲前就脱敏**：日志页会被用户截图发出去，缓冲内容必须事先处理过，
 *      不能依赖"导出时再脱敏"——那样截图就漏了。
 */

export enum LogLevel {
  DEBUG = 'DEBUG',
  INFO = 'INFO',
  WARN = 'WARN',
  ERROR = 'ERROR'
}

/** 一条日志（UI 只读） */
export class LogEntry {
  time: string = '';
  level: string = '';
  msg: string = '';
}

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_APP';
const MAX_ENTRIES: number = 500;

export class Logger {
  private static entries: LogEntry[] = [];
  /** 低于该级别的日志：只进 hilog，不进缓冲（避免 DEBUG 淹没有用信息） */
  private static minLevel: string = LogLevel.INFO;

  /** 由设置页调用；非法值回落 INFO */
  static setMinLevel(level: string): void {
    if (level === LogLevel.DEBUG || level === LogLevel.INFO ||
      level === LogLevel.WARN || level === LogLevel.ERROR) {
      Logger.minLevel = level;
    } else {
      Logger.minLevel = LogLevel.INFO;
    }
  }

  static getMinLevel(): string {
    return Logger.minLevel;
  }

  static info(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', msg);
    Logger.push(LogLevel.INFO, msg);
  }

  static warn(msg: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', msg);
    Logger.push(LogLevel.WARN, msg);
  }

  static error(msg: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', msg);
    Logger.push(LogLevel.ERROR, msg);
  }

  static debug(msg: string): void {
    hilog.debug(DOMAIN, TAG, '%{public}s', msg);
    Logger.push(LogLevel.DEBUG, msg);
  }

  /**
   * 记录**可能含敏感内容**的文本（内核原始错误、第三方响应等）。
   * 用 `%{private}s`：hilog 默认只显示 `<private>`，只有打开隐私日志能力时才展开。
   */
  static sensitiveError(msg: string): void {
    hilog.error(DOMAIN, TAG, '%{private}s', msg);
    Logger.push(LogLevel.ERROR, msg);
  }

  static sensitiveInfo(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{private}s', msg);
    Logger.push(LogLevel.INFO, msg);
  }

  /** 当前缓冲快照（副本，避免调用方改到内部数组） */
  static getEntries(): LogEntry[] {
    return Logger.entries.slice();
  }

  static clear(): void {
    Logger.entries = [];
  }

  private static rank(level: string): number {
    if (level === LogLevel.DEBUG) {
      return 0;
    }
    if (level === LogLevel.INFO) {
      return 1;
    }
    if (level === LogLevel.WARN) {
      return 2;
    }
    return 3;
  }

  private static push(level: string, raw: string): void {
    if (Logger.rank(level) < Logger.rank(Logger.minLevel)) {
      return;
    }
    const e = new LogEntry();
    e.time = Logger.stamp();
    e.level = level;
    // 进缓冲前先脱敏：截图和导出都可能把内容带出去
    e.msg = Logger.redact(raw);
    Logger.entries.push(e);
    if (Logger.entries.length > MAX_ENTRIES) {
      // 超限丢最旧的：保留最近现场比保留完整历史更有用
      Logger.entries.splice(0, Logger.entries.length - MAX_ENTRIES);
    }
  }

  private static stamp(): string {
    const d = new Date();
    const p2 = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    const p3 = (n: number): string => n < 10 ? `00${n}` : (n < 100 ? `0${n}` : `${n}`);
    return `${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}.${p3(d.getMilliseconds())}`;
  }

  /**
   * 脱敏。日志会被用户截图发到群里，默认必须"看不出服务器和凭据"。
   * 处理三类：UUID/密钥形态、分享链接、形如 "password":"..." 的字段。
   */
  static redact(text: string): string {
    let s: string = text;
    // ① UUID
    s = s.replace(
      /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g,
      '****-****-****');
    // ② 分享链接：保留协议名，其余打掉（链接里必然含凭据与服务器地址）
    s = s.replace(/(vless|vmess|trojan|ss):\/\/[^\s"']+/gi, '$1://****');
    // ③ 键值形态的凭据
    s = s.replace(/("?(?:password|passwd|pwd|token|secret|uuid|publicKey|pbk)"?\s*[:=]\s*)"[^"]*"/gi,
      '$1"****"');
    // ④ 节点地址（`protocol@host:port` 是我们自己的日志格式）：
    //    服务器地址属于用户隐私——一张截图就可能暴露他在用哪台机器，所以一并打掉。
    s = s.replace(/@[0-9a-zA-Z.\-]+:\d+/g, '@****');
    // ⑤ 裸 IPv4（含内核错误里回显的地址）
    s = s.replace(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g, '****');
    return s;
  }

  /** 生成导出文本（不含 hilog 前缀，便于用户直接贴出来） */
  static buildReport(): string {
    const lines: string[] = [];
    lines.push('# Tunnelix 运行日志');
    lines.push(`生成时间：${new Date().toISOString()}`);
    lines.push(`日志级别下限：${Logger.minLevel}`);
    lines.push(`条目数：${Logger.entries.length}（上限 ${MAX_ENTRIES}）`);
    lines.push('# 说明：UUID、分享链接、password/token 等字段已脱敏为 ****');
    lines.push('');
    for (let i = 0; i < Logger.entries.length; i++) {
      const e: LogEntry = Logger.entries[i];
      lines.push(`${e.time} [${e.level}] ${e.msg}`);
    }
    return lines.join('\n');
  }
}
