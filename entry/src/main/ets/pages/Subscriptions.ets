import { router } from '@kit.ArkUI';
import { PageHeader } from '../components/PageHeader';
import { Glyph } from '../components/Glyph';
import { EventLog } from '../service/EventLog';
import { FontSize, LineHeight, Space, Height, Radius, IconSize } from '../common/Token';
import { SubRecord, SubscriptionStore } from '../service/SubscriptionStore';
import { SubscriptionImportResult, SubscriptionService } from '../service/SubscriptionService';
import { ConfigService } from '../service/ConfigService';
import { Logger } from '../platform/Logger';

/** 操作菜单宽度（与 NodeRow 保持一致） */
const MENU_WIDTH: number = 180;

/**
 * pages/Subscriptions.ets — 订阅管理
 *
 * 与节点页共用同一套行模型：**整行 + 44 溢出菜单**，两个命中区是兄弟不嵌套。
 * 订阅行与节点行的差别只在操作项（更新 / 删除），所以没有另造一套行样式。
 *
 * 安全约束：
 *   1. 页面**不持有订阅 URL**，只持有 id 与别名；更新时由 service 内部取用一次；
 *   2. 删除订阅不删节点（见 SubscriptionService.remove 的说明），页面文案要说清。
 */
@Entry
@Component
struct Subscriptions {
  @State subs: SubRecord[] = [];
  @State busyId: string = '';
  @State msg: string = '';
  /** 0 信息 / 1 警告 / 2 错误：颜色由级别决定，不由文案决定 */
  @State msgLevel: number = 0;
  /** 过期订阅数；>0 时在顶部给一个「全部更新」入口 */
  @State staleCount: number = 0;
  /** 自动更新间隔（小时）：过期文案要用真实阈值，不能写死"7 天" */
  @State autoUpdateHours: number = 24;
  @State refreshingAll: boolean = false;
  /** 按下中的行 id（为空 = 没有按下）：手机上需要可见反馈 */
  @State pressedId: string = '';
  /** 添加订阅：输入面板是否展开 + 输入内容 + 进行中标记 */
  @State showAdd: boolean = false;
  @State addInput: string = '';
  @State addBusy: boolean = false;
  @State addMsg: string = '';
  /** 正在拖的订阅 id 与累计位移；松手换算成"移动几行" */
  private dragId: string = '';
  private dragOffset: number = 0;
  /** 一行高度：订阅行 minHeight 64 + 间距 8 */
  private static readonly ROW_STEP: number = 72;
  /** 动作执行后收起左滑（key 里带上它，重建即复位） */
  @State swipeRev: number = 0;

  aboutToAppear(): void {
    this.reload();
    this.checkAutoUpdate();
  }

  onPageShow(): void {
    this.reload();
    this.checkAutoUpdate();
  }

  /**
   * 进入页面时检查是否有超过间隔的订阅。
   *
   * 这里**只提示、不自动发请求**：订阅 URL 带 token，背底下联网是用户无法察觉的行为。
   * 真正的"自动"交给用户一次确认（点「全部更新」），而不是我们替他决定。
   */
  private checkAutoUpdate(): void {
    const cfg: ConfigService = ConfigService.getInstance();
    if (!cfg.getConfig().settings.autoUpdateSubs) {
      return;
    }
    const hours: number = cfg.getConfig().settings.autoUpdateHours;
    const limitMs: number = hours * 60 * 60 * 1000;
    const now: number = Date.now();
    // 分两类统计：从未更新 与 超过间隔。"从未更新"不能被说成"超过 N 小时未更新"——
    // 前者根本没有基准时间，写成后者会让用户以为它三天前更新过（实测就被这么误读过）。
    let neverUpdated: number = 0;
    let outdated: number = 0;
    for (let i = 0; i < this.subs.length; i++) {
      const t: number = this.subs[i].lastUpdated;
      if (t <= 0) {
        neverUpdated++;
      } else if ((now - t) > limitMs) {
        outdated++;
      }
    }
    const stale: number = neverUpdated + outdated;
    if (stale > 0 && this.busyId.length === 0) {
      const parts: string[] = [];
      if (outdated > 0) {
        parts.push(`${outdated} 个超过 ${Subscriptions.intervalText(hours)}未更新`);
      }
      if (neverUpdated > 0) {
        parts.push(`${neverUpdated} 个从未更新`);
      }
      this.setNotice(`有 ${parts.join('，')}`, 1);
      this.staleCount = stale;
      return;
    }
    this.staleCount = 0;
  }

