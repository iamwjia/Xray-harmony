import { hilog } from '@kit.PerformanceAnalysisKit';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import nativeEntry from 'libentry.so';
import { ConfigService } from '../service/ConfigService';
import { KernelService } from '../service/KernelService';
import { VpnController } from '../service/VpnController';

const DOMAIN: number = 0x0001;
const TAG: string = 'XVPN_POC';
// 启动即自动探测 VPN 扩展（无需点击）。默认关闭：真机上每次启动都会触发系统 VPN 授权流程，会被用户当成 bug。
const AUTO_PROBE_VPN: boolean = false;

/**
 * pages/DevPanel.ets — 开发者面板（原 Index 的 PoC 探针，全部保留）
 *
 * 为什么保留：这些探针是目前**唯一**能直接验证「内核能否加载/驱动/转发」的手段。
 * 主界面不再出现这些按钮，避免把手动探针当成产品功能。
 * 入口：首页底部「开发者面板（PoC 探针）」。
 */
@Entry
@Component
struct DevPanel {
  @State napiHelloResult: string = '(未运行)';
  @State prebuiltAddResult: string = '(未运行)';
  @State vpnExtResult: string = '(未运行)';
  @State cgoPingResult: string = '(未运行)';
  @State cgoInvokeResult: string = '(未运行)';
  @State xrayVersionResult: string = '(未运行)';
  @State socksProbeResult: string = '(未运行)';
  @State hostProbeResult: string = '(未运行)';

  // 仅用于触发失败路径验证；真正的内核驱动在首页的 KernelService（同一个单例）
  private kernelDebug: KernelService = KernelService.getInstance();

  aboutToAppear(): void {
    if (AUTO_PROBE_VPN) {
      this.probeVpnExt();
    }
  }

  /**
   * 请求启动 VPN 扩展。
   *
   * 这条路径在模拟器上**必然超时**：模拟器缺系统 VPN 授权组件，调用不会 settle。
   * 正因为如此，它是验证"超时归因"最方便的场景——这里要看到的不是成功，
   * 而是限定时间内给出可理解的结论，而不是永远停在"连接中"。
   */
  private probeVpnExt(): void {
    this.vpnExtResult = '请求中…';
    VpnController.start('com.tunnelix.app', 'MyVpnExtAbility').then(() => {
      this.vpnExtResult = '已请求启动（真机上此刻应出现系统授权弹窗）';
      hilog.info(DOMAIN, TAG, 'vpn start resolved');
    }).catch((e: Object) => {
      const msg: string = VpnController.describeError(e);
      this.vpnExtResult = `未成功：${msg}`;
      hilog.error(DOMAIN, TAG, 'vpn start failed: %{public}s', msg);
    });
  }

