import { router } from '@kit.ArkUI';
import { RoutingRule, RoutingMode } from '../model/AppConfig';
import { PageHeader } from '../components/PageHeader';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';
import { ConfigService } from '../service/ConfigService';
import { Logger } from '../platform/Logger';

/**
 * pages/RoutingRules.ets — 自定义分流规则
 *
 * 交互约束：
 *   - 列表顺序 = 下发顺序 = 匹配优先级。**自定义规则排在 geo 规则之前**，
 *     所以这里看到的顺序就是它实际生效的顺序（详见 KernelConfigBuilder.buildRouting）。
 *   - 提供「启用/禁用」而不只是删除：用户经常需要"临时关掉这条，看看会不会好"。
 *   - 全局模式下自定义规则不生效（全局=全部代理），页面顶部必须写明，否则会被当成 bug。
 */

interface MatchOption {
  label: string;
  value: string;
  hint: string;
}

interface ActionOption {
  label: string;
  value: string;
}

interface ModeOption {
  label: string;
  value: RoutingMode;
}

@Entry
@Component
struct RoutingRules {
  @State rules: RoutingRule[] = [];
  @State newPattern: string = '';
  @State matchIdx: number = 0;
  @State actionIdx: number = 0;
  @State msg: string = '';
  /** 分流模式（与规则同页：模式决定"要不要用规则"） */
  @State mode: RoutingMode = RoutingMode.RULE;
  @State modeError: string = '';

  private cfg: ConfigService = ConfigService.getInstance();

  private modes: ModeOption[] = [
    { label: '全局代理', value: RoutingMode.GLOBAL },
    { label: '规则分流', value: RoutingMode.RULE },
    { label: '全部直连', value: RoutingMode.DIRECT }
  ];

  private matches: MatchOption[] = [
    { label: '域名', value: 'domain', hint: '支持精确域名、domain: 前缀、keyword: 关键字、geosite: 分类' },
    { label: 'IP', value: 'ip', hint: '支持单 IP、CIDR 网段、geoip: 分类' }
  ];
  private actions: ActionOption[] = [
    { label: '走代理', value: 'proxy' },
    { label: '直连', value: 'direct' },
    { label: '阻断', value: 'block' }
  ];

  aboutToAppear(): void {
    this.reload();
    this.mode = this.cfg.getConfig().settings.routingMode;
  }

  private setMode(m: RoutingMode): void {
    const ok: boolean = this.cfg.setRoutingMode(m);
    // 写盘失败时 ConfigService 已回滚内存值，这里必须读回真实值
    this.mode = this.cfg.getConfig().settings.routingMode;
    this.modeError = ok ? '' : this.cfg.getPersistError();
  }

  private modeHint(): string {
    if (this.mode === RoutingMode.GLOBAL) {
      return '全局代理：所有流量走当前节点，下面的自定义规则不生效。';
    }
    if (this.mode === RoutingMode.DIRECT) {
      return '全部直连：不经过代理，下面的自定义规则不生效（连上后仅国内可访问）。';
    }
    return '规则分流：先匹配下面的自定义规则，再按内置的国内域名/IP 直连，其余走代理（依赖 geo 资源）。';
  }

  private reload(): void {
    this.rules = this.cfg.getRules().slice();
  }

  private actionLabel(v: string): string {
    for (let i = 0; i < this.actions.length; i++) {
      if (this.actions[i].value === v) {
        return this.actions[i].label;
      }
    }
    return v;
  }

  /** 只做明显的格式校验；是否真能匹配交给内核（它会给出明确报错） */
  private validate(p: string): string {
    if (p.length === 0) {
      return '规则内容不能为空';
    }
    if (p.indexOf(' ') >= 0) {
      return '规则内容不要包含空格（一条规则一个匹配项）';
    }
    if (this.matches[this.matchIdx].value === 'ip' && !p.startsWith('geoip:')) {
      const ok: boolean = /^[0-9a-fA-F:.]+(\/[0-9]{1,3})?$/.test(p);
      if (!ok) {
        return 'IP 规则格式应为 1.2.3.4 或 1.2.3.0/24（或 geoip:xx）';
      }
    }
    return '';
  }

  private doAdd(): void {
    const p: string = this.newPattern.trim();
    const err: string = this.validate(p);
    if (err.length > 0) {
      this.msg = err;
      return;
    }
    const ok: boolean = this.cfg.addRule(this.matches[this.matchIdx].value, p,
      this.actions[this.actionIdx].value);
    if (ok) {
      this.newPattern = '';
      this.msg = `已添加：${p} → ${this.actionLabel(this.actions[this.actionIdx].value)}`;
      this.reload();
    } else {
      this.msg = '添加失败（详见日志）';
    }
  }

  private doDelete(id: string): void {
    if (this.cfg.removeRule(id)) {
      this.reload();
      this.msg = '已删除';
    } else {
      this.msg = '删除失败（详见日志）';
    }
  }

  private doToggle(id: string): void {
    if (this.cfg.toggleRule(id)) {
      this.reload();
    } else {
      this.msg = '切换失败（详见日志）';
    }
  }

