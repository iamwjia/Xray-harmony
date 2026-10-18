import { VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_EXT';

/**
 * M4 骨架：仅用于验证「声明 + 编译」。
 * 不实现隧道、不调用 createVpnConnection —— 那属于 PC1/PC3 的实验范围。
 *
 * 官方约束（research/harmony-platform-constraints.md §3.2）：
 * VpnExtensionAbility 内不允许引用 @ohos.contact / geolocation / multimedia.audio /
 * camera / telephony.call|sim|sms，否则可能导致进程异常退出。
 */
export default class MyVpnExtAbility extends VpnExtensionAbility {
  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate abilityName=%{public}s', want.abilityName ?? '');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
