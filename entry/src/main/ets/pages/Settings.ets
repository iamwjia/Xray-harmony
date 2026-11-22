import { router } from '@kit.ArkUI';
import { ConfigService } from '../service/ConfigService';
import { RoutingMode } from '../model/AppConfig';
import { GeoAssets } from '../service/GeoAssets';
import { KernelService } from '../service/KernelService';
import { common } from '@kit.AbilityKit';
import { PageHeader } from '../components/PageHeader';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';

/**
 * pages/Settings.ets — 设置（最小项：日志级别 / 关于）
 *
 * 结构约束：设置读写 ConfigService（L-A.settings），不直接碰平台 API。
 */
@Entry
@Component
struct Settings {
  @State logLevel: string = 'INFO';
  @State routingMode: RoutingMode = RoutingMode.RULE;
  /** 设置写盘失败提示（不允许"看着改了其实没存"） */
  @State persistError: string = '';
  /** geo 资源版本（未就绪时明确显示"不可用"，不要显示空串让人以为正常） */
  @State geoLabel: string = '';
  /** geo 手动更新状态 */
  @State geoBusy: boolean = false;
  @State geoMsg: string = '';
  /** 自定义规则条数（启用中） */
  @State ruleCount: number = 0;

  private cfg: ConfigService = ConfigService.getInstance();

  private levels: string[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];

  aboutToAppear(): void {
    this.routingMode = this.cfg.getConfig().settings.routingMode;
    this.logLevel = this.cfg.getLogLevel();
    this.geoLabel = GeoAssets.isReady() ? `${GeoAssets.getVersion()}（规则模式下国内直连生效）` : '未就绪（规则模式已降级为仅内网直连）';
    this.refreshRuleCount();
  }

