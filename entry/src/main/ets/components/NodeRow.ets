import { FontSize, LineHeight, Space, Height, Radius, IconSize } from '../common/Token';

/**
 * components/NodeRow.ets — 节点行（两个命中区）
 *
 * 结构约束（改样式时不要破坏）：
 *   1. 整行 `Row.onClick` 只做"选中"；溢出按钮自己消费事件；
 *   2. **禁止**在整行外再包一层 click 容器或 gesture 包裹层，也不许用
 *      `hitTestBehavior` 兜底——两个命中区是兄弟，不是嵌套；
 *   3. 选中态三重编码：竖条（位置）+ 对勾/空心圈（形态）+ 字重，去掉颜色仍可辨；
 *   4. `accessibilityText` 必须读出「已选中 / 未选中」，删文案不等于删语义。
 */
@Component
export struct NodeRow {
  @Prop nodeId: string = '';
  @Prop name: string = '';
  @Prop protocol: string = '';
  @Prop address: string = '';
  @Prop port: number = 0;
  @Prop group: string = '';
  @Prop selected: boolean = false;
  /** 首/末行的"上移/下移"必须置灰，否则用户会一直点一个永远不会生效的项 */
  @Prop canMoveUp: boolean = true;
  @Prop canMoveDown: boolean = true;
  /** 分组 chip 里真正的"标签"，与行内文字同层但不抢宽度 */
  @Prop showGroupChip: boolean = true;

  onPick: (id: string) => void = () => {
  };
  onEdit: (id: string) => void = () => {
  };
  onMove: (id: string, delta: number) => void = () => {
  };
  onDelete: (id: string) => void = () => {
  };
  onProbe: (id: string) => void = () => {
  };

  private rowA11y(): string {
    const g: string = this.group.length > 0 ? this.group : '未分组';
    const sel: string = this.selected ? '已选中' : '未选中';
    return `${this.name}，${this.protocol}，${this.address}:${this.port}，${g}，${sel}`;
  }

  /**
   * 协议短名（仅展示层，不改数据）。
   * `shadowsocks` 在 12fp 下要 73vp，白吃 host 一半宽度，而协议名对用户不是检索键。
   */
  private static protocolShort(p: string): string {
    if (p === 'shadowsocks') {
      return 'ss';
    }
    return p;
  }

  @Builder
  overflowMenu() {
    Column() {
      this.menuItem('编辑', false, true, () => this.onEdit(this.nodeId))
      this.menuItem('测连通性', false, true, () => this.onProbe(this.nodeId))
      this.menuItem('上移', false, this.canMoveUp, () => this.onMove(this.nodeId, -1))
      this.menuItem('下移', false, this.canMoveDown, () => this.onMove(this.nodeId, 1))
      Divider().color($r('app.color.border_subtle'))
      this.menuItem('删除', true, true, () => this.onDelete(this.nodeId))
    }
    .constraintSize({ minWidth: 160 })
    .padding({ top: Space.xs, bottom: Space.xs })
    .backgroundColor($r('app.color.bg_surface'))
    .borderRadius(Radius.panel)
    // 自绘弹层没有系统阴影，深色下两个 bg_surface 会融成一片，必须描边
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
      .enabled(enabled)
      .accessibilityText(enabled ? label : `${label}（不可用）`)
      .onClick(() => {
        if (enabled) {
          action();
        }
      }).lineHeight(LineHeight.bodySm)
  }

  build() {
    Row() {
      // ① 选中竖条：位置编码
      Row()
        .width(3)
        .height(40)
        .borderRadius(1.5)
        .margin({ right: 9 })
        .backgroundColor(this.selected ? $r('app.color.accent') : Color.Transparent)

      // ② 选中形态：对勾 / 空心圈
      Stack() {
        if (this.selected) {
          Text('\u2713')
            .fontSize(IconSize.check)
            .fontColor($r('app.color.accent'))
            .fontWeight(FontWeight.Bold)
            .accessibilityLevel('no')
        } else {
          Row()
            .width(IconSize.sm)
            .height(IconSize.sm)
            .borderRadius(IconSize.sm)
            .border({ width: 1.5, color: $r('app.color.border_strong') })
        }
      }
      .width(IconSize.stateSlot)
      .height(IconSize.stateSlot)
      .margin({ right: 10 })

      // ③ 文字列
      Column({ space: Space.xxs }) {
        // 名称独占整行宽度：节点名是用户自己起的，被分组 chip 压扁会让他找不到自己的节点
        Text(this.name)
          .fontSize(FontSize.bodyLg)
          .lineHeight(LineHeight.bodyLg)
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          // 行级已经整句播报，子节点全部静音，否则读屏会把同一行念两遍
          .accessibilityLevel('no')

        // 元信息行：host 可截断，**:port 独立且恒完整**（地址:端口是排障检索键，尾部不能被吃掉）
        Row({ space: Space.xs }) {
          Text(`${NodeRow.protocolShort(this.protocol)} \u00b7`)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .accessibilityLevel('no')
          Text(this.address)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .accessibilityLevel('no')
          Text(`:${this.port}`)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .accessibilityLevel('no')
          if (this.showGroupChip && this.group.length > 0) {
            Text(this.group)
              .fontSize(FontSize.fontChip)
              .lineHeight(LineHeight.fontChip)
              .fontWeight(FontWeight.Medium)
              .padding({ left: Space.sm, right: Space.sm, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.accent_subtle'))
              .fontColor($r('app.color.accent'))
              .borderRadius(Radius.chip)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 60 })
              .accessibilityLevel('no')
          }
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 命中区②：溢出菜单（自己消费事件，不冒泡到整行）
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
      .bindMenu(this.overflowMenu)
      .accessibilityText('节点操作：编辑、上移、下移、删除')
    }
    .width('100%')
    .constraintSize({ minHeight: Height.row })
    .padding({ left: 0, right: Space.md, top: 10, bottom: 10 })
    .backgroundColor(this.selected ? $r('app.color.selected_row_bg') : $r('app.color.bg_surface'))
    .borderRadius(Radius.card)
    .border({
      width: 1,
      color: this.selected ? Color.Transparent : $r('app.color.border_subtle')
    })
    .onClick(() => {
      // 命中区①：只做选中。编辑/排序/删除都在溢出菜单里，不在这里分流。
      this.onPick(this.nodeId);
    })
    .accessibilityLevel('yes')
    .accessibilityText(this.rowA11y())
  }
}
