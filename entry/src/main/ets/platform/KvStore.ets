import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from './Logger';

/**
 * platform/KvStore.ets — 键值持久化（preferences，同步 API）
 *
 * 为什么不用 PersistentStorage：
 *   在当前的设备/模拟器上，`PersistentStorage.persistProp(key, '')` 的**恢复路径不可靠**——
 *   文件 `/data/.../haps/entry/files/persistent_storage` 里明明白白存着
 *   `{"onboardingDone":true}`，冷启动读到 `rawLen=0`；而且这种"读空"会被后续写回
 *   固化成真实的空值（节点表就被这样清空过一次）。
 *   把恢复改到 `onWindowStageCreate` 之后仍然读到 0，说明不是时序问题，
 *   而是这条链路本身在这套运行时上不成立。
 *
 * 因此这里改用 `preferences` 的同步读写：读到的就是文件里的内容，行为可预测，
 * 并且可以直接用 `hdc shell cat` 核对落盘结果。所有调用都必须在 `init()` 之后。
 */
export class KvStore {
  private static store: preferences.Preferences | null = null;
  private static readonly FILE_NAME: string = 'tunnelix_store';

  /** 初始化；返回 false 表示初始化失败（此时读写都会失败并记日志，绝不静默成功） */
  static init(context: common.UIAbilityContext): boolean {
    if (KvStore.store !== null) {
      return true;
    }
    try {
      KvStore.store = preferences.getPreferencesSync(context, { name: KvStore.FILE_NAME });
      if (KvStore.store === null) {
        Logger.error('kvStore init: getPreferencesSync returned null');
        return false;
      }
      Logger.info('kvStore init ok');
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`kvStore init failed: ${msg}`);
      return false;
    }
  }

  /** 是否可用（未 init 时所有写都会失败，调用方据此提示用户而不是假装存成功） */
  static ready(): boolean {
    return KvStore.store !== null;
  }

  /**
   * 读；不存在或不可用返回空串。
   * 返回空串与"存了一个空串"不区分——本应用的键存的是 JSON，空串无有效语义。
   */
  static read(key: string): string {
    if (KvStore.store === null) {
      Logger.error(`kvStore read before init: key=${key}`);
      return '';
    }
    try {
      const v: preferences.ValueType = KvStore.store.getSync(key, '');
      if (typeof v === 'string') {
        return v;
      }
      return '';
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`kvStore read failed key=${key}: ${msg}`);
      return '';
    }
  }

  /** 写 + 立即刷盘；返回 false 表示失败 */
  static write(key: string, value: string): boolean {
    if (KvStore.store === null) {
      Logger.error(`kvStore write before init: key=${key}`);
      return false;
    }
    try {
      KvStore.store.putSync(key, value);
      KvStore.store.flushSync();
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`kvStore write failed key=${key}: ${msg}`);
      return false;
    }
  }
}
