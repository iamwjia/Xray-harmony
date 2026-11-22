import { hilog } from '@kit.PerformanceAnalysisKit';
import { FontSize, LineHeight, Space, Height, Radius, IconSize } from '../common/Token';
import { PageHeader } from '../components/PageHeader';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Want, common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import nativeEntry from 'libentry.so';
import { ConfigService } from '../service/ConfigService';
import { KernelService } from '../service/KernelService';
import { VpnController } from '../service/VpnController';
import { SessionBuildResult, VpnSessionFactory } from '../service/VpnSessionFactory';
import { VpnState, VpnStateFile } from '../platform/VpnStateFile';
import { GeoAssets } from '../service/GeoAssets';
import { KernelConfigBuilder } from '../service/KernelConfigBuilder';
import { SocksEndpoint, SocksGuard } from '../service/SocksGuard';
import { BundleImportResult, ConfigBundle } from '../service/ConfigBundle';
import { DemoFlags } from '../platform/DemoFlags';

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
  @State bundleResult: string = '(未运行)';
  @State hostProbeResult: string = '(未运行)';
  /** 扩展进程回传的状态（starting / running / error / stopped） */
  @State vpnPhase: string = '';
  /** 首页流量块是否处于演示模式（默认关，打开会带「演示数据」标记） */
  @State trafficDemoOn: boolean = false;

  // 仅用于触发失败路径验证；真正的内核驱动在首页的 KernelService（同一个单例）
  private kernelDebug: KernelService = KernelService.getInstance();
  /** 组装 VPN 会话时需要读当前节点与规则 */
  private cfg: ConfigService = ConfigService.getInstance();

  aboutToAppear(): void {
    this.trafficDemoOn = DemoFlags.trafficDemo();
    if (AUTO_PROBE_VPN) {
      this.probeVpnExt();
    }
  }

  /**
   * 请求启动 VPN 扩展（数据面搬到扩展进程）。
   *
   * 这条路径在模拟器上必然失败或超时：模拟器缺系统 VPN 授权组件。
   * 它的用途是**真机联调时一键验证**：把当前选中节点的完整配置带进扩展进程，
   * 由那边起内核并建 tun，UI 侧只看结果。
   */
  private probeVpnExt(): void {
    this.vpnExtResult = '准备会话…';
    this.vpnPhase = 'starting';
    this.launchVpnSession().then(async () => {
      this.vpnExtResult = '已请求启动，等待扩展进程回传状态…';
      // 这一步就是本轮要验证的东西：应用进程能不能看到另一个进程里的真实状态
      const st: VpnState = await VpnController.waitForState(this.ctx(), 15000);
      this.vpnPhase = st.state;
      if (st.state === 'running') {
        this.vpnExtResult = `扩展进程已运行：${st.msg}`;
      } else {
        this.vpnExtResult = `扩展进程状态=${st.state} code=${st.code} ${st.msg}`;
      }
      hilog.info(DOMAIN, TAG, 'extension state: %{public}s', this.vpnExtResult);
    }).catch((e: Object) => {
      const msg: string = VpnController.describeError(e);
      this.vpnPhase = 'error';
      this.vpnExtResult = `未成功：${msg}`;
    });
  }

  /** 取应用上下文（状态文件在沙箱目录，两个进程同一份） */
  /**
   * 读一次扩展进程回传的状态（不启动、不等待）。
   * 用来排查“为什么没连上”：状态文件里的 code 就是扩展进程真实碰到的错误。
   */
  private readExtState(): void {
    const st: VpnState | null = VpnStateFile.read(this.ctx());
    if (st === null) {
      this.vpnExtResult = '无状态记录（扩展进程本次启动后从未被唤起）';
      return;
    }
    const age: number = st.at > 0 ? Math.round((Date.now() - st.at) / 1000) : -1;
    this.vpnPhase = st.state;
    this.vpnExtResult = `状态=${st.state} code=${st.code} ${st.msg}（${age} 秒前）`;
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  /**
   * 组装会话并启动扩展。
   * 配置在这里生成（而不是让扩展自己拼）：配置怎么写只有一处，避免两个进程各拼一份、
   * 规则悄悄不一致。
   */
  private async launchVpnSession(): Promise<void> {
    // 会话在 VpnSessionFactory 里组装：配置怎么写只有一处，避免两个进程各拼一份、规则惄惄不一致。
    const built: SessionBuildResult = await VpnSessionFactory.build(this.cfg, true);
    if (!built.ok || built.session === null) {
      this.vpnExtResult = built.error.length > 0 ? built.error : '会话构造失败';
      return;
    }
    await VpnController.start('com.tunnelix.app', 'MyVpnExtAbility', built.session);
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

  /**
   * 备份链路自检：导出 → 用错口令必须失败 → 用对口令必须成功。
   * 不做"只看导出成功"的假验证：解密失败路径才是密码学最容易错的地方。
   */
  private runBundleSelfTest(): void {
    this.bundleResult = 'running…';
    ConfigBundle.exportToText('selftest-pass-123').then(async (text: string) => {
      // 错口令必须被拒绝：这里看的是“结果不成功且有明确原因”，
      // 而不是“有没有抛异常”——服务层为了让 UI 可渲染是把错误放进结果对象的。
      const wrong: BundleImportResult = await ConfigBundle.importFromText(text, 'wrong-pass');
      const wrongRejected: boolean = !wrong.ok && wrong.error.length > 0;
      const ok: BundleImportResult = await ConfigBundle.importFromText(text, 'selftest-pass-123');
      const plainCred = text.indexOf('credential') >= 0 && text.indexOf('"credential": ""') < 0;
      const firstDetail: string = ok.details.length > 0
        ? `${ok.details[0].outcome}:${ok.details[0].name}(${ok.details[0].reason})` : 'none';
      const summary = `size=${text.length} wrongPassRejected=${wrongRejected} ` +
        `importOk=${ok.ok} nodes(${ok.addedNodes}/${ok.skippedNodes}) rules(${ok.addedRules}/${ok.skippedRules}) ` +
        `details=${ok.details.length} first=${firstDetail} plaintextCredLeak=${plainCred}`;
      this.bundleResult = summary;
      hilog.info(DOMAIN, TAG, 'bundle self-test: %{public}s', summary);
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.bundleResult = `failed: ${m}`;
      hilog.error(DOMAIN, TAG, 'bundle self-test failed: %{public}s', m);
    });
  }

  private runCGoPing(): void {    hilog.info(DOMAIN, TAG, 'cgoPing clicked');
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
    Column({ space: 0 }) {
      Column() {
        PageHeader({
          title: '开发者面板',
          onBack: () => {
            router.back();
          }
        })
      }
      .width('100%')
      .padding({ left: Space.sm, right: Space.sm })

      Scroll() {
        Column({ space: Space.sm }) {
          // 外观（浅色/深色/跟随系统）已移到「设置 → 外观」：
          // 主题是用户功能，留在调试页会变成第二个入口，两处迟早不一致。
          Button('NAPI hello()').onClick(() => this.runNapiHello()).width('100%')
          Text(this.napiHelloResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          Button('prebuilt_add(1,2)').onClick(() => this.runPrebuiltAdd()).width('100%')
          Text(this.prebuiltAddResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          Button('启动 VpnExtensionAbility（仅代码）').onClick(() => this.probeVpnExt()).width('100%')
          Text(this.vpnExtResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)
          Button('读取扩展进程回传状态').onClick(() => this.readExtState()).width('100%')

          Button('Go CGoPing()').onClick(() => this.runCGoPing()).width('100%')
          Text(this.cgoPingResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          Button('加载 libxray + CGoInvoke').onClick(() => this.runCGoInvoke()).width('100%')
          Text(this.cgoInvokeResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          Button('libxray xrayVersion').onClick(() => this.runXrayVersion()).width('100%')
          Text(this.xrayVersionResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          Button('经内核 SOCKS + 出口 IP 对比').onClick(() => this.runSocksProbe()).width('100%')
          Text(this.socksProbeResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          // E15 Step 1：真测 TCP + HTTP。不用 ping 代替——ICMP 通不代表端口通。
          Button('探测宿主 10.0.2.2:8000').onClick(() => this.runHostProbe()).width('100%')
          Text(this.hostProbeResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          // 备份链路自检：导出 → 错口令必须失败 → 对口令必须成功（脚本化，不依赖系统文件选择器）
          Button('备份自检（导出/解密/导入）').onClick(() => this.runBundleSelfTest()).width('100%')
          Text(this.bundleResult).fontSize(FontSize.caption).width('100%').lineHeight(LineHeight.caption)

          Divider()
          // 调试项：模拟"配置读取失败"，用于验证首页横幅与保存拦截（TODO 持久化接入后删除）
          Button('调试：模拟配置读取失败 → 看首页横幅').width('100%')
            .backgroundColor($r('app.color.warning'))
            .onClick(() => {
              ConfigService.getInstance().debugForceLoadFailure();
              this.socksProbeResult = '已置位 loadFailed=true；返回首页可见横幅，save() 将被拦截';
            })
          Text('预期：首页顶部出现"配置读取异常，已使用默认值（原数据未被覆盖）"').fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption).width('100%')

          // 调试项：让下一次「连接」注入非法配置，用于验证失败路径（ERROR 且不卡 CONNECTING）
          Button('调试：下次连接注入非法配置 → 看 ERROR').width('100%')
            .backgroundColor($r('app.color.warning'))
            .onClick(() => {
              this.kernelDebug.debugInjectInvalidConfig();
              this.socksProbeResult = '已置位 invalidConfig；返回首页点「连接」应显示错误原因（不卡连接中）';
            })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.xl })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_canvas'))
  }
}
