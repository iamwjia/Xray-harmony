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
    NodeProbe.probe(node).then((r: ProbeResult) => {
      if (r.ok) {
        this.setNotice(`「${node.name}」可达：TCP 握手 ${r.ms} ms`, 0);
      } else {
        this.setNotice(`「${node.name}」不可达：${r.error}`, 2);
      }
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`测试失败：${m}`, 2);
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

  private pick(id: string): void {
    if (this.cfg.selectNode(id)) {
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
      Text('管理订阅')
        .height(Height.hit)
        .width('100%')
        .fontSize(FontSize.bodySm)
        .fontColor($r('app.color.accent'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
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
    Text(label)
      .height(Height.hit)
      .padding({ left: Space.lg, right: Space.lg })
      .fontSize(FontSize.bodySm)
      .fontColor(active ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
      .backgroundColor(active ? $r('app.color.accent') : $r('app.color.bg_chip'))
      .borderRadius(Radius.pill)
      .textAlign(TextAlign.Center)
      .accessibilityText(active ? `${label}，当前筛选` : label)
      .onClick(() => {
        action();
      }).lineHeight(LineHeight.bodySm)
  }

  @Builder
  emptyState() {
    Column({ space: Space.sm }) {
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
          .height(Height.hit)
          .padding({ left: Space.lg, right: Space.lg })
          .fontSize(FontSize.bodySm)
          .backgroundColor($r('app.color.bg_chip'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(Radius.pill)
          .onClick(() => {
            this.groupFilter = '';
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
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
        List({ space: Space.sm }) {
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
                canMoveUp: this.canMove(item.id, -1),
                canMoveDown: this.canMove(item.id, 1),
                onPick: (id: string) => this.pick(id),
                onEdit: (id: string) => this.openEdit(id),
                onMove: (id: string, delta: number) => this.doMove(id, delta),
                onProbe: (id: string) => this.probeNode(id),
                onDelete: (id: string) => this.confirmDeleteById(id)
              })
            }
          }, (item: XrayNode) => `${item.id}-${item.name}-${item.group}-${item.protocol}-${item.address}-${item.port}-${item.id === this.selectedId}-${this.cfgRev}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_canvas'))
  }
}
