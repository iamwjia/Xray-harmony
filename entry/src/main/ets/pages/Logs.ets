import { router } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { LogEntry, LogLevel, Logger } from '../platform/Logger';
import { common } from '@kit.AbilityKit';

/**
 * pages/Logs.ets — 运行日志查看与导出
 *
 * 为什么需要它：现在出问题只能"连电脑抓 hilog"，普通用户根本做不到，
 * 我们自己排查也要先让对方装 SDK。应用内能看到 + 能导出，是排查成本的分水岭。
 *
 * 两条安全约束：
 *   1. 缓冲区内容**在写入时已脱敏**（Logger.push 里做），页面只是展示；
 *   2. 导出用系统文件选择器让用户自己决定落点，应用不往公共目录私自写文件。
 */

interface LevelChip {
  label: string;
  value: string;
}

@Entry
@Component
struct Logs {
  @State entries: LogEntry[] = [];
  /** 空串 = 全部级别 */
  @State filter: string = '';
  @State msg: string = '';

  private chips: LevelChip[] = [
    { label: '全部', value: '' },
    { label: 'INFO', value: LogLevel.INFO },
    { label: 'WARN', value: LogLevel.WARN },
    { label: 'ERROR', value: LogLevel.ERROR }
  ];

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    const all: LogEntry[] = Logger.getEntries();
    if (this.filter.length === 0) {
      this.entries = all;
      return;
    }
    const out: LogEntry[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].level === this.filter) {
        out.push(all[i]);
      }
    }
    this.entries = out;
  }

  /** 导出：让用户选保存位置，而不是应用自己往公共目录写 */
  private doExport(): void {
    if (this.entries.length === 0) {
      this.msg = '当前没有可导出的日志';
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const report: string = Logger.buildReport();
    const ts: string = `${Date.now()}`;
    const p = new picker.DocumentViewPicker(ctx);
    const opts = new picker.DocumentSaveOptions();
    opts.newFileNames = [`tunnelix-log-${ts}.txt`];
    p.save(opts).then((uris: string[]) => {
      if (uris === undefined || uris.length === 0) {
        this.msg = '已取消导出';
        return;
      }
      try {
        const f = fileIo.openSync(uris[0],
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(f.fd, report);
        } finally {
          fileIo.closeSync(f);
        }
        this.msg = `已导出 ${this.entries.length} 条（内容已脱敏）`;
      } catch (e) {
        const m: string = e instanceof Error ? e.message : String(e);
        this.msg = `写入失败：${m}`;
      }
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.msg = `导出失败：${m}`;
    });
  }

  private levelColor(level: string): string {
    if (level === LogLevel.ERROR) {
      return '#C62828';
    }
    if (level === LogLevel.WARN) {
      return '#EF6C00';
    }
    if (level === LogLevel.DEBUG) {
      return '#888888';
    }
    return '#2E7D32';
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('返回').fontSize(12)
          .onClick(() => {
            router.back();
          })
        Text('运行日志').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text(`${this.entries.length} 条`).fontSize(11).fontColor('#999999')
      }
      .width('100%')

      Text('内容在写入时已脱敏（UUID / 分享链接 / 密码类字段替换为 ****）。上限 500 条，超出丢弃最旧。')
        .fontSize(10).fontColor('#999999').width('100%')

      Row({ space: 6 }) {
        ForEach(this.chips, (c: LevelChip) => {
          Button(c.label).fontSize(11)
            .backgroundColor(this.filter === c.value ? '#1976D2' : '#E0E0E0')
            .fontColor(this.filter === c.value ? '#FFFFFF' : '#333333')
            .onClick(() => {
              this.filter = c.value;
              this.reload();
            })
        }, (c: LevelChip) => c.label)
        Blank()
        Button('刷新').fontSize(11).onClick(() => this.reload())
        Button('清空').fontSize(11)
          .backgroundColor('#8D6E63')
          .onClick(() => {
            Logger.clear();
            this.reload();
            this.msg = '已清空缓冲（hilog 中的历史不受影响）';
          })
      }
      .width('100%')

      if (this.msg.length > 0) {
        Text(this.msg).fontSize(11).fontColor('#1976D2').width('100%')
      }

      if (this.entries.length === 0) {
        Text('暂无日志。触发一次连接或节点操作后再来看。')
          .fontSize(11).fontColor('#999999').width('100%')
      }

      List({ space: 4 }) {
        ForEach(this.entries, (e: LogEntry) => {
          ListItem() {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(e.level).fontSize(10).fontColor(this.levelColor(e.level))
                Text(e.time).fontSize(10).fontColor('#999999')
              }
              Text(e.msg).fontSize(11).fontColor('#333333')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(8)
            .backgroundColor('#FAFAFA')
            .borderRadius(6)
          }
        }, (e: LogEntry) => `${e.time}-${e.level}-${e.msg.length}`)
      }
      .layoutWeight(1)
      .width('100%')

      Button('导出为文本文件').width('100%').onClick(() => this.doExport())
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
