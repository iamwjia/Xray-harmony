import { router } from '@kit.ArkUI';
import { XrayNode } from '../model/AppConfig';
import { ConfigService } from '../service/ConfigService';
import { ShareLinkParser } from '../service/ShareLinkParser';
import { Logger } from '../platform/Logger';
import { NodeEditParams } from './NodeEdit';
import { SubscriptionImportResult, SubscriptionService } from '../service/SubscriptionService';
import { NodeRow } from '../components/NodeRow';
import { PageHeader } from '../components/PageHeader';
import { NodeProbe, ProbeResult } from '../service/NodeProbe';
import { Glyph } from '../components/Glyph';
import { ShareLinkBuilder } from '../service/ShareLinkBuilder';
import { SecretStore } from '../platform/SecretStore';
import { pasteboard } from '@kit.BasicServicesKit';
import { EventLog } from '../service/EventLog';
import { FontSize, LineHeight, Space, Height, Radius, IconSize } from '../common/Token';

/**
 * pages/Nodes.ets — 节点列表（本地假数据 + 选中切换）
 *
 * 结构约束：只读写 L-A 域模型（ConfigService），**不生成内核配置**；
 * 选中节点 = 改 selectedNodeId，不触发连接（连接由首页开关负责）。
 */
@Entry
@Component
struct Nodes {
  /**
   * 配置版本号：ConfigService 每次改变节点集合/字段都会 +1。
   * 用它驱动 reload()——就地修改的数组赋回 @State 不会触发重渲染，
   * 靠 onPageShow 的时序也不可靠（实测：日志已保存成功、列表仍是旧值）。
   * 注意：`@Watch` 必须挂在 @StorageLink 上才会响应外部写入。
   */
  @StorageLink('cfgRev') @Watch('onRevChange') cfgRev: number = 0;
  @State nodes: XrayNode[] = [];
  @State selectedId: string = '';
  @State groups: string[] = [];
  /** 空串 = 全部；分组筛选只影响展示 */
  @State groupFilter: string = '';
  /** 导入面板：默认收起，点「+」才展开（避免常驻两个输入框） */
  @State showImport: boolean = false;
  @State importInput: string = '';
  @State busy: boolean = false;
  @State importMsg: string = '';
  /**
   * 提示级别由**结果字段**给出（0 信息 / 1 警告 / 2 错误），不靠文案子串匹配。
   * 曾经按 `indexOf('失败')` 判色：一条"新增 3 条，失败 1 条"的部分成功整行变红，
   * 而"已存在 2 条"这种正常结果又被判成警告——颜色跟着措辞漂，等于 UI 在说谎。
   */
  @State importLevel: number = 0;

  private cfg: ConfigService = ConfigService.getInstance();

  /** 用于动作执行后收起已露出的行内操作 */
  private listScroller: Scroller = new Scroller();
  /** 最近一次测连通：id + 文案 + 级别；只显示在被测的那一行上 */
  @State probeResultId: string = '';
  @State probeResultText: string = '';
  @State probeResultLevel: number = 0;
  /** 正在拖的节点 id 与累计位移（vp）；松手时换算成“移动几行” */
  private dragId: string = '';
  private dragOffset: number = 0;
  /** 一行的高度：节点行 minHeight 64 + 行间距 8 */
  private static readonly ROW_STEP: number = 72;
  /** 下拉刷新：重新读盘（另一个入口导入了数据、或外部改了订阅时用） */
  @State refreshing: boolean = false;
  /**
   * 动作执行后收起左滑：当前 API 版本的 Scroller 没有 closeAllSwipeActions，
   * 只能让行重建一次（key 里带上这个版本号），重建后滑开状态自然复位。
   */
  @State swipeRev: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  /** 从编辑页返回时兜底重取：@Watch 在某些时序下不触发，双保险且幂等 */
  onPageShow(): void {
    this.reload();
  }

  private currentSelectedId(): string {
    const cur: XrayNode | null = this.cfg.getSelectedNode();
    return cur === null ? '' : cur.id;
  }

  /** 配置变更回调：重新取数据（必须复制，否则引用相同不触发重渲染） */
  onRevChange(): void {
    this.reload();
  }

