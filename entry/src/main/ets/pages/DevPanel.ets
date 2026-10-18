import { hilog } from '@kit.PerformanceAnalysisKit';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import nativeEntry from 'libentry.so';
import { ConfigService } from '../service/ConfigService';
import { KernelService } from '../service/KernelService';

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_POC';
// 启动即自动探测 M4（无需点击）。默认关闭：真机上每次启动都会触发系统 VPN 授权流程，会被用户当成 bug。
const AUTO_PROBE_M4: boolean = false;

/**
 * pages/DevPanel.ets — 开发者面板（原 Index 的 PoC 探针，全部保留）
 *
 * 为什么保留：M2/M3/M5/M6/M7/M8 是目前**唯一**能直接验证「内核能否加载/驱动/转发」的手段。
 * 主界面不再出现这些按钮，避免把手动探针当成产品功能。
 * 入口：首页底部「开发者面板（PoC 探针）」。
 */
@Entry
@Component
struct DevPanel {
  @State m2Result: string = '(M2 not run)';
  @State m3Result: string = '(M3 not run)';
  @State m4Result: string = '(M4 not run)';
  @State m5Result: string = '(M5 not run)';
  @State m6Result: string = '(M6 not run)';
  @State m7Result: string = '(M7 not run)';
  @State m8Result: string = '(M8 not run)';

  // 仅用于触发失败路径验证；真正的内核驱动在首页的 KernelService（同一个单例）
  private kernelDebug: KernelService = KernelService.getInstance();

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
      bundleName: 'com.tunnelix.app',
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
    const want: Want = {
      deviceId: '',
      bundleName: 'com.tunnelix.app',
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

  private runM5(): void {
    hilog.info(DOMAIN, TAG, 'M5 clicked');
    try {
      const ret: string = nativeEntry.m5CGoPing();
      this.m5Result = ret;
      hilog.info(DOMAIN, TAG, 'M5 result=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.m5Result = `M5 failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'M5 failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runM6(): void {
    hilog.info(DOMAIN, TAG, 'M6 clicked');
    try {
      const ret: string = nativeEntry.m6CGoInvoke();
      this.m6Result = ret;
      hilog.info(DOMAIN, TAG, 'M6 result=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.m6Result = `M6 failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'M6 failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runM7(): void {
    hilog.info(DOMAIN, TAG, 'M7 clicked');
    try {
      const ret: string = nativeEntry.m7CGoVersion();
      this.m7Result = ret;
      hilog.info(DOMAIN, TAG, 'M7 result=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.m7Result = `M7 failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'M7 failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runM8(): void {
    hilog.info(DOMAIN, TAG, 'M8 clicked');
    try {
      const ret: string = nativeEntry.m9ProxyProbe();
      this.m8Result = ret;
      hilog.info(DOMAIN, TAG, 'M8 result=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.m8Result = `M8 failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'M8 failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button('返回').fontSize(12)
          .onClick(() => {
            router.back();
          })
        Text('开发者面板（PoC 探针）').fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
      }
      .width('100%')

      Scroll() {
        Column({ space: 10 }) {
          Button('M2: call NAPI hello()').onClick(() => this.runM2()).width('100%')
          Text(this.m2Result).fontSize(12).width('100%')

          Button('M3: call prebuilt_add(1,2)').onClick(() => this.runM3()).width('100%')
          Text(this.m3Result).fontSize(12).width('100%')

          Button('M4: start VpnExtensionAbility (code only)').onClick(() => this.runM4()).width('100%')
          Text(this.m4Result).fontSize(12).width('100%')

          Button('M5: call Go CGoPing()').onClick(() => this.runM5()).width('100%')
          Text(this.m5Result).fontSize(12).width('100%')

          Button('M6: load libxray + CGoInvoke').onClick(() => this.runM6()).width('100%')
          Text(this.m6Result).fontSize(12).width('100%')

          Button('M7: libxray xrayVersion').onClick(() => this.runM7()).width('100%')
          Text(this.m7Result).fontSize(12).width('100%')

          Button('M8: SOCKS via kernel + IP compare').onClick(() => this.runM8()).width('100%')
          Text(this.m8Result).fontSize(12).width('100%')

          Divider()
          // 调试项：模拟"配置读取失败"，用于验证首页横幅与保存拦截（TODO 持久化接入后删除）
          Button('调试：模拟配置读取失败 → 看首页横幅').width('100%')
            .backgroundColor('#8D6E63')
            .onClick(() => {
              ConfigService.getInstance().debugForceLoadFailure();
              this.m8Result = '已置位 loadFailed=true；返回首页可见横幅，save() 将被拦截';
            })
          Text('预期：首页顶部出现"配置读取异常，已使用默认值（原数据未被覆盖）"').fontSize(11).width('100%')

          // 调试项：让下一次「连接」注入非法配置，用于验证失败路径（ERROR 且不卡 CONNECTING）
          Button('调试：下次连接注入非法配置 → 看 ERROR').width('100%')
            .backgroundColor('#8D6E63')
            .onClick(() => {
              this.kernelDebug.debugInjectInvalidConfig();
              this.m8Result = '已置位 invalidConfig；返回首页点「连接」应显示错误原因（不卡连接中）';
            })
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding(12)
  }
}
