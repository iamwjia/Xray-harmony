import { Logger } from '../platform/Logger';
import nativeEntry from 'libentry.so';

/**
 * service/Forwarding.ets — 把 tun fd 交给转发层
 *
 * 边界（改代码前先读）：
 *   1. **必须在扩展进程调用**：tun fd 只在创建它的进程里有效；
 *   2. 调用顺序固定：内核准好 → 建 tun → 启动转发 → 销毁时先停转发再销毁 tun。
 *      反过来先关 tun，转发层会读到一个已关闭的 fd；
 *   3. socksUrl 里带本次轮换的口令，**绝不进日志**。
 */

/** 启动结果：ok=false 时 error 是给人看的原因 */
export class ForwardingResult {
  ok: boolean = false;
  error: string = '';
}

interface NativeForwardingResp {
  success?: boolean;
  error?: string;
}

export class Forwarding {
  private static running: boolean = false;

  static isRunning(): boolean {
    return Forwarding.running;
  }

  /**
   * 启动转发。
   * @param tunFd  扩展进程刚创建的 tun fd
   * @param socksUser / socksPass 本次轮换的 SOCKS 凭据
   * @param socksPort 本地 SOCKS 端口
   */
  static start(tunFd: number, socksPort: number, socksUser: string, socksPass: string): ForwardingResult {
    const res = new ForwardingResult();
    const url: string = Forwarding.socksUrl(socksPort, socksUser, socksPass);
    let raw: string = '';
    try {
      raw = nativeEntry.startForwarding(tunFd, url);
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      res.error = `native 调用失败：${m}`;
      Logger.error(`forwarding start threw: ${m}`);
      return res;
    }
    const parsed: NativeForwardingResp = Forwarding.parse(raw);
    if (parsed.success === true) {
      Forwarding.running = true;
      // 只记端口与 fd，不记 url（含口令）
      Logger.info(`forwarding started fd=${tunFd} socksPort=${socksPort}`);
      res.ok = true;
      return res;
    }
    res.error = parsed.error === undefined || parsed.error.length === 0 ? '未知错误' : parsed.error;
    Logger.error(`forwarding start failed: ${res.error}`);
    return res;
  }

  static stop(): void {
    if (!Forwarding.running) {
      return;
    }
    try {
      nativeEntry.stopForwarding();
      Logger.info('forwarding stopped');
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      Logger.warn(`forwarding stop threw: ${m}`);
    }
    Forwarding.running = false;
  }

  /** socks5://user:pass@127.0.0.1:port；无口令时降级为 noauth 形式 */
  private static socksUrl(port: number, user: string, pass: string): string {
    const host: string = `127.0.0.1:${port}`;
    if (user.length === 0 && pass.length === 0) {
      return `socks5://${host}`;
    }
    return `socks5://${user}:${pass}@${host}`;
  }

  private static parse(raw: string): NativeForwardingResp {
    try {
      return JSON.parse(raw) as NativeForwardingResp;
    } catch (e) {
      const resp: NativeForwardingResp = {};
      resp.success = false;
      resp.error = `返回内容无法解析：${raw.substring(0, 80)}`;
      return resp;
    }
  }
}
