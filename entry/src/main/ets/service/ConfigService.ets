import { AppConfig, AppSettings, ConfigCodec, createDefaultConfig, XrayNode, RoutingMode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';
import { NodeStore } from './NodeStore';
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
    const persisted: XrayNode[] | null = NodeStore.load();
    if (persisted === null) {
      Logger.error('nodeStore: persisted nodes unreadable; keeping in-memory defaults, persistence blocked until user confirms');
    } else if (persisted.length > 0) {
      this.config.nodes = persisted;
      if (!this.config.selectedNodeId) {
        this.config.selectedNodeId = persisted[0].id;
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
      return false;
    }
    const s: AppSettings = this.config.settings;
    return SettingsStore.save(s.routingMode as string, s.logLevel, s.onboardingDone);
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
  /** 设置分流模式（全局 / 规则 / 直连） */
  setRoutingMode(mode: RoutingMode): void {
    this.config.settings.routingMode = mode;
    Logger.info(`routingMode -> ${mode}`);
    this.persistSettings();
  }
  setLogLevel(level: string): void {
    this.config.settings.logLevel = level;
    Logger.info(`logLevel -> ${level}`);
    this.persistSettings();
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