  /** 从规则页返回时刷新计数（同 @Watch 不生效的场景） */
  onPageShow(): void {
    this.refreshRuleCount();
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

  private setRouting(mode: RoutingMode): void {
    const ok: boolean = this.cfg.setRoutingMode(mode);
    // 写盘失败时 ConfigService 已把内存值回滚，这里必须读回真实值，否则 UI 会显示"改了但没存"
    this.routingMode = this.cfg.getConfig().settings.routingMode;
    this.persistError = ok ? '' : this.cfg.getPersistError();
  }

  private setLevel(v: string): void {
    const ok: boolean = this.cfg.setLogLevel(v);
    this.logLevel = this.cfg.getLogLevel();
    this.persistError = ok ? '' : this.cfg.getPersistError();
  }

  /**
   * geo 手动更新。点击前必须弹确认：这是在**用用户的流量**下载约 25 MB，
   * 不能做成"点了就开始下、下完才告诉用户"。
   */
  private confirmGeoUpdate(): void {
    AlertDialog.show({
      title: '更新分流规则',
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
      this.geoLabel = GeoAssets.isReady()
        ? `${GeoAssets.getVersion()}（规则模式下国内直连生效）`
        : this.geoLabel;
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
      this.geoLabel = GeoAssets.isReady()
        ? `${GeoAssets.getVersion()}（规则模式下国内直连生效）`
        : this.geoLabel;
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

  build() {
    // 可滚：设置项已经多到一屏放不下，包在 Column 里会把底部（geo / 开发者选项）裁掉，
    // 那样"入口存在但点不到"比没有入口更糟。
    Scroll() {
      Column({ space: 16 }) {
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
          .borderRadius(Radius.panel).lineHeight(LineHeight.bodySm)
      }

      Column({ space: 8 }) {
        Text('日志级别').fontSize(FontSize.body).fontWeight(FontWeight.Medium).maxLines(1)
        Row({ space: 8 }) {
          ForEach(this.levels, (lv: string) => {
            Button(lv).fontSize(FontSize.bodySm)
              .backgroundColor(lv === this.logLevel ? $r('app.color.accent') : $r('app.color.bg_chip'))
              .fontColor(lv === this.logLevel ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
              .onClick(() => this.setLevel(lv))
          }, (lv: string) => lv)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(Space.md)
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(Radius.panel)

      Column({ space: 8 }) {
        Text('分流模式').fontSize(FontSize.body).fontWeight(FontWeight.Medium).maxLines(1)
        Row({ space: 8 }) {
          Button('全局').fontSize(FontSize.bodySm)
            .backgroundColor(this.routingMode === RoutingMode.GLOBAL ? $r('app.color.accent') : $r('app.color.bg_chip'))
            .fontColor(this.routingMode === RoutingMode.GLOBAL ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
            .onClick(() => this.setRouting(RoutingMode.GLOBAL))
          Button('规则').fontSize(FontSize.bodySm)
            .backgroundColor(this.routingMode === RoutingMode.RULE ? $r('app.color.accent') : $r('app.color.bg_chip'))
            .fontColor(this.routingMode === RoutingMode.RULE ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
            .onClick(() => this.setRouting(RoutingMode.RULE))
          Button('直连').fontSize(FontSize.bodySm)
            .backgroundColor(this.routingMode === RoutingMode.DIRECT ? $r('app.color.accent') : $r('app.color.bg_chip'))
            .fontColor(this.routingMode === RoutingMode.DIRECT ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
            .onClick(() => this.setRouting(RoutingMode.DIRECT))
        }
        Text('规则：国内域名/IP 与内网直连，其余走代理（依赖下方 geo 资源；资源不可用时降级为仅内网直连）')
          .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
        Divider()
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('自定义规则').fontSize(FontSize.bodySm).maxLines(1)
            Text(`已启用 ${this.ruleCount} 条；先于内置国内直连规则匹配`)
              .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('管理').fontSize(FontSize.bodySm)
            .onClick(() => {
              router.pushUrl({ url: 'pages/RoutingRules' }).catch((e: Error) => {
                this.persistError = `打开规则页失败：${e.message}`;
              });
            })
        }
        .width('100%')
        Divider()
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('运行日志').fontSize(FontSize.bodySm).maxLines(1)
            Text('查看应用内日志并导出（已脱敏）；出问题时用这个代替连电脑抓 hilog')
              .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('查看').fontSize(FontSize.bodySm)
            .onClick(() => {
              router.pushUrl({ url: 'pages/Logs' }).catch((e: Error) => {
                this.persistError = `打开日志页失败：${e.message}`;
              });
            })
        }
        .width('100%')
        Divider()
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('开源许可').fontSize(FontSize.bodySm).maxLines(1)
            Text('第三方组件、MPL-2.0 义务、商标归属与源码获取方式')
              .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('查看').fontSize(FontSize.bodySm)
            .onClick(() => {
              router.pushUrl({ url: 'pages/Licenses' }).catch((e: Error) => {
                this.persistError = `打开许可页失败：${e.message}`;
              });
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(Space.md)
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(Radius.panel)
      Column({ space: 4 }) {
        Text('关于').fontSize(FontSize.body).fontWeight(FontWeight.Medium).maxLines(1)
        Text('Tunnelix · 骨架版本').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).lineHeight(LineHeight.bodySm)
        Text('内核：libXray v26.7.28（libxray.so）').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).lineHeight(LineHeight.bodySm)
        Text(`分流资源：${this.geoLabel}`).fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).lineHeight(LineHeight.bodySm)
        Row({ space: 8 }) {
          Button(this.geoBusy ? '更新中…' : '联网更新（约 25 MB）')
            .fontSize(FontSize.bodySm)
            .enabled(!this.geoBusy)
            .onClick(() => this.confirmGeoUpdate())
          Button('从本地文件导入')
            .fontSize(FontSize.bodySm)
            .enabled(!this.geoBusy)
            .backgroundColor($r('app.color.bg_chip'))
            .onClick(() => this.doGeoImport())
        }
        if (this.geoMsg.length > 0) {
          Text(this.geoMsg).fontSize(FontSize.caption).fontColor($r('app.color.accent')).lineHeight(LineHeight.caption)
        }
        Text('说明：内置资源为 v2fly 官方构建。只有点上面按钮才会联网；访问不了 GitHub 时，' +
          '可自行下载 geoip.dat + geosite.dat（或含两者的 zip）后用「从本地文件导入」，全程不联网。')
          .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(Space.md)
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(Radius.panel)

      Column({ space: 4 }) {
        Text('开发者选项')
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium).maxLines(1)
        Text('失败路径探针、内核与应用状态。正常使用不需要进来。')
          .fontSize(FontSize.bodySm)
          .fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.bodySm)
        Button('打开开发者面板')
          .fontSize(FontSize.bodySm)
          .width('100%')
          .onClick(() => {
            router.pushUrl({ url: 'pages/DevPanel' }).catch((e: Error) => {
              this.persistError = `打开开发者面板失败：${e.message}`;
            });
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(Space.md)
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(Radius.panel)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.bg_canvas'))
  }
}
