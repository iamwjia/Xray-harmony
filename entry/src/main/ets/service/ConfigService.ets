import { AppConfig, ConfigCodec, createDefaultConfig, XrayNode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';

/**
 * service/ConfigService.ets — 配置读写服务（应用服务层）
 *
 * 职责：持有当前 L-A 配置实例、提供节点选择等用例级操作；
 *       序列化/反序列化统一走 ConfigCodec。
 * 边界：**不碰 UI**，也**不生成内核 JSON**（那是后续 service/KernelConfigBuilder 的事）。
 *
 * 当前实现：内存单例 + 默认假数据（3 条占位节点）。
 * 已知缺口：尚未落盘（后续接 RDB 加密库 / preferences），见 APP-SKELETON.md。
 */
export class ConfigService {
  private static instance: ConfigService | null = null;
  private config: AppConfig;

  private constructor() {
    this.config = createDefaultConfig();
    // 演示序列化往返：确保 codec 本身可用（失败则退回默认配置）
    const roundTrip: AppConfig | null = ConfigCodec.decode(ConfigCodec.encode(this.config));
    if (roundTrip === null) {
      Logger.error('ConfigCodec round-trip failed; falling back to defaults');
    } else {
      this.config = roundTrip;
    }
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

  /** 选择节点（不校验可用性——可用性是后续 health 检查的事） */
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

  setLogLevel(level: string): void {
    this.config.settings.logLevel = level;
    Logger.info(`logLevel -> ${level}`);
  }

  getLogLevel(): string {
    return this.config.settings.logLevel;
  }
}
