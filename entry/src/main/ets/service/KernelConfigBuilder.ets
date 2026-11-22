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

import { XrayNode, TransportKind, SecurityKind, RoutingMode, RoutingRule } from '../model/AppConfig';
import { SocksGuard } from './SocksGuard';

export class KernelConfigBuilder {
  static readonly DEFAULT_SOCKS_PORT: number = 18080;

  /**
   * 本地 SOCKS 入站。
   * 传了口令就启用 password 鉴权：loopback 在同设备内是共享的，
   * 无鉴权等于给本机所有应用开了一个走用户节点的出网口。
   *
   * **必须开 udp**：数据面接上以后，tun 里的 UDP 流量（QUIC、DNS）只能通过
   * SOCKS5 的 UDP ASSOCIATE 出去。关着的话表现是「网页能开、部分应用不正常」，
   * 用户看到的是"这软件一半好用"，排查成本极高。
   */
  private static buildInbound(socksPort: number, socksUser: string, socksPass: string): string {
    const settings: string = (socksPass.length > 0)
      ? '{"auth":"password","accounts":[{"user":' + KernelConfigBuilder.esc(socksUser) +
        ',"pass":' + KernelConfigBuilder.esc(socksPass) + '}],"udp":true}'
      : '{"auth":"noauth","udp":true}';
    return '{"tag":"socks-in","listen":"' + SocksGuard.LOCAL_HOST + '","port":' + socksPort.toString() +
      ',"protocol":"socks","settings":' + settings + '}';
  }

  /** 最小配置：socks 入站 + freedom 出站 */
  static buildMinimal(socksPort: number = KernelConfigBuilder.DEFAULT_SOCKS_PORT,
    socksUser: string = '', socksPass: string = ''): string {
    const inbound: string = KernelConfigBuilder.buildInbound(socksPort, socksUser, socksPass);
    const cfg: string = '{"log":{"loglevel":"warning"},"inbounds":[' + inbound + '],' +
      '"outbounds":[{"tag":"direct","protocol":"freedom"}]}';
    return cfg;
  }

  /** 按节点生成配置：socks 入站 + 节点出站 + freedom/blackhole 兜底 */
  static buildWithNode(node: XrayNode, socksPort: number = KernelConfigBuilder.DEFAULT_SOCKS_PORT,
    routingMode: RoutingMode = RoutingMode.RULE, socksUser: string = '', socksPass: string = '',
    credential: string = '', geoReady: boolean = false, rules: RoutingRule[] = []): string {
    const inbound: string = KernelConfigBuilder.buildInbound(socksPort, socksUser, socksPass);
    const proxy: string = KernelConfigBuilder.buildOutbound(node, credential);
    const direct: string = '{"tag":"direct","protocol":"freedom"}';
    // blackhole 只有在"规则里出现 block"时才有意义，但常驻一个空出站成本几乎为零，
    // 且能避免"用户加了一条 block 规则、配置却因缺少出站而启动失败"。
    const block: string = '{"tag":"block","protocol":"blackhole"}';
    const routing: string = KernelConfigBuilder.buildRouting(routingMode, geoReady, rules);
    const dns: string = KernelConfigBuilder.buildDns(routingMode);
    return '{"log":{"loglevel":"warning"},"inbounds":[' + inbound + '],"outbounds":[' +
      proxy + ',' + direct + ',' + block + ']' + dns + routing + '}';
  }

  /**
   * DNS 配置：让域名解析走隧道，而不是在设备上偷偷解析。
   *
   * 为什么要单独写它：分流规则里大量用了域名（`geosite:cn`、用户自定义域名）。
   * 如果解析发生在设备上，“哪些域名被查询”本身就是泄露——即使流量
   * 后续走了代理，DNS 也已经把你要访问什么告诉了本地网络。
   *
   * 两个取舍：
   *   1. 查询策略固定 **UseIP**：避免同一域名同时拿回 IPv6 导致后续走不通；
   *   2. 解析器给两个（1.1.1.1 / 223.5.5.5）：只给一个外国解析器会让国内域名变慢，
   *      只给一个国内解析器又会对被污染域名返回错误结果。
   *
   * 直连模式不生成 dns 段：那个模式下用户就是要本机直连，随便改解析路径反而是擅自作主。
   */
  private static buildDns(mode: RoutingMode): string {
    if (mode === RoutingMode.DIRECT) {
      return '';
    }
    return ',"dns":{"tag":"dns-in","queryStrategy":"UseIP","servers":["1.1.1.1","223.5.5.5"]}';
  }

