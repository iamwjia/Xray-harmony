import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { ConnectionView, ConnState, ConnectionViewModel, StatusTone } from '../viewmodel/ConnectionViewModel';
import { ConfigService } from '../service/ConfigService';
import { KernelError } from '../service/KernelService';
import { SessionBuildResult, VpnSessionFactory } from '../service/VpnSessionFactory';
import { VpnSession } from '../service/VpnSession';
import { SocksEndpoint, SocksGuard } from '../service/SocksGuard';
import { GeoAssets } from '../service/GeoAssets';
import { XrayNode, RoutingMode } from '../model/AppConfig';
import { Logger } from '../platform/Logger';
import { common } from '@kit.AbilityKit';
import { VpnState, VpnStateFile } from '../platform/VpnStateFile';
import { VpnController } from '../service/VpnController';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';
import { NavTile } from '../components/Glyph';
import { AppEvent, EventLog } from '../service/EventLog';
import { DemoFlags } from '../platform/DemoFlags';
import { SubscriptionService } from '../service/SubscriptionService';

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
  /** 系统 VPN（扩展进程）状态文案；空串 = 从未尝试 */
  @State vpnLine: string = '';
  @State vpnLineLevel: number = 0;
  /** 只放 host:port：长按复制的内容必须精确等于它，带括号或说明就等于又把实现细节粘回去了 */
  @State socksPortText: string = '';
  /** 首次连接的一次性明示是否正在显示 */
  @State showNotice: boolean = false;
  /** 凭据迁移失败提示 */
  @State migrationWarning: string = '';

  /** 本次连接已持续时长（mm:ss / h:mm:ss）；未连接为空 */
  @State uptimeText: string = '';
  /** 上下行流量文本（真数据要内核 Stats；未接通时明确写不可用，不显示 0） */
  @State trafficText: string = '';
  /** 是否处于演示数据模式（界面上必须打「演示数据」标记） */
  @State trafficDemo: boolean = false;
  /** 最近事件（最多 3 条） */
  @State events: AppEvent[] = [];

  private vm: ConnectionViewModel = new ConnectionViewModel();
  private cfg: ConfigService = ConfigService.getInstance();
  /** 连接成功的时刻（0 = 未连接） */
  private connectedAt: number = 0;
  /** 连接尝试序号：用户中途取消后 +1，仍在 await 的那次尝试回来后发现自己已过期就不写状态 */
  private attemptSeq: number = 0;
  private tickTimer: number = -1;
  /** 演示流量的累计值（只在演示模式下动） */
  private demoDown: number = 0;
  private demoUp: number = 0;
  // 应用进程不再直接持有内核：数据面在扩展进程，应用侧只发请求 + 读状态文件

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
    this.refreshVpnLine();
    this.refreshStatusStrip();
    this.refreshEvents();
  }

  /** 最近事件：读落盘缓冲的最新 3 条 */
  private refreshEvents(): void {
    this.events = EventLog.recent(3);
  }

  /**
   * 首页状态条：时长 + 流量。
   *
   * 流量**没有真数据**：内核 Stats 要等扩展进程起得内核才有，而现在卡在系统授权（202）。
   * 所以这里只有两种状态：演示模式（带「演示数据」标记）或明说"统计不可用"。
   * 绝不在没有数据时显示 0 —— 那会让用户以为"连上了但没走流量"。
   */
  private refreshStatusStrip(): void {
    this.trafficDemo = DemoFlags.trafficDemo();
    const connected: boolean = this.vm.getState() === ConnState.CONNECTED;
    if (connected) {
      if (this.connectedAt === 0) {
        this.connectedAt = Date.now();
        this.demoDown = 0;
        this.demoUp = 0;
        this.startTick();
      }
    } else if (this.connectedAt !== 0) {
      this.connectedAt = 0;
      this.uptimeText = '';
      this.stopTick();
    }
    this.tickOnce();
  }

  private startTick(): void {
    if (this.tickTimer !== -1) {
      return;
    }
    this.tickTimer = setInterval(() => {
      this.tickOnce();
    }, 1000);
  }

  private stopTick(): void {
    if (this.tickTimer === -1) {
      return;
    }
    clearInterval(this.tickTimer);
    this.tickTimer = -1;
  }

  private tickOnce(): void {
    const connected: boolean = this.connectedAt > 0;
    if (connected) {
      const sec: number = Math.floor((Date.now() - this.connectedAt) / 1000);
      this.uptimeText = this.formatUptime(sec);
    }
    if (this.trafficDemo) {
      // 演示数据：按每秒几百 KB 的节奏累加，只为让布局有"活"的数字可看
      this.demoDown += 1000 + Math.floor(Math.random() * 900);
      this.demoUp += 100 + Math.floor(Math.random() * 90);
      this.trafficText = `↓ ${Index.bytesText(this.demoDown)}  ↑ ${Index.bytesText(this.demoUp)}`;
      return;
    }
    this.trafficText = connected
      ? '统计未接通：内核未提供数据（等真机验证后接入）'
      : '未连接，无流量数据';
  }

  private formatUptime(sec: number): string {
    const h: number = Math.floor(sec / 3600);
    const m: number = Math.floor((sec % 3600) / 60);
    const s: number = sec % 60;
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const ss: string = s < 10 ? `0${s}` : `${s}`;
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  private static bytesText(n: number): string {
    if (n < 1024) {
      return `${n} B`;
    }
    if (n < 1024 * 1024) {
      return `${(n / 1024).toFixed(1)} KB`;
    }
    return `${(n / 1024 / 1024).toFixed(1)} MB`;
  }

  private nav(url: string): void {
    router.pushUrl({ url: url }).catch((e: Error) => {
      Logger.error(`nav ${url} failed: ${e.message}`);
    });
  }

  /** 入口格的副标题：写"有几个"，不写"点击进入"这种废话 */
  private nodeCountHint(): string {
    return `${this.cfg.getNodes().length} 个`;
  }

  private subHint(): string {
    // 订阅存在 SubscriptionStore 里。AppConfig.subscriptions 只有"旧整包 JSON"那条
    // 反序列化路径才会被填，现在的持久化布局下它恒为空——读它就会把"3 个订阅"
    // 显示成"未添加"（这个 bug 就是这么来的）。
    const n: number = SubscriptionService.listSubscriptions().length;
    return n === 0 ? '未添加' : `${n} 个`;
  }

  private routingHint(): string {
    const m: RoutingMode = this.cfg.getConfig().settings.routingMode;
    if (m === RoutingMode.GLOBAL) {
      return '全局代理';
    }
    return m === RoutingMode.DIRECT ? '全部直连' : '规则分流';
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

  /**
   * 把扩展进程回传的状态变成一句人话。
   *
   * 为什么首页要看得到：本地代理开着不等于“全局走代理”。
   * 用户以为连上了却发现未改变流量路径，是最坏的体验；
   * 随时告诉他“系统 VPN 有没有真正接管”。
   */
  private refreshVpnLine(): void {
    const st: VpnState | null = VpnStateFile.read(getContext(this) as common.UIAbilityContext);
    if (st === null) {
      this.vpnLine = '';
      this.vpnLineLevel = 0;
      return;
    }
    if (st.state === 'running') {
      this.vpnLine = VpnStateFile.isStale(st)
        ? '系统 VPN：状态已过期（扩展进程可能已被终止）'
        : `系统 VPN：已接管（${st.msg}）`;
      this.vpnLineLevel = VpnStateFile.isStale(st) ? 1 : 0;
      return;
    }
    if (st.state === 'error') {
      const why: string = VpnController.describeStateCode(st.code);
      this.vpnLine = `系统 VPN：未接管 —— ${why.length > 0 ? why : st.msg}`;
      this.vpnLineLevel = 2;
      return;
    }
    // starting / stopped
    this.vpnLine = st.state === 'starting' ? '系统 VPN：正在接管…' : '';
    this.vpnLineLevel = 0;
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
    const myAttempt: number = ++this.attemptSeq;
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

    // 会话只在一个地方组装（VpnSessionFactory），避免首页与开发者面板各拼一份配置
    const built: SessionBuildResult = await VpnSessionFactory.build(this.cfg, true);
    if (!built.ok) {
      this.busyHint = '';
      this.vm.onKernelError(built.error);
      this.refreshAll();
      return;
    }
    const session: VpnSession | null = built.session;
    if (session === null) {
      this.busyHint = '';
      this.vm.onKernelError('会话构造失败');
      this.refreshAll();
      return;
    }
    // 用户看不懂协议名，但端口是报障时唯一能自证的线索 —— 换词不删信息
    this.socksInfo = `本机代理地址 ${SocksGuard.LOCAL_HOST}:${built.socksPort} · 长按复制`;
    this.socksPortText = `${SocksGuard.LOCAL_HOST}:${built.socksPort}`;
    this.refreshAll();

    try {
      // 数据面只能在扩展进程：tun fd 只在创建它的进程内有效。
      // 不再在应用进程起内核——否则两边各有一个内核，状态互不可见。
      //
      // 注意这里**不 await 启动调用**：首次连接会弹系统授权对话框，
      // 用户不点之前该 promise 不会 settle——但扩展进程很可能已经起来并写了状态。
      // 所以以“状态文件”为准，而不是以调用是否返回为准。
      VpnController.start('com.tunnelix.app', 'MyVpnExtAbility', session).catch((e: Object) => {
        Logger.warn(`vpn start call failed: ${VpnController.describeError(e)}`);
      });
      const st: VpnState = await VpnController.waitForState(this.ctx(), VpnController.START_TIMEOUT_MS);
      // 用户在等待期间点了"取消"（或又发起了一次连接）：这次尝试已过期，
      // 不能再把状态改成 ERROR —— 否则界面上会从"未连接"跳成"连接异常"。
      if (myAttempt !== this.attemptSeq) {
        return;
      }
      this.busyHint = '';
      if (st.state === 'running') {
        this.vm.onKernelConnected();
        EventLog.push(0, `已连接：${this.nodeName}`);
      } else {
        const why: string = VpnController.describeStateCode(st.code);
        EventLog.push(2, `连接失败：${why.length > 0 ? why : st.msg}`);
        this.vm.onKernelError(why.length > 0 ? why : (st.msg.length > 0 ? st.msg : '扩展进程未能就绪'));
      }
      this.refreshAll();
    } catch (err) {
      if (myAttempt !== this.attemptSeq) {
        // 这次尝试已被用户取消（或已被新的尝试取代）：错误属于废弃的流程，直接丢弃
        return;
      }
      const msg: string = VpnController.describeError(err as Object);
      this.busyHint = '';
      this.vm.onKernelError(msg);
      this.refreshAll();
      // 失败后可能留下半启动的扩展进程，发一次停止请求兜底
      VpnController.stop('com.tunnelix.app', 'MyVpnExtAbility').then(() => {
        Logger.warn('post-failure cleanup finished');
      });
    }
  }

  private doDisconnect(): void {
    const wasConnecting: boolean = this.view.busy;
    if (wasConnecting) {
      // 作废仍在进行的那次连接尝试，并说明"这是用户主动取消"而不是失败
      this.attemptSeq++;
      EventLog.push(1, '已取消连接（用户在启动过程中中止）');
    }
    this.busyHint = '正在断开…';
    // 应用侧只能“请求”停止；真正的收尾（停转发 → 停内核 → 销 tun）在扩展进程里
    VpnController.stop('com.tunnelix.app', 'MyVpnExtAbility')
      .then(() => {
        this.vm.requestDisconnect();
        this.busyHint = '';
        EventLog.push(0, `已断开：${this.nodeName}`);
        this.refreshAll();
      })
      .catch((err: Object) => {
        // 断开失败 ≠ 连接异常：用户是来断的，把它标成 ERROR 会让人以为连接出了问题
        const msg: string = VpnController.describeError(err);
        this.busyHint = '';
        this.vm.requestDisconnect();
        // 正在启动时点取消，stop 本来就可能失败（进程还没建起来）——那是预期路径，
        // 记成红色错误只会让用户以为出了问题；只有"已连上后再断开失败"才值得记。
        if (!wasConnecting) {
          EventLog.push(2, `断开时出错：${msg}`);
        }
        this.refreshAll();
      });
  }

  /** 取应用上下文（状态文件在沙箱目录，两个进程同一份） */
  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  /** 按钮文案：ERROR 态明确给出「重试」，而不是让用户猜「连接」还能不能再点 */
  /** 大色块底色：低饱和浅底 + 左侧实色状态条，避免整块高饱和色抢走所有注意力 */
  private toneBg(): Resource {
    const t: StatusTone = this.view.tone;
    if (t === StatusTone.OK) {
      return $r('app.color.success_subtle');
    }
    if (t === StatusTone.PENDING) {
      return $r('app.color.warning_subtle');
    }
    if (t === StatusTone.ERROR) {
      return $r('app.color.danger_subtle');
    }
    return $r('app.color.bg_surface');
  }

  /** 块内那句"点了会发生什么"：状态大字已经有了，这里只写动作，不重复状态 */
  /**
   * 色块里那句"点了会发生什么"。
   * 必须按状态枚举逐个写，不能靠"非 DISCONNECTED 就算已连"——实测连接中时
   * 文案会落成"点此连接"，与标题的"连接中"互相矛盾（用户会以为点了是重新连）。
   */
  private blockActionText(): string {
    const st: ConnState = this.vm.getState();
    if (st === ConnState.ERROR) {
      return '点此重试';
    }
    // busy 先判：启动过程中 vm 状态可能还是 DISCONNECTED（要等扩展进程回传），
    // 但界面上大字已经显示"连接中"，此时那句提示必须同步成"点此取消"，
    // 否则标题说"连接中"、下面说"点此连接"，用户会以为点了是重新连。
    if (this.view.busy || st === ConnState.CONNECTING) {
      return '点此取消';
    }
    if (st === ConnState.CONNECTED) {
      return '点此断开';
    }
    return '点此连接';
  }

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
      Column({ space: Space.lg }) {
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

      // 状态与操作合成一块：色块本身就是状态指示器，整块可点即"连接/断开"。
      // 原来"大字说未连接 + 下面再来一个连接按钮"，同一件事说了两遍，还多一次寻址。
      Row() {
        // 左侧状态条：靠位置+形状也能读到状态，颜色不是唯一载体
        Column()
          .width(8)
          .height(148)
          .backgroundColor(this.toneColor())

        Column({ space: Space.xs }) {
          Text(this.view.label)
            .fontSize(FontSize.display)
            .lineHeight(LineHeight.display)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.toneColor())
          if (this.uptimeText.length > 0) {
            Text(`已连接 ${this.uptimeText}`)
              .fontSize(FontSize.bodySm)
              .lineHeight(LineHeight.bodySm)
              .fontColor($r('app.color.text_secondary'))
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
          Text(this.blockActionText())
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .padding({ top: Space.lg, bottom: Space.lg, left: Space.md, right: Space.md })
      }
      .width('100%')
      .height(148)
      .backgroundColor(this.toneBg())
      .borderRadius(Radius.card)
      .border({ width: 1, color: $r('app.color.border_subtle') })
      .onClick(() => {
        this.onToggle();
      })
      .accessibilityText(`${this.view.label}，${this.blockActionText()}`)

      // 诊断信息放在色块之外：压在色块里会被状态色抢掉，且长按复制的命中区会与整块点击打架
      if (this.socksInfo.length > 0) {
        Text(this.socksInfo)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .accessibilityText(`${this.socksInfo}，长按可复制`)
          .gesture(
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => {
                this.copyProxyAddress();
              })
          )
      }
      if (this.vpnLine.length > 0) {
        Text(this.vpnLine)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor(this.vpnLineLevel === 2
            ? $r('app.color.danger')
            : (this.vpnLineLevel === 1 ? $r('app.color.warning') : $r('app.color.text_secondary')))
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      Row({ space: Space.sm }) {
        Text('当前节点')
          .fontSize(FontSize.body)
          .fontColor($r('app.color.text_secondary')).maxLines(1)
        Text(this.nodeName)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        // 连接中/断开中不让换节点：换完之后进行中的连接还指向旧节点，
        // 用户会以为"换了但没生效"。禁用态同时要看起来是灰的（见下两行）。
        Button('更换')
          .fontSize(FontSize.bodySm)
          .height(Height.hit)
          .enabled(!this.view.busy)
          .backgroundColor(this.view.busy ? $r('app.color.bg_chip') : $r('app.color.accent_subtle'))
          .fontColor(this.view.busy ? $r('app.color.text_tertiary') : $r('app.color.accent'))
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

      // 状态条：时长 + 流量 + 最近事件。
      // 这块原来是纯 Blank，占掉半个屏幕却什么都没说；现在回答三个最常问的问题：
      // "连了多久""走了多少流量""上次为什么没连上"。
      Column({ space: Space.sm }) {
        Row({ space: Space.md }) {
          Column({ space: 2 }) {
            Row({ space: Space.xs }) {
              Text('上下行')
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.text_tertiary'))
              if (this.trafficDemo) {
                // 演示数据必须自曝身份：不标出来就等于用假数字骗人
                Text('演示数据')
                  .fontSize(FontSize.fontChip)
                  .lineHeight(LineHeight.fontChip)
                  .fontColor($r('app.color.warning'))
                  .padding({ left: Space.xs, right: Space.xs, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.warning_subtle'))
                  .borderRadius(Radius.chip)
              }
            }
            Text(this.trafficText)
              .fontSize(this.trafficDemo ? FontSize.titleMd : FontSize.caption)
              .lineHeight(this.trafficDemo ? LineHeight.titleMd : LineHeight.caption)
              .fontColor(this.trafficDemo ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.End)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        if (this.events.length > 0) {
          Divider()
          ForEach(this.events, (e: AppEvent) => {
            Row({ space: Space.sm }) {
              Text(EventLog.timeText(e.ts))
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.text_tertiary'))
              Text(e.text)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor(e.level === 2
                  ? $r('app.color.danger')
                  : (e.level === 1 ? $r('app.color.warning') : $r('app.color.text_secondary')))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
          }, (e: AppEvent) => `${e.ts}-${e.text}`)
        } else {
          Text('还没有事件记录。连接一次，这里会显示结果。')
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(Space.md)
      .backgroundColor($r('app.color.bg_surface'))
      .borderRadius(Radius.panel)

      Blank()

      // 常用入口：2×3 图标格。整格可点（命中区 = 视觉区），
      // 副标题直接写"当前是什么"，省得为了看一眼状态点进去再退出来。
      Column({ space: Space.sm }) {
        Row({ space: Space.sm }) {
          // 图标色按功能族：蓝=数据（节点/备份）、紫=外部内容（订阅）、
          // 青=规则（分流）、琥珀=诊断（日志）、灰=系统（设置）。
          // 不是每格一个随机色——颜色要能回答问题（"这一类"），不是装饰。
          NavTile({
            kind: 'nodes', label: '节点', hint: this.nodeCountHint(),
            iconColor: $r('app.color.accent'), onTap: () => this.nav('pages/Nodes')
          })
          NavTile({
            kind: 'sub', label: '订阅', hint: this.subHint(),
            iconColor: $r('app.color.proto_vmess'), onTap: () => this.nav('pages/Subscriptions')
          })
          NavTile({
            kind: 'routes', label: '分流', hint: this.routingHint(),
            iconColor: $r('app.color.proto_trojan'), onTap: () => this.nav('pages/RoutingRules')
          })
        }.width('100%')

        Row({ space: Space.sm }) {
          NavTile({
            kind: 'logs', label: '日志', hint: '运行记录',
            iconColor: $r('app.color.proto_ss'), onTap: () => this.nav('pages/Logs')
          })
          NavTile({
            kind: 'backup', label: '备份', hint: '加密导出',
            iconColor: $r('app.color.accent'), onTap: () => this.nav('pages/Backup')
          })
          NavTile({
            kind: 'settings', label: '设置', hint: '更多',
            iconColor: $r('app.color.text_secondary'), onTap: () => this.nav('pages/Settings')
          })
        }.width('100%')
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
      Column({ space: Space.md }) {
        Text('连接前请先了解')
          .fontSize(FontSize.titleLg)
          .lineHeight(LineHeight.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

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
        .borderRadius(Radius.pill).lineHeight(LineHeight.caption)
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
