import { router } from '@kit.ArkUI';
import { ClearResult, ConfigService } from '../service/ConfigService';
import { RoutingMode } from '../model/AppConfig';
import { GeoAssets } from '../service/GeoAssets';
import { KernelService } from '../service/KernelService';
import { common } from '@kit.AbilityKit';
import { PageHeader } from '../components/PageHeader';
import { EntryRow } from '../components/Glyph';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';

/**
 * pages/Settings.ets — 设置
 *
 * 结构约定（统一交互模型，避免"同一页两种展开方式"）：
 *   设置页只放**行**——可跳转行（右侧 ›）或开关行（右侧 Toggle）。
 *   任何"选项组"都不在这里内联展开：日志级别在运行日志页，分流模式在分流规则页。
 *   这样点任何一行，用户都知道会发生什么：要么跳页，要么切开关。
 *
 * 数据约束：设置读写 ConfigService，不直接碰平台 API。
 */
@Entry
@Component
struct Settings {
  @State logLevel: string = 'INFO';
  @State routingMode: RoutingMode = RoutingMode.RULE;
  /** 设置写盘失败提示（不允许"看着改了其实没存"） */
  @State persistError: string = '';
  /** 清空数据：进行中标记与结果提示（0 信息 / 2 错误） */
  @State clearing: boolean = false;
  @State clearMsg: string = '';
  @State clearMsgLevel: number = 0;
  /** 订阅自动更新（默认关：不偷偷联网） */
  @State autoUpdateSubs: boolean = false;
  @State autoUpdateHours: number = 24;
  /** geo 资源版本（未就绪时明确显示"不可用"，不要显示空串让人以为正常） */
  @State geoLabel: string = '';
  /** geo 手动更新状态 */
  @State geoBusy: boolean = false;
  @State geoMsg: string = '';
  /** 自定义规则条数（启用中） */
  @State ruleCount: number = 0;
  /** 订阅条数（入口行右侧直接显示，不用点进去数） */
  @State subCount: number = 0;

  private cfg: ConfigService = ConfigService.getInstance();

  aboutToAppear(): void {
    this.routingMode = this.cfg.getConfig().settings.routingMode;
    this.logLevel = this.cfg.getLogLevel();
    this.geoLabel = GeoAssets.isReady() ? `${GeoAssets.getVersion()}（已就绪）` : '未就绪（规则模式降级为仅内网直连）';
    this.refreshRuleCount();
    this.autoUpdateSubs = this.cfg.getConfig().settings.autoUpdateSubs;
    this.autoUpdateHours = this.cfg.getConfig().settings.autoUpdateHours;
    this.subCount = this.cfg.getConfig().subscriptions.length;
  }

  /** 从子页返回时刷新（规则、订阅、日志级别都可能被改过） */
  onPageShow(): void {
    this.refreshRuleCount();
    this.subCount = this.cfg.getConfig().subscriptions.length;
    this.logLevel = this.cfg.getLogLevel();
    this.routingMode = this.cfg.getConfig().settings.routingMode;
  }

  private refreshRuleCount(): void {
    const rules = this.cfg.getRules();
    let n: number = 0;
    for (let i = 0; i < rules.length; i++) {
      if (rules[i].enabled) {
        n++;
      }
    }
    this.ruleCount = n;
  }

  /** 分流模式的文字口径：与分流规则页按钮同一套说法 */
  private routingText(): string {
    if (this.routingMode === RoutingMode.GLOBAL) {
      return '全局代理';
    }
    return this.routingMode === RoutingMode.DIRECT ? '全部直连' : '规则分流';
  }

  /** 切换订阅自动更新；写盘失败回滚并提示 */
  private setAutoUpdate(enabled: boolean): void {
    const ok: boolean = this.cfg.setSubscriptionAutoUpdate(enabled, this.autoUpdateHours);
    this.autoUpdateSubs = this.cfg.getConfig().settings.autoUpdateSubs;
    this.autoUpdateHours = this.cfg.getConfig().settings.autoUpdateHours;
    this.persistError = ok ? '' : this.cfg.getPersistError();
  }

