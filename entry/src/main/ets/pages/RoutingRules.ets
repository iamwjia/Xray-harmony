import { router } from '@kit.ArkUI';
import { RoutingRule } from '../model/AppConfig';
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

@Entry
@Component
struct RoutingRules {
  @State rules: RoutingRule[] = [];
  @State newPattern: string = '';
  @State matchIdx: number = 0;
  @State actionIdx: number = 0;
  @State msg: string = '';

  private cfg: ConfigService = ConfigService.getInstance();

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
      Row({ space: 8 }) {
        Button('返回').fontSize(FontSize.bodySm)
          .onClick(() => {
            router.back();
          })
        Text('自定义分流规则').fontSize(FontSize.titleLg).fontWeight(FontWeight.Bold).layoutWeight(1).maxLines(1)
        Text(`已启用 ${this.enabledCount()} 条`).fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
      }
      .width('100%')

      Text('优先级：这里列出的规则**先于**内置的国内直连规则匹配，顺序即优先级。')
        .fontSize(FontSize.caption).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.caption)
      Text('注意：分流模式为「全局」时，这些规则不生效（全局=全部走代理）。')
        .fontSize(FontSize.caption).fontColor($r('app.color.warning')).width('100%').lineHeight(LineHeight.caption)

      // 新增表单
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          ForEach(this.matches, (m: MatchOption, i: number) => {
            Button(m.label).fontSize(FontSize.caption)
              .backgroundColor(i === this.matchIdx ? $r('app.color.accent') : $r('app.color.bg_chip'))
              .fontColor(i === this.matchIdx ? $r('app.color.text_on_accent') : $r('app.color.text_primary'))
              .onClick(() => {
                this.matchIdx = i;
              })
          }, (m: MatchOption) => m.value)
          Blank()
          ForEach(this.actions, (a: ActionOption, i: number) => {
            Button(a.label).fontSize(FontSize.caption)
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
