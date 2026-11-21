import { router } from '@kit.ArkUI';
import { ConfigService } from '../service/ConfigService';
import { RoutingMode } from '../model/AppConfig';
import { GeoAssets } from '../service/GeoAssets';
import { KernelService } from '../service/KernelService';
import { common } from '@kit.AbilityKit';

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
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Button('返回').fontSize(12)
          .onClick(() => {
            router.back();
          })
        Text('设置').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
      }
      .width('100%')

      // 设置写盘失败横幅：必须可见，否则用户会以为设置已生效
      if (this.persistError.length > 0) {
        Text(this.persistError)
          .fontSize(12)
          .fontColor('#8D6E63')
          .width('100%')
          .padding(10)
          .backgroundColor('#FFF3E0')
          .borderRadius(8)
      }

      Column({ space: 8 }) {
        Text('日志级别').fontSize(14).fontWeight(FontWeight.Medium)
        Row({ space: 8 }) {
          ForEach(this.levels, (lv: string) => {
            Button(lv).fontSize(12)
              .backgroundColor(lv === this.logLevel ? '#1976D2' : '#E0E0E0')
              .fontColor(lv === this.logLevel ? '#FFFFFF' : '#333333')
              .onClick(() => this.setLevel(lv))
          }, (lv: string) => lv)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .backgroundColor('#FAFAFA')
      .borderRadius(8)

      Column({ space: 8 }) {
        Text('分流模式').fontSize(14).fontWeight(FontWeight.Medium)
        Row({ space: 8 }) {
          Button('全局').fontSize(12)
            .backgroundColor(this.routingMode === RoutingMode.GLOBAL ? '#1976D2' : '#E0E0E0')
            .fontColor(this.routingMode === RoutingMode.GLOBAL ? '#FFFFFF' : '#333333')
            .onClick(() => this.setRouting(RoutingMode.GLOBAL))
          Button('规则').fontSize(12)
            .backgroundColor(this.routingMode === RoutingMode.RULE ? '#1976D2' : '#E0E0E0')
            .fontColor(this.routingMode === RoutingMode.RULE ? '#FFFFFF' : '#333333')
            .onClick(() => this.setRouting(RoutingMode.RULE))
          Button('直连').fontSize(12)
            .backgroundColor(this.routingMode === RoutingMode.DIRECT ? '#1976D2' : '#E0E0E0')
            .fontColor(this.routingMode === RoutingMode.DIRECT ? '#FFFFFF' : '#333333')
            .onClick(() => this.setRouting(RoutingMode.DIRECT))
        }
        Text('规则：国内域名/IP 与内网直连，其余走代理（依赖下方 geo 资源；资源不可用时降级为仅内网直连）')
          .fontSize(10).fontColor('#999999')
        Divider()
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('自定义规则').fontSize(13)
            Text(`已启用 ${this.ruleCount} 条；先于内置国内直连规则匹配`)
              .fontSize(10).fontColor('#999999')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('管理').fontSize(12)
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
            Text('运行日志').fontSize(13)
            Text('查看应用内日志并导出（已脱敏）；出问题时用这个代替连电脑抓 hilog')
              .fontSize(10).fontColor('#999999')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('查看').fontSize(12)
            .onClick(() => {
              router.pushUrl({ url: 'pages/Logs' }).catch((e: Error) => {
                this.persistError = `打开日志页失败：${e.message}`;
              });
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .backgroundColor('#FAFAFA')
      .borderRadius(8)
      Column({ space: 4 }) {
        Text('关于').fontSize(14).fontWeight(FontWeight.Medium)
        Text('Tunnelix · 骨架版本').fontSize(12).fontColor('#666666')
        Text('内核：libXray v26.7.28（libxray.so）').fontSize(12).fontColor('#666666')
        Text(`分流资源：${this.geoLabel}`).fontSize(12).fontColor('#666666')
        Row({ space: 8 }) {
          Button(this.geoBusy ? '更新中…' : '联网更新（约 25 MB）')
            .fontSize(12)
            .enabled(!this.geoBusy)
            .onClick(() => this.confirmGeoUpdate())
          Button('从本地文件导入')
            .fontSize(12)
            .enabled(!this.geoBusy)
            .backgroundColor('#607D8B')
            .onClick(() => this.doGeoImport())
        }
        if (this.geoMsg.length > 0) {
          Text(this.geoMsg).fontSize(11).fontColor('#1976D2')
        }
        Text('说明：内置资源为 v2fly 官方构建。只有点上面按钮才会联网；访问不了 GitHub 时，' +
          '可自行下载 geoip.dat + geosite.dat（或含两者的 zip）后用「从本地文件导入」，全程不联网。')
          .fontSize(11).fontColor('#999999')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .backgroundColor('#FAFAFA')
      .borderRadius(8)

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
