import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ConfigService } from '../service/ConfigService';
import { GeoAssets } from '../service/GeoAssets';
import { KvStore } from '../platform/KvStore';
import nativeEntry from 'libentry.so';

/** 启动时从应用进程发一次 TCP+HTTP 到宿主（诊断用，默认关闭）。 */
const HOST_PROBE_ON_BOOT: boolean = false;

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_BOOT';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate bundle=%{public}s', this.context.abilityInfo.bundleName);

    // geo 资源必须在**任何 runXrayFromJson 之前**解好并挂上：
    // RULE 模式的 geosite:cn / geoip:cn 是在实例创建时解析的，缺资源就是启动失败。
    GeoAssets.ensure(this.context).then((ok: boolean) => {
      hilog.info(DOMAIN, TAG, 'geo assets at startup: ok=%{public}s', ok ? 'true' : 'false');
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'geo assets at startup failed: %{private}s', msg);
    });

    if (HOST_PROBE_ON_BOOT) {
      // ICMP 通不代表 TCP 端口通；这里做真正的 connect + HTTP GET
      try {
        const r10: string = nativeEntry.probeHostHttp('10.0.2.2', 8000, '/probe.txt');
        hilog.info(DOMAIN, TAG, 'host probe: %{public}s', r10);
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.error(DOMAIN, TAG, 'host probe threw: %{private}s', msg);
      }
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');
    // 持久化后端初始化必须在任何读写之前：KvStore 拿不到 context 就是"读不到也写不进"。
    KvStore.init(this.context);
    // 持久化数据必须在这时恢复（不能放在 onCreate：实测那个阶段读出来是空串，
    // 而磁盘上数据是好的，读空再写回就会把用户数据清掉）。
    ConfigService.getInstance().loadFromDisk();

    // 凭据迁移必须在**界面前**做，而不是等到第一次连接：
    // 只用不连的用户，明文会一直留在节点表里。
    ConfigService.getInstance().ensureSecureMigration().then((ok: boolean) => {
      hilog.info(DOMAIN, TAG, 'credential migration at startup: ok=%{public}s', ok ? 'true' : 'false');
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      // 异常文本可能来自第三方，用 private 打：现在文案是我们自己的，但这不变量保不住
      hilog.error(DOMAIN, TAG, 'credential migration at startup failed: %{private}s', msg);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed code=%{public}d msg=%{public}s', err.code, err.message);
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent success');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
