import { router } from '@kit.ArkUI';
import { ConnectionView, ConnState, ConnectionViewModel } from '../viewmodel/ConnectionViewModel';
import { ConfigService } from '../service/ConfigService';
import { KernelService, KernelError } from '../service/KernelService';
import { KernelConfigBuilder } from '../service/KernelConfigBuilder';
import { XrayNode, RoutingMode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';

/**
 * pages/Index.ets — 首页（连接开关 + 当前节点 + 连接状态）
 *
 * 结构约束：
 *   - 展示信息全部来自 ConnectionViewModel.deriveView()，页面不自己判断状态；
 *   - 页面只调用 requestConnect / requestDisconnect，不直接置位状态（FR-13）；
 *   - **连接由 KernelService 真实驱动**：start 成功 + getXrayState.running:true 才进 CONNECTED；
 *     失败/超时一律进 ERROR 并给出可读原因（超时兜底见 KernelService，FR-40）。
 */
@Entry
@Component
struct Index {
  @State view: ConnectionView = new ConnectionView();
  @State nodeName: string = '（未选择）';
  @State stateTag: string = 'DISCONNECTED';
  @State configWarning: string = '';
  @State busyHint: string = '';

  private vm: ConnectionViewModel = new ConnectionViewModel();
  private cfg: ConfigService = ConfigService.getInstance();
  private kernel: KernelService = KernelService.getInstance();

  aboutToAppear(): void {
    this.refreshAll();
  }

  /** 回到前台时重新拉取真实状态（FR-13：先拉真实状态再渲染） */
  onPageShow(): void {
    this.refreshAll();
  }

  private refreshAll(): void {
    this.view = this.vm.deriveView();
    this.stateTag = this.vm.getState().toString();
    const n: XrayNode | null = this.cfg.getSelectedNode();
    this.nodeName = n === null ? '（未选择）' : n.name;
    // 配置加载异常必须在 UI 可见（不能只在日志里）：否则用户会以为"节点全没了"
    this.configWarning = this.cfg.hasLoadFailure() ? '配置读取异常，已使用默认值（原数据未被覆盖）' : '';
  }

  private isIdleOrError(): boolean {
    const st: ConnState = this.vm.getState();
    return st === ConnState.DISCONNECTED || st === ConnState.ERROR;
  }

  private toReadable(err: Object): string {
    const ke = err as KernelError;
    if (ke !== null && ke !== undefined && ke.message !== undefined && ke.message.length > 0) {
      return ke.message;
    }
    return '连接失败（原因未知，详见日志）';
  }

  private doConnect(): void {
    this.vm.requestConnect();
    this.busyHint = '';
    this.refreshAll();

    const sel: XrayNode | null = this.cfg.getSelectedNode();
    const mode: RoutingMode = this.cfg.getConfig().settings.routingMode;
    const cfgJson: string = sel === null
      ? KernelConfigBuilder.buildMinimal()
      : KernelConfigBuilder.buildWithNode(sel, KernelConfigBuilder.DEFAULT_SOCKS_PORT, mode);
    this.kernel.start(cfgJson, KernelService.CONNECT_TIMEOUT_MS)
      .then(() => {
        this.vm.onKernelConnected();
        this.busyHint = '';
        this.refreshAll();
      })
      .catch((err: Object) => {
        const msg: string = this.toReadable(err);
        this.busyHint = '';
        this.vm.onKernelError(msg);
        this.refreshAll();
        // 失败/超时可能留下"半启动"内核（占着 18080），必须后台收尾，
        // 否则用户点重试会直接被端口占用挡住。不 await：用户已经在看错误文案，不该再等 5 秒。
        this.kernel.bestEffortStop().then(() => {
          Logger.warn('post-failure cleanup finished');
        });
      });
  }

  private doDisconnect(): void {
    this.busyHint = '正在停止内核…';
    this.kernel.stop(KernelService.DISCONNECT_TIMEOUT_MS)
      .then(() => {
        this.vm.requestDisconnect();
        this.busyHint = '';
        this.refreshAll();
      })
      .catch((err: Object) => {
        const msg: string = this.toReadable(err);
        this.busyHint = '';
        this.vm.onKernelError(msg);
        this.refreshAll();
      });
  }

  /** 按钮文案：ERROR 态明确给出「重试」，而不是让用户猜「连接」还能不能再点 */
  private buttonLabel(): string {
    const st: ConnState = this.vm.getState();
    if (st === ConnState.ERROR) {
      return '重试';
    }
    if (st === ConnState.DISCONNECTED) {
      return '连接';
    }
    if (this.view.busy) {
      return '取消';
    }
    return '断开';
  }

  private onToggle(): void {
    if (this.isIdleOrError()) {
      this.busyHint = '正在启动内核…';
      this.doConnect();
    } else {
      this.doDisconnect();
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('Tunnelix').fontSize(24).fontWeight(FontWeight.Bold)
      Text('内核直连驱动（socks + freedom，未接节点）').fontSize(12).fontColor('#999999')

      // 配置加载异常横幅：必须在 UI 可见（评审要求，不允许只写日志）
      if (this.configWarning.length > 0) {
        Text(this.configWarning)
          .fontSize(12)
          .fontColor('#8D6E63')
          .width('100%')
          .padding(10)
          .backgroundColor('#FFF3E0')
          .borderRadius(8)
      }

      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text(this.view.label).fontSize(22).fontColor(this.view.colorHex)
        }
        Text(this.view.hint).fontSize(13).fontColor('#666666').textAlign(TextAlign.Center)
        if (this.busyHint.length > 0) {
          Text(this.busyHint).fontSize(11).fontColor('#1976D2')
        }
        Text(`state=${this.stateTag}`).fontSize(10).fontColor('#AAAAAA')
        Button(this.buttonLabel())
          .enabled(this.view.canToggle)
          .onClick(() => this.onToggle())
          .width('70%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor('#F5F5F5')
      .borderRadius(12)

      Row({ space: 8 }) {
        Text('当前节点').fontSize(14).fontColor('#666666')
        Text(this.nodeName).fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('更换').fontSize(12)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Nodes' }).catch((e: Error) => {
              Logger.error(`nav Nodes failed: ${e.message}`);
            });
          })
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#FAFAFA')
      .borderRadius(8)

      Blank()

      Row({ space: 12 }) {
        Button('节点列表').layoutWeight(1)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Nodes' }).catch((e: Error) => {
              Logger.error(`nav Nodes failed: ${e.message}`);
            });
          })
        Button('设置').layoutWeight(1)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' }).catch((e: Error) => {
              Logger.error(`nav Settings failed: ${e.message}`);
            });
          })
      }
      .width('100%')

      Button('开发者面板（PoC 探针）').width('100%')
        .backgroundColor('#455A64')
        .onClick(() => {
          router.pushUrl({ url: 'pages/DevPanel' }).catch((e: Error) => {
            Logger.error(`nav DevPanel failed: ${e.message}`);
          });
        })
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
