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

export class KernelService {
  private static instance: KernelService | null = null;

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

  /** 把内核错误文本转成人话；**原文始终进日志** */
  private humanize(rawErr: string): string {
    const e: string = rawErr.length > 0 ? rawErr : '(empty error)';
    Logger.error(`kernel raw error: ${e}`);
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
    return `内核错误：${e}`;
  }

  /** 探针：内核是否在运行（唯一可信的状态来源） */
  private queryRunning(): boolean {
    const resp = this.parse(this.invoke('getXrayState', '{}'));
    if (resp.success === true && resp.data !== null && resp.data !== undefined) {
      return resp.data.running === true;
    }
    return false;
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
  async start(configJson: string, timeoutMs: number = 8000): Promise<void> {
    const effectiveConfig: string = this.debugInvalidConfig ? '{"this_is":"not a valid xray config"' : configJson;
    const payload: string = JSON.stringify({ configJSON: effectiveConfig } as RunPayload);
    Logger.info(`KernelService.start bytes=${effectiveConfig.length}`);

    const raw: string = this.invoke('runXrayFromJson', payload);
    const resp = this.parse(raw);
    if (resp.success !== true) {
      throw new KernelError(this.humanize(resp.error === undefined ? '' : resp.error), raw);
    }
    // start 成功 ≠ 真在跑：必须以 getXrayState 为准
    await this.waitUntil(() => this.queryRunning(), timeoutMs, 250, '内核启动超时（未进入 running 状态）');
    Logger.info('KernelService.start confirmed running=true');
  }

  /** 停止内核并确认已停 */
  async stop(timeoutMs: number = 5000): Promise<void> {
    const raw: string = this.invoke('stopXray', '{}');
    const resp = this.parse(raw);
    if (resp.success !== true) {
      throw new KernelError(this.humanize(resp.error === undefined ? '' : resp.error), raw);
    }
    await this.waitUntil(() => !this.queryRunning(), timeoutMs, 200, '内核停止超时（仍处于 running）');
    Logger.info('KernelService.stop confirmed running=false');
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
