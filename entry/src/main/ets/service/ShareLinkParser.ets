/**
 * service/ShareLinkParser.ets — 分享链接解析
 *
 * 职责：把 vless:// / vmess:// / trojan:// / ss:// 分享链接解析为 L-A 域的 XrayNode。
 *
 * 安全约束（重要）：
 *   - 日志与错误信息**不得**出现 UUID / 密码，只能出现 host:port 与协议名；
 *   - MVP 阶段 UUID 暂存于 `credentialRef`（TODO：改为 HUKS/ASSET 引用），
 *     这意味着当前节点数据落盘时凭据是明文——接入持久化前必须处理。
 */

import { XrayNode, TransportKind, SecurityKind } from '../model/AppConfig';

export class ShareLinkParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ShareLinkParseError';
  }
}

function safeDecode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch (e) {
    return s;
  }
}

/** 简易 base64 解码（ArkTS 无内置 atob，vmess/ss 需要） */
function b64decode(input: string): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  let str = input.replace(/[-_]/g, (c: string) => (c === '-' ? '+' : '/')).replace(/\s/g, '');
  let output = '';
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < str.length; i++) {
    const idx = chars.indexOf(str.charAt(i));
    if (idx === -1) {
      continue;
    }
    buffer = (buffer << 6) | idx;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output += String.fromCharCode((buffer >> bits) & 0xFF);
    }
  }
  return output;
}

/** 解析 query 串为键值对 */
function parseQuery(query: string): Map<string, string> {
  const map: Map<string, string> = new Map<string, string>();
  if (!query) {
    return map;
  }
  const parts = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    const kv = parts[i].split('=');
    if (kv.length >= 1 && kv[0]) {
      map.set(kv[0], kv.length > 1 ? safeDecode(kv.slice(1).join('=')) : '');
    }
  }
  return map;
}

function mapTransport(t: string): TransportKind {
  const v = (t || 'tcp').toLowerCase();
  if (v === 'ws') {
    return TransportKind.WS;
  }
  if (v === 'grpc') {
    return TransportKind.GRPC;
  }
  if (v === 'h2' || v === 'http' || v === 'http2') {
    // 实测：当前内核已移除 HTTP 传输（报错原文 “The feature HTTP transport ... has been
    // removed and migrated to XHTTP”），h2 也不再被接受。继续把它存成 HTTP2 会导致
    // “导入成功、连接必失败且原因看不懂”，所以这里直接拒绝，并给出可执行的替代建议。
    throw new ShareLinkParseError('该内核版本已移除 HTTP/2 传输（迁移至 XHTTP）：请改用 xhttp / ws / grpc 的节点');
  }
  if (v === 'mkcp' || v === 'kcp') {
    return TransportKind.MKCP;
  }
  return TransportKind.TCP;
}

function mapSecurity(s: string): SecurityKind {
  const v = (s || 'none').toLowerCase();
  if (v === 'tls') {
    return SecurityKind.TLS;
  }
  if (v === 'reality') {
    return SecurityKind.REALITY;
  }
  return SecurityKind.NONE;
}

export class ShareLinkParser {

  /**
   * 解析分享链接。失败时抛 ShareLinkParseError（人话原因），不返回半成品。
   */
  static parse(link: string): XrayNode {
    const raw = (link || '').trim();
    if (!raw) {
      throw new ShareLinkParseError('链接为空');
    }
    if (raw.startsWith('vless://')) {
      return ShareLinkParser.finalize(ShareLinkParser.parseVless(raw));
    }
    if (raw.startsWith('vmess://')) {
      return ShareLinkParser.finalize(ShareLinkParser.parseVmess(raw));
    }
    if (raw.startsWith('trojan://')) {
      return ShareLinkParser.finalize(ShareLinkParser.parseTrojan(raw));
    }
    if (raw.startsWith('ss://')) {
      return ShareLinkParser.finalize(ShareLinkParser.parseShadowsocks(raw));
    }
    const proto = raw.indexOf('://') >= 0 ? raw.substring(0, raw.indexOf('://')) : raw.substring(0, 12);
    throw new ShareLinkParseError('不支持的协议：' + proto);
  }

