import { FontSize, LineHeight, Space, Height, IconSize } from '../common/Token';

/**
 * components/PageHeader.ets — 页面顶栏
 *
 * 抽成一个组件的理由：五个页面（Nodes / NodeEdit / Settings / RoutingRules / Logs）
 * 顶栏结构完全一样，各自抄一份的后果是"某页返回键 40、某页 44"这种不一致，
 * 而且改一次要改五处。
 *
 * 约定：
 *   - 返回键与动作键都是 44×44 命中区，图标 20vp；
 *   - 装饰字形一律 `accessibilityLevel('no')`，语义交给按钮的 `accessibilityText`；
 *   - 计数只传数字，不传带单位的字符串（单位属于展示层，由这里拼）。
 */
@Component
export struct PageHeader {
  @Prop title: string = '';
  /** 负数表示不显示计数 */
  @Prop count: number = -1;
  /** 空串表示不显示右侧动作按钮 */
  @Prop actionGlyph: string = '';
  @Prop actionA11y: string = '';

  onBack: () => void = () => {
  };
  onAction: () => void = () => {
  };

  build() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Text('\u2190')
          .fontSize(IconSize.md)
          .fontColor($r('app.color.text_primary'))
          .accessibilityLevel('no')
      }
      .width(Height.hit)
      .height(Height.hit)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回')
      .onClick(() => {
        this.onBack();
      })

      Text(this.title)
        .fontSize(FontSize.titleLg)
        .lineHeight(LineHeight.titleLg)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.count >= 0) {
        Text(`${this.count} 个`)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ right: Space.sm })
      }

      if (this.actionGlyph.length > 0) {
        Button({ type: ButtonType.Circle }) {
          Text(this.actionGlyph)
            .fontSize(IconSize.md)
            .fontColor($r('app.color.accent'))
            .accessibilityLevel('no')
        }
        .width(Height.hit)
        .height(Height.hit)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.actionA11y)
        .onClick(() => {
          this.onAction();
        })
      }
    }
    .width('100%')
    .height(Height.header)
    .padding({ left: Space.xs, right: Space.sm })
  }
}
