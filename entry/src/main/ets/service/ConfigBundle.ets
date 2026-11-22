import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BundleCipher, BundleCrypto } from '../platform/BundleCrypto';
import { Logger } from '../platform/Logger';
import { ConfigService } from './ConfigService';
import { RoutingRule, SecurityKind, TransportKind, XrayNode } from '../model/AppConfig';

/**
 * service/ConfigBundle.ets — 配置备份与恢复（加密的自包含文件）
 *
 * 目的只有一个：**离开这台设备**。换机、重装、给别人一份能直接用的配置。
 * （订阅解决的是"跟着上游更新"，两者不互相替代。）
 *
 * 文件是**自包含且加密**的：
 *   - 含凭据（否则恢复出来是一堆连不上的空壳）；
 *   - 但凭据在文件里始终是密文，解密唯一手段是用户口令；
 *   - 明文部分只放"够让接收方判断这是什么"的元信息：格式、版本、导出时间、条目数，
 *     **不放节点地址、不放在此设备上的任何标识**。
 *
 * 恢复行为：
 *   - 节点一律**新建 id**（避免与现有节点撞 id），凭据重新写入本机安全存储；
 *   - 与已有节点同 protocol+address+port 的跳过（沿用 addNodeSecure 的去重语义）；
 *   - 规则按 pattern+action 去重后追加；
 *   - 设置（分流模式/日志级别）**不覆盖**本机现有值 —— 恢复别人的配置不该顺手改我的分流策略。
 */

/** 文件格式常量：改结构必须同时改 version，旧文件仍可识别 */
const FORMAT: string = 'tunnelix-bundle';
const VERSION: number = 1;
const SCHEMA: number = 1;

interface BundleMeta {
  exportedAt: number;
  nodeCount: number;
  ruleCount: number;
  hasCredentials: boolean;
}

interface BundleEnvelope {
  format: string;
  version: number;
  kdf: string;
  iterations: number;
  salt: string;
  cipher: string;
  nonce: string;
  body: string;
  meta: BundleMeta;
}

interface BundleNode {
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
  remark: string;
  group: string;
  publicKey: string;
  shortId: string;
  fingerprint: string;
  /** 明文凭据，只在内存里存在；落文件前整体被加密 */
  credential: string;
}

interface BundleRule {
  matchType: string;
  pattern: string;
  action: string;
  enabled: boolean;
}

interface BundlePayload {
  schema: number;
  exportedAt: number;
  nodes: BundleNode[];
  rules: BundleRule[];
}

/** 导入结果：UI 只需要"成功几条 / 跳过几条 / 失败原因" */
export class BundleImportResult {
  ok: boolean = false;
  error: string = '';
  addedNodes: number = 0;
  skippedNodes: number = 0;
  addedRules: number = 0;
  skippedRules: number = 0;
  /** 凭据缺失的节点数（对方导出时该节点凭据已丢失） */
  missingCredentials: number = 0;
  /**
   * 逐条明细。
   *
   * 为什么不只给数字：“导入 3 个、跳过 2 个”无法回答用户最关心的问题——
   * **跳过的是哪两个**。用户需要能对照自己的节点表判断“是真的重复，还是我漏了什么”。
   */
  details: ImportDetail[] = [];
}

/** 导入明细行 */
export class ImportDetail {
  name: string = '';
  /** added / skipped / missing-credential */
  outcome: string = '';
  /** 人话原因；added 为空串 */
  reason: string = '';
}

export class ConfigBundle {
  /**
   * 生成文件全文。
   * 凭据逐条从安全存储取出，**只有在这一次序列化过程中**才存在于内存。
   */
  static async exportToText(passphrase: string): Promise<string> {
    if (BundleCrypto.isWeak(passphrase)) {
      throw new Error(BundleCrypto.weaknessHint(passphrase));
    }
    const cfg: ConfigService = ConfigService.getInstance();
    const nodes: XrayNode[] = cfg.getNodes();
    const payload: BundlePayload = {
      schema: SCHEMA,
      exportedAt: Date.now(),
      nodes: [],
      rules: []
    };
    let missing: number = 0;
    for (let i = 0; i < nodes.length; i++) {
      const n: XrayNode = nodes[i];
      const bn: BundleNode = ConfigBundle.toBundleNode(n);
      const secret: string | null = await cfg.resolveCredential(n);
      if (secret === null) {
        missing++;
        bn.credential = '';
      } else {
        bn.credential = secret;
      }
      payload.nodes.push(bn);
    }
    const rules: RoutingRule[] = cfg.getRules();
    for (let i = 0; i < rules.length; i++) {
      const br: BundleRule = {
        matchType: rules[i].matchType,
        pattern: rules[i].pattern,
        action: rules[i].action,
        enabled: rules[i].enabled
      };
      payload.rules.push(br);
    }

    const cipher: BundleCipher = await BundleCrypto.encrypt(JSON.stringify(payload), passphrase);
    const envelope: BundleEnvelope = {
      format: FORMAT,
      version: VERSION,
      kdf: 'PBKDF2|SHA256',
      iterations: BundleCrypto.ITERATIONS,
      salt: cipher.salt,
      cipher: 'AES256|GCM|NoPadding',
      nonce: cipher.nonce,
      body: cipher.body,
      meta: {
        exportedAt: payload.exportedAt,
        nodeCount: payload.nodes.length,
        ruleCount: payload.rules.length,
        hasCredentials: missing < payload.nodes.length
      }
    };
    Logger.info(`bundle export: nodes=${payload.nodes.length} rules=${payload.rules.length} missingCreds=${missing}`);
    return JSON.stringify(envelope, null, 2);
  }