  /** 串行更新全部过期订阅（串行：并发拉取容易被服务器限流） */
  private refreshStale(): void {
    if (this.refreshingAll) {
      return;
    }
    this.refreshingAll = true;
    const cfg: ConfigService = ConfigService.getInstance();
    const limitMs: number = cfg.getConfig().settings.autoUpdateHours * 60 * 60 * 1000;
    const now: number = Date.now();
    const targets: SubRecord[] = [];
    for (let i = 0; i < this.subs.length; i++) {
      const t: number = this.subs[i].lastUpdated;
      if (t <= 0 || (now - t) > limitMs) {
        targets.push(this.subs[i]);
      }
    }
    let done: number = 0;
    let failed: number = 0;
    const step = (idx: number): void => {
      if (idx >= targets.length) {
        this.refreshingAll = false;
        this.reload();
        this.staleCount = 0;
        this.setNotice(`已更新 ${done} 个订阅${failed > 0 ? `，${failed} 个失败` : ''}`, failed > 0 ? 1 : 0);
        return;
      }
      const rec: SubRecord = targets[idx];
      this.busyId = rec.id;
      SubscriptionService.refresh(rec.id).then((r: SubscriptionImportResult) => {
        if (r.total === 0) {
          failed++;
        } else {
          done++;
        }
        step(idx + 1);
      }).catch((e: Object) => {
        failed++;
        step(idx + 1);
      });
    };
    step(0);
  }

  private reload(): void {
    this.subs = SubscriptionService.listSubscriptions().slice();
    this.autoUpdateHours = ConfigService.getInstance().getConfig().settings.autoUpdateHours;
  }

  private setNotice(text: string, level: number): void {
    this.msg = text;
    this.msgLevel = level;
  }

  private noticeColor(): Resource {
    if (this.msgLevel === 2) {
      return $r('app.color.danger');
    }
    if (this.msgLevel === 1) {
      return $r('app.color.warning');
    }
    return $r('app.color.accent');
  }

  private updatedText(rec: SubRecord): string {
    if (rec.lastUpdated <= 0) {
      return '尚未更新';
    }
    const d = new Date(rec.lastUpdated);
    const mm: string = `${d.getMonth() + 1}`.padStart(2, '0');
    const dd: string = `${d.getDate()}`.padStart(2, '0');
    const hh: string = `${d.getHours()}`.padStart(2, '0');
    const mi: string = `${d.getMinutes()}`.padStart(2, '0');
    return `更新于 ${mm}-${dd} ${hh}:${mi}`;
  }

  /**
   * 订阅是会过期的：服务器改了端口、换了腾话，本地节点还是旧的。
   * 7 天是一个意味着“基本不再可信”的粗线，不是精确阈值：它只用来提醒去点更新，
   * 不会自动更新、也不会禁用节点——自动做事反而会让用户不知道发生了什么。
   */
  private isStale(rec: SubRecord): boolean {
    if (rec.lastUpdated <= 0) {
      return false;
    }
    const age: number = Date.now() - rec.lastUpdated;
    return age > 7 * 24 * 60 * 60 * 1000;
  }

