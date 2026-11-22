import { router, promptAction } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { PageHeader } from '../components/PageHeader';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';
import { ConfigBundle, BundleImportResult } from '../service/ConfigBundle';
import { BundleCrypto } from '../platform/BundleCrypto';
import { Logger } from '../platform/Logger';

/**
 * pages/Backup.ets — 配置备份与恢复
 *
 * 一份文件、一个口令：文件可以随便传（网盘、微信、邮件），口令另走一条渠道。
 * 页面上必须把三件事说清楚，否则用户会在最坏的时刻才发现：
 *   1. 口令忘了就打不开，没有找回；
 *   2. 口令要**另发**，跟文件同一条消息发过去等于没加密；
 *   3. 恢复只加不覆盖：不改本机分流模式与日志级别，同地址节点自动跳过。
 */
@Entry
@Component
struct Backup {
  // ---- 导出 ----
  @State exportPass: string = '';
  @State exportPass2: string = '';
  @State exporting: boolean = false;
  @State exportMsg: string = '';
  @State exportMsgLevel: number = 0;

  // ---- 导入 ----
  @State importText: string = '';
  @State importName: string = '';
  @State importPass: string = '';
  @State importing: boolean = false;
  @State importMsg: string = '';
  @State importMsgLevel: number = 0;
  /** 文件头摘要：选完文件先给用户看"这是几个节点、什么时候导的" */
  @State importSummary: string = '';

  private msgColor(level: number): Resource {
    if (level === 2) {
      return $r('app.color.danger');
    }
    if (level === 1) {
      return $r('app.color.warning');
    }
    return $r('app.color.accent');
  }

  private setExportMsg(text: string, level: number): void {
    this.exportMsg = text;
    this.exportMsgLevel = level;
  }

  private setImportMsg(text: string, level: number): void {
    this.importMsg = text;
    this.importMsgLevel = level;
  }

