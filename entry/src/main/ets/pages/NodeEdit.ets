import { router } from '@kit.ArkUI';
import { XrayNode, TransportKind, SecurityKind } from '../model/AppConfig';
import { PageHeader } from '../components/PageHeader';
import { FontSize, LineHeight, Space, Height, Radius } from '../common/Token';
import { ConfigService } from '../service/ConfigService';
import { Logger } from '../platform/Logger';

/**
 * pages/NodeEdit.ets — 节点编辑
 *
 * 结构约束：
 *   - 不直接改列表里的对象：先复制一份到本地 @State，保存成功才写回（失败不留残影）；
 *   - 凭据输入框**默认留空**，留空表示"不修改"。这样用户改端口时不会因为没重填 UUID
 *     而把凭据清掉——这是编辑功能最容易踩的坑；
 *   - 凭据一旦填写就写入安全存储，节点表只存别名（与导入路径同一原则）。
 */

/** 路由参数 */
export class NodeEditParams {
  nodeId: string = '';
}

interface ProtoOption {
  label: string;
  value: string;
}

interface TransportOption {
  label: string;
  value: TransportKind;
}

interface SecurityOption {
  label: string;
  value: SecurityKind;
}

@Entry
@Component
struct NodeEdit {
  @State name: string = '';
  @State protocol: string = 'vless';
  @State address: string = '';
  @State port: string = '443';
  @State serverName: string = '';
  @State wsPath: string = '';
  @State wsHost: string = '';
  @State grpcService: string = '';
  @State flow: string = '';
  @State publicKey: string = '';
  @State shortId: string = '';
  @State fingerprint: string = '';
  @State group: string = '';
  @State groupOptions: SelectOption[] = [];
  @State groupSelectIdx: number = 0;
  @State remark: string = '';
  /** 留空 = 不修改凭据 */
  @State credentialInput: string = '';
  @State transportIdx: number = 0;
  /** 传输类型下拉选项：5 项在 360vp 下已经贴边，再加就放不下了 */
  @State transportOptions: SelectOption[] = [];
  @State securityIdx: number = 0;
  @State saveMsg: string = '';
  @State saving: boolean = false;

  private cfg: ConfigService = ConfigService.getInstance();
  private nodeId: string = '';
  private existed: boolean = false;

  private protos: ProtoOption[] = [
    { label: 'vless', value: 'vless' },
    { label: 'vmess', value: 'vmess' },
    { label: 'trojan', value: 'trojan' },
    { label: 'ss', value: 'shadowsocks' }
  ];
  private transports: TransportOption[] = [
    { label: 'TCP', value: TransportKind.TCP },
    { label: 'WS', value: TransportKind.WS },
    { label: 'gRPC', value: TransportKind.GRPC },
    { label: 'HTTP2', value: TransportKind.HTTP2 },
    { label: 'mKCP', value: TransportKind.MKCP }
  ];
  private securities: SecurityOption[] = [
    { label: '无', value: SecurityKind.NONE },
    { label: 'TLS', value: SecurityKind.TLS },
    { label: 'REALITY', value: SecurityKind.REALITY }
  ];

  aboutToAppear(): void {
    const params = router.getParams() as NodeEditParams;
    if (params === null || params === undefined || params.nodeId.length === 0) {
      this.saveMsg = '缺少节点参数，无法编辑';
      return;
    }
    this.nodeId = params.nodeId;
    const node: XrayNode | null = this.findNode(params.nodeId);
    if (node === null) {
      this.saveMsg = '节点不存在（可能已被删除）';
      return;
    }
    this.existed = true;
    this.name = node.name;
    this.protocol = node.protocol;
    this.address = node.address;
    this.port = node.port.toString();
    this.serverName = node.serverName;
    this.wsPath = node.wsPath;
    this.wsHost = node.wsHost;
    this.grpcService = node.grpcService;
    this.flow = node.flow;
    this.publicKey = node.publicKey;
    this.shortId = node.shortId;
    this.fingerprint = node.fingerprint;
    this.group = node.group;
    this.remark = node.remark;
    this.transportOptions = this.buildTransportOptions();
    this.transportIdx = this.indexOfTransport(node.transport);
    this.securityIdx = this.indexOfSecurity(node.security);
    this.reloadGroups();
  }

