import nativeEntry from 'libentry.so';
import { Logger } from '../platform/Logger';

/**
 * service/KernelService.ets — 内核驱动服务（应用服务层）
 *
 * 职责：把 native 的通用桥 `m8Invoke(method, payloadJSON)` 包成有类型的三个动作：
 *   - start(configJson)：runXrayFromJson
 *   - stop()：stopXray
 *   - probeState()：getXrayState
 *
 * 三条约束（本任务 E14 的核心）：
 *   1. **错误归一化**：内核返回的 `{"success":false,"error":"..."}` 必须转成人话再交给 UI，
 *      但**原始 error 必须进日志**（便于排查），不允许丢掉原文；
 *   2. **超时兜底**：启动 API 可能不 settle（FR-40），所有等待必须有上限，绝不无限挂起；
 *   3. **不猜状态**：连接成功与否以 `getXrayState.running` 为准，不以 `start()` 返回为准。
 */

/** native 桥返回里带 "[ms=N] " 前缀，先剥掉再解析 JSON */
function stripPrefix(raw: string): string {
  if (raw.startsWith('[')) {
    const idx: number = raw.indexOf('] ');
    if (idx > 0) {
      return raw.substring(idx + 2);
    }
  }
  return raw;
}

interface RawInvokeResp {
  success?: boolean;
  data?: RawStateData | null;
  error?: string;
}

interface RawStateData {
  running?: boolean;
}

interface RunPayload {
  configJSON: string;
}

export class KernelError extends Error {
  /** 原始错误文本（保留给日志/诊断，不直接展示给用户） */
  raw: string = '';

  constructor(humanMessage: string, raw: string) {
    super(humanMessage);
    this.raw = raw;
  }
}

/** 状态查询结果：把「查询失败」与「查到了但没在跑」分开，否则超时归因只能靠猜 */
export class KernelProbe {
  ok: boolean = false;
  running: boolean = false;
  error: string = '';
}

export class KernelService {
  private static instance: KernelService | null = null;

  /**
   * 超时上限（FR-40：启动/停止 API 可能不 settle，任何等待都必须有上限）。
   *
   * 8000ms 的依据：内核是**同进程加载 38MB .so**，模拟器实测冷启到 running 约 1~1.5s；
   * 给 6 倍余量以覆盖低端机首次解压与 IO 抖动，同时不超过 10s（超过这个长度用户会
   * 认为应用卡死，而不是"在连接"）。
   */
  static readonly CONNECT_TIMEOUT_MS: number = 8000;
  /** 停止通常远快于启动（只是关监听 + 退出 loop），5s 足够；超时说明内核已僵死 */
  static readonly DISCONNECT_TIMEOUT_MS: number = 5000;
  /** 轮询步长：250ms —— 比这更密是浪费 CPU，更疏会让用户感到"点了没反应" */
  static readonly PROBE_INTERVAL_MS: number = 250;

  /**
   * 单例：内核是**进程级单例资源**（一个进程只能跑一个实例）。
   * 若每个页面各自 new 一个，会出现"页面 A 启动了内核、页面 B 不知道"的双状态，
   * 调试注入（debugInjectInvalidConfig）也会失效——这是 E14 实测踩到的。
   */
  static getInstance(): KernelService {
    if (KernelService.instance === null) {
      KernelService.instance = new KernelService();
    }
    return KernelService.instance;
  }

  /** 调试注入：置位后 start() 使用非法配置，用于验证失败路径（TODO 删除） */
  private debugInvalidConfig: boolean = false;

  private invoke(method: string, payloadJson: string): string {
    return stripPrefix(nativeEntry.m8Invoke(method, payloadJson));
  }

  private parse(raw: string): RawInvokeResp {
    try {
      return JSON.parse(raw) as RawInvokeResp;
    } catch (e) {
      return { success: false, error: `unparsable response: ${raw}` } as RawInvokeResp;
    }
  }

  /**
   * 把内核错误文本转成人话；**原文只进私有日志**，不回显到 UI。
   *
   * 为什么不再把原文拼进 UI 文案：内核的解析错误常常带上配置片段，
   * 而配置里就有节点凭据——那等于把 UUID/密码显示在用户屏幕上。
   * 排查需要原文时看 hilog 的私有日志即可。
   */
  private humanize(rawErr: string): string {
    const e: string = rawErr.length > 0 ? rawErr : '(empty error)';
    Logger.sensitiveError(`kernel raw error: ${KernelService.truncate(e, 400)}`);
    if (e.indexOf('unknown method') >= 0) {
      return '内核不支持该操作（内核版本与桥接不匹配）';
    }
    if (e.indexOf('config') >= 0 || e.indexOf('Config') >= 0) {
      return '配置无效，内核拒绝启动';
    }
    if (e.indexOf('listen') >= 0 || e.indexOf('bind') >= 0 || e.indexOf('address already') >= 0) {
      return '端口被占用，无法监听本地代理端口';
    }
    if (e.indexOf('unparsable') >= 0) {
      return '内核返回无法解析的响应';
    }
    if (e === '(empty error)') {
      return '内核报告失败但未给出原因';
    }
    return '内核错误（详细原因已写入日志）';
  }

  /** 日志截断：避免一次异常把几十 KB 的配置全刷进日志 */
  private static truncate(v: string, max: number): string {
    return v.length <= max ? v : `${v.substring(0, max)}…(${v.length} chars)`;
  }