  /** 读取文件头（不解密）：用于导入前先把"这是不是我们的文件"说清楚 */
  static peekMeta(text: string): BundleMeta | null {
    try {
      const env: BundleEnvelope = JSON.parse(text) as BundleEnvelope;
      if (env === null || env.format !== FORMAT) {
        return null;
      }
      return env.meta === undefined ? null : env.meta;
    } catch (e) {
      return null;
    }
  }

  static async importFromText(text: string, passphrase: string): Promise<BundleImportResult> {
    const result = new BundleImportResult();
    let env: BundleEnvelope;
    try {
      env = JSON.parse(text) as BundleEnvelope;
    } catch (e) {
      result.error = '这不是有效的配置文件（无法解析）';
      return result;
    }
    if (env === null || env.format !== FORMAT) {
      result.error = '文件格式不匹配：请选择本应用导出的备份文件';
      return result;
    }
    if (env.version > VERSION) {
      result.error = `备份文件版本 ${env.version} 高于当前应用支持的 ${VERSION}，请先升级应用`;
      return result;
    }

    const cipher: BundleCipher = new BundleCipher();
    cipher.salt = env.salt;
    cipher.nonce = env.nonce;
    cipher.body = env.body;
    let plain: string = '';
    try {
      plain = await BundleCrypto.decrypt(cipher, passphrase);
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      result.error = m;
      return result;
    }

    let payload: BundlePayload;
    try {
      payload = JSON.parse(plain) as BundlePayload;
    } catch (e) {
      result.error = '文件内容无法解析（可能已损坏）';
      return result;
    }

    const cfg: ConfigService = ConfigService.getInstance();
    for (let i = 0; i < payload.nodes.length; i++) {
      const bn: BundleNode = payload.nodes[i];
      if (bn.credential.length === 0) {
        result.missingCredentials++;
      }
      const node: XrayNode = ConfigBundle.toNode(bn);
      const added: boolean = await cfg.addNodeSecure(node);
      const d = new ImportDetail();
      d.name = bn.name;
      if (added) {
        result.addedNodes++;
        d.outcome = bn.credential.length === 0 ? 'missing-credential' : 'added';
        d.reason = bn.credential.length === 0 ? '已导入，但缺少凭据，需手工补填' : '';
      } else {
        result.skippedNodes++;
        d.outcome = 'skipped';
        // 去重依据是 protocol+address+port，告诉用户具体是哪三项重了
        d.reason = `已存在同地址节点（${bn.protocol} ${bn.address}:${bn.port}）`;
      }
      result.details.push(d);
    }

    const existing: RoutingRule[] = cfg.getRules();
    for (let i = 0; i < payload.rules.length; i++) {
      const br: BundleRule = payload.rules[i];
      let dup: boolean = false;
      for (let k = 0; k < existing.length; k++) {
        if (existing[k].pattern === br.pattern && existing[k].action === br.action) {
          dup = true;
          break;
        }
      }
      if (dup) {
        result.skippedRules++;
        continue;
      }
      if (cfg.addRule(br.matchType, br.pattern, br.action)) {
        result.addedRules++;
      } else {
        result.skippedRules++;
      }
    }

    result.ok = true;
    Logger.info(`bundle import: nodes added=${result.addedNodes} skipped=${result.skippedNodes} ` +
      `rules added=${result.addedRules} skipped=${result.skippedRules} missingCreds=${result.missingCredentials}`);
    return result;
  }

  private static toBundleNode(n: XrayNode): BundleNode {
    const bn: BundleNode = {
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
      remark: n.remark,
      group: n.group,
      publicKey: n.publicKey,
      shortId: n.shortId,
      fingerprint: n.fingerprint,
      credential: ''
    };
    return bn;
  }

  private static toNode(bn: BundleNode): XrayNode {
    // 新 id：导入不 Inherit 对方设备上的标识，也避免与现有节点撞 id
    const node = new XrayNode(ConfigBundle.newId(), bn.name, bn.address, bn.port);
    node.protocol = bn.protocol;
    node.transport = ConfigBundle.transportOf(bn.transport);
    node.security = ConfigBundle.securityOf(bn.security);
    node.serverName = bn.serverName;
    node.wsPath = bn.wsPath;
    node.wsHost = bn.wsHost;
    node.grpcService = bn.grpcService;
    node.flow = bn.flow;
    node.remark = bn.remark;
    node.group = bn.group;
    node.publicKey = bn.publicKey;
    node.shortId = bn.shortId;
    node.fingerprint = bn.fingerprint;
    node.credentialRef = bn.credential;
    return node;
  }

  /** 字符串 → 传输枚举；未知值回落 TCP（与编辑页的默认一致） */
  private static transportOf(v: string): TransportKind {
    if (v === 'ws') {
      return TransportKind.WS;
    }
    if (v === 'grpc') {
      return TransportKind.GRPC;
    }
    if (v === 'mkcp') {
      return TransportKind.MKCP;
    }
    return TransportKind.TCP;
  }

  /** 字符串 → 安全层枚举；未知值回落 TLS */
  private static securityOf(v: string): SecurityKind {
    if (v === 'none') {
      return SecurityKind.NONE;
    }
    if (v === 'reality') {
      return SecurityKind.REALITY;
    }
    return SecurityKind.TLS;
  }

  private static newId(): string {
    const blob: cryptoFramework.DataBlob = cryptoFramework.createRandom().generateRandomSync(8);
    const hex: string = new util.Base64Helper().encodeToStringSync(blob.data)
      .replace(/[+/=]/g, '');
    return `node-${hex.substring(0, 12)}`;
  }
}
