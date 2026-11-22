import { VpnExtensionAbility, vpnExtension, connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { KernelService } from '../service/KernelService';
import { VpnSession } from '../service/VpnSession';
import { VpnStateFile } from '../platform/VpnStateFile';
import { Forwarding, ForwardingResult } from '../service/Forwarding';

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_EXT';
/** 虚拟网卡地址：不落进常见家庭网段，避免与要访问的内网地址冲突 */
const TUN_ADDRESS: string = '10.8.0.1';
const TUN_PREFIX: number = 24;
const TUN_MTU: number = 1500;

/**
 * VPN 扩展：数据面宿主进程。
 *
 * 架构决定（为什么内核搬到这里）：
 *   `tun fd` 只在创建它的进程内有效。内核若继续跑在 UI 进程，扩展拿到的 fd 就没人能用；
 *   把 fd 跨进程交给 UI 进程，代价与风险都高于"把内核搬过来"。
 *   所以：**扩展进程 = 数据面（内核 + 转发），UI 进程 = 控制与展示**。
 *
 * 因此本进程的职责：
 *   1. 按 Want 里带过来的配置先启动内核（SOCKS 入站监听 loopback）；
 *   2. 再建立系统 tun，拿到 fd；
 *   3. 把 tun fd 交给转发层 —— **这一步尚未实现**，见 bootstrap() 末尾说明；
 *   4. 销毁时先停内核再销毁 tun，顺序反了会留下"网卡还在、转发已死"的黑洞状态。
 *
 * 官方约束：扩展内不得引用 contact / geolocation / multimedia.audio / camera /
 * telephony.call|sim|sms，否则可能导致进程异常退出。
 */
export default class MyVpnExtAbility extends VpnExtensionAbility {
  private conn: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;
  private session: VpnSession | null = null;
  // 见文件末尾的 BusinessErrorLike
  private kernel: KernelService = KernelService.getInstance();

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate abilityName=%{public}s', want.abilityName ?? '');
    this.session = VpnSession.fromWant(want);
    if (this.session === null) {
      // 没有会话参数就不该建 tun：建了也无人转发，只会把设备流量吸进黑洞
      hilog.error(DOMAIN, TAG, 'missing session parameters, refusing to establish tun');
      VpnStateFile.put(this.context, 'error', 0, '会话参数缺失，已拒绝建立 tun');
      return;
    }
    // 先告知“正在起”：否则应用进程只能看到旧状态，分不清“没启动”与“启动中”
    VpnStateFile.put(this.context, 'starting', 0, '');
    hilog.info(DOMAIN, TAG, 'session: %{public}s', this.session.describe());
    this.bootstrap().then(() => {
      hilog.info(DOMAIN, TAG, 'bootstrap finished');
    }).catch((e: Object) => {
      // 不能直接 String(e)：BusinessError 是对象，打出来是 "[object Object]"，
      // 等于把最有用的 code 丢掉了（实测踩到）。
      hilog.error(DOMAIN, TAG, 'bootstrap failed: %{public}s', MyVpnExtAbility.describe(e));
      const err = e as BusinessErrorLike;
      const code: number = err.code === undefined ? 0 : err.code;
      VpnStateFile.put(this.context, 'error', code, MyVpnExtAbility.describe(e));
    });
  }

  /** 把错误对象压成一行可读文本；code 必须保留，它决定了归因 */
  private static describe(e: Object): string {
    const err = e as BusinessErrorLike;
    if (err !== null && err !== undefined && err.code !== undefined) {
      const code: number = err.code;
      const msg: string = err.message === undefined ? '' : err.message;
      return `code=${code} msg=${msg}`;
    }
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy tunFd=%{public}d', this.tunFd);
    this.shutdown().then(() => {
      hilog.info(DOMAIN, TAG, 'shutdown finished');
      VpnStateFile.put(this.context, 'stopped', 0, '');
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'shutdown failed: %{private}s', msg);
    });
  }

  private buildConfig(): vpnExtension.VpnConfig {
    const tunAddr: connection.NetAddress = { address: TUN_ADDRESS, family: 1 };
    const tunLink: connection.LinkAddress = { address: tunAddr, prefixLength: TUN_PREFIX };
    const anyAddr: connection.NetAddress = { address: '0.0.0.0', family: 1 };
    const anyLink: connection.LinkAddress = { address: anyAddr, prefixLength: 0 };
    const defaultRoute: connection.RouteInfo = {
      interface: 'vpn-tun',
      destination: anyLink,
      gateway: anyAddr,
      hasGateway: false,
      isDefaultRoute: true
    };
    const cfg: vpnExtension.VpnConfig = {
      addresses: [tunLink],
      routes: [defaultRoute],
      // DNS 目前给公共地址；隧道内解析未实现，DNS 查询会绕过代理（已知泄漏点）
      dnsAddresses: ['1.1.1.1'],
      mtu: TUN_MTU,
      isIPv4Accepted: true
    };
    return cfg;
  }

  /**
   * 顺序是刻意的：**先起内核，再建 tun**。
   * 反过来，tun 一旦建立系统就开始往里送流量，而此刻 SOCKS 还没在监听，
   * 这批流量会被直接丢掉——表现是"连上的一瞬间所有应用断网"。
   *
   * 失败处理也是刻意的：**内核一旦起来，后面任何一步失败都必须把内核停掉**。
   * 否则 SOCKS 端口一直占着、进程里还挂着一个内核，下一次连接的报错会变成
   * "端口被占用"这种和真实原因无关的形式，排查成本极高。
   */
  private async bootstrap(): Promise<void> {
    const s: VpnSession | null = this.session;
    if (s === null) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'starting kernel in extension process');
    // 这一步失败时内核没起来，不需要回滚
    await this.kernel.start(s.configJson, KernelService.CONNECT_TIMEOUT_MS);
    hilog.info(DOMAIN, TAG, 'kernel running in extension process');

    try {
      this.conn = vpnExtension.createVpnConnection(this.context);
      this.tunFd = await this.conn.create(this.buildConfig());
      hilog.info(DOMAIN, TAG, 'tun established fd=%{public}d address=%{public}s/%{public}d mtu=%{public}d',
        this.tunFd, TUN_ADDRESS, TUN_PREFIX, TUN_MTU);

      // tun 已就绪：把 fd 交给转发层。这一步之后，设备全局流量才真的进代理。
      // 失败不能当成“已连接”：tun 已建立但无人读，流量会被吸进黑洞。
      const fr: ForwardingResult = Forwarding.start(this.tunFd, s.socksPort, s.socksUser, s.socksPass);
      if (!fr.ok) {
        throw new Error(`转发启动失败：${fr.error}`);
      }

      // 内核已经持有配置，明文凭据没有理由继续留在本进程内存里
      this.dropSessionSecrets();

      // 回传给应用进程。msg 不带任何敏感信息（无地址、无 fd、无口令）。
      VpnStateFile.put(this.context, 'running', 0,
        '内核、tun 与转发层均就绪');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'bootstrap step failed, rolling back: %{public}s', MyVpnExtAbility.describe(e));
      await this.rollback();
      throw e as Error;
    }
  }

  /** 配置与 SOCKS 口令用完即弃：内核与转发层各自持有自己的副本 */
  private dropSessionSecrets(): void {
    const s: VpnSession | null = this.session;
    if (s === null) {
      return;
    }
    s.configJson = '';
    s.socksPass = '';
  }

  /**
   * 启动中任一环节失败后的清理：转发 → tun → 内核，顺序与 shutdown 一致。
   * 每一步独立 try：前一步失败不能连带后面的清理也不做（那正是"半成品状态"的来源）。
   */
  private async rollback(): Promise<void> {
    try {
      Forwarding.stop();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'rollback: forwarding stop failed');
    }
    if (this.conn !== null) {
      try {
        await this.conn.destroy();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'rollback: tun destroy failed');
      }
      this.conn = null;
      this.tunFd = -1;
    }
    try {
      await this.kernel.stop(KernelService.DISCONNECT_TIMEOUT_MS);
      hilog.info(DOMAIN, TAG, 'rollback: kernel stopped');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'rollback: kernel stop failed');
    }
  }

  /** 先停内核再销毁 tun：避免"网卡还在、转发已死"的中间态 */
  private async shutdown(): Promise<void> {
    // 顺序：先停转发，再销 tun，最后停内核。
    // 反过来会让转发层读到一个已关闭的 fd。
    Forwarding.stop();
    try {
      await this.kernel.stop(KernelService.DISCONNECT_TIMEOUT_MS);
      hilog.info(DOMAIN, TAG, 'kernel stopped');
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'kernel stop failed: %{private}s', msg);
    }
    if (this.conn !== null) {
      await this.conn.destroy();
      this.conn = null;
      this.tunFd = -1;
      hilog.info(DOMAIN, TAG, 'tun destroyed');
    }
  }
}

/** BusinessError 的形状：只取我们需要的字段，避免引入整套错误类型 */
interface BusinessErrorLike {
  code: number;
  message?: string;
}
