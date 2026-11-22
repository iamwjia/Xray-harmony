import { ConfigService } from './ConfigService';
import { GeoAssets } from './GeoAssets';
import { KernelConfigBuilder } from './KernelConfigBuilder';
import { SocksEndpoint, SocksGuard } from './SocksGuard';
import { VpnSession } from './VpnSession';
import { XrayNode, RoutingMode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';

/**
 * service/VpnSessionFactory.ets — 组装一次 VPN 会话（唯一入口）
 *
 * 为什么必须只有一个入口：配置怎么拼、端口口令怎么轮换、规则与 geo 怎么带，
 * 这些一旦在两个地方各写一份，就会悄悄分叉——表现是"首页能连、开发者面板连不上"，
 * 而且两边的错误信息还不一样，排查时先被自己误导。
 *
 * 这里只做"组装"，不做"启动"：启动与状态查询在 VpnController。
 */

export class SessionBuildResult {
  ok: boolean = false;
  /** ok=false 时给人看的原因 */
  error: string = '';
  session: VpnSession | null = null;
  /** 本次轮换的端口，供 UI 显示"本机代理地址" */
  socksPort: number = 0;
}

export class VpnSessionFactory {
  /**
   * 组装会话。
   * @param cfg 配置服务
   * @param useSelectedNode true=带当前节点；false=只做本地 SOCKS（无节点时的驱动链路验证）
   */
  static async build(cfg: ConfigService, useSelectedNode: boolean = true): Promise<SessionBuildResult> {
    const res = new SessionBuildResult();
    const sel: XrayNode | null = useSelectedNode ? cfg.getSelectedNode() : null;

    let credential: string = '';
    if (sel !== null) {
      const c: string | null = await cfg.resolveCredential(sel);
      if (c === null) {
        // 拿不到凭据必须阻断：拿空串去连，内核只会给一个与真实原因无关的握手错误
        res.error = '节点凭据不可用（安全存储中找不到对应密钥），请重新导入该节点';
        return res;
      }
      credential = c;
    }

    const mode: RoutingMode = cfg.getConfig().settings.routingMode;
    // 每次连接轮换端口与口令：loopback 是同设备共享的，不能免鉴权
    const ep: SocksEndpoint = SocksGuard.rotate();
    const cfgJson: string = sel === null
      ? KernelConfigBuilder.buildMinimal(ep.port, ep.user, ep.password)
      : KernelConfigBuilder.buildWithNode(sel, ep.port, mode, ep.user, ep.password, credential,
        GeoAssets.isReady(), cfg.getRules());

    const s = new VpnSession();
    s.configJson = cfgJson;
    s.socksPort = ep.port;
    s.socksUser = ep.user;
    s.socksPass = ep.password;
    s.routingMode = mode as string;

    Logger.info(`session built: ${s.describe()}`);
    res.ok = true;
    res.session = s;
    res.socksPort = ep.port;
    return res;
  }
}
