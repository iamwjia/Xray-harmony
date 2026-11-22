import { router, promptAction } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { LogEntry, LogLevel, Logger } from '../platform/Logger';
import { LastEndpoint, SocksGuard } from '../service/SocksGuard';
import { KernelService } from '../service/KernelService';
import { ConfigService } from '../service/ConfigService';
import { common } from '@kit.AbilityKit';
import { PageHeader } from '../components/PageHeader';
import { IconButton } from '../components/Glyph';
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
  /** 缓冲里的总数（未筛选）；筛选时与 entries.length 一起显示 */
  @State allCount: number = 0;
  /** 下拉刷新中：与节点/订阅页同一套手势，不再单独放刷新按钮 */
  @State refreshing: boolean = false;
  /** 空串 = 全部级别 */
  @State filter: string = '';
  @State msg: string = '';
  /** 写入级别（控制"记不记"，与上面的"筛不筛"是两件事，必须分开说明） */
  @State writeLevel: string = 'INFO';
  @State levelPersistError: string = '';

  private levelOptions: string[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
  private cfg: ConfigService = ConfigService.getInstance();

  private chips: LevelChip[] = [
    // 语义：全部 = 不筛；其余 = "该级别及以上"。
    // 所以不需要 DEBUG 选项——"DEBUG 及以上"就是全部，留着是两个等价项。
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

  /** 级别权重：用于"该级别及以上"的筛选 */
  private static rank(level: string): number {
    if (level === LogLevel.DEBUG) {
      return 0;
    }
    if (level === LogLevel.INFO) {
      return 1;
    }
    return level === LogLevel.WARN ? 2 : 3;
  }

  private reload(): void {
    const all: LogEntry[] = Logger.getEntries();
    this.allCount = all.length;
    if (this.filter.length === 0) {
      this.entries = all;
      return;
    }
    // 阈值匹配（该级别及以上）：与"写入级别"同一套直觉。
    // 精确匹配时选 INFO 只能看到 INFO，用户会以为 WARN/ERROR 丢了。
    const min: number = Logs.rank(this.filter);
    const out: LogEntry[] = [];
    for (let i = 0; i < all.length; i++) {
      if (Logs.rank(all[i].level) >= min) {
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
  /** 清空前的确认：日志是排障凭据，误点一次就没了 */
  private confirmClear(): void {
    AlertDialog.show({
      title: '清空运行日志',
      message: '将删除应用内缓冲的全部日志（当前 ' + this.allCount + ' 条）。\n\n' +
        '不会删除：hilog 中的系统日志、已导出的文本文件。\n此操作不可恢复。',
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
          Logger.clear();
          this.reload();
          this.msg = '已清空缓冲（hilog 中的历史不受影响）';
        }
      }
    });
  }

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
  textAction(label: string, action: () => void) {
    Text(label)
      .fontSize(FontSize.bodySm)
      .lineHeight(LineHeight.bodySm)
      .fontColor($r('app.color.accent'))
      .padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.xs })
      .onClick(() => {
        action();
      })
      .accessibilityText(label)
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
          // 筛选时写"筛选后/总数"：只写一个数字会让人以为日志被清掉了
          countText: this.filter.length > 0
            ? `${this.entries.length} / ${this.allCount} 条`
            : `${this.entries.length} 条`,
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
          Text('写入级别')
            .fontSize(FontSize.bodySm)
            .lineHeight(LineHeight.bodySm)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
          Text('设置项 · 低于该级别不写入')
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
      .backgroundColor($r('app.color.bg_surface'))
      .borderRadius(Radius.panel)
      // 加描边：浅色下 bg_surface_alt 与画布几乎同色，卡片"存在感"太弱，
      // 用户看不出"这是设置块"还是"这是列表开头"
      .border({ width: 1, color: $r('app.color.border_subtle') })

      // 筛选行：只筛"已经记下来的"，与上面的写入级别是两件事。
      // 两组控件长得一样（胶囊），必须各带一行标题才不会混——用户原话："没有明显的分类提示"。
      Row({ space: Space.xs }) {
        Text('筛选')
          .fontSize(FontSize.bodySm)
          .lineHeight(LineHeight.bodySm)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text('该级别及以上；只影响显示，不改写入')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
        // 动作放标题行右侧：它们是"刷新/清空"，与"筛选项"不是一类，
        // 混在同一排胶囊里会出现 6 个宽窄不一的块，用户会问"为什么大小不一样"
        // 保留一个显式的「刷新」入口：下拉刷新在模拟器上注入手势不生效（hilog 无记录），
        // 真机能否触发需人眼确认；在确认之前，不能只留一个"可能不工作"的手势。
        this.textAction('刷新', () => this.reload())
        this.textAction('清空', () => {
          this.confirmClear();
        })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, bottom: Space.xs })

      Row({ space: Space.sm }) {
        ForEach(this.chips, (c: LevelChip) => {
          Button(c.label, { type: ButtonType.Capsule })
            .layoutWeight(1)
            .padding({ left: 0, right: 0 })
            .height(Height.hit)
            .fontSize(FontSize.bodySm)
            .backgroundColor(this.filter === c.value ? $r('app.color.accent') : $r('app.color.bg_chip'))
            .fontColor(this.filter === c.value
              ? $r('app.color.text_on_accent') : $r('app.color.text_secondary'))
            .accessibilityText(this.filter === c.value ? `${c.label}，当前筛选` : c.label)
            .onClick(() => {
              this.filter = c.value;
              this.reload();
            })
        }, (c: LevelChip) => c.label)
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })

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
        // 下拉刷新：与节点/订阅页同一套手势。列表页的"刷新"做成按钮属于桌面习惯，
        // 手机上手指本来就在列表上，下拉更省一次定位。
        Refresh({ refreshing: $$this.refreshing }) {
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
          .width('100%')
          .height('100%')
          .padding({ left: Space.lg, right: Space.lg })
          .scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing(() => {
          Logger.info('logs pull-refresh');
          this.reload();
          setTimeout(() => {
            this.refreshing = false;
          }, 300);
        })
      }

      // 底部动作条统一规格：外层 padding（左右 16 / 上 8 / 下 12）+ 内层按钮撑满。
      // 早先这里是 width('100%') + margin：margin 加在 100% 宽度外侧，按钮被撑出屏幕、
      // 两侧边距实际不生效，看起来"贴着屏幕边"，与其它页的底部条不一致。
      Row() {
        IconButton({
          kind: 'export',
          label: this.entries.length === 0 ? '导出（暂无日志）' : '导出',
          variant: 'primary',
          enabledState: this.entries.length > 0,
          onTap: () => this.doExport()
        })
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
