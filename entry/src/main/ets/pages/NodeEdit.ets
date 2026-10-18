import { router } from '@kit.ArkUI';
import { XrayNode, TransportKind, SecurityKind } from '../model/AppConfig';
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
  @State group: string = '';
  @State remark: string = '';
  /** 留空 = 不修改凭据 */
  @State credentialInput: string = '';
  @State transportIdx: number = 0;
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
    this.group = node.group;
    this.remark = node.remark;
    this.transportIdx = this.indexOfTransport(node.transport);
    this.securityIdx = this.indexOfSecurity(node.security);
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
      // 已知缺陷（PC9 FR-31）：http2 会被映射成已被内核移除的 http 传输
      return 'HTTP2 传输当前不可用（内核已移除 http 传输），请改用 WS 或 gRPC';
    }
    const s: SecurityKind = this.securities[this.securityIdx].value;
    if (s === SecurityKind.REALITY && this.serverName.trim().length === 0) {
      return 'REALITY 必须填写 SNI / serverName';
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
      Row({ space: 8 }) {
        Button('返回').fontSize(12)
          .onClick(() => {
            router.back();
          })
        Text('编辑节点').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
      }
      .width('100%')

      Scroll() {
        Column({ space: 10 }) {
          Text('名称').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.name }).fontSize(12)
            .onChange((v: string) => {
              this.name = v;
            })

          Text('服务器地址').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.address }).fontSize(12)
            .onChange((v: string) => {
              this.address = v;
            })

          Text('端口').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.port }).fontSize(12).type(InputType.Number)
            .onChange((v: string) => {
              this.port = v;
            })

          Text('协议').fontSize(12).fontColor('#666666').width('100%')
          Row({ space: 6 }) {
            ForEach(this.protos, (p: ProtoOption) => {
              Button(p.label).fontSize(11)
                .backgroundColor(p.value === this.protocol ? '#1976D2' : '#E0E0E0')
                .fontColor(p.value === this.protocol ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  this.protocol = p.value;
                })
            }, (p: ProtoOption) => p.value)
          }.width('100%')

          Text('传输').fontSize(12).fontColor('#666666').width('100%')
          Row({ space: 6 }) {
            ForEach(this.transports, (t: TransportOption, i: number) => {
              Button(t.label).fontSize(11)
                .backgroundColor(i === this.transportIdx ? '#1976D2' : '#E0E0E0')
                .fontColor(i === this.transportIdx ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  this.transportIdx = i;
                })
            }, (t: TransportOption) => t.label)
          }.width('100%')

          Text('安全').fontSize(12).fontColor('#666666').width('100%')
          Row({ space: 6 }) {
            ForEach(this.securities, (s: SecurityOption, i: number) => {
              Button(s.label).fontSize(11)
                .backgroundColor(i === this.securityIdx ? '#1976D2' : '#E0E0E0')
                .fontColor(i === this.securityIdx ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  this.securityIdx = i;
                })
            }, (s: SecurityOption) => s.label)
          }.width('100%')

          Text('SNI / serverName').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.serverName }).fontSize(12)
            .onChange((v: string) => {
              this.serverName = v;
            })

          Text('WS 路径').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.wsPath }).fontSize(12)
            .onChange((v: string) => {
              this.wsPath = v;
            })

          Text('WS Host').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.wsHost }).fontSize(12)
            .onChange((v: string) => {
              this.wsHost = v;
            })

          Text('gRPC 服务名').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.grpcService }).fontSize(12)
            .onChange((v: string) => {
              this.grpcService = v;
            })

          Text('flow（vless 可选）').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.flow }).fontSize(12)
            .onChange((v: string) => {
              this.flow = v;
            })

          Text('分组（留空=未分组）').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.group }).fontSize(12)
            .onChange((v: string) => {
              this.group = v;
            })

          Text('备注').fontSize(12).fontColor('#666666').width('100%')
          TextInput({ text: $$this.remark }).fontSize(12)
            .onChange((v: string) => {
              this.remark = v;
            })

          Column({ space: 4 }) {
            Text('凭据（UUID / 密码）').fontSize(12).fontColor('#666666').width('100%')
            TextInput({ placeholder: '留空表示不修改；填写则覆盖安全存储中的凭据', text: this.credentialInput })
              .fontSize(12)
              .type(InputType.Password)
              .onChange((v: string) => {
                this.credentialInput = v;
              })
            Text('凭据不会显示明文；修改后需重新连接生效。').fontSize(10).fontColor('#999999')
          }.width('100%')

          if (this.saveMsg.length > 0) {
            Text(this.saveMsg).fontSize(12).fontColor('#C62828').width('100%')
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
        .enabled(!this.saving && this.existed)
        .onClick(() => this.doSave())
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
