import { KvStore } from '../platform/KvStore';
import { Logger } from '../platform/Logger';

const KEY: string = 'tunnelix_probes_v1';

/** 一个节点的最近一次连通性结论 */
export class ProbeRecord {
  ok: boolean = false;
  /** 成功时的握手耗时（ms）；失败为 0 */
  ms: number = 0;
  /** 时间戳 */
  ts: number = 0;
  /** 失败原因（已脱敏的短文案） */
  error: string = '';
}

interface ProbeFile {
  schema: number;
  records: Record<string, ProbeRecord>;
}

/**
 * service/ProbeStore.ets — 测连通结果的落盘
 *
 * 为什么不能只放内存：点完"测连通"看到「失败」，去改个节点再回来就没了，
 * 用户无法回答"我几分钟前测过吗、结果是啥"。测连通是**诊断动作**，
 * 结论必须留得住，而且要能看出"这结论是多久以前的"。
 *
 * 存法：一张 id → 结论 的表，单独一个 key；不给节点表加字段（那会牵动 schema 迁移）。
 * 保留最近 50 条，避免长期使用后无限增长。
 */
export class ProbeStore {
  private static cache: Record<string, ProbeRecord> | null = null;
  private static readonly MAX: number = 50;

  private static load(): Record<string, ProbeRecord> {
    if (ProbeStore.cache !== null) {
      return ProbeStore.cache;
    }
    const raw: string = KvStore.read(KEY);
    const out: Record<string, ProbeRecord> = {};
    if (raw.length > 0) {
      try {
        const parsed: ProbeFile = JSON.parse(raw) as ProbeFile;
        const recs: Record<string, ProbeRecord> | undefined = parsed.records;
        if (recs !== undefined) {
          const keys: string[] = Object.keys(recs);
          for (let i = 0; i < keys.length; i++) {
            out[keys[i]] = recs[keys[i]];
          }
        }
      } catch (e) {
        Logger.warn('probe store parse failed, reset');
      }
    }
    ProbeStore.cache = out;
    return out;
  }

  private static save(map: Record<string, ProbeRecord>): void {
    // ArkTS 不支持 delete：超量时重建一张只含"留下的 key"的表（从新到旧保留 MAX 条）
    const keys: string[] = Object.keys(map);
    let kept: Record<string, ProbeRecord> = map;
    if (keys.length > ProbeStore.MAX) {
      keys.sort((a: string, b: string) => map[b].ts - map[a].ts);
      kept = {};
      for (let i = 0; i < ProbeStore.MAX; i++) {
        kept[keys[i]] = map[keys[i]];
      }
      ProbeStore.cache = kept;
    }
    const file: ProbeFile = { schema: 1, records: kept };
    if (!KvStore.write(KEY, JSON.stringify(file))) {
      Logger.warn('probe store write failed');
    }
  }

  static put(nodeId: string, ok: boolean, ms: number, error: string): void {
    const map: Record<string, ProbeRecord> = ProbeStore.load();
    const rec: ProbeRecord = new ProbeRecord();
    rec.ok = ok;
    rec.ms = ms;
    rec.ts = Date.now();
    rec.error = error;
    map[nodeId] = rec;
    ProbeStore.cache = map;
    ProbeStore.save(map);
  }

  static get(nodeId: string): ProbeRecord | null {
    const map: Record<string, ProbeRecord> = ProbeStore.load();
    const rec: ProbeRecord | undefined = map[nodeId];
    return rec === undefined ? null : rec;
  }

  static clear(): void {
    ProbeStore.cache = {};
    KvStore.write(KEY, '');
  }

  /** 超过这个时长就不算"刚刚测过"，界面上要降级显示（灰） */
  static readonly FRESH_MS: number = 10 * 60 * 1000;

  static isFresh(rec: ProbeRecord): boolean {
    return Date.now() - rec.ts <= ProbeStore.FRESH_MS;
  }

  /** 人话时长：刚刚 / 3 分钟前 / 2 小时前 */
  static ageText(rec: ProbeRecord): string {
    const sec: number = Math.floor((Date.now() - rec.ts) / 1000);
    if (sec < 60) {
      return '刚刚';
    }
    if (sec < 3600) {
      return `${Math.floor(sec / 60)} 分钟前`;
    }
    if (sec < 86400) {
      return `${Math.floor(sec / 3600)} 小时前`;
    }
    return `${Math.floor(sec / 86400)} 天前`;
  }
}
