import { router } from '@kit.ArkUI';
import { ConnectionView, ConnState, ConnectionViewModel } from '../viewmodel/ConnectionViewModel';
import { ConfigService } from '../service/ConfigService';
import { XrayNode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';

/**
 * pages/Index.ets — 首页（连接开关 + 当前节点 + 连接状态）
 *
 * 结构约束：
 *   - 展示信息全部来自 ConnectionViewModel.deriveView()，页面不自己判断状态；
 *   - 页面只调用 requestConnect / requestDisconnect，不直接置位状态（FR-13）；
 *   - 骨架实现：连接为占位（无内核、无 tun），真实链路见 toolchain/APP-SKELETON.md。
 */
@Entry
@Component
struct Index {
  @State view: ConnectionView = new ConnectionView();
  @State nodeName: string = '（未选择）';
  @State stateTag: string = 'DISCONNECTED';

  private vm: ConnectionViewModel = new ConnectionViewModel();
  private cfg: ConfigService = ConfigService.getInstance();
  private simulateTimer: number = -1;

  aboutToAppear(): void {
    this.refreshAll();
  }

  aboutToDisappear(): void {
    if (this.simulateTimer >= 0) {
      clearTimeout(this.simulateTimer);
      this.simulateTimer = -1;
    }
  }

  /** 回到前台时重新拉取（等价于 FR-13 的"先拉真实状态再渲染"的最小版） */
  onPageShow(): void {
    this.refreshAll();
  }

  private refreshAll(): void {
    this.view = this.vm.deriveView();
    this.stateTag = this.vm.getState().toString();
    const n: XrayNode | null = this.cfg.getSelectedNode();
    this.nodeName = n === null ? '（未选择）' : n.name;
  }

  private isIdleOrError(): boolean {
    const st: ConnState = this.vm.getState();
    return st === ConnState.DISCONNECTED || st === ConnState.ERROR;
  }

  private onToggle(): void {
    if (this.isIdleOrError()) {
      this.vm.requestConnect();
      this.refreshAll();
      // 占位：真实实现里由 KernelService 回调 onKernelConnected / onKernelError。
      this.simulateTimer = setTimeout(() => {
        if (this.vm.getState() === ConnState.CONNECTING) {
          this.vm.onKernelConnected();
          this.refreshAll();
        }
      }, 800);
    } else {
      this.vm.requestDisconnect();
      this.refreshAll();
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('xray-harmony').fontSize(24).fontWeight(FontWeight.Bold)
      Text('骨架版本 · 未接入真实链路').fontSize(12).fontColor('#999999')

      Column({ space: 8 }) {
        Text(this.view.label).fontSize(22).fontColor(this.view.colorHex)
        Text(this.view.hint).fontSize(13).fontColor('#666666').textAlign(TextAlign.Center)
        Text(`state=${this.stateTag}`).fontSize(10).fontColor('#AAAAAA')
        Button(this.isIdleOrError() ? '连接' : (this.view.busy ? '取消' : '断开'))
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
