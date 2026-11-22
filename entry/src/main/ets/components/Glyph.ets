import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';

/**
 * components/Glyph.ets — 24vp 线性图标（画出来的，不是图片资源）
 *
 * 为什么不用 SVG/PNG 资源：
 *   1. 位图在深色模式下要么配两套、要么发灰；
 *   2. SVG 的 fillColor 只能整体染一种色，没法跟着 `$r('app.color.*')` 走两套主题；
 *   3. 用 Line/Rect/Circle 直接画，颜色天然走令牌，切深色不用改一个字。
 *
 * 约定：所有坐标都在 24×24 的画布里，线宽 2，端点圆头；调用方只给 size 与颜色。
 */
@Component
export struct Glyph {
  /** nodes / sub / routes / logs / backup / settings */
  @Prop kind: string = 'nodes';
  @Prop color: ResourceColor = $r('app.color.accent');
  @Prop box: number = 24;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.kind === 'nodes') {
        // 三行列表：长度递减，避免和"日志"三行等长撞脸
        Line().width(24).height(24).startPoint([3, 6]).endPoint([21, 6])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([3, 12]).endPoint([18, 12])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([3, 18]).endPoint([13, 18])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'sub') {
        // 向下的箭头 + 底线：拉取/接收
        Line().width(24).height(24).startPoint([12, 3]).endPoint([12, 14])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([7, 9]).endPoint([12, 14])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([17, 9]).endPoint([12, 14])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([4, 20]).endPoint([20, 20])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'routes') {
        // 一条主干分两支：分流的本义
        Line().width(24).height(24).startPoint([12, 3]).endPoint([12, 11])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([12, 11]).endPoint([5, 19])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([12, 11]).endPoint([19, 19])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'logs') {
        // 单据：外框 + 三条等长记录行
        Rect().width(16).height(18).radius(3).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 4, y: 3 })
        Line().width(24).height(24).startPoint([8, 9]).endPoint([16, 9])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([8, 13]).endPoint([16, 13])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([8, 17]).endPoint([13, 17])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'edit') {
        // 笔：斜向笔杆 + 笔尖
        Line().width(24).height(24).startPoint([7, 17]).endPoint([18, 6])
          .stroke(this.color).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([4, 20]).endPoint([8, 18])
          .stroke(this.color).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'trash') {
        // 垃圾桶：盖 + 桶身 + 提手
        Line().width(24).height(24).startPoint([4, 7]).endPoint([20, 7])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([9, 4]).endPoint([15, 4])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Rect().width(12).height(13).radius(2).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 6, y: 7 })
      } else if (this.kind === 'export') {
        // 导出：向外的箭头 + 底座（离开本机）
        Line().width(24).height(24).startPoint([12, 15]).endPoint([12, 4])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([7, 9]).endPoint([12, 4])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([17, 9]).endPoint([12, 4])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([4, 19]).endPoint([20, 19])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'import-file') {
        // 导入：向内的箭头 + 底座（进入本机）——与 export 成对，方向相反
        Line().width(24).height(24).startPoint([12, 4]).endPoint([12, 15])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([7, 10]).endPoint([12, 15])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([17, 10]).endPoint([12, 15])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([4, 20]).endPoint([20, 20])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'plus') {
        Line().width(24).height(24).startPoint([12, 5]).endPoint([12, 19])
          .stroke(this.color).strokeWidth(2.2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([5, 12]).endPoint([19, 12])
          .stroke(this.color).strokeWidth(2.2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'share') {
        // 分享：三个节点连线（系统分享的通用形状）
        Circle().width(6).height(6).fill(this.color).position({ x: 15, y: 3 })
        Circle().width(6).height(6).fill(this.color).position({ x: 15, y: 15 })
        Circle().width(6).height(6).fill(this.color).position({ x: 3, y: 9 })
        Line().width(24).height(24).startPoint([9, 12]).endPoint([15, 6])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([9, 12]).endPoint([15, 18])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'file-export') {
        // 存成文件：文档外形 + 向外的箭头（区别于纯 export 的"离开本机"）
        Rect().width(11).height(14).radius(2).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 3, y: 6 })
        Line().width(24).height(24).startPoint([14, 13]).endPoint([21, 13])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([18, 10]).endPoint([21, 13])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([18, 16]).endPoint([21, 13])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'cloud-down') {
        // 云端下载：云 + 向下箭头
        Line().width(24).height(24).startPoint([7, 9]).endPoint([17, 9])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([7, 9]).endPoint([6, 13])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([17, 9]).endPoint([18, 13])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([4, 14]).endPoint([20, 14])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([12, 15]).endPoint([12, 20])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([9, 18]).endPoint([12, 20])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([15, 18]).endPoint([12, 20])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'key') {
        // 口令：钥匙
        Circle().width(8).height(8).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 3, y: 4 })
        Line().width(24).height(24).startPoint([10, 9]).endPoint([20, 19])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([16, 15]).endPoint([19, 12])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'info') {
        Circle().width(16).height(16).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 4, y: 4 })
        Line().width(24).height(24).startPoint([12, 11]).endPoint([12, 17])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Circle().width(2).height(2).fill(this.color).position({ x: 11, y: 7 })
      } else if (this.kind === 'copy') {
        // 两个重叠的方框：复制/分享的通用形状
        Rect().width(11).height(11).radius(2).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 9, y: 9 })
        Rect().width(11).height(11).radius(2).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 4, y: 4 })
      } else if (this.kind === 'probe') {
        // 脉冲：握手/连通性的通用表达
        Line().width(24).height(24).startPoint([3, 12]).endPoint([8, 12])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([8, 12]).endPoint([11, 5])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([11, 5]).endPoint([15, 19])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([15, 19]).endPoint([18, 12])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([18, 12]).endPoint([21, 12])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else if (this.kind === 'backup') {
        // 盒子 + 提手：备份是"装起来存别处"
        Rect().width(18).height(13).radius(3).fill(Color.Transparent)
          .stroke(this.color).strokeWidth(2)
          .position({ x: 3, y: 8 })
        Line().width(24).height(24).startPoint([3, 12]).endPoint([21, 12])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([10, 16]).endPoint([14, 16])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
      } else {
        // 设置：两条滑轨 + 两个旋钮（比齿轮好画、在小尺寸下更清楚）
        Line().width(24).height(24).startPoint([3, 8]).endPoint([21, 8])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Line().width(24).height(24).startPoint([3, 16]).endPoint([21, 16])
          .stroke(this.color).strokeWidth(2).strokeLineCap(LineCapStyle.Round)
        Circle().width(8).height(8).fill($r('app.color.bg_surface'))
          .stroke(this.color).strokeWidth(2).position({ x: 6, y: 4 })
        Circle().width(8).height(8).fill($r('app.color.bg_surface'))
          .stroke(this.color).strokeWidth(2).position({ x: 14, y: 12 })
      }
    }
    .width(this.box)
    .height(this.box)
    .accessibilityLevel('no')
  }
}

