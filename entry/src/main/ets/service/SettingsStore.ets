/**
 * service/SettingsStore.ets — 设置持久化（最小实现）
 *
 * 与 NodeStore 同方案：AppStorage + PersistentStorage，无需 Context。
 * 单独一个 KEY，避免"改一个分流开关要重写整个节点列表"。
 *
 * 约束：
 *   1. 读取失败返回 null，调用方保留内存默认值并**不写盘**；
 *   2. 只存枚举字符串与简单标量，不存任何凭据。
 */

import { Logger } from '../platform/Logger';

const KEY: string = 'tunnelix_settings_v1';
const SCHEMA: number = 1;

/** 落盘的扁平结构 */
interface StoredSettings {
  schema: number;
  routingMode: string;
  logLevel: string;
  onboardingDone: boolean;
}

/** 读取结果：调用方按字段覆盖自己已有的默认值 */
export class SettingsSnapshot {
  routingMode: string = '';
  logLevel: string = '';
  onboardingDone: boolean = false;
}

export class SettingsStore {
  /** 初始化持久化属性（幂等） */
  static ensure(): void {
    PersistentStorage.persistProp<string>(KEY, '');
  }

  /** 保存；返回 false 表示写失败（调用方应提示，不要静默） */
  static save(routingMode: string, logLevel: string, onboardingDone: boolean): boolean {
    try {
      SettingsStore.ensure();
      const payload: StoredSettings = {
        schema: SCHEMA,
        routingMode: routingMode,
        logLevel: logLevel,
        onboardingDone: onboardingDone
      };
      AppStorage.setOrCreate<string>(KEY, JSON.stringify(payload));
      Logger.info(`settingsStore save ok: routing=${routingMode} log=${logLevel}`);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`settingsStore save failed: ${msg}`);
      return false;
    }
  }

  /**
   * 读取。
   * 返回 null = 「读到了但解析失败」→ 调用方必须保留默认值且不要立刻写盘（否则会冲掉用户数据）。
   * 返回对象（字段可能为空串）= 「没有保存过」或「读到有效内容」，空串字段表示沿用默认值。
   */
  static load(): SettingsSnapshot | null {
    const snap: SettingsSnapshot = new SettingsSnapshot();
    try {
      SettingsStore.ensure();
      const raw: string | undefined = AppStorage.get<string>(KEY);
      if (raw === undefined || raw === '') {
        return snap; // 首次启动：全空，调用方沿用默认
      }
      const payload: StoredSettings = JSON.parse(raw) as StoredSettings;
      if (payload === null) {
        Logger.error('settingsStore load: payload null');
        return null;
      }
      if (payload.schema !== SCHEMA) {
        Logger.warn(`settingsStore load: schema ${payload.schema} != ${SCHEMA}`);
      }
      snap.routingMode = payload.routingMode === undefined ? '' : payload.routingMode;
      snap.logLevel = payload.logLevel === undefined ? '' : payload.logLevel;
      snap.onboardingDone = payload.onboardingDone === undefined ? false : payload.onboardingDone;
      Logger.info(`settingsStore load ok: routing=${snap.routingMode} log=${snap.logLevel}`);
      return snap;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`settingsStore load failed: ${msg}`);
      return null;
    }
  }
}
