import { VpnExtensionAbility, vpnExtension, connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_EXT';
/** 虚拟网卡地址：不落进常见家庭网段，避免与应用要访问的内网地址冲突 */
const TUN_ADDRESS: string = '10.8.0.1';
const TUN_PREFIX: number = 24;
const TUN_MTU: number = 1500;

/**
 * VPN 扩展：建立系统级 tun。
 *
 * 当前范围（有意收窄，不是遗漏）：
 *   1. 建立 VpnConnection，配置虚拟网卡地址、默认路由、DNS、MTU；
 *   2. `create()` 拿到 tun fd 并把 fd 记进日志，用于真机确认这一步通不通过；
 *   3. **不做转发**。
 *
 * 为什么不在这里写转发：数据面是 `tun fd -> userspace 协议栈 -> loopback SOCKS -> 内核出站`。
 * 架构上有一条硬约束——**一个进程只能加载一个 Go runtime**。内核已经是 Go 共享库；
 * 若转发层也用 Go 实现，必须与内核合并进同一次构建，否则只能用 C/C++。
 * 选型未定之前写转发代码，只会得到"看起来完整、实际跑不通"的东西。
 *
 * 另一条同样重要的边界：**tun fd 只在这个扩展进程内有效**。主应用进程拿不到它，
 * 所以转发层必须活在扩展进程里——这直接决定了后面的构建方案（合并后的 .so 在这里加载）。
 *
 * 官方约束：扩展内不得引用 contact / geolocation / multimedia.audio / camera /
 * telephony.call|sim|sms，否则可能导致进程异常退出。
 */
export default class MyVpnExtAbility extends VpnExtensionAbility {
  private conn: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate abilityName=%{public}s', want.abilityName ?? '');
    // 不阻塞生命周期回调：首次连接会弹系统授权框，用户不点之前 create() 不会返回，
    // 必须放到异步流程里并自己兜底超时。
    this.establish().then(() => {
      hilog.info(DOMAIN, TAG, 'establish finished');
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'establish failed: %{private}s', msg);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy tunFd=%{public}d', this.tunFd);
    this.teardown().then(() => {
      hilog.info(DOMAIN, TAG, 'teardown finished');
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'teardown failed: %{private}s', msg);
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
      // DNS 先给公共地址；后续要改成"隧道内解析"，否则 DNS 查询会绕过代理（泄漏点）
      dnsAddresses: ['1.1.1.1'],
      mtu: TUN_MTU,
      isIPv4Accepted: true
    };
    return cfg;
  }

  private async establish(): Promise<void> {
    this.conn = vpnExtension.createVpnConnection(this.context);
    const cfg: vpnExtension.VpnConfig = this.buildConfig();
    this.tunFd = await this.conn.create(cfg);
    hilog.info(DOMAIN, TAG, 'tun established fd=%{public}d address=%{public}s/%{public}d mtu=%{public}d',
      this.tunFd, TUN_ADDRESS, TUN_PREFIX, TUN_MTU);
    hilog.info(DOMAIN, TAG, 'forwarding NOT implemented: fd stays in this process, traffic goes nowhere yet');
  }

  private async teardown(): Promise<void> {
    if (this.conn !== null) {
      await this.conn.destroy();
      this.conn = null;
      this.tunFd = -1;
    }
  }
}