  build() {
    Column({ space: 12 }) {
      // 页头统一用 PageHeader：返回是箭头图标（44 命中区），标题与计数位置与其它页一致。
      // 原先这里是 Button('返回')，默认按钮形态在五个页面里显得突兀。
      PageHeader({
        title: '分流',
        countText: `已启用 ${this.enabledCount()} 条`,
        onBack: () => {
          router.back();
        }
      })

      // 分流模式：从设置页搬到它的归属页——模式与规则是同一件事的两层，
      // 分开放在两页会让用户来回跳着改。
      Column({ space: Space.sm }) {
        Text('分流模式')
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Row({ space: Space.sm }) {
          ForEach(this.modes, (m: ModeOption) => {
            Button(m.label, { type: ButtonType.Capsule })
              .layoutWeight(1)
              .padding({ left: 0, right: 0 })
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor(m.value === this.mode ? $r('app.color.accent') : $r('app.color.bg_chip'))
              .fontColor(m.value === this.mode ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
              .onClick(() => {
                this.setMode(m.value);
              })
          }, (m: ModeOption) => m.value)
        }
        .width('100%')
        Text(this.modeHint())
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        if (this.modeError.length > 0) {
          Text(this.modeError)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.warning'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(Space.md)
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(Radius.panel)

      Text('优先级：这里列出的规则**先于**内置的国内直连规则匹配，顺序即优先级。')
        .fontSize(FontSize.caption).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.caption)
      Text('注意：分流模式为「全局」时，这些规则不生效（全局=全部走代理）。')
        .fontSize(FontSize.caption).fontColor($r('app.color.warning')).width('100%').lineHeight(LineHeight.caption)

      // 新增表单
      Column({ space: 8 }) {
        // 匹配方式与动作分两行、各自等宽：原来五个按钮挤在一行靠 Blank 隔开，
        // 结果"域名"和"走代理"宽度不同、还分不清哪几个是一组（属于哪一组看标签才知道）。
        Text('匹配方式')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Row({ space: Space.sm }) {
          ForEach(this.matches, (m: MatchOption, i: number) => {
            Button(m.label, { type: ButtonType.Capsule })
              .layoutWeight(1)
              .padding({ left: 0, right: 0 })
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor(i === this.matchIdx ? $r('app.color.accent') : $r('app.color.bg_chip'))
              .fontColor(i === this.matchIdx ? $r('app.color.text_on_accent') : $r('app.color.text_primary'))
              .onClick(() => {
                this.matchIdx = i;
              })
          }, (m: MatchOption) => m.value)
        }
        .width('100%')

        Text('命中后')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Row({ space: Space.sm }) {
          ForEach(this.actions, (a: ActionOption, i: number) => {
            Button(a.label, { type: ButtonType.Capsule })
              .layoutWeight(1)
              .padding({ left: 0, right: 0 })
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor(i === this.actionIdx ? $r('app.color.accent') : $r('app.color.bg_chip'))
              .fontColor(i === this.actionIdx ? $r('app.color.text_on_accent') : $r('app.color.text_primary'))
              .onClick(() => {
                this.actionIdx = i;
              })
          }, (a: ActionOption) => a.value)
        }
        .width('100%')

        Row({ space: 8 }) {
          TextInput({ placeholder: '例如 example.com / keyword:google / 10.0.0.0/8', text: this.newPattern })
            .fontSize(FontSize.bodySm)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.newPattern = v;
            })
          Button('添加').fontSize(FontSize.bodySm).onClick(() => this.doAdd())
        }
        .width('100%')

        Text(this.matches[this.matchIdx].hint).fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).width('100%').lineHeight(LineHeight.caption)
      }
      .width('100%')
      .padding(10)
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(8)

      if (this.msg.length > 0) {
        Text(this.msg).fontSize(FontSize.caption).fontColor($r('app.color.accent')).width('100%').lineHeight(LineHeight.caption)
      }

      if (this.rules.length === 0) {
        Text('还没有自定义规则。不添加时，规则模式使用内置的国内直连 + 内网直连。')
          .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).width('100%').lineHeight(LineHeight.caption)
      }

      List({ space: 8 }) {
        ForEach(this.rules, (r: RoutingRule) => {
          ListItem() {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(r.pattern).fontSize(FontSize.body)
                  .fontColor(r.enabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary')).lineHeight(LineHeight.body)
                Text(`${r.matchType === 'ip' ? 'IP' : '域名'} · ${this.actionLabel(r.action)}` +
                  (r.enabled ? '' : ' · 已禁用'))
                  .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(r.enabled ? '禁用' : '启用')
                .fontSize(FontSize.bodySm).fontColor($r('app.color.accent'))
                .onClick(() => this.doToggle(r.id)).lineHeight(LineHeight.bodySm)
              Text('删除')
                .fontSize(FontSize.bodySm).fontColor($r('app.color.danger'))
                .onClick(() => this.doDelete(r.id)).maxLines(1)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(r.enabled ? $r('app.color.bg_surface_alt') : $r('app.color.bg_chip'))
            .borderRadius(8)
          }
        }, (r: RoutingRule) => `${r.id}-${r.enabled}-${r.pattern}`)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  private enabledCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.rules.length; i++) {
      if (this.rules[i].enabled) {
        n++;
      }
    }
    return n;
  }
}
