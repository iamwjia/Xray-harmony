import { KvStore } from './KvStore';

const KEY: string = 'tunnelix_demo_flags_v1';

/**
 * platform/DemoFlags.ets — 演示数据开关（只为"没接上数据源时也能看布局"）
 *
 * 为什么需要它：
 *   流量统计要等内核 Stats 接通才有真数据，而内核现在卡在系统授权（202）。
 *   没有数据就没法确认这块布局合不合适，所以给一个**显式打开**的演示开关。
 *
 * 铁律：演示数据必须在界面上带「演示数据」标记，且默认关闭。
 *   任何"看起来像真数据但没有标记"的假数字都算 bug——用户会拿它判断流量是否异常。
 */
export class DemoFlags {
  private static traffic: boolean = false;
  private static loaded: boolean = false;

  private static load(): void {
    if (DemoFlags.loaded) {
      return;
    }
    DemoFlags.traffic = KvStore.read(KEY) === '1';
    DemoFlags.loaded = true;
  }

  static trafficDemo(): boolean {
    DemoFlags.load();
    return DemoFlags.traffic;
  }

  static setTrafficDemo(on: boolean): boolean {
    DemoFlags.load();
    DemoFlags.traffic = on;
    return KvStore.write(KEY, on ? '1' : '0');
  }
}