  /**
   * 分组候选：来自现有节点。
   * 为什么要下拉 + 手输并存：纯自由输入会让「Home」和「home」分裂成两个组，
   * 而分组的价值就在归类；纯下拉又不能新建组。所以两者都留。
   */
  /** 把 transports 转成下拉选项（Select 需要 SelectOption[]） */
  private buildTransportOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < this.transports.length; i++) {
      opts.push({ value: this.transports[i].label } as SelectOption);
    }
    return opts;
  }

  private reloadGroups(): void {
    const list: string[] = this.cfg.getGroups();
    const opts: SelectOption[] = [{ value: '（不分组）' } as SelectOption];
    for (let i = 0; i < list.length; i++) {
      opts.push({ value: list[i] } as SelectOption);
    }
    this.groupOptions = opts;
    this.groupSelectIdx = 0;
    for (let i = 0; i < list.length; i++) {
      if (list[i] === this.group) {
        this.groupSelectIdx = i + 1;
      }
    }
  }

  private findNode(id: string): XrayNode | null {
    const nodes: XrayNode[] = this.cfg.getNodes();
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].id === id) {
        return nodes[i];
      }
    }
    return null;
  }

  private indexOfTransport(t: TransportKind): number {
    for (let i = 0; i < this.transports.length; i++) {
      if (this.transports[i].value === t) {
        return i;
      }
    }
    return 0;
  }

  private indexOfSecurity(s: SecurityKind): number {
    for (let i = 0; i < this.securities.length; i++) {
      if (this.securities[i].value === s) {
        return i;
      }
    }
    return 1;
  }

  /** 校验：宁可拒绝保存，也不要存一个"看起来能用但连不上"的节点 */
  private validate(): string {
    if (this.name.trim().length === 0) {
      return '名称不能为空';
    }
    if (this.address.trim().length === 0) {
      return '服务器地址不能为空';
    }
    const p: number = Number.parseInt(this.port, 10);
    if (Number.isNaN(p) || p < 1 || p > 65535) {
      return '端口必须是 1~65535 的整数';
    }
    const t: TransportKind = this.transports[this.transportIdx].value;
    if (t === TransportKind.HTTP2) {
      // 内核实测报错：“The feature HTTP transport ... has been removed and migrated to
      // XHTTP stream-one H2 & H3”。既然不支持，就不要让用户存下一个必失败节点。
      return '该内核版本已移除 HTTP/2 传输（迁移至 XHTTP），请改用 WS / gRPC';
    }
    const s: SecurityKind = this.securities[this.securityIdx].value;
    if (s === SecurityKind.REALITY) {
      if (this.serverName.trim().length === 0) {
        return 'REALITY 必须填写 SNI / serverName';
      }
      // 缺 publicKey 的 REALITY 是「导入成功但必然握手失败」的典型静默坑，必须前置拦住
      if (this.publicKey.trim().length === 0) {
        return 'REALITY 必须填写公钥（publicKey / pbk）';
      }
    }
    return '';
  }

  private doSave(): void {
    if (this.saving || !this.existed) {
      return;
    }
    const err: string = this.validate();
    if (err.length > 0) {
      this.saveMsg = err;
      return;
    }
    const origin: XrayNode | null = this.findNode(this.nodeId);
    if (origin === null) {
      this.saveMsg = '节点不存在（可能已被删除）';
      return;
    }
    // 复制而非就地修改：保存失败时列表里的对象必须保持原样
    const updated = new XrayNode(origin.id, this.name.trim(), this.address.trim(),
      Number.parseInt(this.port, 10));
    updated.protocol = this.protocol;
    updated.transport = this.transports[this.transportIdx].value;
    updated.security = this.securities[this.securityIdx].value;
    updated.serverName = this.serverName.trim();
    updated.wsPath = this.wsPath.trim();
    updated.wsHost = this.wsHost.trim();
    updated.grpcService = this.grpcService.trim();
    updated.flow = this.flow.trim();
    updated.publicKey = this.publicKey.trim();
    updated.shortId = this.shortId.trim();
    updated.fingerprint = this.fingerprint.trim();
    updated.group = this.group.trim();
    updated.remark = this.remark.trim();
    updated.credentialRef = origin.credentialRef;

    this.saving = true;
    this.saveMsg = '';
    this.cfg.updateNode(updated, this.credentialInput.trim()).then((ok: boolean) => {
      this.saving = false;
      if (ok) {
        Logger.info('node edit saved');
        router.back();
      } else {
        this.saveMsg = '保存失败（详见日志），原数据未改动';
      }
    }).catch((e: Object) => {
      this.saving = false;
      const msg: string = e instanceof Error ? e.message : String(e);
      this.saveMsg = `保存失败：${msg}`;
    });
  }

  /**
   * 表单字段**必须内联**，不能抽成 @Builder + 回调。
   * 实测教训：@Builder 里通过参数接收 `(v) => { this.xxx = v }` 时，
   * 输入框能显示用户敲的字，但组件状态从未被更新 —— 保存时用的还是打开页时的旧值，
   * 表现为"编辑看起来成功、实际什么都没改"。这类问题不会报错，只能靠实测发现。
   */
  build() {
    Column({ space: 12 }) {
      PageHeader({
        title: '编辑节点',
        onBack: () => {
          router.back();
        }
      })

      Scroll() {
        Column({ space: 10 }) {
          Text('名称').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          TextInput({ text: $$this.name }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.name = v;
            })

          Text('服务器地址').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          TextInput({ text: $$this.address }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.address = v;
            })

          Text('端口').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          TextInput({ text: $$this.port }).fontSize(FontSize.bodySm).type(InputType.Number)
            .onChange((v: string) => {
              this.port = v;
            })

          Text('协议').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          Row({ space: 6 }) {
            ForEach(this.protos, (p: ProtoOption) => {
              Button(p.label).fontSize(FontSize.caption)
                .layoutWeight(1)
                .padding({ left: 0, right: 0 })
                .backgroundColor(p.value === this.protocol ? $r('app.color.accent') : $r('app.color.bg_chip'))
                .fontColor(p.value === this.protocol ? $r('app.color.text_on_accent') : $r('app.color.text_primary'))
                .onClick(() => {
                  this.protocol = p.value;
                })
            }, (p: ProtoOption) => p.value)
          }.width('100%')

          Text('传输').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          // 传输用下拉而不是按钮组：5 项等宽时 HTTP2/mKCP 已经贴边，
          // 再加传输类型（QUIC 等）就放不下；下拉项数增长不会挤爆布局。
          Select(this.transportOptions)
            .selected(this.transportIdx)
            .value(this.transports[this.transportIdx].label)
            .font({ size: FontSize.body })
            .width('100%')
            .height(Height.input)
            // 与输入框同款浅底：白底在浅色页面里等于"看不见的控件"
            .backgroundColor($r('app.color.bg_chip'))
            .borderRadius(Radius.panel)
            .onSelect((index: number, value: string) => {
              this.transportIdx = index;
            })

          Text('安全').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          Row({ space: 6 }) {
            ForEach(this.securities, (s: SecurityOption, i: number) => {
              Button(s.label).fontSize(FontSize.caption)
                .layoutWeight(1)
                .padding({ left: 0, right: 0 })
                .backgroundColor(i === this.securityIdx ? $r('app.color.accent') : $r('app.color.bg_chip'))
                .fontColor(i === this.securityIdx ? $r('app.color.text_on_accent') : $r('app.color.text_primary'))
                .onClick(() => {
                  this.securityIdx = i;
                })
            }, (s: SecurityOption) => s.label)
          }.width('100%')

          Text('SNI / serverName').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.bodySm)
          TextInput({ text: $$this.serverName }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.serverName = v;
            })

          Text('WS 路径').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          TextInput({ text: $$this.wsPath }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.wsPath = v;
            })

          Text('WS Host').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          TextInput({ text: $$this.wsHost }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.wsHost = v;
            })

          Text('gRPC 服务名').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          TextInput({ text: $$this.grpcService }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.grpcService = v;
            })

          Text('flow（vless 可选）').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.bodySm)
          TextInput({ text: $$this.flow }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.flow = v;
            })

          // REALITY 参数：缺 publicKey 时握手必然失败，且内核不会在 parse 阶段报错
          Text('REALITY 公钥 publicKey（pbk）').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.bodySm)
          TextInput({ text: $$this.publicKey }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.publicKey = v;
            })

          Text('REALITY shortId（sid，可空）').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.bodySm)
          TextInput({ text: $$this.shortId }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.shortId = v;
            })

          Text('uTLS 指纹 fp（留空默认 chrome）').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.bodySm)
          TextInput({ text: $$this.fingerprint }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.fingerprint = v;
            })

          Text('分组（选已有，或直接输入新组名）').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.bodySm)
          if (this.groupOptions.length > 1) {
            Select(this.groupOptions)
              .selected(this.groupSelectIdx)
              .value(this.groupSelectIdx === 0 ? '（不分组）' : this.group)
              .font({ size: 12 })
              .width('100%')
              .onSelect((index: number, value: string) => {
                this.groupSelectIdx = index;
                this.group = index === 0 ? '' : value;
              })
          }
          TextInput({ text: $$this.group, placeholder: '输入新组名会覆盖上面的选择' }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.group = v;
            })

          Text('备注').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').maxLines(1)
          TextInput({ text: $$this.remark }).fontSize(FontSize.bodySm)
            .onChange((v: string) => {
              this.remark = v;
            })

          Column({ space: 4 }) {
            Text('凭据（UUID / 密码）').fontSize(FontSize.bodySm).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(LineHeight.bodySm)
            TextInput({ placeholder: '留空表示不修改；填写则覆盖安全存储中的凭据', text: this.credentialInput })
              .fontSize(FontSize.bodySm)
              .type(InputType.Password)
              .onChange((v: string) => {
                this.credentialInput = v;
              })
            Text('凭据不会显示明文；修改后需重新连接生效。').fontSize(FontSize.caption).fontColor($r('app.color.text_tertiary')).lineHeight(LineHeight.caption)
          }.width('100%')

          if (this.saveMsg.length > 0) {
            Text(this.saveMsg).fontSize(FontSize.bodySm).fontColor($r('app.color.danger')).width('100%').lineHeight(LineHeight.bodySm)
          }
        }
        .width('100%')
        .padding({ bottom: 12 })
      }
      .layoutWeight(1)
      .width('100%')

      // 保存按钮固定在滚动区之外：
      // 表单比一屏长，键盘弹起后如果按钮在滚动内容底部，用户会找不到保存入口
      // （实测在模拟器上就是滚不动、按钮被键盘挡住的局面）。
      Button(this.saving ? '保存中…' : '保存')
        .width('100%')
        .height(Height.hit)
        .fontSize(FontSize.bodyLg)
        .backgroundColor(!this.saving && this.existed ? $r('app.color.accent') : $r('app.color.bg_chip'))
        .fontColor(!this.saving && this.existed ? $r('app.color.text_on_accent') : $r('app.color.text_tertiary'))
        .enabled(!this.saving && this.existed)
        .onClick(() => this.doSave())
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