/**
 * 首页入口格：图标 + 文字，整格可点（不是"图标旁边放个小按钮"）。
 */
@Component
export struct NavTile {
  @Prop kind: string = 'nodes';
  @Prop label: string = '';
  /** 副标题：写"当前是什么"，避免用户为了看一眼状态而点进去 */
  @Prop hint: string = '';
  /** 图标颜色按功能分组（数据/规则/外部/诊断/系统），不是每格一个随机色 */
  @Prop iconColor: ResourceColor = $r('app.color.accent');
  onTap: () => void = () => {
  };
  @State pressed: boolean = false;

  build() {
    Column({ space: Space.xs }) {
      Glyph({ kind: this.kind, color: this.iconColor })
      Text(this.label)
        .fontSize(FontSize.bodyLg)
        .lineHeight(LineHeight.bodyLg)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    // 放在 Row 里用：靠 layoutWeight 均分，不能再写 width('100%')——
    // 那样每个格子都会抢满一行，结果是一行只显示第一个（实测如此）。
    .layoutWeight(1)
    .constraintSize({ minHeight: 88 })
    .justifyContent(FlexAlign.Center)
    .padding({ top: Space.sm, bottom: Space.sm, left: Space.xs, right: Space.xs })
    .backgroundColor(this.pressed ? $r('app.color.bg_chip') : $r('app.color.bg_surface'))
    .borderRadius(Radius.card)
    .border({ width: 1, color: $r('app.color.border_subtle') })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.onTap();
    })
    .accessibilityText(this.hint.length > 0 ? `${this.label}，${this.hint}` : this.label)
  }
}

