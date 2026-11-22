import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { ConnectionView, ConnState, ConnectionViewModel, StatusTone } from '../viewmodel/ConnectionViewModel';
import { ConfigService } from '../service/ConfigService';
import { KernelService, KernelError } from '../service/KernelService';
import { KernelConfigBuilder } from '../service/KernelConfigBuilder';
import { SocksEndpoint, SocksGuard } from '../service/SocksGuard';
import { GeoAssets } from '../service/GeoAssets';
import { XrayNode, RoutingMode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';

/**
 * pages/Index.ets — 首页（连接开关 + 当前节点 + 连接状态）
 *
 * 结构约束：
 *   - 展示信息全部来自 ConnectionViewModel.deriveView()，页面不自己判断状态；
 *   - 页面只调用 requestConnect / requestDisconnect，不直接置位状态；
 *   - **连接由 KernelService 真实驱动**：start 成功 + getXrayState.running:true 才进 CONNECTED；
 *     失败/超时一律进 ERROR 并给出可读原因（超时兜底见 KernelService）。
 */
@Entry
@Component
struct Index {
  @State view: ConnectionView = new ConnectionView();
  @State nodeName: string = '（未选择）';
  @State configWarning: string = '';
  @State busyHint: string = '';
  /** 当前本地 SOCKS 端点（端口可变，调试时需要看得到） */
  @State socksInfo: string = '';
  /** 只放 host:port：长按复制的内容必须精确等于它，带括号或说明就等于又把实现细节粘回去了 */
  @State socksPortText: string = '';
  /** 首次连接的一次性明示是否正在显示 */
  @State showNotice: boolean = false;
  /** 凭据迁移失败提示 */
  @State migrationWarning: string = '';

  private vm: ConnectionViewModel = new ConnectionViewModel();
  private cfg: ConfigService = ConfigService.getInstance();
  private kernel: KernelService = KernelService.getInstance();

  aboutToAppear(): void {
    this.refreshAll();
  }

  /** 回到前台时重新拉取真实状态（先拉真实状态再渲染） */
  onPageShow(): void {
    this.refreshAll();
  }

  private refreshAll(): void {
    const n: XrayNode | null = this.cfg.getSelectedNode();
    // 只把展示字符串交给 viewmodel：节点名优先，退到 host:port（不传 port/mode 这类实现字段）
    const label: string = n === null ? '' : (n.name.length > 0 ? n.name : `${n.address}:${n.port}`);
    this.view = this.vm.deriveView(label);
    this.nodeName = n === null ? '（未选择）' : n.name;
    // 配置加载异常必须在 UI 可见（不能只在日志里）：否则用户会以为"节点全没了"
    this.configWarning = this.cfg.hasLoadFailure() ? '配置读取异常，已使用默认值（原数据未被覆盖）' : '';
    this.migrationWarning = this.cfg.getMigrationError();
  }

  /** 语义色调 → 资源色（页面是唯一知道"哪个令牌对应哪种状态"的地方） */
  private toneColor(): Resource {
    const t: StatusTone = this.view.tone;
    if (t === StatusTone.OK) {
      return $r('app.color.status_connected');
    }
    if (t === StatusTone.PENDING) {
      return $r('app.color.status_connecting');
    }
    if (t === StatusTone.ERROR) {
      return $r('app.color.status_error');
    }
    return $r('app.color.status_disconnected');
  }

  /** 长按复制代理地址：内容严格等于 host:port，不带括号与说明 */
  private copyProxyAddress(): void {
    if (this.socksPortText.length === 0) {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.socksPortText);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '已复制', duration: 1500 });
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.warn(`copy proxy address failed: ${msg}`);
      promptAction.showToast({ message: '复制失败', duration: 1500 });
    });
  }

  private isIdleOrError(): boolean {    const st: ConnState = this.vm.getState();
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
    this.runConnect().then(() => {
    }).catch((e: Object) => {
      this.busyHint = '';
      this.vm.onKernelError(this.toReadable(e));
      this.refreshAll();
    });
  }

  private async runConnect(): Promise<void> {
    // 首次连接必须先完成一次性明示：**在改状态之前**拦下，否则 UI 会先跳到“连接中”
    // 再弹窗，用户会以为已经连上了。明示确认后由 noticeOverlay 的按钮回调继续连接。
    if (!this.cfg.isOnboardingDone()) {
      this.showNotice = true;
      return;
    }
    this.vm.requestConnect();
    this.busyHint = '';
    this.refreshAll();

    // v1 明文凭据在此迁移到 Asset Store（幂等）；失败不阻断连接，但必须可见
    await this.cfg.ensureSecureMigration();

    const sel: XrayNode | null = this.cfg.getSelectedNode();
    let credential: string = '';
    if (sel !== null) {
      const c: string | null = await this.cfg.resolveCredential(sel);
      if (c === null) {
        // 拿不到凭据就必须阻断：拿空串去连，内核只会给一个与真实原因无关的握手错误
        this.busyHint = '';
        this.vm.onKernelError('节点凭据不可用（安全存储中找不到对应密钥），请重新导入该节点');
        this.refreshAll();
        return;
      }
      credential = c;
    }

    const mode: RoutingMode = this.cfg.getConfig().settings.routingMode;
    // 每次连接轮换本机代理端口与口令（loopback 同设备共享，不能免鉴权）
    const ep: SocksEndpoint = SocksGuard.rotate();
    const cfgJson: string = sel === null
      ? KernelConfigBuilder.buildMinimal(ep.port, ep.user, ep.password)
      : KernelConfigBuilder.buildWithNode(sel, ep.port, mode, ep.user, ep.password, credential,
        GeoAssets.isReady(), this.cfg.getRules());
    // 用户看不懂协议名，但端口是报障时唯一能自证的线索 —— 换词不删信息
    this.socksInfo = `本机代理地址 127.0.0.1:${ep.port}`;
    this.socksPortText = `127.0.0.1:${ep.port}`;

    try {
      await this.kernel.start(cfgJson, KernelService.CONNECT_TIMEOUT_MS);
      this.vm.onKernelConnected();
      this.busyHint = '';
      this.refreshAll();
    } catch (err) {
      const msg: string = this.toReadable(err as Object);
      this.busyHint = '';
      this.vm.onKernelError(msg);
      this.refreshAll();
      // 失败/超时可能留下"半启动"内核（占着端口），必须后台收尾，
      // 否则用户点重试会直接被端口占用挡住。不 await：用户已经在看错误文案，不该再等 5 秒。
      this.kernel.bestEffortStop().then(() => {
        Logger.warn('post-failure cleanup finished');
      });
    }
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
      // 先判明示：没确认过就不该出现“正在启动内核”的提示，
      // 否则弹窗和进度文案同时出现，用户会以为连接已经在进行。
      if (!this.cfg.isOnboardingDone()) {
        this.showNotice = true;
        return;
      }
      this.busyHint = '正在启动内核…';
      this.doConnect();
    } else {
      this.doDisconnect();
    }
  }

  build() {
    Stack() {
      Column({ space: 16 }) {
      Text('Tunnelix')
        .fontSize(FontSize.display)
        .lineHeight(LineHeight.display)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      // 定位语：不写实现细节（协议名/内核/未接节点都归状态行与日志）
      Text('本地转发，规则由你定')
        .fontSize(FontSize.bodySm)
        .lineHeight(LineHeight.bodySm)
        .fontColor($r('app.color.text_tertiary'))

      // 配置加载异常横幅：必须在 UI 可见（评审要求，不允许只写日志）
      if (this.configWarning.length > 0) {
        Text(this.configWarning)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.warning'))
          .width('100%')
          .padding(Space.md)
          .backgroundColor($r('app.color.warning_subtle'))
          .borderRadius(Radius.panel)
      }

      // 凭据迁移失败横幅：不允许"以为已加密，其实还是明文"
      if (this.migrationWarning.length > 0) {
        Text(this.migrationWarning)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding(Space.md)
          .backgroundColor($r('app.color.danger_subtle'))
          .borderRadius(Radius.panel)
      }

      Column({ space: Space.sm }) {
        Row({ space: Space.xs }) {
          // 语义枚举 → 资源色：ViewModel 里不再有 hex，深色模式才有解
          Text(this.view.label)
            .fontSize(FontSize.display)
            .lineHeight(LineHeight.display)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.toneColor())
        }
        Text(this.view.hint)
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        if (this.busyHint.length > 0) {
          Text(this.busyHint)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.accent'))
        }
        if (this.socksInfo.length > 0) {
          // 诊断类信息：层级明确低于节点名/状态，但端口必须可读、可复制
          Text(this.socksInfo)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .accessibilityText(`${this.socksInfo}，长按可复制`)
            .gesture(
              LongPressGesture({ repeat: false, duration: 500 })
                .onAction(() => {
                  this.copyProxyAddress();
                })
            )
        }
        Button(this.buttonLabel())
          .enabled(this.view.canToggle)
          .width('70%')
          .height(Height.hit)
          .fontSize(FontSize.bodyLg)
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.text_on_accent'))
          .onClick(() => this.onToggle())
      }
      .width('100%')
      .padding(Space.lg)
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(Radius.card)

      Row({ space: Space.sm }) {
        Text('当前节点')
          .fontSize(FontSize.body)
          .fontColor($r('app.color.text_secondary'))
        Text(this.nodeName)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('更换')
          .fontSize(FontSize.bodySm)
          .height(Height.hit)
          .backgroundColor($r('app.color.bg_chip'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            router.pushUrl({ url: 'pages/Nodes' }).catch((e: Error) => {
              Logger.error(`nav Nodes failed: ${e.message}`);
            });
          })
      }
      .width('100%')
      .padding(Space.md)
      .backgroundColor($r('app.color.bg_surface'))
      .borderRadius(Radius.panel)

      Blank()

      Row({ space: Space.md }) {
        Button('节点列表').layoutWeight(1)
          .height(Height.hit)
          .fontSize(FontSize.bodySm)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Nodes' }).catch((e: Error) => {
              Logger.error(`nav Nodes failed: ${e.message}`);
            });
          })
        Button('设置').layoutWeight(1)
          .height(Height.hit)
          .fontSize(FontSize.bodySm)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' }).catch((e: Error) => {
              Logger.error(`nav Settings failed: ${e.message}`);
            });
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(Space.lg)
    .backgroundColor($r('app.color.bg_canvas'))

      if (this.showNotice) {
        this.noticeOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 首次连接的一次性明示（四要素）。
   *
   * 硬约束（都是需求原文，不是我的偏好）：
   *   - 四要素必须**同屏可见**，不能折叠进“详情”；
   *   - 只能通过「我已了解」关闭：没有预勾选的“不再提示”，没有跳过按钮，
   *     背景点击 / 返回键 / 手势返回都不能关掉（见 onBackPress）；
   *   - 文案不得出现“不影响使用”“仅偶发”这类淡化表述。
   */
  @Builder
  noticeOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text('连接前请先了解').fontSize(18).fontWeight(FontWeight.Bold)

        this.noticeItem('1',
          '应用被系统或你手动终止时，代理会一起停止，设备流量将恢复直连——' +
          '也就是说，退出应用之后网络不再受保护。')
        this.noticeItem('2',
          '本应用不提供进程级 kill switch，无法做到“断了也不许直连”。')
        this.noticeItem('3',
          'IPv6 策略：当前 IPv6 已接管并阻断，流量走 IPv4；如需 IPv6 代理，' +
          '需要在设置中显式开启（开启后会显示“IPv6 代理已启用”）。')
        this.noticeItem('4',
          '如果长时任务通知被清除，后台保活会停止，连接可能中断。')

        Button('我已了解')
          .width('100%')
          .height(Height.hit)
          .fontSize(FontSize.bodyLg)
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.text_on_accent'))
          .onClick(() => {
            if (this.cfg.markOnboardingDone()) {
              this.showNotice = false;
              // 确认后直接继续这次连接，不让用户再点一次
              this.doConnect();
            } else {
              this.busyHint = '无法保存“已了解”状态，请重试';
            }
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width('88%')
      .padding(Space.xl)
      .backgroundColor($r('app.color.bg_surface'))
      .borderRadius(Radius.lg)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 全屏遮罩：点空白处不关闭（没有 onClick），只挡住背景交互
    .backgroundColor($r('app.color.scrim'))
  }

  @Builder
  noticeItem(index: string, text: string) {
    Row({ space: Space.sm }) {
      Text(index)
        .fontSize(FontSize.caption)
        .fontColor($r('app.color.text_on_accent'))
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.accent'))
        .borderRadius(Radius.pill)
      Text(text)
        .fontSize(FontSize.bodySm)
        .lineHeight(LineHeight.bodySm)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  /** 明示未确认时，返回键不得关闭它——需求里明确把这条列为绕过尝试之一 */
  onBackPress(): boolean {
    if (this.showNotice) {
      return true;
    }
    return false;
  }
}