  private setAutoUpdateHours(h: number): void {
    const ok: boolean = this.cfg.setSubscriptionAutoUpdate(this.autoUpdateSubs, h);
    this.autoUpdateSubs = this.cfg.getConfig().settings.autoUpdateSubs;
    this.autoUpdateHours = this.cfg.getConfig().settings.autoUpdateHours;
    this.persistError = ok ? '' : this.cfg.getPersistError();
  }

  private nav(url: string, what: string): void {
    router.pushUrl({ url: url }).catch((e: Error) => {
      this.persistError = `打开${what}失败：${e.message}`;
    });
  }

  /**
   * geo 手动更新。点击前必须弹确认：这是在**用用户的流量**下载约 25 MB，
   * 不能做成"点了就开始下、下完才告诉用户"。
   */
  private confirmGeoUpdate(): void {
    AlertDialog.show({
      title: '更新分流资源',
      message: '将从 v2fly 官方下载最新 geoip / geosite（约 25 MB），使用当前网络流量。\n' +
        '更新不影响已保存的节点；若正在连接，需断开重连后生效。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '开始更新',
        action: () => {
          this.doGeoUpdate();
        }
      }
    });
  }

  private doGeoUpdate(): void {
    if (this.geoBusy) {
      return;
    }
    this.geoBusy = true;
    this.geoMsg = '准备中…';
    GeoAssets.updateFromNetwork((m: string) => {
      this.geoMsg = m;
    }).then((err: string) => {
      this.geoBusy = false;
      this.geoLabel = GeoAssets.isReady() ? `${GeoAssets.getVersion()}（已就绪）` : this.geoLabel;
      if (err.length > 0) {
        this.geoMsg = `更新失败：${err}（已保留原有规则）`;
        return;
      }
      this.geoMsg = KernelService.getInstance().isRunning()
        ? '已更新，请断开后重连使新规则生效'
        : '已更新，下次连接生效';
    }).catch((e: Object) => {
      this.geoBusy = false;
      const msg: string = e instanceof Error ? e.message : String(e);
      this.geoMsg = `更新失败：${msg}（已保留原有规则）`;
    });
  }

  private doGeoImport(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    GeoAssets.pickAndImport(ctx).then((err: string) => {
      if (err === 'CANCEL') {
        return;
      }
      this.geoLabel = GeoAssets.isReady() ? `${GeoAssets.getVersion()}（已就绪）` : this.geoLabel;
      if (err.length === 0) {
        this.geoMsg = KernelService.getInstance().isRunning()
          ? '已导入，请断开后重连使新规则生效'
          : '已导入，下次连接生效';
      } else {
        this.geoMsg = `导入失败：${err}（已保留原有规则）`;
      }
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.geoMsg = `导入失败：${msg}（已保留原有规则）`;
    });
  }

  /**
   * 清空前的确认。
   * 弹窗里直接把“会删什么”列出来，不写“确认清空吗？”这种只会被习惯性点掉的句子。
   */
  private confirmClearAll(): void {
    AlertDialog.show({
      title: '清空所有数据',
      message: '将删除：\n' +
        '• 全部节点及其保存的凭据（UUID / 密码 / 密钥）\n' +
        '• 自定义分流规则\n' +
        '• 订阅记录与保存的订阅地址\n' +
        '• 设置（分流模式、日志级别、首次连接明示标志）\n\n' +
        '不会删：已导出的备份文件、geo 数据。\n' +
        '此操作不可恢复。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认清空',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.doClearAll();
        }
      }
    });
  }

  private doClearAll(): void {
    this.clearing = true;
    this.clearMsgLevel = 0;
    this.clearMsg = '正在清理…';
    this.cfg.clearAllData().then((r: ClearResult) => {
      this.clearing = false;
      let text: string = `已清空：节点 ${r.nodes} 个、规则 ${r.rules} 条、订阅 ${r.subscriptions} 个`;
      if (r.nodeSecrets + r.subUrls > 0) {
        text += `，并清理了 ${r.nodeSecrets + r.subUrls} 条凭据`;
      }
      if (r.secretFailures > 0) {
        text += `。注意：${r.secretFailures} 条凭据没能从安全存储中删除，详见日志`;
        this.clearMsgLevel = 2;
      }
      this.clearMsg = text;
      this.refreshRuleCount();
      this.routingMode = this.cfg.getConfig().settings.routingMode;
      this.logLevel = this.cfg.getLogLevel();
      this.subCount = this.cfg.getConfig().subscriptions.length;
    }).catch((e: Object) => {
      this.clearing = false;
      this.clearMsgLevel = 2;
      const m: string = e instanceof Error ? e.message : String(e);
      this.clearMsg = `清空失败：${m}`;
    });
  }

  build() {
    // 可滚：设置项已经多到一屏放不下，包在 Column 里会把底部裁掉，
    // 那样"入口存在但点不到"比没有入口更糟。
    Scroll() {
      Column({ space: Space.md }) {
        Row() {
          PageHeader({
            title: '设置',
            onBack: () => {
              router.back();
            }
          })
        }
        .width('100%')

        // 设置写盘失败横幅：必须可见，否则用户会以为设置已生效
        if (this.persistError.length > 0) {
          Text(this.persistError)
            .fontSize(FontSize.bodySm)
            .fontColor($r('app.color.warning'))
            .width('100%')
            .padding(10)
            .backgroundColor($r('app.color.warning_subtle'))
            .borderRadius(Radius.panel)
            .lineHeight(LineHeight.bodySm)
        }

        Text('网络')
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: Space.xs })
        Column() {
          EntryRow({
            title: '分流方式与规则',
            detail: `已启用 ${this.ruleCount} 条自定义规则`,
            value: this.routingText(),
            onTap: () => this.nav('pages/RoutingRules', '分流规则')
          })
          EntryRow({
            title: '订阅管理',
            detail: '更新订阅、查看上次更新时间；删订阅不删节点',
            value: this.subCount === 0 ? '未添加' : `${this.subCount} 个`,
            onTap: () => this.nav('pages/Subscriptions', '订阅管理')
          })
          // 开关行：右侧是 Toggle 而不是 ›，一眼可分辨"会跳走"还是"就地切换"
          Column({ space: Space.sm }) {
            Row({ space: Space.sm }) {
              Column({ space: 2 }) {
                Text('自动更新订阅')
                  .fontSize(FontSize.bodyLg)
                  .lineHeight(LineHeight.bodyLg)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                Text('进入应用时若超过间隔会提示更新（不会静默联网）')
                  .fontSize(FontSize.caption)
                  .lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.autoUpdateSubs })
                .onChange((on: boolean) => {
                  this.setAutoUpdate(on);
                })
            }
            .width('100%')
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })

            if (this.autoUpdateSubs) {
              // 用 Flex 换行而不是 Row：四个调度在 360vp 宽下会拤一起、第四个被压扁
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach([6, 12, 24, 168], (h: number) => {
                  Button(h === 168 ? '每周' : `每 ${h} 小时`, { type: ButtonType.Capsule })
                    .height(Height.hit)
                    .padding({ left: Space.md, right: Space.md })
                    .fontSize(FontSize.bodySm)
                    .fontColor(this.autoUpdateHours === h
                      ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
                    .backgroundColor(this.autoUpdateHours === h
                      ? $r('app.color.accent') : $r('app.color.bg_chip'))
                    .margin({ right: Space.sm, bottom: Space.sm })
                    .onClick(() => {
                      this.setAutoUpdateHours(h);
                    })
                }, (h: number) => `${h}`)
              }
              .width('100%')
              .padding({ left: Space.md, right: Space.sm, bottom: Space.xs })
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: Space.xs, bottom: Space.xs })
        .backgroundColor($r('app.color.bg_surface_alt'))
        .borderRadius(Radius.panel)

        Text('维护')
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: Space.xs })
        Column() {
          EntryRow({
            title: '运行日志',
            detail: '查看与导出（已脱敏）；写入级别也在这里改',
            value: this.logLevel,
            onTap: () => this.nav('pages/Logs', '运行日志')
          })
          EntryRow({
            title: '备份与恢复',
            detail: '加密导出，含凭据需口令；换机、重装时用',
            onTap: () => this.nav('pages/Backup', '备份页')
          })
          // geo 不是导航，是一组动作：单独一块说明 + 两个按钮，避免伪装成可跳转行
          Column({ space: Space.sm }) {
            Column({ space: 2 }) {
              Text('分流资源')
                .fontSize(FontSize.bodyLg)
                .lineHeight(LineHeight.bodyLg)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
              Text(this.geoLabel)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Row({ space: Space.sm }) {
              Button(this.geoBusy ? '更新中…' : '联网更新')
                .layoutWeight(1)
                .height(Height.hit)
                .fontSize(FontSize.bodySm)
                .enabled(!this.geoBusy)
                .onClick(() => this.confirmGeoUpdate())
              Button('从本地导入')
                .layoutWeight(1)
                .height(Height.hit)
                .fontSize(FontSize.bodySm)
                .backgroundColor($r('app.color.bg_chip'))
                .fontColor($r('app.color.text_primary'))
                .enabled(!this.geoBusy)
                .onClick(() => this.doGeoImport())
            }
            .width('100%')

            if (this.geoMsg.length > 0) {
              Text(this.geoMsg)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.accent'))
                .width('100%')
            }
            Text('内置资源为 v2fly 官方构建。只有点「联网更新」才会联网（约 25 MB）；' +
              '访问不了 GitHub 时，可自行下载 geoip.dat + geosite.dat 后用「从本地导入」。')
              .fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.md })
        }
        .width('100%')
        .padding({ top: Space.xs, bottom: Space.xs })
        .backgroundColor($r('app.color.bg_surface_alt'))
        .borderRadius(Radius.panel)

        Text('关于')
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: Space.xs })
        Column() {
          EntryRow({
            title: '开源许可',
            detail: '第三方组件、MPL-2.0 义务、商标归属',
            onTap: () => this.nav('pages/Licenses', '许可页')
          })
          EntryRow({
            title: '开发者选项',
            detail: '失败路径探针、内核与应用状态；正常使用不用进来',
            onTap: () => this.nav('pages/DevPanel', '开发者面板')
          })
          EntryRow({
            title: '版本',
            detail: '内核 libXray v26.7.28',
            value: '骨架版本',
            showChevron: false,
            onTap: () => {
            }
          })
        }
        .width('100%')
        .padding({ top: Space.xs, bottom: Space.xs })
        .backgroundColor($r('app.color.bg_surface_alt'))
        .borderRadius(Radius.panel)

        // 危险区域：放在最底部，且必须写清"删掉什么、留什么"
        Column({ space: Space.sm }) {
          Text('清空会删除：全部节点、节点凭据、自定义规则、订阅记录、设置。' +
            '内核文件与 geo 数据不受影响；操作不可恢复，建议先做一次备份。')
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          EntryRow({
            title: this.clearing ? '清理中…' : '清空所有数据',
            danger: true,
            onTap: () => {
              if (!this.clearing) {
                this.confirmClearAll();
              }
            }
          })
          if (this.clearMsg.length > 0) {
            Text(this.clearMsg)
              .fontSize(FontSize.bodySm)
              .lineHeight(LineHeight.bodySm)
              .fontColor(this.clearMsgLevel === 2 ? $r('app.color.danger') : $r('app.color.accent'))
              .width('100%')
              .accessibilityText(`清空结果：${this.clearMsg}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(Space.md)
        .backgroundColor($r('app.color.danger_subtle'))
        .borderRadius(Radius.panel)
      }
      .width('100%')
      .padding(Space.md)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.bg_canvas'))
  }
}