  /**
   * 分流配置。
   *
   * 顺序（这是本方法最容易被改坏的地方）：
   *   1. **用户自定义规则**（按用户看到的顺序）
   *   2. 内置 geo 规则（`geosite:cn` 域名直连、`geoip:cn` 与内网网段直连）
   *
   * 为什么自定义必须在前：xray 按顺序匹配、命中即停。若 geo 在前，
   * 用户加的 "某域名走代理" 会被 `geosite:cn` 先命中成直连，表现就是"规则加了没用"。
   *
   * geoReady=false 时**必须降级**：只保留内网/回环网段直连。缺资源时内核会在解析
   * `geosite:cn` 阶段直接启动失败，而不是"规则不生效"。
   */
  private static buildRouting(mode: RoutingMode, geoReady: boolean, userRules: RoutingRule[]): string {
    // DNS 规则放在函数内部：这个函数体会被测试整段抽出来执行（跑的是真代码），
    // 引用类静态方法会在抽取环境里找不到定义。
    const dnsRule = '{"type":"field","network":"tcp,udp","port":"53","outboundTag":"proxy"}';
    if (mode === RoutingMode.DIRECT) {
      return ',"routing":{"rules":[{"type":"field","network":"tcp,udp","outboundTag":"direct"}]}';
    }
    if (mode === RoutingMode.GLOBAL) {
      // 全局模式语义 = 全部走代理；此时用户规则不生效（界面上需要说明，否则会被当成 bug）。
      // 但 DNS 必须说：否则“全局代理”只管流量、不管查询，域名仍在本机被解析。
      // 写成完整字面量而不拼变量：这一条会被测试单独求值（不带函数上下文）。
      // 与 RULE 段里那条保持一致，测试里有一条断言专门盯着它们相等。
      return ',"routing":{"rules":[{"type":"field","network":"tcp,udp","port":"53","outboundTag":"proxy"}]}';
    }
    const parts: string[] = [];

    // 0) DNS 走隧道：必须在最前面。否则会被 `geosite:cn` 之类的规则先命中，
    //    变成“国内域名的 DNS 走直连”——那正是要避免的泄露。
    parts.push(dnsRule);

    // 1) 用户自定义规则
    for (let i = 0; i < userRules.length; i++) {
      const r: RoutingRule = userRules[i];
      if (!r.enabled || r.pattern.length === 0) {
        continue;
      }
      let tag: string = 'proxy';
      if (r.action === 'direct') {
        tag = 'direct';
      } else if (r.action === 'block') {
        tag = 'block';
      }
      const field: string = r.matchType === 'ip' ? 'ip' : 'domain';
      parts.push('{"type":"field","' + field + '":[' + KernelConfigBuilder.esc(r.pattern) +
        '],"outboundTag":"' + tag + '"}');
    }

    // 2) 内置 geo / 内网
    const lan: string = '"127.0.0.0/8","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16",' +
      '"169.254.0.0/16","::1/128","fc00::/7","fe80::/10"';
    if (geoReady) {
      // 域名优先：命中 geosite:cn 直接直连，避免走 IP 判定后被代理
      parts.push('{"type":"field","domain":["geosite:cn"],"outboundTag":"direct"}');
    }
    const ipRule: string = geoReady ? '"ip":["geoip:cn",' + lan + ']' : '"ip":[' + lan + ']';
    parts.push('{"type":"field",' + ipRule + ',"outboundTag":"direct"}');

    return ',"routing":{"domainStrategy":"IPIfNonMatch","rules":[' + parts.join(',') + ']}';
  }
  private static buildOutbound(node: XrayNode, credential: string): string {
    const proto: string = (node.protocol || 'vless').toLowerCase();
    const stream: string = KernelConfigBuilder.buildStreamSettings(node);
    const addr: string = KernelConfigBuilder.esc(node.address);
    const port: string = node.port.toString();
    // 优先用调用方从安全存储取出的明文；取不到时回落（仅调试路径）
    const cred: string = credential.length > 0 ? credential : node.credentialRef;

    if (proto === 'vless') {
      let user: string = '{"id":' + KernelConfigBuilder.esc(cred) + ',"encryption":"none"';
      if (node.flow) {
        user += ',"flow":' + KernelConfigBuilder.esc(node.flow);
      }
      user += '}';
      return '{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":' + addr +
        ',"port":' + port + ',"users":[' + user + ']}]},"streamSettings":' + stream + '}';
    }
    if (proto === 'vmess') {
      return '{"tag":"proxy","protocol":"vmess","settings":{"vnext":[{"address":' + addr +
        ',"port":' + port + ',"users":[{"id":' + KernelConfigBuilder.esc(cred) +
        ',"alterId":0,"security":"auto"}]}]},"streamSettings":' + stream + '}';
    }
    if (proto === 'trojan') {
      return '{"tag":"proxy","protocol":"trojan","settings":{"servers":[{"address":' + addr +
        ',"port":' + port + ',"password":' + KernelConfigBuilder.esc(cred) +
        '}]},"streamSettings":' + stream + '}';
    }
    if (proto === 'shadowsocks') {
      const sep: number = cred.indexOf(':');
      const method: string = sep > 0 ? cred.substring(0, sep) : 'aes-256-gcm';
      const password: string = sep > 0 ? cred.substring(sep + 1) : cred;
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
      // REALITY 必须带 publicKey（及可选 shortId/fingerprint）。
      // 缺 publicKey 时内核不会报"配置非法"，而是连接阶段握手失败——
      // 表现为"导入成功、就是连不上"，所以这里把字段照实下发，并在编辑页做前置校验。
      const fp: string = node.fingerprint.length > 0 ? node.fingerprint : 'chrome';
      s += ',"realitySettings":{"serverName":' + KernelConfigBuilder.esc(node.serverName || node.address) +
        ',"fingerprint":' + KernelConfigBuilder.esc(fp) +
        ',"publicKey":' + KernelConfigBuilder.esc(node.publicKey) +
        ',"shortId":' + KernelConfigBuilder.esc(node.shortId) + ',"show":false}';
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
      // 目标内核已移除旧的 "http" 传输名，HTTP/2 现为 "h2"。
      // 之前映射成 "http" 会让配置在 parse 阶段就被拒（用户看到的是"导入成功但连不上"）。
      return 'h2';
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