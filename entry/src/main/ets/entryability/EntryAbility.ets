import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ConfigService } from '../service/ConfigService';

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_BOOT';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate bundle=%{public}s', this.context.abilityInfo.bundleName);
    // 凭据迁移必须在**启动时**做，而不是等到第一次连接：
    // 只用不连的用户，明文会一直留在节点表里。
    ConfigService.getInstance().ensureSecureMigration().then((ok: boolean) => {
      hilog.info(DOMAIN, TAG, 'credential migration at startup: ok=%{public}s', ok ? 'true' : 'false');
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      // 异常文本可能来自第三方，用 private 打：现在文案是我们自己的，但这不变量保不住
      hilog.error(DOMAIN, TAG, 'credential migration at startup failed: %{private}s', msg);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');
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
