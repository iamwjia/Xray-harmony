import { KvStore } from '../platform/KvStore';
import { Logger } from '../platform/Logger';

const KEY: string = 'tunnelix_events_v1';
const SCHEMA: number = 1;
/** 只留最近 5 条：这是"刚才发生了什么"，不是审计日志；要看全量去运行日志页 */
const MAX: number = 5;

export class AppEvent {
  /** 毫秒时间戳 */
  ts: number = 0;
  /** 0 信息 / 1 警告 / 2 错误 */
  level: number = 0;
  /** 相同事件在短时间内重复时的计数（≥1）；首页显示成 `文案 ×N` */
  count: number = 1;
  text: string = '';
}

interface EventFile {
  schema: number;
  events: AppEvent[];
}

/**
 * service/EventLog.ets — 首页"最近事件"的落盘缓冲
 *
 * 为什么单独存一份而不是直接读运行日志：
 *   运行日志是排障用的技术流水（含英文内核消息、可能 500 条），首页要的是
 *   **用户能看懂的三五条结论**（连上了 / 为什么没连上）。两者受众不同，混在一起两边都难看。
 *
 * 约束：
 *   - 只存结论，不存凭据、地址与节点 ID；文案由调用方保证已脱敏。
 *   - 写失败只记日志，不打断主流程（连不上不能因为"记事件失败"而更连不上）。
 */
export class EventLog {
  private static cache: AppEvent[] | null = null;

  private static load(): AppEvent[] {
    if (EventLog.cache !== null) {
      return EventLog.cache;
    }
    const raw: string = KvStore.read(KEY);
    if (raw.length === 0) {
      EventLog.cache = [];
      return EventLog.cache;
    }
    try {
      const parsed: EventFile = JSON.parse(raw) as EventFile;
      const list: AppEvent[] = [];
      const src: AppEvent[] = parsed.events !== undefined ? parsed.events : [];
      for (let i = 0; i < src.length; i++) {
        const e: AppEvent = new AppEvent();
        e.ts = src[i].ts;
        e.level = src[i].level;
        e.text = src[i].text;
        e.count = src[i].count === undefined || src[i].count < 1 ? 1 : src[i].count;
        list.push(e);
      }
      EventLog.cache = list;
      return list;
    } catch (e) {
      Logger.warn('event log parse failed, reset');
      EventLog.cache = [];
      return EventLog.cache;
    }
  }

  /** 追加一条；最新的在最前面 */
  static push(level: number, text: string): void {
    if (text.length === 0) {
      return;
    }
    const list: AppEvent[] = EventLog.load().slice();
    // 同一句话在一分钟内反复出现（例如连点几次连接）合并成一条 ×N：
    // 事件区只有三行，被同一句失败占满等于什么都没说。
    const now: number = Date.now();
    if (list.length > 0 && list[0].text === text && now - list[0].ts <= 60000) {
      list[0].ts = now;
      list[0].count = list[0].count + 1;
      EventLog.cache = list;
      const merged: EventFile = { schema: SCHEMA, events: list };
      KvStore.write(KEY, JSON.stringify(merged));
      return;
    }
    const e: AppEvent = new AppEvent();
    e.ts = now;
    e.level = level;
    e.text = text;
    list.unshift(e);
    while (list.length > MAX) {
      list.pop();
    }
    EventLog.cache = list;
    const file: EventFile = { schema: SCHEMA, events: list };
    if (!KvStore.write(KEY, JSON.stringify(file))) {
      Logger.warn('event log write failed');
    }
  }

  /** 最近 n 条（n ≤ MAX）；返回副本，调用方可随意渲染 */
  static recent(n: number): AppEvent[] {
    const list: AppEvent[] = EventLog.load();
    const out: AppEvent[] = [];
    for (let i = 0; i < list.length && i < n; i++) {
      out.push(list[i]);
    }
    return out;
  }

  /** 清空所有数据时一并清掉，避免"清空后首页还留着旧事件" */
  static clear(): void {
    EventLog.cache = [];
    KvStore.write(KEY, '');
  }

  /** HH:mm，首页空间小，不显示日期（跨天时靠列表顺序判断即可） */
  static timeText(ts: number): string {
    const d: Date = new Date(ts);
    const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
    const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
    return `${hh}:${mm}`;
  }
}
