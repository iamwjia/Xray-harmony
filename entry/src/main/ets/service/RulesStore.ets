/**
 * service/RulesStore.ets — 用户自定义分流规则持久化
 *
 * 与 NodeStore / SubscriptionStore 同一套方案（AppStorage + PersistentStorage，分键存储）。
 *
 * 为什么单独一个键：规则是"用户意图"，和节点/订阅的生命周期完全独立——
 * 换节点不该丢规则，删订阅也不该影响规则。
 */

import { Logger } from '../platform/Logger';
import { RoutingRule } from '../model/AppConfig';

const KEY: string = 'tunnelix_rules_v1';
const SCHEMA: number = 1;

interface StoredRule {
  id: string;
  matchType: string;
  pattern: string;
  action: string;
  enabled: boolean;
}

interface StoredPayload {
  schema: number;
  rules: StoredRule[];
}

export class RulesStore {
  static ensure(): void {
    PersistentStorage.persistProp<string>(KEY, '');
  }

  static save(rules: RoutingRule[]): boolean {
    try {
      RulesStore.ensure();
      const list: StoredRule[] = [];
      for (let i = 0; i < rules.length; i++) {
        const r: RoutingRule = rules[i];
        const st: StoredRule = {
          id: r.id,
          matchType: r.matchType,
          pattern: r.pattern,
          action: r.action,
          enabled: r.enabled
        };
        list.push(st);
      }
      const payload: StoredPayload = { schema: SCHEMA, rules: list };
      AppStorage.setOrCreate<string>(KEY, JSON.stringify(payload));
      Logger.info(`rulesStore save ok: ${list.length} rule(s)`);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`rulesStore save failed: ${msg}`);
      return false;
    }
  }

  /** null = 读到了但解析失败（调用方保留原数据，不得覆盖写） */
  static load(): RoutingRule[] | null {
    try {
      RulesStore.ensure();
      const raw: string | undefined = AppStorage.get<string>(KEY);
      if (raw === undefined || raw === '') {
        return [];
      }
      const payload: StoredPayload = JSON.parse(raw) as StoredPayload;
      if (payload === null || payload.rules === undefined) {
        Logger.error('rulesStore load: payload malformed');
        return null;
      }
      const out: RoutingRule[] = [];
      for (let i = 0; i < payload.rules.length; i++) {
        const st: StoredRule = payload.rules[i];
        const r = new RoutingRule();
        r.id = st.id;
        r.matchType = st.matchType;
        r.pattern = st.pattern;
        r.action = st.action;
        r.enabled = st.enabled;
        out.push(r);
      }
      return out;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`rulesStore load failed: ${msg}`);
      return null;
    }
  }
}