  /** 补齐稳定 id：protocol@address:port（解析器不依赖 id，但选择/去重需要） */
  private static finalize(n: XrayNode): XrayNode {
    if (!n.id) {
      n.id = n.protocol + '@' + n.address + ':' + n.port.toString();
    }
    return n;
  }
  /** vless://uuid@host:port?params#name */
  private static parseVless(raw: string): XrayNode {
    const body = raw.substring('vless://'.length);
    const hashIdx = body.indexOf('#');
    const name = hashIdx >= 0 ? safeDecode(body.substring(hashIdx + 1)) : '';
    const beforeHash = hashIdx >= 0 ? body.substring(0, hashIdx) : body;
    const qIdx = beforeHash.indexOf('?');
    const authority = qIdx >= 0 ? beforeHash.substring(0, qIdx) : beforeHash;
    const query = qIdx >= 0 ? parseQuery(beforeHash.substring(qIdx + 1)) : new Map<string, string>();

    const atIdx = authority.lastIndexOf('@');
    if (atIdx < 0) {
      throw new ShareLinkParseError('vless 链接缺少 @（无法分离 UUID 与地址）');
    }
    const uuid = authority.substring(0, atIdx);
    const hostPort = authority.substring(atIdx + 1);
    if (!uuid) {
      throw new ShareLinkParseError('vless 链接缺少 UUID');
    }

    const hp = ShareLinkParser.splitHostPort(hostPort, 'vless');
    const node = new XrayNode('', name || (hp.host + ':' + hp.port), hp.host, hp.port);
    node.protocol = 'vless';
    node.transport = mapTransport(query.get('type') || 'tcp');
    node.security = mapSecurity(query.get('security') || 'none');
    node.serverName = query.get('sni') || query.get('host') || '';
    node.wsPath = query.get('path') || '/';
    node.wsHost = query.get('host') || '';
    node.grpcService = query.get('serviceName') || '';
    node.flow = query.get('flow') || '';
    // REALITY 必需参数。缺 publicKey 的 REALITY 节点"能导入但必然握手失败"，
    // 所以这里照实解析出来，交由 KernelConfigBuilder / 编辑页校验。
    node.publicKey = query.get('pbk') || '';
    node.shortId = query.get('sid') || '';
    node.fingerprint = query.get('fp') || '';
    node.credentialRef = uuid; // TODO: 改为 HUKS/ASSET 引用，当前为明文占位
    node.remark = name;
    return node;
  }

  /** vmess://base64(json) */
  private static parseVmess(raw: string): XrayNode {
    const payload = raw.substring('vmess://'.length).trim();
    let json = '';
    try {
      json = b64decode(payload);
    } catch (e) {
      throw new ShareLinkParseError('vmess 链接 base64 解码失败');
    }
    let obj: Record<string, string> = {};
    try {
      obj = JSON.parse(json) as Record<string, string>;
    } catch (e) {
      throw new ShareLinkParseError('vmess 链接内容不是合法 JSON');
    }
    const host = (obj['add'] || '').toString();
    const portStr = (obj['port'] || '').toString();
    const port = parseInt(portStr, 10);
    if (!host || isNaN(port)) {
      throw new ShareLinkParseError('vmess 链接缺少地址或端口');
    }
    const net = (obj['net'] || 'tcp').toString();
    const tls = (obj['tls'] || '').toString();
    const node = new XrayNode('', (obj['ps'] || (host + ':' + port)).toString(), host, port);
    node.protocol = 'vmess';
    node.transport = mapTransport(net);
    node.security = tls === 'tls' ? SecurityKind.TLS : SecurityKind.NONE;
    node.serverName = (obj['sni'] || obj['host'] || '').toString();
    node.wsPath = (obj['path'] || '/').toString();
    node.wsHost = (obj['host'] || '').toString();
    node.grpcService = (obj['path'] || '').toString();
    node.credentialRef = (obj['id'] || '').toString(); // TODO: 安全存储
    node.remark = (obj['ps'] || '').toString();
    return node;
  }

  /** trojan://password@host:port?params#name */
  private static parseTrojan(raw: string): XrayNode {
    const body = raw.substring('trojan://'.length);
    const hashIdx = body.indexOf('#');
    const name = hashIdx >= 0 ? safeDecode(body.substring(hashIdx + 1)) : '';
    const beforeHash = hashIdx >= 0 ? body.substring(0, hashIdx) : body;
    const qIdx = beforeHash.indexOf('?');
    const authority = qIdx >= 0 ? beforeHash.substring(0, qIdx) : beforeHash;
    const query = qIdx >= 0 ? parseQuery(beforeHash.substring(qIdx + 1)) : new Map<string, string>();

    const atIdx = authority.lastIndexOf('@');
    if (atIdx < 0) {
      throw new ShareLinkParseError('trojan 链接缺少 @（无法分离密码与地址）');
    }
    const password = authority.substring(0, atIdx);
    const hp = ShareLinkParser.splitHostPort(authority.substring(atIdx + 1), 'trojan');
    const node = new XrayNode('', name || (hp.host + ':' + hp.port), hp.host, hp.port);
    node.protocol = 'trojan';
    node.transport = mapTransport(query.get('type') || 'tcp');
    node.security = mapSecurity(query.get('security') || 'tls');
    node.serverName = query.get('sni') || query.get('peer') || '';
    node.wsPath = query.get('path') || '/';
    node.wsHost = query.get('host') || '';
    node.credentialRef = password; // TODO: 安全存储
    node.remark = name;
    return node;
  }

