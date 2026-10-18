import { router } from '@kit.ArkUI';
import { ConfigService } from '../service/ConfigService';
import { RoutingMode } from '../model/AppConfig';
import { GeoAssets } from '../service/GeoAssets';

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
  /** 设置写盘失败提示（FR-44：不允许"看着改了其实没存"） */
  @State persistError: string = '';
  /** geo 资源版本（未就绪时明确显示"不可用"，不要显示空串让人以为正常） */
  @State geoLabel: string = '';

  private cfg: ConfigService = ConfigService.getInstance();

  private levels: string[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];

  aboutToAppear(): void {
    this.routingMode = this.cfg.getConfig().settings.routingMode;
    this.logLevel = this.cfg.getLogLevel();
    this.geoLabel = GeoAssets.isReady() ? `${GeoAssets.getVersion()}（规则模式下国内直连生效）` : '未就绪（规则模式已降级为仅内网直连）';
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
        Text('规则：内网/回环直连，其余走代理（geo 规则待内置资源后补齐）').fontSize(10).fontColor('#999999')
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
        Text('说明：内置 geo 资源为 v2fly 官方构建；规则随版本更新，需发版才会变化（不做后台自动下载）。')
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
