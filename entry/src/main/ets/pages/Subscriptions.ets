import { router } from '@kit.ArkUI';
import { PageHeader } from '../components/PageHeader';
import { FontSize, LineHeight, Space, Height, Radius, IconSize } from '../common/Token';
import { SubRecord } from '../service/SubscriptionStore';
import { SubscriptionImportResult, SubscriptionService } from '../service/SubscriptionService';
import { Logger } from '../platform/Logger';

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

  aboutToAppear(): void {
    this.reload();
  }

  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    this.subs = SubscriptionService.listSubscriptions().slice();
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
    }).catch((e: Object) => {
      this.busyId = '';
      const m: string = e instanceof Error ? e.message : String(e);
      this.setNotice(`更新失败：${m}`, 2);
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
    .constraintSize({ minWidth: 160 })
    .padding({ top: Space.xs, bottom: Space.xs })
    .backgroundColor($r('app.color.bg_surface'))
    .borderRadius(Radius.panel)
    .border({ width: 1, color: $r('app.color.border_subtle') })
  }

  @Builder
  menuItem(label: string, dangerous: boolean, enabled: boolean, action: () => void) {
    Text(label)
      .width('100%')
      .height(Height.hit)
      .padding({ left: Space.lg, right: Space.lg })
      .fontSize(FontSize.bodySm)
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
          Text(this.busyId === rec.id ? '更新中…' : `${rec.nodeCount} 个节点`)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .accessibilityLevel('no')
          Text('\u00b7')
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .accessibilityLevel('no')
          Text(this.updatedText(rec))
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .accessibilityLevel('no')
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Circle }) {
        Text('\u22ef')
          .fontSize(IconSize.md)
          .fontColor($r('app.color.text_secondary'))
          .accessibilityLevel('no')
      }
      .width(Height.hit)
      .height(Height.hit)
      .margin({ left: Space.xs })
      .backgroundColor(Color.Transparent)
      .bindMenu(this.overflowMenu(rec))
      .accessibilityText('订阅操作：更新、删除')
    }
    .width('100%')
    .constraintSize({ minHeight: Height.row })
    .padding({ left: 0, right: Space.md, top: Space.sm, bottom: Space.sm })
    .backgroundColor($r('app.color.bg_surface'))
    .borderRadius(Radius.card)
    .border({ width: 1, color: $r('app.color.border_subtle') })
    // 整行没有"选中"语义，只有操作；这里不挂 onClick，避免出现"点了没反应"的假命中区
    .accessibilityLevel('yes')
    .accessibilityText(`${rec.name}，${rec.nodeCount} 个节点，${this.updatedText(rec)}`)
  }

  @Builder
  emptyState() {
    Column({ space: Space.sm }) {
      Text('还没有订阅')
        .fontSize(FontSize.titleMd)
        .lineHeight(LineHeight.titleMd)
        .fontColor($r('app.color.text_secondary'))
      Text('在「节点列表」右上角「+」里粘贴 http(s) 订阅地址即可添加')
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

      if (this.msg.length > 0) {
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
        List({ space: Space.sm }) {
          ForEach(this.subs, (rec: SubRecord) => {
            ListItem() {
              this.subRow(rec)
            }
          }, (rec: SubRecord) => `${rec.id}-${rec.name}-${rec.nodeCount}-${rec.lastUpdated}-${this.busyId}`)
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
