/**
 * model/AppConfig.ets — 配置域模型（L-A 层）
 *
 * 职责：定义「用户意图」的数据结构（节点 / 订阅 / 分流规则 / 设置），
 * 并提供序列化与 schema 版本号，供后续迁移使用。
 *
 * 重要（design §4.7 三层真源）：
 *   L-A（本文件）= 唯一可编辑真源；
 *   L-B（内核 JSON）= 运行期由 L-A 生成，**不落盘、不回写**；
 *   因此本文件里**不出现**任何 Xray 配置字段（如 inbounds/outbounds/routing）。
 */

export const SCHEMA_VERSION: number = 1;

/** 传输层类型（刻意只保留客户端需要感知的项） */
export enum TransportKind {
  TCP = 'tcp',
  WS = 'ws',
  GRPC = 'grpc',
  HTTP2 = 'http2',
  MKCP = 'mkcp'
}

/** 安全层类型 */
export enum SecurityKind {
  NONE = 'none',
  TLS = 'tls',
  REALITY = 'reality'
}

/** 分流模式（与 FR-06 对应） */
export enum RoutingMode {
  GLOBAL = 'global',
  RULE = 'rule',
  DIRECT = 'direct'
}

/** 单个节点（凭据本身不落此结构，另存安全存储；这里只保留引用键） */
export class XrayNode {
  id: string = '';
  name: string = '';
  protocol: string = 'vless';
  address: string = '';
  port: number = 443;
  transport: TransportKind = TransportKind.TCP;
  security: SecurityKind = SecurityKind.TLS;
  /** SNI / serverName，reality 必填 */
  serverName: string = '';
  /** 凭据引用键（指向安全存储中的条目，不存明文） */
  credentialRef: string = '';
  /** 备注 */
  remark: string = '';

  constructor(id: string = '', name: string = '', address: string = '', port: number = 443) {
    this.id = id;
    this.name = name;
    this.address = address;
    this.port = port;
  }
}

/** 订阅源 */
export class Subscription {
  id: string = '';
  name: string = '';
  /** 订阅地址本身可能含 token，实际存储时应加密；L-A 只保存引用与外显名 */
  urlRef: string = '';
  lastUpdated: number = 0;
  nodeCount: number = 0;
}

/** 分流规则（最小形态） */
export class RoutingRule {
  id: string = '';
  /** domain / ip / keyword 等，先用字符串表达 */
  matchType: string = 'domain';
  pattern: string = '';
  /** proxy / direct / block */
  action: string = 'proxy';
  enabled: boolean = true;
}

/** 应用设置 */
export class AppSettings {
  routingMode: RoutingMode = RoutingMode.RULE;
  logLevel: string = 'INFO';
  /** 是否已看过首启说明（FR-17 用得上） */
  onboardingDone: boolean = false;
}

/** 顶层配置（L-A 根对象） */
export class AppConfig {
  schemaVersion: number = SCHEMA_VERSION;
  nodes: XrayNode[] = [];
  subscriptions: Subscription[] = [];
  rules: RoutingRule[] = [];
  settings: AppSettings = new AppSettings();
  selectedNodeId: string = '';

