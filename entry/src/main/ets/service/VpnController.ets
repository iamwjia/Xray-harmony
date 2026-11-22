import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { Logger } from '../platform/Logger';
import { VpnSession } from './VpnSession';
import { common } from '@kit.AbilityKit';
import { VpnState, VpnStateFile } from '../platform/VpnStateFile';

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
  /** 停止等待：扩展侧要停转发、停内核、销 tun，5s 是实测上限 */
  static readonly DISCONNECT_TIMEOUT_MS: number = 5000;
  /**
   * 会话参数上限（字符数，保守值）。
   * Want 参数的官方建议是"轻量"，具体上限未公开；64K 字符（≈64KB JSON）远低于常见限制，
   * 同时远高于实测配置（几十节点 + 几十条规则约 4–8KB）。
   */
  static readonly MAX_SESSION_CHARS: number = 64 * 1024;

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
    const params: Record<string, Object> = session.toParameters();
    // Want 参数要跨进程序列化，官方建议保持"轻量"。配置串随节点数与规则数增长，
    // 真到超大配置时 startVpnExtensionAbility 会失败，而错误信息看不出是"参数太大"。
    // 这里先拦住并说清原因——阈值取保守值，宁可在大配置上提前报错，
    // 也不要抛一个用户和我们都读不懂的错误码。
    const raw: Object | undefined = params[VpnSession.PARAM_SESSION];
    const size: number = typeof raw === 'string' ? (raw as string).length : 0;
    if (size > VpnController.MAX_SESSION_CHARS) {
      Logger.error(`vpn session payload too large: ${size} chars`);
      throw new Error(`配置过大（${Math.floor(size / 1024)} KB），无法通过启动参数传给 VPN 扩展；` +
        `请减少节点或规则数量后重试`);
    }
    const want: Want = {
      bundleName: bundleName,
      abilityName: abilityName,
      parameters: params
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

  /**
   * 轮询扩展进程回传的状态，直到 running / error / 超时。
   *
   * 为什么要轮询而不是事件：两个进程共享的只有沙箱目录，没有跨进程回调通道。
   * 轮询只在“正在连接”这个短窗口里进行，拿到结果立即停，不留常驻定时器。
   */
  static async waitForState(ctx: common.Context, timeoutMs: number): Promise<VpnState> {
    const start: number = Date.now();
    let last: VpnState | null = null;
    while (Date.now() - start < timeoutMs) {
      const st: VpnState | null = VpnStateFile.read(ctx);
      if (st !== null) {
        last = st;
        if (st.state === 'running' || st.state === 'error') {
          // running 也要查过期：扩展进程被系统杀掉时不会写 stopped
          if (VpnStateFile.isStale(st)) {
            const stale = new VpnState();
            stale.state = 'error';
            stale.code = -1;
            stale.msg = '状态已过期：扩展进程可能已被系统终止';
            stale.at = Date.now();
            return stale;
          }
          return st;
        }
      }
      await VpnController.sleep(KernelSleepMs);
    }
    if (last !== null) {
      return last;
    }
    const timeout = new VpnState();
    timeout.state = 'error';
    timeout.code = -2;
    // 文案要能指向原因，而不是只说"超时"。实测（模拟器 API 26）：
    // 系统的 NETMANAGER_EXT 收到 startVpnExtensionAbility 后，会去拉起授权对话框组件
    // `com.huawei.hmos.vpndialog/VpnServiceExtAbility`；模拟器镜像里没有这个包，
    // 于是 `connectAbility failed 2097152`，我们的 Promise 永不 settle → 只能等到超时。
    // 也就是说：**弹窗是系统组件画的，不是应用画的**；系统组件缺失时，用户什么也看不到。
    timeout.msg = '系统未响应 VPN 授权请求（没有出现授权弹窗）';
    timeout.at = Date.now();
    Logger.error('vpn start: no state and no dialog within timeout; ' +
      'if this device is an emulator, it likely lacks com.huawei.hmos.vpndialog');
    return timeout;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /**
   * 停止 VPN 扩展。
   *
   * 为什么不直接杀进程：系统不允许三方应用杀别人的进程，只能"请求"扩展停止；
   * 真正的收尾（停转发 → 停内核 → 销毁 tun）在扩展进程的 `onDestroy` 里完成。
   * 所以这里只发出请求，状态由状态文件回传（`stopped`）。
   */
  static async stop(bundleName: string, abilityName: string,
    timeoutMs: number = VpnController.DISCONNECT_TIMEOUT_MS): Promise<boolean> {
    const want: Want = {
      bundleName: bundleName,
      abilityName: abilityName
    };
    let timer: number = -1;
    const timeout = new Promise<boolean>((resolve) => {
      timer = setTimeout(() => {
        resolve(false);
      }, timeoutMs);
    });
    const call = vpnExtension.stopVpnExtensionAbility(want).then(() => true).catch((e: Object) => {
      const err = e as BusinessErrorLike;
      Logger.warn(`vpn stop failed code=${err.code === undefined ? 0 : err.code}`);
      return false;
    });
    const ok: boolean = await Promise.race([call, timeout]);
    if (timer !== -1) {
      clearTimeout(timer);
    }
    VpnController.running = false;
    if (!ok) {
      // 注意：超时不等于"还在跑"，也不等于"已停"——调用方必须以后续状态文件为准
      Logger.warn('vpn stop not confirmed within timeout');
    } else {
      Logger.info('vpn extension stop requested');
    }
    return ok;
  }

  static markStopped(): void {
    VpnController.running = false;
  }

  /**
   * 把扩展进程回传的状态码翻成人话 + 可操作建议。
   *
   * 为什么要单独一张表：这些码不是我们自己定的，而是系统返回的。
   * 用户看到“202”只会以为是应用坏了；看到“需要真机/系统授权”才知道该做什么。
   */
  static describeStateCode(code: number): string {
    if (code === 202) {
      return '系统拒绝非系统应用创建 VPN（需真机与系统授权）';
    }
    if (code === 2203002) {
      return '已有其他 VPN 连接，请先在系统中断开';
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
    if (code === -1) {
      return '扩展进程状态已过期（可能已被系统终止）';
    }
    if (code === -2) {
      // 实测（模拟器 API 26）：系统 NETMANAGER_EXT 收到请求后会去拉起授权对话框组件
      // com.huawei.hmos.vpndialog/VpnServiceExtAbility，该包缺失时 connectAbility failed，
      // 我们的 Promise 永不 settle。用户看到的现象就是"没弹窗、一直在连接中"，
      // 所以这句话必须指出"没有弹窗"这件事，否则用户会以为是自己没点或网络慢。
      return '系统未响应 VPN 授权请求（没有出现授权弹窗）';
    }
    return code === 0 ? '' : `未知错误码 ${code}`;
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

/** 轮询间隔：250ms —— 比这更密是白费 CPU，更稀会让用户觉得“点了没反应” */
const KernelSleepMs: number = 250;
