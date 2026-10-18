import { router } from '@kit.ArkUI';
import { ConnectionView, ConnState, ConnectionViewModel } from '../viewmodel/ConnectionViewModel';
import { ConfigService } from '../service/ConfigService';
import { XrayNode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';

/**
 * 骨架期模拟开关。
 *
 * TODO(必须删除)：`KernelService` 接入完成（能真实驱动 runXrayFromJson + 用户态健康探测）后，
 *   删除本常量与下方 onToggle() 里的 simulateTimer 分支，改由 KernelService 回调
 *   onKernelConnected / onKernelError。
 *
 * 为什么保留：让骨架能演示状态流转。但它"看起来像真的连上了"，
 * 所以 UI 必须显示 `(模拟)` 标识——避免两周后有人拿它演示、对方误以为已能连接。
 */
const IS_SKELETON_MOCK: boolean = true;

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
  @State configWarning: string = '';

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
    // 配置加载异常必须在 UI 可见（不能只在日志里）：否则用户会以为"节点全没了"
    this.configWarning = this.cfg.hasLoadFailure() ? '配置读取异常，已使用默认值（原数据未被覆盖）' : '';
  }

  private isIdleOrError(): boolean {
    const st: ConnState = this.vm.getState();
    return st === ConnState.DISCONNECTED || st === ConnState.ERROR;
  }

  private onToggle(): void {
    if (this.isIdleOrError()) {
      this.vm.requestConnect();
      this.refreshAll();
      // TODO(必须删除)：骨架期模拟服务回调；KernelService 接入后改为由其回调
      // onKernelConnected / onKernelError（并配合用户态健康探测，见 design §3.7）。
      if (IS_SKELETON_MOCK) {
        this.simulateTimer = setTimeout(() => {
          if (this.vm.getState() === ConnState.CONNECTING) {
            this.vm.onKernelConnected();
            this.refreshAll();
          }
        }, 800);
      }
    } else {
      this.vm.requestDisconnect();
      this.refreshAll();
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('xray-harmony').fontSize(24).fontWeight(FontWeight.Bold)
      Text('骨架版本 · 未接入真实链路').fontSize(12).fontColor('#999999')

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
          // 模拟标识：避免"看起来像真连上了"
          if (IS_SKELETON_MOCK) {
            Text('(模拟)').fontSize(12).fontColor('#FF7043')
          }
        }
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