  private doRefresh(rec: SubRecord): void {
    if (this.busyId.length > 0) {
      return;
    }
    this.busyId = rec.id;
    this.setNotice(`正在更新「${rec.name}」…`, 0);
    SubscriptionService.refresh(rec.id).then((r: SubscriptionImportResult) => {
      this.busyId = '';
      this.reload();
      if (r.total === 0) {
        this.setNotice(`更新失败：${r.error.length > 0 ? r.error : '订阅里没有可识别的节点'}`, 2);
      EventLog.push(2, `订阅「${rec.name}」更新失败`);
        return;
      }
      let text: string = `「${rec.name}」解析 ${r.total} 条，新增 ${r.added} 条`;
      if (r.skipped > 0) {
        text += `，已存在 ${r.skipped} 条`;
      }
      if (r.failed > 0) {
        text += `，失败 ${r.failed} 条`;
      }
      // 部分失败才是警告；"新增 + 已存在"是正常结果
      this.setNotice(text, r.failed > 0 ? 1 : 0);
      EventLog.push(r.failed > 0 ? 1 : 0, `订阅「${rec.name}」更新：新增 ${r.added} 个节点`);
    }).catch((e: Object) => {
      this.busyId = '';
      const m: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`更新失败：${m}`, 2);
      EventLog.push(2, `订阅「${rec.name}」更新失败`);
      Logger.error(`subscription refresh failed: ${m}`);
    });
  }

  /** 删除前二次确认；文案要写清"节点不会被删"，否则用户不敢点 */
  private confirmRemove(rec: SubRecord): void {
    AlertDialog.show({
      title: '删除订阅',
      message: `将删除订阅「${rec.name}」及其保存的地址。已导入的 ${rec.nodeCount} 个节点不会被删除。`,
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
          this.doRemove(rec);
        }
      }
    });
  }

  private doRemove(rec: SubRecord): void {
    SubscriptionService.remove(rec.id).then((ok: boolean) => {
      this.reload();
      this.setNotice(ok ? `已删除订阅「${rec.name}」（节点保留）` : '删除失败，详见日志', ok ? 0 : 2);
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`删除失败：${m}`, 2);
      Logger.error(`subscription remove failed: ${m}`);
    });
  }

  @Builder
  overflowMenu(rec: SubRecord) {
    Column() {
      this.menuItem('立即更新', false, this.busyId !== rec.id, () => this.doRefresh(rec))
      Divider().color($r('app.color.border_subtle'))
      this.menuItem('删除', true, true, () => this.confirmRemove(rec))
    }
    .width(MENU_WIDTH)
    .padding({ top: Space.xs, bottom: Space.xs })
    .backgroundColor($r('app.color.bg_surface'))
    .borderRadius(Radius.panel)
    .border({ width: 1, color: $r('app.color.border_subtle') })
  }

  @Builder
  menuItem(label: string, dangerous: boolean, enabled: boolean, action: () => void) {
    Text(label)
      .width(MENU_WIDTH)
      .height(Height.hit)
      .padding({ left: Space.lg, right: Space.lg })
      // 菜单项比正文大一档：弹层里只有几个词，13/14 看着偏小且难点
      .fontSize(FontSize.bodyLg)
      .lineHeight(LineHeight.bodyLg)
      .fontColor(!enabled
        ? $r('app.color.text_tertiary')
        : (dangerous ? $r('app.color.danger') : $r('app.color.text_primary')))
      .textAlign(TextAlign.Start)
      .maxLines(1)
      .enabled(enabled)
      .accessibilityText(enabled ? label : `${label}（不可用）`)
      .onClick(() => {
        if (enabled) {
          action();
        }
      })
  }

  @Builder
  subRow(rec: SubRecord) {
    Row() {
      // 更新中：用文字态表示"正在动"，不额外加转圈，避免行高抖动
      Row()
        .width(3)
        .height(40)
        .borderRadius(1.5)
        .margin({ right: 9 })
        .backgroundColor(this.busyId === rec.id ? $r('app.color.accent') : Color.Transparent)

      Column({ space: Space.xxs }) {
        Text(rec.name)
          .fontSize(FontSize.bodyLg)
          .lineHeight(LineHeight.bodyLg)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .accessibilityLevel('no')

        Row({ space: Space.xs }) {
          Text(this.busyId === rec.id ? '更新中…' : `上次导入 ${rec.nodeCount} 个`)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .accessibilityLevel('no')
          Text('\u00b7')
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .accessibilityLevel('no')
          Text(this.isStale(rec)
            ? `超过${Subscriptions.intervalText(this.autoUpdateHours)}未更新`
            : this.updatedText(rec))
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor(this.isStale(rec) ? $r('app.color.warning') : $r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .accessibilityLevel('no')
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 与节点行一致：点抓手 = 操作选项，按住拖动 = 排序
      Column() {
        Text('\u2261')
          .fontSize(IconSize.md)
          .fontColor(this.dragId === rec.id ? $r('app.color.accent') : $r('app.color.text_secondary'))
          .lineHeight(LineHeight.bodyLg)
          .accessibilityLevel('no')
      }
      .width(40)
      .height(Height.hit)
      .justifyContent(FlexAlign.Center)
      .margin({ left: Space.xs })
      .bindMenu(this.overflowMenu(rec))
      .priorityGesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 4 })
          .onActionStart(() => {
            this.dragId = rec.id;
            this.dragOffset = 0;
          })
          .onActionUpdate((e: GestureEvent) => {
            this.dragOffset = e.offsetY;
          })
          .onActionEnd(() => {
            this.applyDrag(rec.id);
          })
          .onActionCancel(() => {
            this.dragId = '';
            this.dragOffset = 0;
          })
      )
      .accessibilityText('订阅操作与排序')
    }
    .width('100%')
    .constraintSize({ minHeight: Height.row })
    .padding({ left: 0, right: Space.md, top: Space.sm, bottom: Space.sm })
    .backgroundColor(this.pressedId === rec.id ? $r('app.color.bg_chip') : $r('app.color.bg_surface'))
    .borderRadius(Radius.card)
    .border({ width: 1, color: $r('app.color.border_subtle') })
    // 整行没有"选中"语义，只有操作；不挂 onClick（避免假命中区），
    // 但按下时给一个底色变化：否则手指按下去什么都不变，像没点着
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressedId = rec.id;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedId = '';
      }
    })
    .accessibilityLevel('yes')
    .accessibilityText(`${rec.name}，${rec.nodeCount} 个节点，` +
      `${this.isStale(rec) ? '超过 7 天未更新' : this.updatedText(rec)}`)
  }

  @Builder
  emptyState() {
    Column({ space: Space.sm }) {
      Glyph({ kind: 'sub', color: $r('app.color.text_tertiary'), box: 40 })
      Text('还没有订阅')
        .fontSize(FontSize.titleMd)
        .lineHeight(LineHeight.titleMd)
        .fontColor($r('app.color.text_secondary'))
      Text('点击下方「＋ 添加订阅地址」粘贴 http(s) 订阅地址即可')
        .fontSize(FontSize.bodySm)
        .lineHeight(LineHeight.bodySm)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: Space.xl, right: Space.xl })
  }

  /** 地址是否"看起来能加"：只做前缀校验，真正的合法性由服务端/解析器判 */
  private canAddSub(): boolean {
    const v: string = this.addInput.trim();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  /** 添加订阅：与节点页导入走同一个服务方法，避免两套解析逻辑 */
  private doAddSubscription(): void {
    const url: string = this.addInput.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.addMsg = '请粘贴 http(s) 开头的订阅地址';
      return;
    }
    if (this.addBusy) {
      return;
    }
    this.addBusy = true;
    this.addMsg = '正在拉取…';
    SubscriptionService.importFromUrl(url, '').then((r: SubscriptionImportResult) => {
      this.addBusy = false;
      this.reload();
      if (r.total === 0) {
        this.addMsg = `失败：${r.error.length > 0 ? r.error : '里面没有可识别的节点'}`;
        EventLog.push(2, '订阅添加失败');
        return;
      }
      this.addMsg = `已添加：解析 ${r.total} 条，新增 ${r.added} 条`;
      this.setNotice(this.addMsg, r.failed > 0 ? 1 : 0);
      EventLog.push(r.failed > 0 ? 1 : 0, `订阅已添加：新增 ${r.added} 个节点`);
      this.addInput = '';
      this.showAdd = false;
    }).catch((e: Object) => {
      this.addBusy = false;
      const m: string = e instanceof Error ? e.message : String(e);
      this.addMsg = `失败：${m}`;
    });
  }

  private applyDrag(id: string): void {
    const steps: number = Math.round(this.dragOffset / Subscriptions.ROW_STEP);
    this.dragId = '';
    this.dragOffset = 0;
    if (steps === 0) {
      return;
    }
    const dir: number = steps > 0 ? 1 : -1;
    let applied: number = 0;
    for (let i = 0; i < Math.abs(steps); i++) {
      if (!SubscriptionStore.move(id, dir)) {
        break;
      }
      applied++;
    }
    if (applied > 0) {
      this.reload();
      this.setNotice(`已${dir > 0 ? '下' : '上'}移 ${applied} 位`, 0);
    }
  }

  /** 168 小时这种数字要翻成人话：7 天 / 每周，不要直接把小时数印在界面上 */
  private static intervalText(hours: number): string {
    if (hours >= 168) {
      return ' 1 周';
    }
    if (hours >= 48) {
      return ` ${Math.round(hours / 24)} 天`;
    }
    return ` ${hours} 小时`;
  }

  private closeSwipe(): void {
    this.swipeRev = this.swipeRev + 1;
  }

  /** 左滑露出（行右端）：立即更新 + 删除订阅（不删已导入的节点） */
  @Builder
  rowEndActions(rec: SubRecord) {
    Row() {
      Column({ space: 2 }) {
        Glyph({ kind: 'sub', color: $r('app.color.text_on_accent'), box: 20 })
        Text('更新')
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
        this.doRefresh(rec);
      })
      .accessibilityText(`立即更新 ${rec.name}`)

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
        this.confirmRemove(rec);
      })
      .accessibilityText(`删除订阅 ${rec.name}`)
    }
    .height('100%')
  }

  build() {
    Column({ space: 0 }) {
      Column() {
        PageHeader({
          title: '订阅管理',
          countText: `${this.subs.length} 个`,
          onBack: () => {
            router.back();
          }
        })
      }
      .width('100%')

      if (this.staleCount > 0) {
        Row({ space: Space.sm }) {
          Text(this.msg.length > 0 ? this.msg : `有 ${this.staleCount} 个订阅需更新`)
            .fontSize(FontSize.bodySm)
            .lineHeight(LineHeight.bodySm)
            .fontColor($r('app.color.warning'))
            .layoutWeight(1)
            .maxLines(2)
          Button(this.refreshingAll ? '更新中…' : '全部更新')
            .height(Height.hit)
            .fontSize(FontSize.bodySm)
            .backgroundColor($r('app.color.warning_subtle'))
            .fontColor(!this.refreshingAll ? $r('app.color.warning') : $r('app.color.text_tertiary'))
            .enabled(!this.refreshingAll)
            .onClick(() => this.refreshStale())
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
      }

      if (this.msg.length > 0 && this.staleCount === 0) {
        Text(this.msg)
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor(this.noticeColor())
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
          .accessibilityText(`订阅结果：${this.msg}`)
      }

      if (this.subs.length === 0) {
        this.emptyState()
      } else {
        // 下拉刷新 = 更新全部过期订阅（与顶部「全部更新」同一件事，只是手势更顺）
        Refresh({ refreshing: $$this.refreshingAll }) {
          List({ space: Space.sm }) {
            ForEach(this.subs, (rec: SubRecord) => {
              ListItem() {
                this.subRow(rec)
              }
              // 与节点行同一套手势：左滑露出「立即更新 / 删除」，右滑收回
              .swipeAction({
                end: {
                  builder: () => {
                    this.rowEndActions(rec)
                  }
                }
              })
            }, (rec: SubRecord) => `${rec.id}-${rec.name}-${rec.nodeCount}-${rec.lastUpdated}-${this.busyId}-${this.swipeRev}`)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
        .onRefreshing(() => {
          Logger.info('subscriptions pull-refresh');
          this.refreshStale();
        })
      }

      // 与节点页同款：顶部没有任何入口时，这个页面就没有"添加"的落点，
      // 用户只能回节点页粘贴订阅地址——入口一致才不需要记路径。
      if (this.showAdd) {
        Column({ space: Space.sm }) {
          TextInput({ placeholder: '粘贴 http(s) 订阅地址', text: $$this.addInput })
            .fontSize(FontSize.bodySm)
            .height(Height.input)
            .onSubmit(() => {
              this.doAddSubscription();
            })
            .onChange((v: string) => {
              this.addInput = v;
            })
          Row({ space: Space.sm }) {
            // 两个按钮等宽：一宽一窄会让人以为"取消"是附属控件
            Button(this.addBusy ? '添加中…' : '添加')
              .layoutWeight(1)
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor(!this.addBusy && this.canAddSub() ? $r('app.color.accent') : $r('app.color.bg_chip'))
              .fontColor(!this.addBusy && this.canAddSub()
                ? $r('app.color.text_on_accent') : $r('app.color.text_tertiary'))
              // 没粘贴合法地址前不给点：点了只会弹一句"请粘贴 http(s) …"
              .enabled(!this.addBusy && this.canAddSub())
              .onClick(() => this.doAddSubscription())
            Button('取消')
              .layoutWeight(1)
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor($r('app.color.bg_chip'))
              .fontColor($r('app.color.text_primary'))
              .onClick(() => {
                this.showAdd = false;
                this.addMsg = '';
              })
          }
          .width('100%')
          if (this.addMsg.length > 0) {
            Text(this.addMsg)
              .fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption)
              .fontColor(this.addBusy ? $r('app.color.accent') : $r('app.color.text_secondary'))
              .width('100%')
          }
        }
        .width('100%')
        .padding(Space.md)
        .backgroundColor($r('app.color.bg_surface_alt'))
        .borderRadius(Radius.panel)
        .margin({ left: Space.lg, right: Space.lg, bottom: Space.sm })
      }

      Row() {
        Button(this.showAdd ? '收起' : '＋ 添加')
          .accessibilityText('添加订阅地址')
          .width('100%')
          .height(Height.hit)
          .fontSize(FontSize.bodySm)
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.text_on_accent'))
          .onClick(() => {
            this.showAdd = !this.showAdd;
            if (!this.showAdd) {
              this.addMsg = '';
            }
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