  private runNapiHello(): void {
    try {
      const ret: string = nativeEntry.hello();
      this.napiHelloResult = ret;
      hilog.info(DOMAIN, TAG, 'napi hello=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.napiHelloResult = `
api failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'napi failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runPrebuiltAdd(): void {
    try {
      const sum: number = nativeEntry.prebuiltAdd(1, 2);
      this.prebuiltAddResult = `prebuilt_add(1,2)=${sum}`;
      hilog.info(DOMAIN, TAG, 'prebuilt prebuiltAdd result=%{public}d', sum);
    } catch (e) {
      const err = e as BusinessError;
      this.prebuiltAddResult = `prebuilt failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'prebuilt failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runVpnExt(): void {
    hilog.info(DOMAIN, TAG, 'vpnExt clicked');
    const want: Want = {
      deviceId: '',
      bundleName: 'com.tunnelix.app',
      abilityName: 'MyVpnExtAbility',
    };
    vpnExtension.startVpnExtensionAbility(want)
      .then(() => {
        this.vpnExtResult = 'startVpnExtensionAbility: ok (check device log)';
        hilog.info(DOMAIN, TAG, 'vpnExt start ok');
      })
      .catch((err: BusinessError) => {
        this.vpnExtResult = `start failed: ${err.code} ${err.message}`;
        hilog.error(DOMAIN, TAG, 'vpnExt start failed code=%{public}d msg=%{public}s', err.code, err.message);
      });
  }

  private runCGoPing(): void {
    hilog.info(DOMAIN, TAG, 'cgoPing clicked');
    try {
      const ret: string = nativeEntry.probeGoPing();
      this.cgoPingResult = ret;
      hilog.info(DOMAIN, TAG, 'cgoPing result=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.cgoPingResult = `cgoPing failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'cgoPing failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runCGoInvoke(): void {
    hilog.info(DOMAIN, TAG, 'cgoInvoke clicked');
    try {
      const ret: string = nativeEntry.probeGoInvoke();
      this.cgoInvokeResult = this.maskSensitive(ret);
      hilog.info(DOMAIN, TAG, 'cgoInvoke result(len=%{public}d)=%{private}s', ret.length, ret);
    } catch (e) {
      const err = e as BusinessError;
      this.cgoInvokeResult = `cgoInvoke failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'cgoInvoke failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  private runXrayVersion(): void {
    hilog.info(DOMAIN, TAG, 'xrayVersion clicked');
    try {
      const ret: string = nativeEntry.probeKernelVersion();
      this.xrayVersionResult = this.maskSensitive(ret);
      hilog.info(DOMAIN, TAG, 'xrayVersion result(len=%{public}d)=%{private}s', ret.length, ret);
    } catch (e) {
      const err = e as BusinessError;
      this.xrayVersionResult = `xrayVersion failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'xrayVersion failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  /**
   * 面板展示用的脱敏。
   *
   * 只遮 UUID 是不够的（审计 R-b 指出）：trojan 的密码、ss 的 method:password、
   * 配置里形如 `"password":"…"` 的值都不是 UUID 形态，会原样上屏。所以按"字段名 + 值"
   * 与"独立凭据形态"两类分别遮，再截断。
   */
  private maskSensitive(raw: string): string {
    let masked: string = raw;
    // ① UUID 形态
    masked = masked.replace(
      /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g,
      '****-****-****');
    // ② 常见凭据字段：password / passwd / pwd / id / uuid / token / secret
    masked = masked.replace(
      /("?(?:password|passwd|pwd|token|secret|uuid)"?\s*[:=]\s*)"[^"]*"/gi,
      '$1"****"');
    // ③ ss 的 method:password 形态（method 是公开的，密码不是）
    masked = masked.replace(
      /(aes-\d+-gcm|chacha20-ietf-poly1305|xchacha20-poly1305)(:)[^\s",}]+/gi,
      '$1$2****');
    return masked.length <= 300 ? masked : `${masked.substring(0, 300)}…(truncated)`;
  }

  private runSocksProbe(): void {
    hilog.info(DOMAIN, TAG, 'socksProbe clicked');
    try {
      const ret: string = nativeEntry.probeSocksForward();
      // UI 也不能显示内核原文：原文可能含配置片段，而配置里有节点凭据
      this.socksProbeResult = this.maskSensitive(ret);
      // 内核原始响应不可控（可能回显配置片段），日志走 private + 长度，避免整段落进公共日志
      hilog.info(DOMAIN, TAG, 'socksProbe result(len=%{public}d)=%{private}s', ret.length, ret);
    } catch (e) {
      const err = e as BusinessError;
      this.socksProbeResult = `socksProbe failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'socksProbe failed code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  /**
   * E15 Step 1：从**应用进程**发一次真正的 TCP 连接 + HTTP GET。
   *
   * 为什么不能只 ping：ICMP 通只说明路由可达，不说明宿主的 8000 端口在监听、
   * 也不说明 NAT 允许该端口。这两件事必须用 TCP 握手来证明。
   * 探针走 native（模拟器 shell 没有 curl/wget/nc），顺带还能复用同一套 socket 代码。
   */
  private runHostProbe(): void {
    hilog.info(DOMAIN, TAG, 'hostProbe clicked');
    try {
      const ret: string = nativeEntry.probeHostHttp('10.0.2.2', 8000, '/probe.txt');
      this.hostProbeResult = ret;
      hilog.info(DOMAIN, TAG, 'hostProbe result=%{public}s', ret);
    } catch (e) {
      const err = e as BusinessError;
      this.hostProbeResult = `hostProbe failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'hostProbe failed code=%{public}d msg=%{public}s', err.code, err.message);
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
          Button('NAPI hello()').onClick(() => this.runNapiHello()).width('100%')
          Text(this.napiHelloResult).fontSize(12).width('100%')

          Button('prebuilt_add(1,2)').onClick(() => this.runPrebuiltAdd()).width('100%')
          Text(this.prebuiltAddResult).fontSize(12).width('100%')

          Button('启动 VpnExtensionAbility（仅代码）').onClick(() => this.runVpnExt()).width('100%')
          Text(this.vpnExtResult).fontSize(12).width('100%')

          Button('Go CGoPing()').onClick(() => this.runCGoPing()).width('100%')
          Text(this.cgoPingResult).fontSize(12).width('100%')

          Button('加载 libxray + CGoInvoke').onClick(() => this.runCGoInvoke()).width('100%')
          Text(this.cgoInvokeResult).fontSize(12).width('100%')

          Button('libxray xrayVersion').onClick(() => this.runXrayVersion()).width('100%')
          Text(this.xrayVersionResult).fontSize(12).width('100%')

          Button('经内核 SOCKS + 出口 IP 对比').onClick(() => this.runSocksProbe()).width('100%')
          Text(this.socksProbeResult).fontSize(12).width('100%')

          // E15 Step 1：真测 TCP + HTTP。不用 ping 代替——ICMP 通不代表端口通。
          Button('探测宿主 10.0.2.2:8000').onClick(() => this.runHostProbe()).width('100%')
          Text(this.hostProbeResult).fontSize(12).width('100%')

          Divider()
          // 调试项：模拟"配置读取失败"，用于验证首页横幅与保存拦截（TODO 持久化接入后删除）
          Button('调试：模拟配置读取失败 → 看首页横幅').width('100%')
            .backgroundColor('#8D6E63')
            .onClick(() => {
              ConfigService.getInstance().debugForceLoadFailure();
              this.socksProbeResult = '已置位 loadFailed=true；返回首页可见横幅，save() 将被拦截';
            })
          Text('预期：首页顶部出现"配置读取异常，已使用默认值（原数据未被覆盖）"').fontSize(11).width('100%')

          // 调试项：让下一次「连接」注入非法配置，用于验证失败路径（ERROR 且不卡 CONNECTING）
          Button('调试：下次连接注入非法配置 → 看 ERROR').width('100%')
            .backgroundColor('#8D6E63')
            .onClick(() => {
              this.kernelDebug.debugInjectInvalidConfig();
              this.socksProbeResult = '已置位 invalidConfig；返回首页点「连接」应显示错误原因（不卡连接中）';
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
