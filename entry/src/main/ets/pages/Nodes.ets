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

  /** 删除前二次确认：删除不可恢复，不做"点了就没了" */
  private confirmDelete(item: XrayNode): void {
    AlertDialog.show({
      title: '删除节点',
      message: `将删除「${item.name}」及其保存的凭据，该操作不可恢复。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#C62828',
        action: () => {
          this.doDelete(item.id);
        }
      }
    });
  }

  private doDelete(id: string): void {
    this.cfg.removeNode(id).then((ok: boolean) => {
      this.reload();
      this.importMsg = ok ? '已删除节点（凭据一并清除）' : '删除失败，详见日志';
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.importMsg = `删除失败：${msg}`;
      Logger.error(`removeNode failed: ${msg}`);
    });
  }

  /** 导入分享链接：解析成功后写入安全存储 + 节点表，并选中 */
  private doImport(): void {
    const link: string = this.linkInput.trim();
    if (!link) {
      this.importMsg = '请先粘贴分享链接';
      return;
    }
    let node: XrayNode;
    try {
      node = ShareLinkParser.parse(link);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.importMsg = `导入失败：${msg}`;
      Logger.warn(`import failed: ${msg}`);
      return;
    }
    // 凭据先落 Asset Store，节点表只存别名（新增数据不再有明文凭据）
    this.cfg.addNodeSecure(node).then((added: boolean) => {
      this.cfg.selectNode(node.id);
      this.reload();
      this.importMsg = added
        ? `已导入：${node.name}（${node.protocol}）`
        : `节点已存在，已切换选中：${node.name}`;
      this.linkInput = '';
      Logger.info(`import ok: ${node.protocol} @ ${node.address}:${node.port}`);
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.importMsg = `导入失败：凭据写入安全存储失败（${msg}）`;
      Logger.error(`import failed at secret store: ${msg}`);
    });
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
                .onClick(() => this.pick(item.id))

              Text('删除')
                .fontSize(12)
                .fontColor('#C62828')
                .padding({ left: 10 })
                .onClick(() => this.confirmDelete(item))
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