  /** ss://base64(method:password)@host:port#name  或  ss://base64(整串) */
  private static parseShadowsocks(raw: string): XrayNode {
    const body = raw.substring('ss://'.length);
    const hashIdx = body.indexOf('#');
    const name = hashIdx >= 0 ? safeDecode(body.substring(hashIdx + 1)) : '';
    let core = hashIdx >= 0 ? body.substring(0, hashIdx) : body;
    const qIdx = core.indexOf('?');
    if (qIdx >= 0) {
      core = core.substring(0, qIdx);
    }
    let hostPort = '';
    let credential = '';
    if (core.indexOf('@') >= 0) {
      const atIdx = core.lastIndexOf('@');
      const userInfo = core.substring(0, atIdx);
      hostPort = core.substring(atIdx + 1);
      credential = userInfo.indexOf(':') >= 0 ? b64decode(userInfo) : b64decode(userInfo);
    } else {
      const decoded = b64decode(core);
      const atIdx = decoded.lastIndexOf('@');
      if (atIdx < 0) {
        throw new ShareLinkParseError('ss 链接格式无法识别（缺少 @）');
      }
      credential = decoded.substring(0, atIdx);
      hostPort = decoded.substring(atIdx + 1);
    }
    const hp = ShareLinkParser.splitHostPort(hostPort, 'ss');
    const node = new XrayNode('', name || (hp.host + ':' + hp.port), hp.host, hp.port);
    node.protocol = 'shadowsocks';
    node.transport = TransportKind.TCP;
    node.security = SecurityKind.NONE;
    node.credentialRef = credential; // method:password，TODO: 安全存储
    node.remark = name;
    return node;
  }

  /** host:port（支持 [ipv6]:port） */
  private static splitHostPort(hostPort: string, proto: string): HostPort {
    const hp = new HostPort();
    const v6 = hostPort.match(/^\[([^\]]+)\]:(\d+)$/);
    if (v6) {
      hp.host = v6[1];
      hp.port = parseInt(v6[2], 10);
    } else {
      const idx = hostPort.lastIndexOf(':');
      if (idx <= 0) {
        throw new ShareLinkParseError(proto + ' 链接缺少端口（应为 host:port）');
      }
      hp.host = hostPort.substring(0, idx);
      hp.port = parseInt(hostPort.substring(idx + 1), 10);
    }
    if (!hp.host) {
      throw new ShareLinkParseError(proto + ' 链接缺少主机地址');
    }
    if (isNaN(hp.port) || hp.port <= 0 || hp.port > 65535) {
      throw new ShareLinkParseError(proto + ' 链接端口非法');
    }
    return hp;
  }

  /** 自检：用脱敏假链接验证四条解析路径，返回一行摘要 */
  static selfTest(): string {
    const samples: string[] = [
      'vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&security=tls&type=ws&host=example.com&path=%2Fws#demo-vless',
      'vmess://' + 'eyJ2IjoiMiIsInBzIjoiZGVtby12bWVzcyIsImFkZCI6ImV4YW1wbGUubmV0IiwicG9ydCI6IjQ0MyIsImlkIjoiMDAwMDAwMDAtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAwIiwibmV0IjoidGNwIiwidGxzIjoidGxzIn0=',
      'trojan://password@example.org:443?security=tls&sni=example.org#demo-trojan',
      'ss://' + 'YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.io:8388#demo-ss'
    ];
    const names: string[] = ['vless', 'vmess', 'trojan', 'ss'];
    const out: string[] = [];
    for (let i = 0; i < samples.length; i++) {
      try {
        const n = ShareLinkParser.parse(samples[i]);
        out.push(names[i] + ': OK(' + n.protocol + '@' + n.address + ':' + n.port + ')');
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        out.push(names[i] + ': FAIL(' + msg + ')');
      }
    }
    return out.join(' / ');
  }
}

/** 解析结果的中间载体（ArkTS 不支持元组，用类代替） */
class HostPort {
  host: string = '';
  port: number = 0;
}
