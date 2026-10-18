/**
 * service/KernelConfigBuilder.ets — L-A → L-B（内核 JSON）生成器
 *
 * 两个入口：
 *   - buildMinimal()   socks + freedom，用于「无节点」时验证驱动链路；
 *   - buildWithNode()  socks + 真实节点出站（vless / vmess / trojan / ss）。
 *
 * 约束：
 *   - 生成物不落盘（design §4.7：L-B 是生成物，不回写）；
 *   - 所有动态值经 JSON.stringify 转义：手拼字符串遇到引号/反斜杠会产出非法 JSON，
 *     而内核报错不会告诉你哪个字符错了；
 *   - ArkTS 严格模式禁止无类型对象字面量（arkts-no-untyped-obj-literals），
 *     因此采用「字符串构造 + 逐值转义」而非对象字面量。
 */

import { XrayNode, TransportKind, SecurityKind, RoutingMode } from '../model/AppConfig';

export class KernelConfigBuilder {
  static readonly DEFAULT_SOCKS_PORT: number = 18080;

  /** 最小配置：socks 入站 + freedom 出站 */
  static buildMinimal(socksPort: number = KernelConfigBuilder.DEFAULT_SOCKS_PORT): string {
    const cfg: string = '{"log":{"loglevel":"warning"},' +
      '"inbounds":[{"tag":"socks-in","listen":"127.0.0.1","port":' + socksPort.toString() + ',' +
      '"protocol":"socks","settings":{"auth":"noauth","udp":false}}],' +
      '"outbounds":[{"tag":"direct","protocol":"freedom"}]}';
    return cfg;
  }

  /** 按节点生成配置：socks 入站 + 节点出站 + freedom 兜底 */
  static buildWithNode(node: XrayNode, socksPort: number = KernelConfigBuilder.DEFAULT_SOCKS_PORT,
    routingMode: RoutingMode = RoutingMode.RULE): string {
    const inbound: string = '{"tag":"socks-in","listen":"127.0.0.1","port":' +
      socksPort.toString() + ',"protocol":"socks","settings":{"auth":"noauth","udp":false}}';
    const proxy: string = KernelConfigBuilder.buildOutbound(node);
    const direct: string = '{"tag":"direct","protocol":"freedom"}';
    const routing: string = KernelConfigBuilder.buildRouting(routingMode);
    return '{"log":{"loglevel":"warning"},"inbounds":[' + inbound + '],"outbounds":[' +
      proxy + ',' + direct + ']' + routing + '}';
  }

  /**
   * 分流配置。
   * 说明：不依赖 geoip.dat / geosite.dat（当前应用未内置资源文件），
   * 只用内置可判定的内网网段，避免"资源缺失 → 内核启动失败"。
   * TODO: 内置 geo 资源后，规则模式补 geosite:cn / geoip:cn。
   */
  private static buildRouting(mode: RoutingMode): string {
    if (mode === RoutingMode.DIRECT) {
      return ',"routing":{"rules":[{"type":"field","network":"tcp,udp","outboundTag":"direct"}]}';
    }
    if (mode === RoutingMode.GLOBAL) {
      return '';
    }
    // RULE：内网/回环直连，其余走代理
    return ',"routing":{"domainStrategy":"IPIfNonMatch","rules":[' +
      '{"type":"field","ip":["127.0.0.0/8","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16",' +
      '"169.254.0.0/16","::1/128","fc00::/7","fe80::/10"],"outboundTag":"direct"}' +
      ']}';
  }
  private static buildOutbound(node: XrayNode): string {
    const proto: string = (node.protocol || 'vless').toLowerCase();
    const stream: string = KernelConfigBuilder.buildStreamSettings(node);
    const addr: string = KernelConfigBuilder.esc(node.address);
    const port: string = node.port.toString();

    if (proto === 'vless') {
      let user: string = '{"id":' + KernelConfigBuilder.esc(node.credentialRef) + ',"encryption":"none"';
      if (node.flow) {
        user += ',"flow":' + KernelConfigBuilder.esc(node.flow);
      }
      user += '}';
      return '{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":' + addr +
        ',"port":' + port + ',"users":[' + user + ']}]},"streamSettings":' + stream + '}';
    }
    if (proto === 'vmess') {
      return '{"tag":"proxy","protocol":"vmess","settings":{"vnext":[{"address":' + addr +
        ',"port":' + port + ',"users":[{"id":' + KernelConfigBuilder.esc(node.credentialRef) +
        ',"alterId":0,"security":"auto"}]}]},"streamSettings":' + stream + '}';
    }
    if (proto === 'trojan') {
      return '{"tag":"proxy","protocol":"trojan","settings":{"servers":[{"address":' + addr +
        ',"port":' + port + ',"password":' + KernelConfigBuilder.esc(node.credentialRef) +
        '}]},"streamSettings":' + stream + '}';
    }
    if (proto === 'shadowsocks') {
      const sep: number = node.credentialRef.indexOf(':');
      const method: string = sep > 0 ? node.credentialRef.substring(0, sep) : 'aes-256-gcm';
      const password: string = sep > 0 ? node.credentialRef.substring(sep + 1) : node.credentialRef;
      return '{"tag":"proxy","protocol":"shadowsocks","settings":{"servers":[{"address":' + addr +
        ',"port":' + port + ',"method":' + KernelConfigBuilder.esc(method) +
        ',"password":' + KernelConfigBuilder.esc(password) + '}]}}';
    }
    return '{"tag":"proxy","protocol":"freedom"}';
  }

  private static buildStreamSettings(node: XrayNode): string {
    const network: string = KernelConfigBuilder.networkOf(node.transport);
    const security: string = KernelConfigBuilder.securityOf(node.security);
    let s: string = '{"network":' + KernelConfigBuilder.esc(network) +
      ',"security":' + KernelConfigBuilder.esc(security);

    if (network === 'ws') {
      const host: string = node.wsHost || node.address;
      s += ',"wsSettings":{"path":' + KernelConfigBuilder.esc(node.wsPath || '/') +
        ',"headers":{"Host":' + KernelConfigBuilder.esc(host) + '}}';
    } else if (network === 'grpc') {
      s += ',"grpcSettings":{"serviceName":' + KernelConfigBuilder.esc(node.grpcService || '') + '}';
    }

    if (security === 'tls') {
      s += ',"tlsSettings":{"serverName":' + KernelConfigBuilder.esc(node.serverName || node.address) +
        ',"allowInsecure":false}';
    } else if (security === 'reality') {
      s += ',"realitySettings":{"serverName":' + KernelConfigBuilder.esc(node.serverName || node.address) +
        ',"fingerprint":"chrome","show":false}';
    }
    s += '}';
    return s;
  }

  private static esc(v: string): string {
    return JSON.stringify(v === undefined || v === null ? '' : v);
  }

  private static networkOf(t: TransportKind): string {
    if (t === TransportKind.WS) {
      return 'ws';
    }
    if (t === TransportKind.GRPC) {
      return 'grpc';
    }
    if (t === TransportKind.HTTP2) {
      return 'http';
    }
    if (t === TransportKind.MKCP) {
      return 'mkcp';
    }
    return 'tcp';
  }

  private static securityOf(s: SecurityKind): string {
    if (s === SecurityKind.TLS) {
      return 'tls';
    }
    if (s === SecurityKind.REALITY) {
      return 'reality';
    }
    return 'none';
  }
}