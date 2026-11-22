import { FontSize, LineHeight, Space, Height, Radius, IconSize } from '../common/Token';

/** 操作菜单宽度：固定值，不跟屏幕宽度变化 */
const MENU_WIDTH: number = 180;

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
  /** 按下中：手机上必须有可见反馈，否则用户不知道自己点到了没有 */
  @State pressed: boolean = false;
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
  /** 长按整行：复制分享链接（含凭据，调用方负责提示风险） */
  onCopyLink: (id: string) => void = () => {
  };

  private rowA11y(): string {
    const g: string = this.group.length > 0 ? this.group : '未分组';
    const sel: string = this.selected ? '已选中' : '未选中';
    return `${this.name}，${this.protocol}，${this.address}:${this.port}，${g}，${sel}；长按可复制分享链接`;
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

  /**
   * 协议色标：四种协议各占一个色相（蓝/紫/青/琥珀），同一协议在任何页面都是同一颜色。
   *
   * 为什么值得上色：协议是"这行能不能用"的第一判据（不同协议的握手与失败原因完全不同），
   * 眼睛扫一列小方块就能分出"我这一堆节点里哪些是 vless"，比逐行读文字快一个数量级。
   * 颜色不是唯一信息载体——旁边仍写着协议名，色盲用户也不丢信息。
   */
  private static protocolText(p: string): Resource {
    if (p === 'vmess') {
      return $r('app.color.proto_vmess');
    }
    if (p === 'trojan') {
      return $r('app.color.proto_trojan');
    }
    if (p === 'shadowsocks') {
      return $r('app.color.proto_ss');
    }
    return $r('app.color.proto_vless');
  }

  private static protocolBg(p: string): Resource {
    if (p === 'vmess') {
      return $r('app.color.proto_vmess_bg');
    }
    if (p === 'trojan') {
      return $r('app.color.proto_trojan_bg');
    }
    if (p === 'shadowsocks') {
      return $r('app.color.proto_ss_bg');
    }
    return $r('app.color.proto_vless_bg');
  }

  /** 分组按名字取色：同名恒同色，用户能靠颜色认出"我那一组" */
  private static groupIdx(g: string): number {
    let h: number = 0;
    for (let i = 0; i < g.length; i++) {
      h = (h * 31 + g.charCodeAt(i)) % 9973;
    }
    return h % 3;
  }

  private static groupText(g: string): Resource {
    const i: number = NodeRow.groupIdx(g);
    if (i === 1) {
      return $r('app.color.group_b');
    }
    return i === 2 ? $r('app.color.group_c') : $r('app.color.group_a');
  }

  private static groupBg(g: string): Resource {
    const i: number = NodeRow.groupIdx(g);
    if (i === 1) {
      return $r('app.color.group_b_bg');
    }
    return i === 2 ? $r('app.color.group_c_bg') : $r('app.color.group_a_bg');
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
    // 定宽而不是 minWidth：弹层是“自适应”容器，只给下限会被拉到几乎全屏宽，
    // 行内文字又是 width('100%')，于是文字看起来偏左、像被遮挡。
    .width(MENU_WIDTH)
    .padding({ top: Space.xs, bottom: Space.xs })
    .backgroundColor($r('app.color.bg_surface'))
    .borderRadius(Radius.panel)
    // 自绘弹层没有系统阴影，深色下两个 bg_surface 会融成一片，必须描边
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
          // 协议色标：色底 + 色字，取代原来的"协议名 ·"，既省一次分隔符也自带检索色
          Text(NodeRow.protocolShort(this.protocol))
            .fontSize(FontSize.fontChip)
            .lineHeight(LineHeight.fontChip)
            .fontWeight(FontWeight.Medium)
            .padding({ left: Space.xs, right: Space.xs, top: 3, bottom: 3 })
            .backgroundColor(NodeRow.protocolBg(this.protocol))
            .fontColor(NodeRow.protocolText(this.protocol))
            .borderRadius(Radius.chip)
            .maxLines(1)
            .margin({ right: Space.xs })
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
              .backgroundColor(NodeRow.groupBg(this.group))
              .fontColor(NodeRow.groupText(this.group))
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
        Stack() {
          Text('\u22ef')
            .fontSize(IconSize.md)
            .fontColor($r('app.color.text_secondary'))
            .accessibilityLevel('no')
        }
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.bg_chip'))
        .borderRadius(Radius.pill)
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
    .backgroundColor(this.pressed
      ? (this.selected ? $r('app.color.accent_subtle') : $r('app.color.bg_chip'))
      : (this.selected ? $r('app.color.selected_row_bg') : $r('app.color.bg_surface')))
    .borderRadius(Radius.card)
    .border({
      width: 1,
      color: this.selected ? Color.Transparent : $r('app.color.border_subtle')
    })
    .onTouch((e: TouchEvent) => {
      // 只跟随按下/抬起与取消；不在这里做选中逻辑（那是 onClick 的事）
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      // 命中区①：只做选中。编辑/排序/删除都在溢出菜单里，不在这里分流。
      this.onPick(this.nodeId);
    })
    // 长按整行 = 复制分享链接。换机、求助、问"这节点还能用吗"都要把节点发出去，
    // 现在没有这条路径就只能照着屏幕手打一遍。
    // 用 parallelGesture：行的 onTouch/onClick 与列表的滑动都要正常，长按是并列识别，
    // 用 .gesture() 会与列表的滑动手势互相等待，实测命令行注入的长按完全收不到。
    .parallelGesture(
      // 450ms：系统长按普遍是 500ms，取 450 才能被"标准长按"命中
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction(() => {
          this.onCopyLink(this.nodeId);
        })
    )
    .accessibilityLevel('yes')
    .accessibilityText(this.rowA11y())
  }
}