  private reload(): void {
    this.nodes = this.cfg.getNodes().slice();
    this.selectedId = this.currentSelectedId();
    this.groups = this.cfg.getGroups();
    if (this.groupFilter.length > 0 && this.groups.indexOf(this.groupFilter) < 0) {
      // 分组被删空（用户把该组最后一个节点改了组/删了）→ 自动回到"全部"，避免列表空白无解释
      this.groupFilter = '';
    }
  }

  /** 分组筛选后的可见列表；筛选状态只影响展示，不改变存储顺序 */
  private visibleNodes(): XrayNode[] {
    if (this.groupFilter.length === 0) {
      return this.nodes;
    }
    const out: XrayNode[] = [];
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].group === this.groupFilter) {
        out.push(this.nodes[i]);
      }
    }
    return out;
  }

  private openEdit(id: string): void {
    const params: NodeEditParams = new NodeEditParams();
    params.nodeId = id;
    router.pushUrl({ url: 'pages/NodeEdit', params: params }).catch((e: Error) => {
      Logger.error(`nav NodeEdit failed: ${e.message}`);
    });
  }

  /** 该节点能否按 delta 移动（首行不能上移、末行不能下移）——菜单项据此置灰 */
  private canMove(id: string, delta: number): boolean {
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === id) {
        const target: number = i + delta;
        return target >= 0 && target < this.nodes.length;
      }
    }
    return false;
  }

  /**
   * 测一个节点的 TCP 可达性。
   * 结果用提示条展示，不改动列表排序也不改选中态——这是一个"看一眼"的动作。
   */
  private probeNode(id: string): void {
    let target: XrayNode | null = null;
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === id) {
        target = this.nodes[i];
        break;
      }
    }
    if (target === null) {
      return;
    }
    const node: XrayNode = target;
    this.setNotice(`正在测「${node.name}」…`, 0);
    this.probeResultId = node.id;
    this.probeResultText = '测试中…';
    this.probeResultLevel = 0;
    NodeProbe.probe(node).then((r: ProbeResult) => {
      if (r.ok) {
        this.setNotice(`「${node.name}」可达：TCP 握手 ${r.ms} ms`, 0);
        EventLog.push(0, `测连通「${node.name}」：${r.ms} ms`);
        this.probeResultText = `${r.ms} ms`;
        this.probeResultLevel = 0;
      } else {
        this.setNotice(`「${node.name}」不可达：${r.error}`, 2);
        EventLog.push(2, `测连通「${node.name}」失败：${r.error}`);
        this.probeResultText = '失败';
        this.probeResultLevel = 2;
      }
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`测试失败：${m}`, 2);
      this.probeResultText = '失败';
      this.probeResultLevel = 2;
    });
  }

  private doMove(id: string, delta: number): void {    if (this.cfg.moveNode(id, delta)) {
      this.reload();
      return;
    }
    // 失败必须可见：原来这里静默返回，用户点了「上移」没反应会以为是卡了
    this.setNotice(delta < 0 ? '已在列表顶部' : '已在列表底部', 1);
  }

  /**
   * 订阅导入。
   * 结果话术刻意区分三种情况，避免"只导入了一部分却像全部成功"：
   * 全失败 / 部分成功 / 全部成功。
   */
  private doImportSubscription(url: string): void {
    this.busy = true;
    this.setNotice('正在拉取订阅…', 0);
    SubscriptionService.importFromUrl(url, '').then((r: SubscriptionImportResult) => {
      this.busy = false;
      this.reload();
      if (r.total === 0) {
        this.setNotice(`订阅导入失败：${r.error.length > 0 ? r.error : '里面没有可识别的节点'}`, 2);
        return;
      }
      let msg: string = `订阅：解析 ${r.total} 条，新增 ${r.added} 条`;
      if (r.skipped > 0) {
        // 重新导入同一份订阅时全是"已存在"，把它说成失败会误导用户
        msg += `，已存在 ${r.skipped} 条`;
      }
      if (r.failed > 0) {
        msg += `，失败 ${r.failed} 条`;
      }
      if (r.error.length > 0) {
        msg += `（首条错误：${r.error}）`;
      }
      // 部分失败才是警告；"新增 + 已存在"是正常结果，不该变色
      this.setNotice(msg, r.failed > 0 ? 1 : 0);
      this.importInput = '';
      this.showImport = false;
    }).catch((e: Object) => {
      this.busy = false;
      const msg: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`订阅导入失败：${msg}`, 2);
    });
  }

  private setNotice(msg: string, level: number): void {
    this.importMsg = msg;
    this.importLevel = level;
  }

  private pick(id: string): void {    if (this.cfg.selectNode(id)) {
      this.selectedId = id;
    } else {
      Logger.warn(`pick node failed: ${id}`);
    }
  }

  /** 删除前二次确认：删除不可恢复，不做"点了就没了" */
  private confirmDeleteById(id: string): void {
    let target: XrayNode | null = null;
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === id) {
        target = this.nodes[i];
        break;
      }
    }
    if (target === null) {
      return;
    }
    const item: XrayNode = target;
    AlertDialog.show({
      title: '删除节点',
      message: `将删除「${item.name}」及其保存的凭据，该操作不可恢复。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.doDelete(item.id);
        }
      }
    });
  }

  private doDelete(id: string): void {
    this.cfg.removeNode(id).then((ok: boolean) => {
      this.reload();
      this.setNotice(ok ? '已删除节点（凭据一并清除）' : '删除失败，详见日志', ok ? 0 : 2);
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`删除失败：${msg}`, 2);
      Logger.error(`removeNode failed: ${msg}`);
    });
  }
  /**
   * 统一导入入口：按前缀自动判断类型，用户不需要先想"这是链接还是订阅"。
   * 判断规则刻意只认协议头，不做模糊猜测——猜错会让用户拿着一条链接去请求网络。
   */
  private doSmartImport(): void {
    const input: string = this.importInput.trim();
    if (input.length === 0) {
      this.setNotice('请先粘贴链接或订阅地址', 1);
      return;
    }
    const lower: string = input.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      this.doImportSubscription(input);
      return;
    }
    if (lower.startsWith('vless://') || lower.startsWith('vmess://') ||
      lower.startsWith('trojan://') || lower.startsWith('ss://')) {
      this.doImportLink(input);
      return;
    }
    this.setNotice('无法识别：应以 vless:// vmess:// trojan:// ss:// 或 http(s):// 开头', 1);
  }

  /** 导入分享链接：解析成功后写入安全存储 + 节点表，并选中 */
  private doImportLink(link: string): void {
    let node: XrayNode;
    try {
      node = ShareLinkParser.parse(link);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`导入失败：${msg}`, 2);
      Logger.warn(`import failed: ${msg}`);
      return;
    }
    this.busy = true;
    // 凭据先落 Asset Store，节点表只存别名（新增数据不再有明文凭据）
    this.cfg.addNodeSecure(node).then((added: boolean) => {
      this.busy = false;
      this.cfg.selectNode(node.id);
      this.reload();
      // 「节点已存在，已切换选中」是正常结果（重导入同一链接），不用警告色
      this.setNotice(added
        ? `已导入：${node.name}（${node.protocol}）`
        : `节点已存在，已切换选中：${node.name}`, 0);
      this.importInput = '';
      this.showImport = false;
      Logger.info(`import ok: ${node.protocol} @ ${node.address}:${node.port}`);
    }).catch((e: Object) => {
      this.busy = false;
      const msg: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`导入失败：凭据写入安全存储失败（${msg}）`, 2);
      Logger.error(`import failed at secret store: ${msg}`);
    });
  }

  /** 分色只看级别，不看文案 —— 颜色跟着措辞走，迟早会说谎 */
  private importColor(): Resource {
    if (this.importLevel === 2) {
      return $r('app.color.danger');
    }
    if (this.importLevel === 1) {
      return $r('app.color.warning');
    }
    return $r('app.color.accent');
  }

  @Builder
  header() {
    PageHeader({
      title: '节点列表',
      countText: `${this.visibleNodes().length} 个`,
      actionGlyph: this.showImport ? '\u00d7' : '+',
      actionA11y: this.showImport ? '收起导入面板' : '导入节点或订阅',
      onBack: () => {
        router.back();
      },
      onAction: () => {
        this.showImport = !this.showImport;
        if (!this.showImport) {
          this.importMsg = '';
          this.importLevel = 0;
        }
      }
    })
  }

  @Builder
  importPanel() {
    Column({ space: Space.md }) {
      TextInput({
        placeholder: '粘贴分享链接（vless://…）或订阅地址（https://…）',
        text: this.importInput
      })
        .height(Height.input)
        .fontSize(FontSize.body)
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.bg_surface'))
        .borderRadius(Radius.panel)
        .onChange((v: string) => {
          this.importInput = v;
        })
        // 回车直接导入：手机上键盘会遮住下方「导入」按钮，
        // 抬手去点它是桌面习惯（实测下半屏被键盘占满）。
        .enterKeyType(EnterKeyType.Go)
        .onSubmit(() => {
          this.doSmartImport();
        })

      Text('vless / vmess / trojan / ss 走单条导入；http(s) 走订阅导入')
        .fontSize(FontSize.caption)
        .lineHeight(LineHeight.caption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      Button(this.busy ? '处理中…' : '导入')
        .width('100%')
        .height(Height.hit)
        .fontSize(FontSize.bodySm)
        .backgroundColor($r('app.color.accent'))
        .fontColor($r('app.color.text_on_accent'))
        .borderRadius(Radius.panel)
        .enabled(!this.busy)
        .onClick(() => this.doSmartImport())

      // 导入完就能就地管理订阅，不必先退回设置页
      // 用 Button：手机上“看起来像文字”的东西就会被当成不可点
      Button('管理订阅', { type: ButtonType.Normal })
        .height(Height.hit)
        .width('100%')
        .fontSize(FontSize.bodySm)
        .fontColor($r('app.color.accent'))
        .backgroundColor(Color.Transparent)
        .accessibilityText('打开订阅管理')
        .onClick(() => {
          router.pushUrl({ url: 'pages/Subscriptions' }).catch((e: Error) => {
            this.setNotice(`打开订阅管理失败：${e.message}`, 2);
          });
        })
    }
    .width('100%')
    .padding(Space.md)
    .backgroundColor($r('app.color.bg_surface_alt'))
    .borderRadius(Radius.panel)
  }

  @Builder
  groupChips() {
    Scroll() {
      Row({ space: Space.sm }) {
        this.chip('全部', this.groupFilter.length === 0, () => {
          this.groupFilter = '';
        })
        ForEach(this.groups, (g: string) => {
          this.chip(g, this.groupFilter === g, () => {
            this.groupFilter = g;
          })
        }, (g: string) => g)
      }
      .padding({ left: Space.lg, right: Space.lg })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  chip(label: string, active: boolean, action: () => void) {
    // 用 Button 而不是 Text：Text 上没有按下反馈，手指点下去什么都不变——
    // 那是鼠标想象（hover 代替了反馈），碰屏上会像“没点着”。
    Button(label, { type: ButtonType.Capsule })
      .height(Height.hit)
      .padding({ left: Space.lg, right: Space.lg })
      .fontSize(FontSize.bodySm)
      .fontColor(active ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
      .backgroundColor(active ? $r('app.color.accent') : $r('app.color.bg_chip'))
      .accessibilityText(active ? `${label}，当前筛选` : label)
      .onClick(() => {
        action();
      })
  }

  @Builder
  emptyState() {
    Column({ space: Space.sm }) {
      // 空态不是"没东西"，是"该怎么开始"：图标 + 一句指路，比纯文字少一次犹豫
      Glyph({ kind: 'nodes', color: $r('app.color.text_tertiary'), box: 40 })
      Text(this.groupFilter.length > 0 ? '该分组下没有节点' : '还没有节点')
        .fontSize(FontSize.titleMd)
        .lineHeight(LineHeight.titleMd)
        .fontColor($r('app.color.text_secondary'))
      Text(this.groupFilter.length > 0
        ? `「${this.groupFilter}」里的节点都被移走了`
        : '点右上角「+」，粘贴分享链接或订阅地址')
        .fontSize(FontSize.bodySm)
        .lineHeight(LineHeight.bodySm)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
      if (this.groupFilter.length > 0) {
        Button('查看全部')
          .backgroundColor($r('app.color.bg_chip'))
          .fontColor($r('app.color.text_primary'))
          .height(Height.hit)
          .padding({ left: Space.lg, right: Space.lg })
          .fontSize(FontSize.bodySm)
          .backgroundColor($r('app.color.bg_chip'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.groupFilter = '';
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 长按复制分享链接。凭据从安全存储临时取出，只在内存里拼进链接，不写日志、不落盘。
   * 复制完的提示必须是警告级：剪贴板是其他应用能读的地方，链里含凭据。
   */
  private copyShareLink(id: string): void {
    Logger.info(`copyShareLink: id=${id}`);
    const nodes: XrayNode[] = this.cfg.getNodes();
    let target: XrayNode | null = null;
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].id === id) {
        target = nodes[i];
        break;
      }
    }
    if (target === null) {
      this.setNotice('节点已不存在，请下拉刷新后再试', 2);
      return;
    }
    const node: XrayNode = target;
    const alias: string = node.credentialRef.startsWith('node:')
      ? node.credentialRef
      : SecretStore.aliasForNode(node.id);
    SecretStore.get(alias).then((secret: string | null) => {
      if (secret === null || secret.length === 0) {
        this.setNotice('这条节点没有可用凭据，无法生成分享链接', 2);
        return;
      }
      const link: string = ShareLinkBuilder.build(node, secret);
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, link);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.setNotice('已复制分享链接（含凭据，等同于密码，别发到公开的地方）', 1);
      }).catch((e: Error) => {
        this.setNotice(`复制失败：${e.message}`, 2);
      });
    }).catch((e: Error) => {
      this.setNotice(`读取凭据失败：${e.message}`, 2);
    });
  }

  private onRowDragStart(id: string): void {
    this.dragId = id;
    this.dragOffset = 0;
  }

  private onRowDragUpdate(offsetY: number): void {
    this.dragOffset = offsetY;
  }

  private onRowDragEnd(id: string): void {
    const steps: number = Math.round(this.dragOffset / Nodes.ROW_STEP);
    this.dragId = '';
    this.dragOffset = 0;
    if (steps === 0) {
      return;
    }
    // ConfigService 只提供"移一位"，多位就循环；先按位移方向逐步挪，避免一次算错位置
    const dir: number = steps > 0 ? 1 : -1;
    let applied: number = 0;
    for (let i = 0; i < Math.abs(steps); i++) {
      if (!this.cfg.moveNode(id, dir)) {
        break;
      }
      applied++;
    }
    if (applied > 0) {
      // 排序是用户亲手做的，必须给一句确认；否则他会怀疑到底是"系统动了"还是"自己拖错了"
      this.setNotice(`已${dir > 0 ? '下' : '上'}移 ${applied} 位`, 0);
    }
    this.reload();
  }

  private closeSwipe(): void {
    // 执行完动作就收起露出的操作，否则列表会留着一排开着的行。
    // 这一版 SDK 的 Scroller 没有 closeAllSwipeActions，只能靠重建行来复位滑动状态。
    this.swipeRev = this.swipeRev + 1;
  }

  /** 左滑露出（行右端）：测连通性 + 删除。实色块 + 白字，按动作类型分色，不按深浅区分 */
  @Builder
  rowEndActions(item: XrayNode) {
    Row() {
      Column({ space: 2 }) {
        Glyph({ kind: 'probe', color: $r('app.color.text_on_accent'), box: 20 })
        Text('测连通')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_on_accent'))
      }
      .width(84)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.action_probe'))
      .onClick(() => {
        this.closeSwipe();
        this.probeNode(item.id);
      })
      .accessibilityText(`测 ${item.name} 的连通性`)

      Column({ space: 2 }) {
        Glyph({ kind: 'trash', color: $r('app.color.text_on_accent'), box: 20 })
        Text('删除')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_on_accent'))
      }
      .width(84)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.action_delete'))
      .onClick(() => {
        this.closeSwipe();
        this.confirmDeleteById(item.id);
      })
      .accessibilityText(`删除 ${item.name}`)
    }
    .height('100%')
  }

  /** 右滑露出（行左端）：编辑。紫色，与"测连通"的蓝、"删除"的红互不混淆 */
  @Builder
  rowStartActions(item: XrayNode) {
    Row() {
      Column({ space: 2 }) {
        Glyph({ kind: 'edit', color: $r('app.color.text_on_accent'), box: 20 })
        Text('编辑')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_on_accent'))
      }
      .width(84)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.action_edit'))
      .onClick(() => {
        this.closeSwipe();
        this.openEdit(item.id);
      })
      .accessibilityText(`编辑 ${item.name}`)

      // 复制分享链接：原来挂在"整行长按"上，但长按与拖拽抓手抢手势，
      // 实测按住抓手拖动会先触发长按。挪到右滑里，滑动手势与拖动不重叠。
      Column({ space: 2 }) {
        Glyph({ kind: 'copy', color: $r('app.color.text_on_accent'), box: 20 })
        Text('复制')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_on_accent'))
      }
      .width(84)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.action_probe'))
      .onClick(() => {
        this.closeSwipe();
        this.copyShareLink(item.id);
      })
      .accessibilityText(`复制 ${item.name} 的分享链接`)
    }
    .height('100%')
  }

  build() {
    Column({ space: 0 }) {
      this.header()

      if (this.showImport) {
        Column() {
          this.importPanel()
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.md })
      }

      if (this.importMsg.length > 0) {
        Text(this.importMsg)
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor(this.importColor())
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
          .accessibilityText(`导入结果：${this.importMsg}`)
      }

      // 分组筛选：只在真的有分组时出现，避免空界面上多一行无用控件
      if (this.groups.length > 0) {
        Column() {
          this.groupChips()
        }
        .width('100%')
        .padding({ bottom: Space.sm })
      }

      if (this.visibleNodes().length === 0) {
        this.emptyState()
      } else {
        // 下拉刷新：重新读一次持久化（另一个入口刚导入、或订阅刚在别的页面更新过）
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: Space.sm, scroller: this.listScroller }) {
          ForEach(this.visibleNodes(), (item: XrayNode) => {
            ListItem() {
              NodeRow({
                nodeId: item.id,
                name: item.name,
                protocol: item.protocol,
                address: item.address,
                port: item.port,
                group: item.group,
                selected: item.id === this.selectedId,
                onPick: (id: string) => this.pick(id),
                onEdit: (id: string) => this.openEdit(id),
                onHandleDragStart: (id: string) => this.onRowDragStart(id),
                onHandleDragMove: (offsetY: number) => this.onRowDragUpdate(offsetY),
                onHandleDragEnd: (id: string) => this.onRowDragEnd(id),
                onProbe: (id: string) => this.probeNode(id),
                onDelete: (id: string) => this.confirmDeleteById(id),
                onCopyLink: (id: string) => this.copyShareLink(id),
                probeText: item.id === this.probeResultId ? this.probeResultText : '',
                probeLevel: this.probeResultLevel
              })
            }
            // 行内左滑：右侧露出「测连通性 / 删除」，按危险程度配色 + 图标；
            // 右滑露出「编辑」。滑回去或执行任一动作即收起——操作始终属于这一行，
            // 不是抽屉式导航。
            .swipeAction({
              end: {
                builder: () => {
                  this.rowEndActions(item)
                }
              },
              start: {
                builder: () => {
                  this.rowStartActions(item)
                }
              }
            })
          }, (item: XrayNode) => `${item.id}-${item.name}-${item.group}-${item.protocol}-${item.address}-${item.port}-${item.id === this.selectedId}-${this.cfgRev}-${this.swipeRev}`)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
        .onRefreshing(() => {
          this.reload();
          // 留一点时间让指示器转完，否则手指一松就消失，用户会以为没刷新
          setTimeout(() => {
            this.refreshing = false;
          }, 400);
        })
      }

      // 单手可达：顶栏那个「+」在屏幕顶端右侧，单手拿手机时很难够到。
      // 底部再给一个同样入口（大命中区），两个入口指向同一个导入面板。
      Row() {
        Button(this.showImport ? '收起导入面板' : '＋ 导入节点 / 订阅地址')
          .width('100%')
          .height(Height.hit)
          .fontSize(FontSize.bodySm)
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.text_on_accent'))
          .onClick(() => {
            this.showImport = !this.showImport;
          })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.md })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_canvas'))
  }
}