/**
 * 设置页入口行：整行可点，右侧一个 › 提示"会跳走"。
 *
 * 为什么不再用"文字 + 右侧小按钮"：按钮只有 60vp 宽，其余区域点了没反应，
 * 手上就是"明明看到这一行却点不动"。整行可点之后，命中区 = 视觉区。
 */
@Component
export struct EntryRow {
  @Prop title: string = '';
  @Prop detail: string = '';
  /** 右侧值（如"规则""INFO"），让用户不点也能看到当前状态 */
  @Prop value: string = '';
  @Prop danger: boolean = false;
  /** 行首图标（空串表示不显示）。和首页入口格同一套图标语言 */
  @Prop iconKind: string = '';
  @Prop iconColor: ResourceColor = $r('app.color.text_secondary');
  /** 没有跳转行为的行（如"版本"）不要画 ›，否则看起来点了会跳走 */
  @Prop showChevron: boolean = true;
  onTap: () => void = () => {
  };
  @State pressed: boolean = false;

  build() {
    Row({ space: Space.md }) {
      if (this.iconKind.length > 0) {
        Glyph({ kind: this.iconKind, color: this.iconColor, box: 22 })
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FontSize.bodyLg)
          .lineHeight(LineHeight.bodyLg)
          .fontColor(this.danger ? $r('app.color.danger') : $r('app.color.text_primary'))
          .maxLines(1)
        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
      }
      if (this.showChevron) {
        Text('\u203a')
          .fontSize(FontSize.titleMd)
          .lineHeight(LineHeight.titleMd)
          .fontColor($r('app.color.text_tertiary'))
          .accessibilityLevel('no')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: Height.hit + 8 })
    .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
    .borderRadius(Radius.panel)
    .backgroundColor(this.pressed ? $r('app.color.bg_chip') : Color.Transparent)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.onTap();
    })
    .accessibilityText(`${this.title}${this.value.length > 0 ? '，当前 ' + this.value : ''}`)
  }
}

/**
 * 带图标的按钮（图标 + 文字）。
 *
 * 为什么单独做一个组件：Button('文字') 没法内嵌图标，各页面自己拼 Row 会出现
 * 图标 18/20 混用、间距 4/6 混用、禁用态只改字不改边框等问题。集中一处，
 * 三种变体与 ui-spec §12 的三级形态一一对应。
 *
 * 只给"含义能被图标补强"的按钮用：**成对的动作（导入/导出）最值得**——
 * 方向相反的箭头，比读两个字更快分辨。
 */
@Component
export struct IconButton {
  /** Glyph 的 kind：export / import-file / plus / cloud-down / key / copy / trash ... */
  @Prop kind: string = '';
  @Prop label: string = '';
  /** primary=实心主色；outline=描边；chip=填充浅底 */
  @Prop variant: string = 'outline';
  @Prop enabledState: boolean = true;
  onTap: () => void = () => {
  };

  private fillColorOf(): ResourceColor {
    if (!this.enabledState) {
      return this.variant === 'outline' ? $r('app.color.bg_surface') : $r('app.color.bg_chip');
    }
    if (this.variant === 'primary') {
      return $r('app.color.accent');
    }
    return this.variant === 'outline' ? $r('app.color.bg_surface') : $r('app.color.bg_chip');
  }

  private fontColorOf(): ResourceColor {
    if (!this.enabledState) {
      return $r('app.color.text_tertiary');
    }
    if (this.variant === 'primary') {
      return $r('app.color.text_on_accent');
    }
    return this.variant === 'outline' ? $r('app.color.accent') : $r('app.color.text_primary');
  }

  private strokeColorOf(): ResourceColor {
    if (this.variant !== 'outline') {
      return Color.Transparent;
    }
    return this.enabledState ? $r('app.color.accent') : $r('app.color.border_subtle');
  }

  build() {
    // Capsule：与全站其它按钮（解密并恢复 / 输入框旁的按钮）保持同一外形
    Button({ type: ButtonType.Capsule }) {
      Row({ space: Space.sm }) {
        Glyph({ kind: this.kind, color: this.fontColorOf(), box: 18 })
        Text(this.label)
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor(this.fontColorOf())
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .height(Height.hit)
    .borderRadius(Radius.pill)
    .backgroundColor(this.fillColorOf())
    .border({ width: this.variant === 'outline' ? 1 : 0, color: this.strokeColorOf() })
    .enabled(this.enabledState)
    .accessibilityText(this.label)
    .onClick(() => {
      this.onTap();
    })
  }
}