  /** 生成并保存：先加密，再让用户选落点（应用不往公共目录私自写） */
  /**
   * 生成一个高熵口令。
   *
   * 为什么不让用户自己想：这个口令**只用一次**（导出时设、恢复时输），
   * 用户没有动机记住它，也就没有动机把它想得够强——人手输的口令大多是
   * 同一串字符换个顺序，直接生成反而更安全。
   */
  private generatePassphrase(): void {
    const alphabet: string = 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    const bytes: Uint8Array = BundleCrypto.randomBytes(20);
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      out += alphabet.charAt(bytes[i] % alphabet.length);
    }
    this.exportPass = out;
    this.exportPass2 = out;
    this.setExportMsg('已生成随机口令：先导出文件，再把口令另发一条消息', 0);
  }

  private doExport(): void {
    const weak: string = BundleCrypto.weaknessHint(this.exportPass);
    if (weak.length > 0) {
      this.setExportMsg(weak, 1);
      return;
    }
    if (this.exportPass !== this.exportPass2) {
      this.setExportMsg('两次输入的口令不一致', 1);
      return;
    }
    this.exporting = true;
    this.setExportMsg('正在生成…', 0);
    ConfigBundle.exportToText(this.exportPass).then((text: string) => {
      const ctx = getContext(this) as common.UIAbilityContext;
      const p = new picker.DocumentViewPicker(ctx);
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`tunnelix-backup-${Date.now()}.tunnelixbak`];
      return p.save(opts).then((uris: string[]) => {
        this.exporting = false;
        if (uris === undefined || uris.length === 0) {
          this.setExportMsg('已取消保存', 1);
          return;
        }
        try {
          const f = fileIo.openSync(uris[0],
            fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          try {
            fileIo.writeSync(f.fd, text);
          } finally {
            fileIo.closeSync(f);
          }
          this.setExportMsg('已导出。请把口令另发（别和文件放在同一条消息里）。', 0);
          this.exportPass = '';
          this.exportPass2 = '';
        } catch (e) {
          const m: string = e instanceof Error ? e.message : String(e);
          this.setExportMsg(`写入失败：${m}`, 2);
        }
      });
    }).catch((e: Object) => {
      this.exporting = false;
      const m: string = e instanceof Error ? e.message : String(e);
      this.setExportMsg(m, 2);
      Logger.error(`bundle export failed: ${m}`);
    });
  }

  /** 选文件 + 先看文件头（不解密），避免用户对着一个不相关的文件输口令 */
  private pickImportFile(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    const p = new picker.DocumentViewPicker(ctx);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    p.select(opts).then((uris: string[]) => {
      if (uris === undefined || uris.length === 0) {
        return;
      }
      try {
        const f = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
        let text: string = '';
        try {
          const stat = fileIo.statSync(f.fd);
          const buf = new ArrayBuffer(stat.size);
          fileIo.readSync(f.fd, buf);
          text = new util.TextDecoder().decodeToString(new Uint8Array(buf));
        } finally {
          fileIo.closeSync(f);
        }
        this.importText = text;
        this.importName = uris[0].substring(uris[0].lastIndexOf('/') + 1);
        const meta = ConfigBundle.peekMeta(text);
        if (meta === null) {
          this.importSummary = '';
          this.setImportMsg('这个文件不是本应用导出的备份', 2);
          return;
        }
        const d = new Date(meta.exportedAt);
        this.importSummary = `文件信息：${meta.nodeCount} 个节点、${meta.ruleCount} 条规则，` +
          `导出于 ${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')}` +
          `；${meta.hasCredentials ? '包含凭据（需口令解密）' : '不含凭据（导入后需自行填写）'}`;
        this.setImportMsg('文件已读取，请输入导出时设置的口令', 0);
      } catch (e) {
        const m: string = e instanceof Error ? e.message : String(e);
        this.setImportMsg(`读取失败：${m}`, 2);
      }
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.setImportMsg(`选择文件失败：${m}`, 2);
    });
  }

  private doImport(): void {
    if (this.importText.length === 0) {
      this.setImportMsg('请先选择备份文件', 1);
      return;
    }
    if (this.importPass.length === 0) {
      this.setImportMsg('请输入备份口令', 1);
      return;
    }
    this.importing = true;
    this.setImportMsg('正在解密并恢复…', 0);
    ConfigBundle.importFromText(this.importText, this.importPass).then((r: BundleImportResult) => {
      this.importing = false;
      if (!r.ok) {
        this.setImportMsg(r.error.length > 0 ? r.error : '恢复失败', 2);
        return;
      }
      let text: string = `已恢复：新增节点 ${r.addedNodes} 个`;
      if (r.skippedNodes > 0) {
        text += `，已存在跳过 ${r.skippedNodes} 个`;
      }
      if (r.addedRules > 0) {
        text += `；新增规则 ${r.addedRules} 条`;
      }
      if (r.skippedRules > 0) {
        text += `，规则已存在跳过 ${r.skippedRules} 条`;
      }
      if (r.missingCredentials > 0) {
        text += `。注意：${r.missingCredentials} 个节点缺凭据，需手工补填`;
      }
      this.setImportMsg(text, r.missingCredentials > 0 ? 1 : 0);
      this.importPass = '';
      this.importText = '';
    }).catch((e: Object) => {
      this.importing = false;
      const m: string = e instanceof Error ? e.message : String(e);
      this.setImportMsg(`恢复失败：${m}`, 2);
      Logger.error(`bundle import failed: ${m}`);
    });
  }

  /** 口令复制：只复制口令本身，方便用户"另发一条消息" */
  private copyPassphrase(): void {
    if (this.exportPass.length === 0) {
      this.setExportMsg('先输入口令再复制', 1);
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.exportPass);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '口令已复制，请单独发送', duration: 2000 });
    }).catch((e: Object) => {
      const m: string = e instanceof Error ? e.message : String(e);
      this.setExportMsg(`复制失败：${m}`, 2);
    });
  }

  /**
   * 页面退出时把口令从内存里抹掉。
   * 它不是应用密码，只属于“这一次导出”：不存盘、不进安全存储、不进日志。
   */
  aboutToDisappear(): void {
    this.exportPass = '';
    this.exportPass2 = '';
    this.importPass = '';
  }

  @Builder
  section(title: string, hint: string) {
    Column({ space: Space.xxs }) {
      Text(title)
        .fontSize(FontSize.titleMd)
        .lineHeight(LineHeight.titleMd)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
      Text(hint)
        .fontSize(FontSize.caption)
        .lineHeight(LineHeight.caption)
        .fontColor($r('app.color.text_tertiary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  passField(placeholder: string, value: string, onEdit: (v: string) => void) {
    TextInput({ placeholder: placeholder, text: value })
      .type(InputType.Password)
      .height(Height.input)
      .fontSize(FontSize.body)
      .placeholderColor($r('app.color.text_tertiary'))
      .backgroundColor($r('app.color.bg_surface'))
      .borderRadius(Radius.panel)
      .onChange((v: string) => {
        onEdit(v);
      })
  }

  build() {
    Column({ space: 0 }) {
      Column() {
        PageHeader({
          title: '备份与恢复',
          onBack: () => {
            router.back();
          }
        })
      }
      .width('100%')

      Scroll() {
        Column({ space: Space.lg }) {
          // ---------- 导出 ----------
          Column({ space: Space.sm }) {
            this.section('导出备份', '把本机节点、凭据、规则打包成一个加密文件')
            this.passField('设置备份口令（至少 8 位）', this.exportPass, (v: string) => {
              this.exportPass = v;
            })
            this.passField('再输一次', this.exportPass2, (v: string) => {
              this.exportPass2 = v;
            })
            Row({ space: Space.sm }) {
              Button(this.exporting ? '生成中…' : '导出到文件')
                .layoutWeight(1)
                .height(Height.hit)
                .fontSize(FontSize.bodySm)
                .backgroundColor($r('app.color.accent'))
                .fontColor($r('app.color.text_on_accent'))
                .enabled(!this.exporting)
                .onClick(() => this.doExport())
              Button('随机生成')
                .height(Height.hit)
                .fontSize(FontSize.bodySm)
                .backgroundColor($r('app.color.bg_chip'))
                .fontColor($r('app.color.text_primary'))
                .onClick(() => this.generatePassphrase())
              Button('复制口令')
                .height(Height.hit)
                .fontSize(FontSize.bodySm)
                .backgroundColor($r('app.color.bg_chip'))
                .fontColor($r('app.color.text_primary'))
                .onClick(() => this.copyPassphrase())
            }
            .width('100%')

            Text('口令是这个文件的唯一保护：忘了就打不开，也没有任何找回方式。' +
              '请把口令**另外发一条消息**给接收方——和文件放在一起发，等于没有加密。')
              .fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption)
              .fontColor($r('app.color.warning'))
              .width('100%')

            if (this.exportMsg.length > 0) {
              Text(this.exportMsg)
                .fontSize(FontSize.bodySm)
                .lineHeight(LineHeight.bodySm)
                .fontColor(this.msgColor(this.exportMsgLevel))
                .width('100%')
                .accessibilityText(`导出结果：${this.exportMsg}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(Space.md)
          .backgroundColor($r('app.color.bg_surface_alt'))
          .borderRadius(Radius.card)

          // ---------- 导入 ----------
          Column({ space: Space.sm }) {
            this.section('从备份恢复', '恢复只增不删，也不改本机的分流模式与日志级别')
            Button(this.importName.length > 0 ? '重新选择文件' : '选择备份文件')
              .width('100%')
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor($r('app.color.bg_chip'))
              .fontColor($r('app.color.text_primary'))
              .onClick(() => this.pickImportFile())

            if (this.importName.length > 0) {
              Text(this.importName)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            if (this.importSummary.length > 0) {
              Text(this.importSummary)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }

            this.passField('输入备份口令', this.importPass, (v: string) => {
              this.importPass = v;
            })

            Button(this.importing ? '恢复中…' : '解密并恢复')
              .width('100%')
              .height(Height.hit)
              .fontSize(FontSize.bodySm)
              .backgroundColor($r('app.color.accent'))
              .fontColor($r('app.color.text_on_accent'))
              .enabled(!this.importing)
              .onClick(() => this.doImport())

            if (this.importMsg.length > 0) {
              Text(this.importMsg)
                .fontSize(FontSize.bodySm)
                .lineHeight(LineHeight.bodySm)
                .fontColor(this.msgColor(this.importMsgLevel))
                .width('100%')
                .accessibilityText(`恢复结果：${this.importMsg}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(Space.md)
          .backgroundColor($r('app.color.bg_surface_alt'))
          .borderRadius(Radius.card)
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.xl })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_canvas'))
  }
}


