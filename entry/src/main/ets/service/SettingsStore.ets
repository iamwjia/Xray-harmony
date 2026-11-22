/**
 * service/SettingsStore.ets — 设置持久化（最小实现）
 *
 * 与 NodeStore 同方案：KvStore（preferences），由 KvStore 负责落盘与恢复。
 * 单独一个 KEY，避免"改一个分流开关要重写整个节点列表"。
 *
 * 约束：
 *   1. 读取失败返回 null，调用方保留内存默认值并**不写盘**；
 *   2. 只存枚举字符串与简单标量，不存任何凭据。
 */

import { Logger } from '../platform/Logger';
import { KvStore } from '../platform/KvStore';

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
  /** 保存；返回 false 表示写失败（调用方应提示，不要静默） */
  static save(routingMode: string, logLevel: string, onboardingDone: boolean): boolean {
    try {
      const payload: StoredSettings = {
        schema: SCHEMA,
        routingMode: routingMode,
        logLevel: logLevel,
        onboardingDone: onboardingDone
      };
      if (!KvStore.write(KEY, JSON.stringify(payload))) {
        return false;
      }
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
      const raw: string = KvStore.read(KEY);
      // 每次都记录原始长度：排查"设置写了但重启丢失"时，第一步要分清
      // "根本没写进去"和"写了但没读回来"——这两种原因的修法完全不同。
      Logger.info(`settingsStore load: rawLen=${raw.length}`);
      if (raw === '') {
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