  /** 找到当前选中节点（找不到返回 null，调用方必须处理） */
  findSelectedNode(): XrayNode | null {
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === this.selectedNodeId) {
        return this.nodes[i];
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// 序列化 / 反序列化
// 说明：ArkTS 下 JSON.parse 得到的是松散对象，这里逐字段赋值，避免把外部结构
// 直接当成 AppConfig 使用（同时也为后续 schema 迁移留出显式检查点）。
// ---------------------------------------------------------------------------

interface RawNode {
  id?: string; name?: string; protocol?: string; address?: string; port?: number;
  transport?: string; security?: string; serverName?: string; credentialRef?: string; remark?: string;
}
interface RawSubscription {
  id?: string; name?: string; urlRef?: string; lastUpdated?: number; nodeCount?: number;
}
interface RawRule {
  id?: string; matchType?: string; pattern?: string; action?: string; enabled?: boolean;
}
interface RawSettings {
  routingMode?: string; logLevel?: string; onboardingDone?: boolean;
}
interface RawConfig {
  schemaVersion?: number; nodes?: RawNode[]; subscriptions?: RawSubscription[];
  rules?: RawRule[]; settings?: RawSettings; selectedNodeId?: string;
}

function toTransport(v: string | undefined): TransportKind {
  if (v === 'ws') return TransportKind.WS;
  if (v === 'grpc') return TransportKind.GRPC;
  if (v === 'http2') return TransportKind.HTTP2;
  if (v === 'mkcp') return TransportKind.MKCP;
  return TransportKind.TCP;
}

function toSecurity(v: string | undefined): SecurityKind {
  if (v === 'none') return SecurityKind.NONE;
  if (v === 'reality') return SecurityKind.REALITY;
  return SecurityKind.TLS;
}

function toRoutingMode(v: string | undefined): RoutingMode {
  if (v === 'global') return RoutingMode.GLOBAL;
  if (v === 'direct') return RoutingMode.DIRECT;
  return RoutingMode.RULE;
}

export class ConfigCodec {
  /** 序列化为可落盘的 JSON 文本 */
  static encode(cfg: AppConfig): string {
    return JSON.stringify(cfg);
  }

  /**
   * 反序列化。返回 null 表示「不可用」，调用方必须走安全模式（仅直连）而不是猜测。
   * 版本更高 → 拒绝（不尝试逆向迁移，见 design §4.2）。
   */
  static decode(text: string): AppConfig | null {
    if (text.length === 0) {
      return null;
    }
    let raw: RawConfig | null = null;
    try {
      raw = JSON.parse(text) as RawConfig;
    } catch (e) {
      return null;
    }
    if (raw === null) {
      return null;
    }
    const version: number = raw.schemaVersion === undefined ? 0 : raw.schemaVersion;
    if (version > SCHEMA_VERSION) {
      return null; // 降级安装：拒绝加载，避免数据损坏
    }

    const cfg = new AppConfig();
    cfg.schemaVersion = SCHEMA_VERSION;

    const rawNodes: RawNode[] = raw.nodes === undefined ? [] : raw.nodes;
    for (let i = 0; i < rawNodes.length; i++) {
      const rn = rawNodes[i];
      const n = new XrayNode(rn.id === undefined ? '' : rn.id,
        rn.name === undefined ? '' : rn.name,
        rn.address === undefined ? '' : rn.address,
        rn.port === undefined ? 443 : rn.port);
      n.protocol = rn.protocol === undefined ? 'vless' : rn.protocol;
      n.transport = toTransport(rn.transport);
      n.security = toSecurity(rn.security);
      n.serverName = rn.serverName === undefined ? '' : rn.serverName;
      n.credentialRef = rn.credentialRef === undefined ? '' : rn.credentialRef;
      n.remark = rn.remark === undefined ? '' : rn.remark;
      cfg.nodes.push(n);
    }

    const rawSubs: RawSubscription[] = raw.subscriptions === undefined ? [] : raw.subscriptions;
    for (let i = 0; i < rawSubs.length; i++) {
      const rs = rawSubs[i];
      const s = new Subscription();
      s.id = rs.id === undefined ? '' : rs.id;
      s.name = rs.name === undefined ? '' : rs.name;
      s.urlRef = rs.urlRef === undefined ? '' : rs.urlRef;
      s.lastUpdated = rs.lastUpdated === undefined ? 0 : rs.lastUpdated;
      s.nodeCount = rs.nodeCount === undefined ? 0 : rs.nodeCount;
      cfg.subscriptions.push(s);
    }

    const rawRules: RawRule[] = raw.rules === undefined ? [] : raw.rules;
    for (let i = 0; i < rawRules.length; i++) {
      const rr = rawRules[i];
      const r = new RoutingRule();
      r.id = rr.id === undefined ? '' : rr.id;
      r.matchType = rr.matchType === undefined ? 'domain' : rr.matchType;
      r.pattern = rr.pattern === undefined ? '' : rr.pattern;
      r.action = rr.action === undefined ? 'proxy' : rr.action;
      r.enabled = rr.enabled === undefined ? true : rr.enabled;
      cfg.rules.push(r);
    }

    if (raw.settings !== undefined) {
      cfg.settings.routingMode = toRoutingMode(raw.settings.routingMode);
      cfg.settings.logLevel = raw.settings.logLevel === undefined ? 'INFO' : raw.settings.logLevel;
      cfg.settings.onboardingDone = raw.settings.onboardingDone === undefined ? false : raw.settings.onboardingDone;
    }
    cfg.selectedNodeId = raw.selectedNodeId === undefined ? '' : raw.selectedNodeId;
    return cfg;
  }
}

/** 默认配置（首启 / 安全模式共用） */
export function createDefaultConfig(): AppConfig {
  const cfg = new AppConfig();
  cfg.nodes.push(new XrayNode('n1', '示例节点 A（占位）', '203.0.113.10', 443));
  cfg.nodes.push(new XrayNode('n2', '示例节点 B（占位）', '203.0.113.11', 443));
  cfg.nodes.push(new XrayNode('n3', '示例节点 C（占位）', '203.0.113.12', 443));
  cfg.selectedNodeId = 'n1';
  const r = new RoutingRule();
  r.id = 'r1';
  r.matchType = 'domain';
  r.pattern = 'geosite:cn';
  r.action = 'direct';
  cfg.rules.push(r);
  return cfg;
}
