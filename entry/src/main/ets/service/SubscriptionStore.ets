/**
 * service/SubscriptionStore.ets — 订阅源持久化（最小实现）
 *
 * 与 NodeStore 同一套方案（AppStorage + PersistentStorage，无需 Context），但**分键存储**：
 * 订阅是"来源"，节点是"结果"，两者的生命周期不同——删掉订阅不该顺带删掉已导入的节点，
 * 反过来改一个节点也不该重写订阅表。
 *
 * 安全约束（与凭据同一条原则）：
 *   订阅 URL 里**通常带 token**（`.../api/v1/client/subscribe?token=xxx`），
 *   所以订阅表里只存**别名**，真实 URL 放 Asset Store；别名不进日志。
 */

import { Logger } from '../platform/Logger';
import { SecretStore } from '../platform/SecretStore';

const KEY: string = 'tunnelix_subs_v1';
const SCHEMA: number = 1;

interface StoredSub {
  id: string;
  name: string;
  /** Asset Store 别名（`sub:<hash>`），不是明文 URL */
  urlRef: string;
  lastUpdated: number;
  nodeCount: number;
}

interface StoredPayload {
  schema: number;
  subs: StoredSub[];
}

/** 订阅记录（对外只暴露不含凭据的字段） */
export class SubRecord {
  id: string = '';
  name: string = '';
  /** Asset Store 别名 */
  urlRef: string = '';
  lastUpdated: number = 0;
  nodeCount: number = 0;
}

export class SubscriptionStore {
  /** 订阅 URL 的别名：与节点凭据同一命名空间隔离（`sub:` 前缀） */
  static aliasFor(subId: string): string {
    return `sub:${subId}`;
  }

  static ensure(): void {
    PersistentStorage.persistProp<string>(KEY, '');
  }

  static save(subs: SubRecord[]): boolean {
    try {
      SubscriptionStore.ensure();
      const list: StoredSub[] = [];
      for (let i = 0; i < subs.length; i++) {
        const s: SubRecord = subs[i];
        const st: StoredSub = {
          id: s.id,
          name: s.name,
          urlRef: s.urlRef,
          lastUpdated: s.lastUpdated,
          nodeCount: s.nodeCount
        };
        list.push(st);
      }
      const payload: StoredPayload = { schema: SCHEMA, subs: list };
      AppStorage.setOrCreate<string>(KEY, JSON.stringify(payload));
      Logger.info(`subStore save ok: ${list.length} sub(s)`);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`subStore save failed: ${msg}`);
      return false;
    }
  }

  /** null = 读到了但解析失败（调用方必须保留原数据，不得覆盖写） */
  static load(): SubRecord[] | null {
    try {
      SubscriptionStore.ensure();
      const raw: string | undefined = AppStorage.get<string>(KEY);
      if (raw === undefined || raw === '') {
        return [];
      }
      const payload: StoredPayload = JSON.parse(raw) as StoredPayload;
      if (payload === null || payload.subs === undefined) {
        Logger.error('subStore load: payload malformed');
        return null;
      }
      const out: SubRecord[] = [];
      for (let i = 0; i < payload.subs.length; i++) {
        const st: StoredSub = payload.subs[i];
        const r: SubRecord = new SubRecord();
        r.id = st.id;
        r.name = st.name;
        r.urlRef = st.urlRef;
        r.lastUpdated = st.lastUpdated;
        r.nodeCount = st.nodeCount;
        out.push(r);
      }
      return out;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`subStore load failed: ${msg}`);
      return null;
    }
  }

  /** 把订阅 URL 写进安全存储，返回别名；失败返回空串 */
  static async putUrl(subId: string, url: string): Promise<string> {
    const alias: string = SubscriptionStore.aliasFor(subId);
    if (await SecretStore.put(alias, url)) {
      return alias;
    }
    return '';
  }

  /** 取回订阅 URL；null = 取不到（调用方不得用空串硬拼请求） */
  static async getUrl(urlRef: string): Promise<string | null> {
    return await SecretStore.get(urlRef);
  }
}
