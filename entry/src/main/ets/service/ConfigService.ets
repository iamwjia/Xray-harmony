import { AppConfig, AppSettings, ConfigCodec, createDefaultConfig, XrayNode, RoutingMode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';
import { SecretStore } from '../platform/SecretStore';
import { NodeStore, NodeLoadResult } from './NodeStore';
import { SettingsStore, SettingsSnapshot } from './SettingsStore';

/**
 * service/ConfigService.ets — 配置读写服务（应用服务层）
 *
 * 职责：持有当前 L-A 配置实例、提供节点选择等用例级操作。
 * 边界：不碰 UI；不生成内核 JSON（后续由 KernelConfigBuilder 负责）。
 *
 * 数据安全约束（2026-10-18 评审增补）：
 *   1. **解码失败绝不覆盖原数据**：内存退回默认值，但保留原始文本
 *      （`rawTextOnLoadFailure`，只读、仅供诊断/恢复），并让 `canPersist()` 返回 false；
 *   2. **保存前必须 `confirmOverwrite()`**：显式表示"用户已知悉会覆盖"；
 *   3. 失败状态必须**在 UI 可见**（首页横幅），不允许只写在日志里。
 *      静默降级到默认配置，最容易造成"用户节点全没了"的事故。
 */
export class ConfigService {
  private static instance: ConfigService | null = null;
  private config: AppConfig;

  /** 上次加载是否失败（true ⇒ 当前 config 可能是默认值，而非用户真实配置） */
  private loadFailed: boolean = false;
  /** 加载失败时保留的原始文本：只读，绝不自动写回 */
  private rawTextOnLoadFailure: string = '';
  /** 用户是否已确认"允许用当前内存配置覆盖原数据" */
  private overwriteConfirmed: boolean = false;
  /** 上次设置写盘失败的原因（空串 = 没有失败），供 UI 横幅使用 */
  private persistError: string = '';
  /** v1 明文凭据待迁移到 Asset Store */
  private pendingCredentialMigration: boolean = false;
  /** 迁移失败原因（空串 = 无失败）；失败时必须阻断依赖明文凭据的连接 */
  private migrationError: string = '';

  private constructor() {
    this.config = createDefaultConfig();
    // 骨架期无持久化：用一次 encode→decode 往返，让 codec 从第一天就在真实路径上被跑过。
    // 接入存储后改为：读原始文本 → ConfigCodec.decode() → 判空。
    const encoded: string = ConfigCodec.encode(this.config);
    const decoded: AppConfig | null = ConfigCodec.decode(encoded);
    if (decoded === null) {
      this.loadFailed = true;
      this.rawTextOnLoadFailure = encoded;
      Logger.error('config decode failed at startup: using defaults; persistence disabled until user confirms');
    } else {
      this.config = decoded;
    }
    // 载入已保存的节点：解析失败时**保留原数据**，只记日志（不覆盖、不清空）
    const loaded: NodeLoadResult = NodeStore.loadResult();
    if (!loaded.ok) {
      Logger.error('nodeStore: persisted nodes unreadable; keeping in-memory defaults, persistence blocked until user confirms');
    } else if (loaded.nodes.length > 0) {
      this.config.nodes = loaded.nodes;
      if (!this.config.selectedNodeId) {
        this.config.selectedNodeId = loaded.nodes[0].id;
      }
      // v1 明文凭据需要迁移到 Asset Store（FR-35 / NFR-06）
      this.pendingCredentialMigration = !loaded.allSecretsMigrated;
      if (this.pendingCredentialMigration) {
        Logger.warn('credential migration pending: v1 plaintext credentialRef detected');
      }
    }
    // 载入设置（分流模式/日志级别）：解析失败时保留默认值，不写盘覆盖
    const settings: SettingsSnapshot | null = SettingsStore.load();
    if (settings === null) {
      Logger.error('settingsStore: persisted settings unreadable; keeping defaults, not overwriting');
    } else {
      if (settings.routingMode.length > 0) {
        this.config.settings.routingMode = ConfigService.routingModeOf(settings.routingMode);
      }
      if (settings.logLevel.length > 0) {
        this.config.settings.logLevel = settings.logLevel;
      }
      this.config.settings.onboardingDone = settings.onboardingDone;
    }
  }

  /** 字符串 → 枚举（解码与外部输入的统一入口，未知值回落 RULE） */
  private static routingModeOf(v: string): RoutingMode {
    if (v === 'global') {
      return RoutingMode.GLOBAL;
    }
    if (v === 'direct') {
      return RoutingMode.DIRECT;
    }
    return RoutingMode.RULE;
  }

  /** 设置落盘：与节点分开存，减少写放大 */
  private persistSettings(): boolean {
    if (!this.canPersist()) {
      Logger.error('settings save blocked: config load failed and overwrite not confirmed');
      this.persistError = '配置读取异常，已禁止写入（避免覆盖原数据）';
      return false;
    }
    const s: AppSettings = this.config.settings;
    const ok: boolean = SettingsStore.save(s.routingMode as string, s.logLevel, s.onboardingDone);
    this.persistError = ok ? '' : '设置保存失败，已恢复原值（详见日志）';
    return ok;
  }

  /**
   * 上次设置写盘失败的原因（UI 横幅用）。
   * 空串表示没有失败。FR-44：写失败**必须可见**，不允许"看着改了其实没存"。
   */
  getPersistError(): string {
    return this.persistError;
  }

  getRoutingMode(): RoutingMode {
    return this.config.settings.routingMode;
  }

  static getInstance(): ConfigService {
    if (ConfigService.instance === null) {
      ConfigService.instance = new ConfigService();
    }
    return ConfigService.instance;
  }

  getConfig(): AppConfig {
    return this.config;
  }

  getNodes(): XrayNode[] {
    return this.config.nodes;
  }

  getSelectedNode(): XrayNode | null {
    return this.config.findSelectedNode();
  }

  /** 配置加载是否失败（UI 横幅用） */
  hasLoadFailure(): boolean {
    return this.loadFailed;
  }

  /** 仅用于诊断/恢复；不要在保存路径里使用 */
  getRawTextOnLoadFailure(): string {
    return this.rawTextOnLoadFailure;
  }

  /** 是否允许落盘：加载失败时必须先经用户确认覆盖 */
  canPersist(): boolean {
    return !this.loadFailed || this.overwriteConfirmed;
  }

  /**
   * TODO(删除)：仅骨架期调试用——模拟"配置读取失败"，以验证首页横幅与保存拦截是否真的生效。
   * 删除条件：持久化接入并有真实失败路径可复现后。
   */
  debugForceLoadFailure(): void {
    this.loadFailed = true;
    this.overwriteConfirmed = false;
    Logger.warn('debug: forced config load failure (banner + save-block path)');
  }

  /** UI 上显式确认「用当前配置覆盖」后才允许写盘 */
  confirmOverwrite(): void {
    this.overwriteConfirmed = true;
    Logger.warn('user confirmed overwrite after config load failure');
  }

  /** 选择节点（不校验可用性——可用性由后续 health 检查负责） */
  selectNode(id: string): boolean {
    const cfg = this.config;
    for (let i = 0; i < cfg.nodes.length; i++) {
      if (cfg.nodes[i].id === id) {
        cfg.selectedNodeId = id;
        Logger.info(`selectNode -> ${id}`);
        return true;
      }
    }
    Logger.warn(`selectNode: unknown id ${id}`);
    return false;
  }

  /**
   * 添加节点（分享链接导入后调用）。按 protocol + address + port 去重。
   * 若当前无选中节点，则自动选中所添加的节点。
   */
  addNode(node: XrayNode): boolean {
    const cfg = this.config;
    for (let i = 0; i < cfg.nodes.length; i++) {
      const n = cfg.nodes[i];
      if (n.protocol === node.protocol && n.address === node.address && n.port === node.port) {
        Logger.warn(`addNode duplicated: ${node.protocol}@${node.address}:${node.port}`);
        cfg.selectedNodeId = n.id;
        return false;
      }
    }
    cfg.nodes.push(node);
    NodeStore.save(cfg.nodes);
    if (!cfg.selectedNodeId) {
      cfg.selectedNodeId = node.id;
    }
    Logger.info(`addNode ok: ${node.protocol}@${node.address}:${node.port} total=${cfg.nodes.length}`);
    return true;
  }
  /**
   * 删除节点（不可恢复）。
   *
   * 顺序：改内存 → 落盘 → 成功后才删密钥。
   * 落盘失败必须**回滚内存**，否则会出现"界面删了、重启又回来"的假删除。
   * 密钥删除失败只记日志：残留的 secret 不可寻址（别名已不在节点表里），
   * 危害远小于"节点表与内存不一致"。
   */
  async removeNode(id: string): Promise<boolean> {
    const cfg = this.config;
    let idx: number = -1;
    for (let i = 0; i < cfg.nodes.length; i++) {
      if (cfg.nodes[i].id === id) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      Logger.warn(`removeNode: unknown id ${id}`);
      return false;
    }
    if (!this.canPersist()) {
      Logger.error('removeNode blocked: persistence disabled');
      return false;
    }

    const removed: XrayNode = cfg.nodes[idx];
    const prevSelected: string = cfg.selectedNodeId;
    cfg.nodes.splice(idx, 1);
    if (cfg.selectedNodeId === id) {
      cfg.selectedNodeId = cfg.nodes.length > 0 ? cfg.nodes[0].id : '';
    }
    if (!NodeStore.save(cfg.nodes)) {
      // 回滚：内存必须与磁盘一致
      cfg.nodes.splice(idx, 0, removed);
      cfg.selectedNodeId = prevSelected;
      Logger.error(`removeNode failed to persist, rolled back: ${id}`);
      return false;
    }

    const alias: string = removed.credentialRef.startsWith('node:')
      ? removed.credentialRef
      : SecretStore.aliasForNode(removed.id);
    if (!await SecretStore.remove(alias)) {
      Logger.warn(`removeNode: node removed but secret cleanup failed for ${alias}`);
    }
    Logger.info(`removeNode ok: ${removed.protocol}@${removed.address}:${removed.port} total=${cfg.nodes.length}`);
    return true;
  }

  /** 是否存在待迁移的明文凭据（UI 可据此提示） */
  hasPendingCredentialMigration(): boolean {
    return this.pendingCredentialMigration;
  }

  /** 迁移失败原因（空串 = 无失败） */
  getMigrationError(): string {
    return this.migrationError;
  }

  /**
   * 一次性迁移：v1 明文 `credentialRef` → Asset Store，节点表只留别名（`node:<id>`）。
   *
   * 顺序是刻意的：**先写入安全存储，全部成功后才写 v2 节点表**。
   * 任一步失败就保留明文原数据并返回 false —— 宁可继续用明文跑，
   * 也不能出现"凭据进了安全存储、节点表却写坏"的半成品状态。
   */
  async ensureSecureMigration(): Promise<boolean> {
    if (!this.pendingCredentialMigration) {
      return true;
    }
    if (!this.canPersist()) {
      this.migrationError = '配置读取异常，暂不迁移凭据（原数据未改动）';
      Logger.error('credential migration skipped: persistence blocked');
      return false;
    }
    const nodes: XrayNode[] = this.config.nodes;
    for (let i = 0; i < nodes.length; i++) {
      const n: XrayNode = nodes[i];
      if (n.credentialRef.length === 0 || n.credentialRef.startsWith('node:')) {
        continue;
      }
      const alias: string = SecretStore.aliasForNode(n.id);
      const ok: boolean = await SecretStore.put(alias, n.credentialRef);
      if (!ok) {
        this.migrationError = '凭据迁移失败（原数据未改动，仍为明文），请查看日志';
        Logger.error(`credential migration aborted at node ${n.id}: asset store put failed`);
        return false;
      }
      n.credentialRef = alias;
    }
    if (!NodeStore.save(nodes)) {
      this.migrationError = '凭据已迁移但节点表写入失败，仍按原数据运行';
      Logger.error('credential migration: nodes persist failed');
      return false;
    }
    this.pendingCredentialMigration = false;
    this.migrationError = '';
    Logger.info('credential migration done: credentialRef are asset aliases now');
    return true;
  }

  /**
   * 取节点凭据明文。
   * 返回 null = 取不到。调用方**必须阻断连接**，不能拿空串当凭据硬连——
   * 那样内核只会给出一个与真实原因无关的握手错误。
   *
   * 兼容旧别名：早期版本的别名是 `node:<host:port>`，命中旧别名时顺手迁到
   * 哈希别名并删除旧条目（别名本身不该泄漏服务器地址）。
   */
  async resolveCredential(node: XrayNode): Promise<string | null> {
    const alias: string = SecretStore.aliasForNode(node.id);
    const fresh: string | null = await SecretStore.get(alias);
    if (fresh !== null) {
      return fresh;
    }
    const legacy: string = SecretStore.legacyAliasForNode(node.id);
    const old: string | null = await SecretStore.get(legacy);
    if (old === null) {
      return null;
    }
    Logger.warn('credential found under legacy alias, re-keying to hashed alias');
    if (await SecretStore.put(alias, old)) {
      node.credentialRef = alias;
      NodeStore.save(this.config.nodes);
      await SecretStore.remove(legacy);
    }
    return old;
  }

  /** 导入节点：先把凭据写进 Asset Store，再落节点表（新数据从第一天起就不存明文） */
  async addNodeSecure(node: XrayNode): Promise<boolean> {
    if (!this.canPersist()) {
      Logger.error('addNodeSecure blocked: persistence disabled');
      return false;
    }
    const alias: string = SecretStore.aliasForNode(node.id);
    if (!await SecretStore.put(alias, node.credentialRef)) {
      Logger.error(`addNodeSecure: secret store put failed for ${node.protocol}@${node.address}:${node.port}`);
      return false;
    }
    node.credentialRef = alias;
    return this.addNode(node);
  }

  /**
   * 设置分流模式（全局 / 规则 / 直连）。
   * 返回 false 表示**未保存成功**：此时内存值已回滚，UI 必须据此提示（FR-44）。
   */
  setRoutingMode(mode: RoutingMode): boolean {
    const prev: RoutingMode = this.config.settings.routingMode;
    this.config.settings.routingMode = mode;
    if (!this.persistSettings()) {
      this.config.settings.routingMode = prev;
      Logger.error(`routingMode set failed, rolled back to ${prev as string}`);
      return false;
    }
    Logger.info(`routingMode -> ${mode}`);
    return true;
  }

  /** 设置日志级别；返回 false 表示未保存成功且已回滚（FR-44） */
  setLogLevel(level: string): boolean {
    const prev: string = this.config.settings.logLevel;
    this.config.settings.logLevel = level;
    if (!this.persistSettings()) {
      this.config.settings.logLevel = prev;
      Logger.error(`logLevel set failed, rolled back to ${prev}`);
      return false;
    }
    Logger.info(`logLevel -> ${level}`);
    return true;
  }

  getLogLevel(): string {
    return this.config.settings.logLevel;
  }

  /**
   * 保存入口（骨架期未实现持久化）。
   * 真实实现里所有写盘都必须先过 `canPersist()`；返回 false 表示"未实现"，不是"保存失败"。
   */
  save(): boolean {
    if (!this.canPersist()) {
      Logger.error('save blocked: config load failed and overwrite not confirmed');
      return false;
    }
    Logger.info('save: persistence not implemented yet (skeleton)');
    return false;
  }
}
