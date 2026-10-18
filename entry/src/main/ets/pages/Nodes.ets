import { router } from '@kit.ArkUI';
import { XrayNode } from '../model/AppConfig';
import { ConfigService } from '../service/ConfigService';
import { ShareLinkParser } from '../service/ShareLinkParser';
import { Logger } from '../platform/Logger';

/**
 * pages/Nodes.ets — 节点列表（本地假数据 + 选中切换）
 *
 * 结构约束：只读写 L-A 域模型（ConfigService），**不生成内核配置**；
 * 选中节点 = 改 selectedNodeId，不触发连接（连接由首页开关负责）。
 */
@Entry
@Component
struct Nodes {
  @State nodes: XrayNode[] = [];
  @State selectedId: string = '';
  @State linkInput: string = '';
  @State importMsg: string = '';

  private cfg: ConfigService = ConfigService.getInstance();

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.nodes = this.cfg.getNodes();
    const cur: XrayNode | null = this.cfg.getSelectedNode();
    this.selectedId = cur === null ? '' : cur.id;
  }

  private pick(id: string): void {
    if (this.cfg.selectNode(id)) {
      this.selectedId = id;
    } else {
      Logger.warn(`pick node failed: ${id}`);
    }
  }

  /** 导入分享链接：解析成功后加入列表并选中 */
  private doImport(): void {
    const link: string = this.linkInput.trim();
    if (!link) {
      this.importMsg = '请先粘贴分享链接';
      return;
    }
    try {
      const node = ShareLinkParser.parse(link);
      const added: boolean = this.cfg.addNode(node);
      this.cfg.selectNode(node.id);
      this.reload();
      this.importMsg = added
        ? `已导入：${node.name}（${node.protocol}）`
        : `节点已存在，已切换选中：${node.name}`;
      this.linkInput = '';
      Logger.info(`import ok: ${node.protocol} @ ${node.address}:${node.port}`);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.importMsg = `导入失败：${msg}`;
      Logger.warn(`import failed: ${msg}`);
    }
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button('返回').fontSize(12)
          .onClick(() => {
            router.back();
          })
        Text('节点列表').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text(`${this.nodes.length} 个`).fontSize(12).fontColor('#999999')
      }
      .width('100%')

      Text('粘贴分享链接导入（支持 vless / vmess / trojan / ss）').fontSize(11).fontColor('#999999')

      Row({ space: 8 }) {
        TextInput({ placeholder: 'vless://... 或 vmess://...', text: this.linkInput })
          .fontSize(12)
          .layoutWeight(1)
          .onChange((v: string) => { this.linkInput = v; })
        Button('导入').fontSize(12)
          .onClick(() => this.doImport())
      }
      .width('100%')

      if (this.importMsg) {
        Text(this.importMsg).fontSize(11).fontColor('#1976D2').width('100%')
      }

      List({ space: 8 }) {
        ForEach(this.nodes, (item: XrayNode) => {
          ListItem() {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(item.name).fontSize(15).fontWeight(item.id === this.selectedId ? FontWeight.Bold : FontWeight.Normal)
                Text(`${item.protocol} · ${item.address}:${item.port}`).fontSize(11).fontColor('#777777')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(item.id === this.selectedId ? '已选中' : '选择')
                .fontSize(12)
                .fontColor(item.id === this.selectedId ? '#2E7D32' : '#1976D2')
            }
            .width('100%')
            .padding(12)
            .backgroundColor(item.id === this.selectedId ? '#E8F5E9' : '#FAFAFA')
            .borderRadius(8)
            .onClick(() => this.pick(item.id))
          }
        }, (item: XrayNode) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
