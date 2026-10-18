import { router } from '@kit.ArkUI';
import { XrayNode } from '../model/AppConfig';
import { ConfigService } from '../service/ConfigService';
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

      Text('当前为本地假数据（占位），后续接订阅导入 / 手动添加').fontSize(11).fontColor('#999999')

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
