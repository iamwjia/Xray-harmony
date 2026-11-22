import { router } from '@kit.ArkUI';
import { ClearResult, ConfigService } from '../service/ConfigService';
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

  private cfg: ConfigService = ConfigService.getInstance();

  private levels: string[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];

  aboutToAppear(): void {
    this.routingMode = this.cfg.getConfig().settings.routingMode;
    this.logLevel = this.cfg.getLogLevel();
    this.geoLabel = GeoAssets.isReady() ? `${GeoAssets.getVersion()}（规则模式下国内直连生效）` : '未就绪（规则模式已降级为仅内网直连）';
    this.refreshRuleCount();
    this.autoUpdateSubs = this.cfg.getConfig().settings.autoUpdateSubs;
    this.autoUpdateHours = this.cfg.getConfig().settings.autoUpdateHours;
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
    }).catch((e: Object) => {
      this.clearing = false;
      this.clearMsgLevel = 2;
      const m: string = e instanceof Error ? e.message : String(e);
      this.clearMsg = `清空失败：${m}`;
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
            Text('订阅管理').fontSize(FontSize.bodySm).maxLines(1)
            Text('已添加的订阅、上次更新时间；可单独更新或删除（删订阅不删已导入的节点）')
              .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('管理').fontSize(FontSize.bodySm)
            .onClick(() => {
              router.pushUrl({ url: 'pages/Subscriptions' }).catch((e: Error) => {
                this.persistError = `打开订阅管理失败：${e.message}`;
              });
            })
        }
        .width('100%')
        Divider()
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('备份与恢复').fontSize(FontSize.bodySm).maxLines(1)
            Text('导出加密备份文件（含凭据，需口令）；换机、重装或分享给别人时用')
              .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('打开').fontSize(FontSize.bodySm)
            .onClick(() => {
              router.pushUrl({ url: 'pages/Backup' }).catch((e: Error) => {
                this.persistError = `打开备份页失败：${e.message}`;
              });
            })
        }
        .width('100%')
        Divider()
        Column({ space: Space.sm }) {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text('自动更新订阅').fontSize(FontSize.bodySm).maxLines(1)
              Text('开启后，进入应用时若超过间隔会提示更新（不会静默联网）')
                .fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoUpdateSubs })
              .onChange((on: boolean) => {
                this.setAutoUpdate(on);
              })
          }
          .width('100%')

          if (this.autoUpdateSubs) {
            Row({ space: Space.sm }) {
              ForEach([6, 12, 24, 168], (h: number) => {
                Text(h === 168 ? '每周' : `每 ${h} 小时`)
                  .height(Height.hit)
                  .padding({ left: Space.md, right: Space.md })
                  .fontSize(FontSize.bodySm)
                  .fontColor(this.autoUpdateHours === h
                    ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
                  .backgroundColor(this.autoUpdateHours === h
                    ? $r('app.color.accent') : $r('app.color.bg_chip'))
                  .borderRadius(Radius.pill)
                  .maxLines(1)
                  .onClick(() => {
                    this.setAutoUpdateHours(h);
                  })
              }, (h: number) => `${h}`)
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
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

      // 危险区域：放在最底部，且必须写清"删掉什么、留什么"
      Column({ space: 4 }) {
        Text('危险操作')
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium).maxLines(1)
          .fontColor($r('app.color.danger'))
        Text('清空会删除：全部节点、节点凭据、自定义规则、订阅记录、设置。' +
          '内核文件与 geo 数据不受影响；操作不可恢复，建议先做一次备份。')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_secondary'))
        Button(this.clearing ? '清理中…' : '清空所有数据')
          .fontSize(FontSize.bodySm)
          .width('100%')
          .height(Height.hit)
          .backgroundColor($r('app.color.danger_subtle'))
          .fontColor($r('app.color.danger'))
          .enabled(!this.clearing)
          .onClick(() => this.confirmClearAll())
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
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.bg_canvas'))
  }
}
