/**
 * service/NodeStore.ets — 节点持久化（最小实现）
 *
 * 方案：AppStorage + PersistentStorage（ArkUI 持久化属性），无需 Context，
 *       由框架负责落盘与恢复。数据以 JSON 字符串形式保存，带 schema 版本号。
 *
 * 约束（与 ConfigService 同一原则）：
 *   1. **读取失败绝不覆盖原数据**：解析失败时返回 null 并由调用方决定处理，
 *      本模块不主动写入；
 *   2. 凭据目前随节点一起明文落盘 —— TODO：迁移到 HUKS/ASSET 引用，
 *      迁移完成后本文件只保存 credentialRef，不保存明文。
 */

import { XrayNode, TransportKind, SecurityKind } from '../model/AppConfig';
import { Logger } from '../platform/Logger';

const KEY: string = 'tunnelix_nodes_v1';
/**
 * schema 2：`credentialRef` 语义从「明文凭据」改为「Asset Store 别名（`node:<id>`）」。
 * v1 数据仍可读，由 ConfigService 做一次性迁移（不静默丢弃）。
 */
const SCHEMA: number = 2;
/** v1：credentialRef 是明文凭据 */
const SCHEMA_PLAINTEXT: number = 1;

/** 载入结果：把 schema 一并交给调用方，迁移决策必须基于它，不能靠猜 */
export class NodeLoadResult {
  /** false = 读到了但解析失败（调用方必须保留原数据、禁止覆盖写） */
  ok: boolean = false;
  /** 落盘时的 schema 版本；首次启动为 0 */
  schema: number = 0;
  nodes: XrayNode[] = [];
  /** 是否所有凭据都已是别名形式（false ⇒ 需要迁移） */
  allSecretsMigrated: boolean = true;
}

/** 落盘用的扁平结构（只存必要字段，且字段名短一些以减小体积） */
interface StoredNode {
  id: string;
  name: string;
  protocol: string;
  address: string;
  port: number;
  transport: string;
  security: string;
  serverName: string;
  wsPath: string;
  wsHost: string;
  grpcService: string;
  flow: string;
  credentialRef: string;
  remark: string;
}

interface StoredPayload {
  schema: number;
  nodes: StoredNode[];
}

export class NodeStore {
  /** 初始化持久化属性（幂等，可多次调用） */
  static ensure(): void {
    PersistentStorage.persistProp<string>(KEY, '');
  }

  /** 保存节点列表；返回 false 表示参数不合法（未写入） */
  static save(nodes: XrayNode[]): boolean {
    try {
      NodeStore.ensure();
      const list: StoredNode[] = [];
      for (let i = 0; i < nodes.length; i++) {
        list.push(NodeStore.toStored(nodes[i]));
      }
      const payload: StoredPayload = { schema: SCHEMA, nodes: list };
      AppStorage.setOrCreate<string>(KEY, JSON.stringify(payload));
      Logger.info(`nodeStore save ok: ${list.length} node(s)`);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`nodeStore save failed: ${msg}`);
      return false;
    }
  }

  /**
   * 读取节点列表（含 schema 与迁移状态）。
   * ok=false 表示「读到了但解析失败」，调用方必须**保留原数据、不得覆盖**。
   * ok=true 且 nodes 为空表示「没有已保存的节点」（首次启动）。
   */
  static loadResult(): NodeLoadResult {
    const out = new NodeLoadResult();
    try {
      NodeStore.ensure();
      const raw: string | undefined = AppStorage.get<string>(KEY);
      if (raw === undefined || raw === '') {
        out.ok = true;
        out.schema = 0;
        return out;
      }
      const payload: StoredPayload = JSON.parse(raw) as StoredPayload;
      if (payload === null || payload.nodes === undefined) {
        Logger.error('nodeStore load: payload malformed (missing nodes)');
        out.ok = false;
        return out;
      }
      out.schema = payload.schema === undefined ? SCHEMA_PLAINTEXT : payload.schema;
      if (out.schema !== SCHEMA) {
        // 版本不符：不静默丢弃，交给调用方决定迁移或安全失败
        Logger.warn(`nodeStore load: schema ${out.schema} != ${SCHEMA}`);
      }
      for (let i = 0; i < payload.nodes.length; i++) {
        const n: XrayNode = NodeStore.fromStored(payload.nodes[i]);
        out.nodes.push(n);
        // v1 数据的 credentialRef 是明文；别名形如 node:<id>
        if (n.credentialRef.length > 0 && !n.credentialRef.startsWith('node:')) {
          out.allSecretsMigrated = false;
        }
      }
      out.ok = true;
      Logger.info(`nodeStore load ok: ${out.nodes.length} node(s) schema=${out.schema} migrated=${out.allSecretsMigrated}`);
      return out;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`nodeStore load failed: ${msg}`);
      out.ok = false;
      return out;
    }
  }

  /** 兼容旧调用：只需要节点列表时用它；失败返回 null */
  static load(): XrayNode[] | null {
    const r: NodeLoadResult = NodeStore.loadResult();
    return r.ok ? r.nodes : null;
  }

  private static toStored(n: XrayNode): StoredNode {
    const s: StoredNode = {
      id: n.id,
      name: n.name,
      protocol: n.protocol,
      address: n.address,
      port: n.port,
      transport: n.transport as string,
      security: n.security as string,
      serverName: n.serverName,
      wsPath: n.wsPath,
      wsHost: n.wsHost,
      grpcService: n.grpcService,
      flow: n.flow,
      credentialRef: n.credentialRef, // TODO: 改为 HUKS/ASSET 引用
      remark: n.remark
    };
    return s;
  }

  private static fromStored(s: StoredNode): XrayNode {
    const n: XrayNode = new XrayNode(s.id, s.name, s.address, s.port);
    n.protocol = s.protocol;
    n.transport = NodeStore.transportOf(s.transport);
    n.security = NodeStore.securityOf(s.security);
    n.serverName = s.serverName;
    n.wsPath = s.wsPath;
    n.wsHost = s.wsHost;
    n.grpcService = s.grpcService;
    n.flow = s.flow;
    n.credentialRef = s.credentialRef; // TODO: 安全存储引用
    n.remark = s.remark;
    return n;
  }

  private static transportOf(v: string): TransportKind {
    if (v === 'ws') {
      return TransportKind.WS;
    }
    if (v === 'grpc') {
      return TransportKind.GRPC;
    }
    if (v === 'http2') {
      return TransportKind.HTTP2;
    }
    if (v === 'mkcp') {
      return TransportKind.MKCP;
    }
    return TransportKind.TCP;
  }

  private static securityOf(v: string): SecurityKind {
    if (v === 'tls') {
      return SecurityKind.TLS;
    }
    if (v === 'reality') {
      return SecurityKind.REALITY;
    }
    return SecurityKind.NONE;
  }
}
