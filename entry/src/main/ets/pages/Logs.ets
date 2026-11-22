import { router, promptAction } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { LogEntry, LogLevel, Logger } from '../platform/Logger';
import { LastEndpoint, SocksGuard } from '../service/SocksGuard';
import { KernelService } from '../service/KernelService';
import { ConfigService } from '../service/ConfigService';
import { common } from '@kit.AbilityKit';
import { PageHeader } from '../components/PageHeader';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';

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
  /** 写入级别（控制"记不记"，与上面的"筛不筛"是两件事，必须分开说明） */
  @State writeLevel: string = 'INFO';
  @State levelPersistError: string = '';

  private levelOptions: string[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
  private cfg: ConfigService = ConfigService.getInstance();

  private chips: LevelChip[] = [
    { label: '全部', value: '' },
    { label: 'INFO', value: LogLevel.INFO },
    { label: 'WARN', value: LogLevel.WARN },
    { label: 'ERROR', value: LogLevel.ERROR }
  ];

  aboutToAppear(): void {
    this.reload();
    this.writeLevel = this.cfg.getLogLevel();
  }

  private setWriteLevel(v: string): void {
    const ok: boolean = this.cfg.setLogLevel(v);
    this.writeLevel = this.cfg.getLogLevel();
    this.levelPersistError = ok ? '' : this.cfg.getPersistError();
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

  /**
   * 代理端点的三态文案。
   * 关键是第二态：**已断开但仍显示最近一次的地址**——用户报障几乎都发生在断开之后，
   * 那时候查不到端口，等于把唯一的线索删掉。
   */
  private endpointText(): string {
    const ep: LastEndpoint | null = SocksGuard.lastEndpoint();
    if (ep === null) {
      return '暂无代理地址记录（本次启动未连接过）';
    }
    if (KernelService.getInstance().isRunning()) {
      return `当前代理地址 ${ep.host}:${ep.port} · 长按复制`;
    }
    return `最近一次代理地址 ${ep.host}:${ep.port}（已断开）· 长按复制`;
  }

  /** 复制：内容严格等于 host:port，不带括号与说明文字 */
  private copyEndpoint(): void {
    const ep: LastEndpoint | null = SocksGuard.lastEndpoint();
    if (ep === null) {
      return;
    }
    const text: string = `${ep.host}:${ep.port}`;
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '已复制', duration: 1500 });
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.msg = `复制失败：${m}`;
    });
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

  private levelColor(level: string): Resource {
    if (level === LogLevel.ERROR) {
      return $r('app.color.danger');
    }
    if (level === LogLevel.WARN) {
      return $r('app.color.warning');
    }
    if (level === LogLevel.DEBUG) {
      return $r('app.color.text_tertiary');
    }
    return $r('app.color.success');
  }

  @Builder
  chip(label: string, value: string) {
    // 同 Nodes：可点元素用 Button，手机上才有按下反馈（Text 只有 onClick）
    Button(label, { type: ButtonType.Capsule })
      .height(Height.hit)
      .padding({ left: Space.lg, right: Space.lg })
      .fontSize(FontSize.bodySm)
      .fontColor(this.filter === value
        ? $r('app.color.text_on_accent')
        : $r('app.color.text_secondary'))
      .backgroundColor(this.filter === value
        ? $r('app.color.accent')
        : $r('app.color.bg_chip'))
      .accessibilityText(this.filter === value ? `${label}，当前筛选` : label)
      .onClick(() => {
        this.filter = value;
        this.reload();
      })
  }

  build() {
    Column({ space: 0 }) {
      Column() {
        PageHeader({
          title: '运行日志',
          countText: `${this.entries.length} 条`,
          onBack: () => {
            router.back();
          }
        })
      }
      .width('100%')

      Column({ space: Space.xs }) {
        Text('内容在写入时已脱敏（UUID / 分享链接 / 密码类字段替换为 ****）。上限 500 条，超出丢弃最旧。')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')

        // 诊断行：层级低于标题与筛选，但端口必须可读、可复制
        Text(this.endpointText())
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .accessibilityText(`${this.endpointText()}，长按可复制`)
          .gesture(
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => {
                this.copyEndpoint();
              })
          )
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })

      // 写入级别：从设置页搬过来的。它属于日志，放在这里用户才看得懂
      // "为什么我没看到某某日志"——要么被级别挡住、要么被筛选挡住。
      // 用卡片包起来，是为了和下面那条"筛选"胶囊行在视觉上分层：一个是设置，一个是筛选。
      Column({ space: Space.sm }) {
        Row({ space: Space.sm }) {
          Text('记录级别')
            .fontSize(FontSize.bodySm)
            .lineHeight(LineHeight.bodySm)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
          Text('低于该级别不写入；下面那条只是筛选已记录的')
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: Space.sm }) {
          ForEach(this.levelOptions, (lv: string) => {
            Button(lv, { type: ButtonType.Capsule })
              .layoutWeight(1)
              .padding({ left: 0, right: 0 })
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor(lv === this.writeLevel ? $r('app.color.accent') : $r('app.color.bg_chip'))
              .fontColor(lv === this.writeLevel ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
              .onClick(() => {
                this.setWriteLevel(lv);
              })
          }, (lv: string) => lv)
        }
        .width('100%')

        if (this.levelPersistError.length > 0) {
          Text(this.levelPersistError)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.warning'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(Space.md)
      .margin({ left: Space.lg, right: Space.lg, bottom: Space.sm })
      .backgroundColor($r('app.color.bg_surface_alt'))
      .borderRadius(Radius.panel)

      // 筛选行：只筛"已经记下来的"，与上面的记录级别是两件事
      Scroll() {
        Row({ space: Space.sm }) {
          ForEach(this.chips, (c: LevelChip) => {
            this.chip(c.label, c.value)
          }, (c: LevelChip) => c.label)
          this.actionChip('刷新', () => this.reload())
          this.actionChip('清空', () => {
            Logger.clear();
            this.reload();
            this.msg = '已清空缓冲（hilog 中的历史不受影响）';
          })
        }
        .padding({ left: Space.lg, right: Space.lg })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ bottom: Space.sm })

      if (this.msg.length > 0) {
        Text(this.msg)
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.accent'))
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })
      }

      if (this.entries.length === 0) {
        Column({ space: Space.sm }) {
          Text('暂无日志')
            .fontSize(FontSize.titleMd)
            .lineHeight(LineHeight.titleMd)
            .fontColor($r('app.color.text_secondary'))
          Text('触发一次连接或节点操作后再来看')
            .fontSize(FontSize.bodySm)
            .lineHeight(LineHeight.bodySm)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: Space.xs }) {
          ForEach(this.entries, (e: LogEntry) => {
            ListItem() {
              Column({ space: Space.xxs }) {
                Row({ space: Space.xs }) {
                  Text(e.level)
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.levelColor(e.level))
                  Text(e.time)
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontColor($r('app.color.text_tertiary'))
                }
                Text(e.msg)
                  .fontSize(FontSize.caption)
                  .lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(Space.sm)
              .backgroundColor($r('app.color.bg_surface_alt'))
              .borderRadius(Radius.chip)
            }
          }, (e: LogEntry) => `${e.time}-${e.level}-${e.msg.length}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg })
        .scrollBar(BarState.Off)
      }

      // 底部动作条统一规格：外层 padding（左右 16 / 上 8 / 下 12）+ 内层按钮撑满。
      // 早先这里是 width('100%') + margin：margin 加在 100% 宽度外侧，按钮被撑出屏幕、
      // 两侧边距实际不生效，看起来"贴着屏幕边"，与其它页的底部条不一致。
      Row() {
        Button(this.entries.length === 0 ? '导出（暂无日志）' : '导出')
          .accessibilityText('导出日志为文本文件')
          .width('100%')
          .height(Height.hit)
          .fontSize(FontSize.bodySm)
          .enabled(this.entries.length > 0)
          // 禁用时必须看着"不能点"：自定义背景色的按钮不会自动变灰
          .backgroundColor(this.entries.length > 0 ? $r('app.color.accent') : $r('app.color.bg_chip'))
          .fontColor(this.entries.length > 0 ? $r('app.color.text_on_accent') : $r('app.color.text_tertiary'))
          .onClick(() => this.doExport())
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.md })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_canvas'))
  }

  @Builder
  actionChip(label: string, action: () => void) {
    Button(label, { type: ButtonType.Capsule })
      .height(Height.hit)
      .padding({ left: Space.lg, right: Space.lg })
      .fontSize(FontSize.bodySm)
      .fontColor($r('app.color.text_primary'))
      .backgroundColor($r('app.color.bg_chip'))
      .onClick(() => {
        action();
      })
  }
}
