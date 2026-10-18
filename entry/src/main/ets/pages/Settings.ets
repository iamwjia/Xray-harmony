import { router } from '@kit.ArkUI';
import { ConfigService } from '../service/ConfigService';

/**
 * pages/Settings.ets — 设置（最小项：日志级别 / 关于）
 *
 * 结构约束：设置读写 ConfigService（L-A.settings），不直接碰平台 API。
 */
@Entry
@Component
struct Settings {
  @State logLevel: string = 'INFO';

  private cfg: ConfigService = ConfigService.getInstance();

  private levels: string[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];

  aboutToAppear(): void {
    this.logLevel = this.cfg.getLogLevel();
  }

  private setLevel(v: string): void {
    this.cfg.setLogLevel(v);
    this.logLevel = v;
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

      Column({ space: 4 }) {
        Text('关于').fontSize(14).fontWeight(FontWeight.Medium)
        Text('xray-harmony · 骨架版本').fontSize(12).fontColor('#666666')
        Text('内核：libXray v26.7.28（libxray.so）').fontSize(12).fontColor('#666666')
        Text('说明：当前未接入真实连接链路，所有网络行为在下一阶段接入。').fontSize(11).fontColor('#999999')
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
