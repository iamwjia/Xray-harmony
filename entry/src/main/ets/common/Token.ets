/**
 * common/Token.ets — 视觉令牌（除颜色外的数值部分）
 *
 * 颜色一律走资源 `$r('app.color.*')`（base / dark 双套同键）；
 * 这里只放字号、行高、间距、高度、圆角。
 *
 * 约束：页面与组件里**不再写字面量数字**。要新数值先在本文件定义，
 * 否则同一个"12"会在十几个地方各写一遍，改一次漏一片。
 */
export class FontSize {
  static readonly display: number = 24;
  static readonly titleLg: number = 20;
  static readonly titleMd: number = 16;
  static readonly bodyLg: number = 15;
  static readonly body: number = 14;
  static readonly bodySm: number = 13;
  static readonly caption: number = 12;
  /** 标签类不可点短标签（≤4 字）专用档位；正文/说明/元信息用 11fp 即违规 */
  static readonly fontChip: number = 11;
}

export class LineHeight {
  static readonly display: number = 32;
  static readonly titleLg: number = 28;
  static readonly titleMd: number = 22;
  static readonly bodyLg: number = 22;
  static readonly body: number = 20;
  static readonly bodySm: number = 20;
  static readonly caption: number = 16;
  static readonly fontChip: number = 16;
}

export class Space {
  static readonly xxs: number = 2;
  static readonly xs: number = 4;
  static readonly sm: number = 8;
  static readonly md: number = 12;
  static readonly lg: number = 16;
  static readonly xl: number = 24;
}

export class Height {
  /** 顶栏 */
  static readonly header: number = 56;
  /** 所有可点控件的命中高度下限（含图标按钮） */
  static readonly hit: number = 44;
  /** 输入框 */
  static readonly input: number = 44;
  /** 列表行下限 */
  static readonly row: number = 64;
  /** 标签 chip 视觉高度（lineHeight 16 + padding 6×2） */
  static readonly chipLabel: number = 28;
}

export class Radius {
  static readonly card: number = 12;
  static readonly panel: number = 8;
  static readonly chip: number = 4;
  /** 弹层 / 大卡片 */
  static readonly lg: number = 16;
  /** 胶囊用足够大的值表达"两端半圆" */
  static readonly pill: number = 999;
}

export class IconSize {
  static readonly md: number = 20;
  static readonly sm: number = 18;
  static readonly check: number = 20;
  static readonly stateSlot: number = 24;
}
