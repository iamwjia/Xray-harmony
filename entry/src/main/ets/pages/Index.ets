import { hilog } from '@kit.PerformanceAnalysisKit';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import nativeEntry from 'libentry.so';

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_POC';
// 启动即自动探测 M4（无需点击）。默认关闭：真机上每次启动都会触发系统 VPN 授权流程，会被用户当成 bug。
// 需要排查时临时置 true 并重建。
const AUTO_PROBE_M4: boolean = false;

@Entry
@Component
struct Index {
  @State m2Result: string = '(M2 not run)';
  @State m3Result: string = '(M3 not run)';
  @State m4Result: string = '(M4 not run)';

  // 启动即探测：无需点击即可区分「API 不存在 / 调用悬挂 / 调用被拒」
  aboutToAppear(): void {
    if (AUTO_PROBE_M4) {
      this.probeM4();
    }
  }

  private probeM4(): void {
    try {
      const t: string = typeof vpnExtension.startVpnExtensionAbility;
      hilog.info(DOMAIN, TAG, 'M4PROBE typeof=%{public}s', t);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'M4PROBE typeof threw code=%{public}d msg=%{public}s', err.code, err.message);
    }
    const want: Want = {
      deviceId: '',
      bundleName: 'com.example.xraypoc',
      abilityName: 'MyVpnExtAbility',
    };
    hilog.info(DOMAIN, TAG, 'M4PROBE invoking startVpnExtensionAbility');
    vpnExtension.startVpnExtensionAbility(want)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'M4PROBE resolved');
      })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'M4PROBE rejected code=%{public}d msg=%{public}s', err.code, err.message);
      });
    setTimeout(() => {
      hilog.info(DOMAIN, TAG, 'M4PROBE pending-after-6s (no resolve/reject within 6s)');
    }, 6000);
  }

  private runM2(): void {
    try {
      const ret: string = nativeEntry.hello();
      this.m2Result = ret;
      hilog.info(DOMAIN, TAG, 'M2 hello=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.m2Result = `M2 failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'M2 failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runM3(): void {
    try {
      const sum: number = nativeEntry.prebuiltAdd(1, 2);
      this.m3Result = `prebuilt_add(1,2)=${sum}`;
      hilog.info(DOMAIN, TAG, 'M3 prebuiltAdd result=%{public}d', sum);
    } catch (e) {
      const err = e as BusinessError;
      this.m3Result = `M3 failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'M3 failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runM4(): void {
    hilog.info(DOMAIN, TAG, 'M4 clicked');
    // M4：仅验证「代码可编译 + 声明合法」。真机上的行为需要单独记录，见 doc/poc 构建记录。
    const want: Want = {
      deviceId: '',
      bundleName: 'com.example.xraypoc',
      abilityName: 'MyVpnExtAbility',
    };
    vpnExtension.startVpnExtensionAbility(want)
      .then(() => {
        this.m4Result = 'startVpnExtensionAbility: ok (check device log)';
        hilog.info(DOMAIN, TAG, 'M4 start ok');
      })
      .catch((err: BusinessError) => {
        this.m4Result = `start failed: ${err.code} ${err.message}`;
        hilog.error(DOMAIN, TAG, 'M4 start failed code=%{public}d msg=%{public}s', err.code, err.message);
      });
  }

  build() {
    Column({ space: 12 }) {
      Text('xray-harmony PoC skeleton').fontSize(20).fontWeight(FontWeight.Bold)

      Button('M2: call NAPI hello()').onClick(() => this.runM2()).width('90%')
      Text(this.m2Result).fontSize(14)

      Button('M3: call prebuilt_add(1,2)').onClick(() => this.runM3()).width('90%')
      Text(this.m3Result).fontSize(14)

      Button('M4: start VpnExtensionAbility (code only)').onClick(() => this.runM4()).width('90%')
      Text(this.m4Result).fontSize(14)
    }
    .width('100%')
    .padding(16)
  }
}
