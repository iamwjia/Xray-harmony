import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { Logger } from '../platform/Logger';
import { VpnSession } from './VpnSession';

/**
 * 主应用侧的 VPN 接管控制器。
 *
 * 只负责一件事：把 `startVpnExtensionAbility` 这步**包成有超时、有归因**的操作。
 *
 * 为什么必须有超时：首次连接会弹系统授权框，用户不点之前这个调用不会 settle。
 * 没有上限的话，UI 会永远停在"连接中"，而用户看到的是"应用卡死了"——这比直接报错更糟。
 *
 * 为什么不在这里做转发：tun fd 只存在于扩展进程，主应用拿不到。
 * 转发层必须跑在扩展进程里，见 vpnability/VpnExtAbility.ets 的说明。
 */
export class VpnController {
  /** 授权框等人点的时间上限；超时后必须给用户一个可理解的结论，而不是继续转圈 */
  static readonly START_TIMEOUT_MS: number = 15000;

  private static running: boolean = false;

  static isRequested(): boolean {
    return VpnController.running;
  }

  /**
   * 请求启动 VPN 扩展，并把本次会话参数带过去。
   * 成功返回 true；失败抛出带人话的 Error（原始 code 进日志）。
   */
  static async start(bundleName: string, abilityName: string, session: VpnSession,
    timeoutMs: number = VpnController.START_TIMEOUT_MS): Promise<boolean> {
    const want: Want = {
      bundleName: bundleName,
      abilityName: abilityName,
      parameters: session.toParameters()
    };
    let timer: number = -1;
    const timeout = new Promise<boolean>((resolve) => {
      timer = setTimeout(() => {
        resolve(false);
      }, timeoutMs);
    });
    const call = vpnExtension.startVpnExtensionAbility(want).then(() => true);
    const first: boolean = await Promise.race([call, timeout]);
    if (timer !== -1) {
      clearTimeout(timer);
    }
    if (!first) {
      // 关键：调用没 settle，不代表失败。可能只是授权框还开着。
      // 但对用户来说"没反应"就是失败，所以按超时处理并给出可操作建议。
      Logger.warn(`vpn start not settled within ${timeoutMs}ms (authorization dialog may be pending)`);
      throw new Error('VPN 授权未在限定时间内完成（请确认系统弹窗已允许，或检查是否有其他 VPN 正在使用）');
    }
    VpnController.running = true;
    Logger.info('vpn extension start requested');
    return true;
  }

  static markStopped(): void {
    VpnController.running = false;
  }

  /** 把系统错误码翻成人话；原始 code 一律进日志，便于排查 */
  static describeError(e: Object): string {
    const err = e as BusinessErrorLike;
    const code: number = err.code === undefined ? 0 : err.code;
    Logger.error(`vpn start failed code=${code} msg=${err.message === undefined ? '' : err.message}`);
    if (code === 2203002) {
      return '已有其他 VPN 连接，请先在系统中断开后再试';
    }
    if (code === 2203001) {
      return '当前账户类型不允许创建 VPN';
    }
    if (code === 16000001) {
      return '找不到 VPN 扩展组件（安装包可能不完整）';
    }
    if (code === 201) {
      return '缺少权限或用户未授权';
    }
    return 'VPN 启动失败（详见日志）';
  }
}

interface BusinessErrorLike {
  code: number;
  message: string;
}
