import { KvStore } from './KvStore';

const KEY: string = 'tunnelix_theme_v1';

/**
 * 主题偏好：system / light / dark
 *
 * 主题是**用户功能**，不是调试开关——放在设置页「外观」里；开发者面板那份已删掉，
 * 两处入口迟早会不一致。
 *
 * 为什么不用系统设置联动：HarmonyOS 上系统级深色开关在部分设备/模拟器上不可用，
 * 应用内提供强制浅/深色后，用户不必去系统设置里翻，QA 也能逐页比对两套资源。
 */
export class ThemeMode {
  static readonly SYSTEM: string = 'system';
  static readonly LIGHT: string = 'light';
  static readonly DARK: string = 'dark';
}

export class ThemeStore {
  private static cached: string = '';

  static get(): string {
    if (ThemeStore.cached.length === 0) {
      const raw: string = KvStore.read(KEY);
      ThemeStore.cached = (raw === ThemeMode.LIGHT || raw === ThemeMode.DARK) ? raw : ThemeMode.SYSTEM;
    }
    return ThemeStore.cached;
  }

  static set(mode: string): boolean {
    ThemeStore.cached = mode;
    return KvStore.write(KEY, mode);
  }

  /** 名称映射，供设置页显示当前值用 */
  static label(mode: string): string {
    if (mode === ThemeMode.LIGHT) {
      return '浅色';
    }
    return mode === ThemeMode.DARK ? '深色' : '跟随系统';
  }
}