  /** 探针：内核是否在运行（唯一可信的状态来源） */
  private queryRunning(): boolean {
    const resp = this.parse(this.invoke('getXrayState', '{}'));
    if (resp.success === true && resp.data !== null && resp.data !== undefined) {
      return resp.data.running === true;
    }
    return false;
  }

  /**
   * 带归因的探针：把「查询本身失败」与「查到了但没在跑」分开。
   * 这两类在 UX 上完全不同（内核没响应 vs 内核启动了但没进 running），
   * 合成一个 boolean 就只能给用户一句含糊的"超时"。
   */
  private probe(): KernelProbe {
    const p = new KernelProbe();
    const raw: string = this.invoke('getXrayState', '{}');
    const resp = this.parse(raw);
    if (resp.success !== true) {
      p.ok = false;
      p.error = resp.error === undefined ? `unparsable: ${raw}` : resp.error;
      return p;
    }
    p.ok = true;
    p.running = resp.data !== null && resp.data !== undefined && resp.data.running === true;
    return p;
  }

  /** 带超时的等待：到点即失败，绝不无限等 */
  private async waitUntil(check: () => boolean, timeoutMs: number, stepMs: number, timeoutMsg: string): Promise<void> {
    const deadline: number = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (check()) {
        return;
      }
      await new Promise<void>((resolve) => {
        setTimeout(() => resolve(), stepMs);
      });
    }
    throw new KernelError(timeoutMsg, `waitUntil timeout after ${timeoutMs}ms`);
  }

  /** 启动内核并确认真的在跑；失败抛 KernelError（消息已人话化） */
  async start(configJson: string, timeoutMs: number = KernelService.CONNECT_TIMEOUT_MS): Promise<void> {
    const effectiveConfig: string = this.debugInvalidConfig ? '{"this_is":"not a valid xray config"' : configJson;
    const payload: string = JSON.stringify({ configJSON: effectiveConfig } as RunPayload);
    Logger.info(`KernelService.start bytes=${effectiveConfig.length}`);

    const raw: string = this.invoke('runXrayFromJson', payload);
    const resp = this.parse(raw);
    if (resp.success !== true) {
      throw new KernelError(this.humanize(resp.error === undefined ? '' : resp.error), raw);
    }

    // start 返回成功 ≠ 真在跑：必须以 getXrayState 为准
    const deadline: number = Date.now() + timeoutMs;
    let lastProbeError: string = '';
    while (Date.now() < deadline) {
      const p: KernelProbe = this.probe();
      if (p.ok && p.running) {
        Logger.info('KernelService.start confirmed running=true');
        return;
      }
      if (!p.ok) {
        lastProbeError = p.error;
      }
      await new Promise<void>((resolve) => {
        setTimeout(() => resolve(), KernelService.PROBE_INTERVAL_MS);
      });
    }

    // 超时归因：区分「内核没响应」与「内核在但没进 running」
    if (lastProbeError.length > 0) {
      Logger.error(`kernel probe failed during start: ${lastProbeError}`);
      throw new KernelError('内核未响应（启动后无法确认运行状态）', lastProbeError);
    }
    throw new KernelError(
      `内核已接收配置但 ${timeoutMs}ms 内未进入运行状态（可能启动即崩溃，详见日志）`,
      `running=false after ${timeoutMs}ms`);
  }

  /** 停止内核并确认已停 */
  async stop(timeoutMs: number = KernelService.DISCONNECT_TIMEOUT_MS): Promise<void> {
    const raw: string = this.invoke('stopXray', '{}');
    const resp = this.parse(raw);
    if (resp.success !== true) {
      throw new KernelError(this.humanize(resp.error === undefined ? '' : resp.error), raw);
    }
    await this.waitUntil(() => !this.queryRunning(), timeoutMs, KernelService.PROBE_INTERVAL_MS,
      `内核停止超时（${timeoutMs}ms 后仍处于 running）`);
    Logger.info('KernelService.stop confirmed running=false');
  }

  /**
   * 尽力收尾：连接失败/超时后调用，避免留下"半启动"内核（占着 18080，导致下次启动直接失败）。
   * **绝不抛异常**，也绝不让调用方等它——失败只记日志，因为此时用户已经在看错误文案了。
   */
  async bestEffortStop(): Promise<void> {
    try {
      if (!this.queryRunning()) {
        Logger.info('bestEffortStop: kernel not running, nothing to clean up');
        return;
      }
      Logger.warn('bestEffortStop: kernel still running after failure, stopping it');
      await this.stop(KernelService.DISCONNECT_TIMEOUT_MS);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`bestEffortStop failed (kernel may be wedged): ${msg}`);
    }
  }

  /** 供 UI 显示的当前真实状态 */
  isRunning(): boolean {
    return this.queryRunning();
  }

  /**
   * TODO(删除)：仅用于验证失败路径——置位后 start() 传入非法配置。
   * 删除条件：有真实可复现的失败场景（如节点不可达）后。
   */
  debugInjectInvalidConfig(): void {
    this.debugInvalidConfig = true;
    Logger.warn('debug: next start() will use an INVALID config to exercise the failure path');
  }

  clearDebugInjection(): void {
    this.debugInvalidConfig = false;
  }
}
