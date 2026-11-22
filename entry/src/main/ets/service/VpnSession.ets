import { Want } from '@kit.AbilityKit';
import { Logger } from '../platform/Logger';

/**
 * 一次 VPN 会话的启动参数（跨进程传递用）。
 *
 * 为什么需要它：内核要从 UI 进程搬到 VPN 扩展进程，而 `startVpnExtensionAbility` 是
 * 唯一能把参数带进扩展的通道。所以会话参数必须能序列化进 `Want.parameters`。
 *
 * 传递内容的选择：
 *   - **内核配置整串**（含路由规则）由 UI 进程生成后传过来。这样"配置怎么写"只有一处，
 *     不会出现两个进程各自拼一份、规则悄悄不一致；
 *   - **SOCKS 端口与口令**也要传：扩展进程要用它把转发层指向本地入站；
 *   - **凭据不单独传**：它已经在配置串里，且配置串只在进程内存与 Want 参数中流转，
 *     不落盘（内核配置本来就是生成物，见三层真源约定）。
 */
export class VpnSession {
  /** 内核配置 JSON（L-B 生成物） */
  configJson: string = '';
  /** 本地 SOCKS 入站端口（转发层要连它） */
  socksPort: number = 0;
  socksUser: string = '';
  socksPass: string = '';
  /** 路由模式，仅用于日志与状态展示 */
  routingMode: string = '';

  static readonly PARAM_SESSION: string = 'tunnelix.session';

  /** 打包成 Want.parameters 里的单个字符串参数（避免多键拼装出错） */
  toParameters(): Record<string, Object> {
    const payload: SessionPayload = {
      configJson: this.configJson,
      socksPort: this.socksPort,
      socksUser: this.socksUser,
      socksPass: this.socksPass,
      routingMode: this.routingMode
    };
    const params: Record<string, Object> = {};
    params[VpnSession.PARAM_SESSION] = JSON.stringify(payload);
    return params;
  }

  /** 从 Want 还原；缺失或损坏返回 null，调用方必须据此拒绝启动而不是猜默认值 */
  static fromWant(want: Want): VpnSession | null {
    if (want.parameters === undefined) {
      return null;
    }
    const raw: Object | undefined = want.parameters[VpnSession.PARAM_SESSION];
    if (raw === undefined || typeof raw !== 'string') {
      Logger.error('vpn session param missing or not a string');
      return null;
    }
    try {
      const p: SessionPayload = JSON.parse(raw as string) as SessionPayload;
      if (p === null || p.configJson === undefined || p.configJson.length === 0) {
        Logger.error('vpn session payload malformed');
        return null;
      }
      const s = new VpnSession();
      s.configJson = p.configJson;
      s.socksPort = p.socksPort === undefined ? 0 : p.socksPort;
      s.socksUser = p.socksUser === undefined ? '' : p.socksUser;
      s.socksPass = p.socksPass === undefined ? '' : p.socksPass;
      s.routingMode = p.routingMode === undefined ? '' : p.routingMode;
      return s;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`vpn session payload unparsable: ${msg}`);
      return null;
    }
  }

  /** 只记录可安全外显的字段：口令与配置内容不进日志 */
  describe(): string {
    return `socksPort=${this.socksPort} routing=${this.routingMode} configBytes=${this.configJson.length}`;
  }
}

interface SessionPayload {
  configJson: string;
  socksPort?: number;
  socksUser?: string;
  socksPass?: string;
  routingMode?: string;
}
