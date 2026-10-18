import { router } from '@kit.ArkUI';
import { XrayNode } from '../model/AppConfig';
import { ConfigService } from '../service/ConfigService';
import { ShareLinkParser } from '../service/ShareLinkParser';
import { Logger } from '../platform/Logger';
import { NodeEditParams } from './NodeEdit';

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
  @State groups: string[] = [];
  /** 空串 = 全部；分组筛选只影响展示 */
  @State groupFilter: string = '';
  @State linkInput: string = '';
  @State importMsg: string = '';

  private cfg: ConfigService = ConfigService.getInstance();

  aboutToAppear(): void {
    this.reload();
  }

  /**
   * 从编辑页返回时必须重新拉取。
   * 原因：ConfigService 是**就地修改**节点数组（splice），ArkUI 的 @State 只追踪赋值、
   * 不追踪数组内部变更，所以不重新赋值就不会重渲染。
   * 表现就是"保存成功、日志正确，但列表还是旧的"——实测踩过。
   */
  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    // 必须**复制**：ConfigService 返回的是它持有的同一个数组引用，
    // 直接赋回 @State 时 ArkUI 判定"引用没变"而跳过重渲染，
    // 表现就是日志已显示保存成功、列表却还是旧数据（实测踩过）。
    this.nodes = this.cfg.getNodes().slice();
    this.groups = this.cfg.getGroups();
    if (this.groupFilter.length > 0 && this.groups.indexOf(this.groupFilter) < 0) {
      // 分组被删空（用户把该组最后一个节点改了组/删了）→ 自动回到"全部"，避免列表空白无解释
      this.groupFilter = '';
    }
    const cur: XrayNode | null = this.cfg.getSelectedNode();
    this.selectedId = cur === null ? '' : cur.id;
  }

  /** 分组筛选后的可见列表；筛选状态只影响展示，不改变存储顺序 */
  private visibleNodes(): XrayNode[] {
    if (this.groupFilter.length === 0) {
      return this.nodes;
    }
    const out: XrayNode[] = [];
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].group === this.groupFilter) {
        out.push(this.nodes[i]);
      }
    }
    return out;
  }

  private openEdit(id: string): void {
    const params: NodeEditParams = new NodeEditParams();
    params.nodeId = id;
    router.pushUrl({ url: 'pages/NodeEdit', params: params }).catch((e: Error) => {
      Logger.error(`nav NodeEdit failed: ${e.message}`);
    });
  }

  private doMove(id: string, delta: number): void {
    if (this.cfg.moveNode(id, delta)) {
      this.reload();
    }
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

      // 分组筛选：只在真的有分组时出现，避免空界面上多一行无用控件
      if (this.groups.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            Button('全部').fontSize(11)
              .backgroundColor(this.groupFilter.length === 0 ? '#1976D2' : '#E0E0E0')
              .fontColor(this.groupFilter.length === 0 ? '#FFFFFF' : '#333333')
              .onClick(() => {
                this.groupFilter = '';
              })
            ForEach(this.groups, (g: string) => {
              Button(g).fontSize(11)
                .backgroundColor(this.groupFilter === g ? '#1976D2' : '#E0E0E0')
                .fontColor(this.groupFilter === g ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  this.groupFilter = g;
                })
            }, (g: string) => g)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%')
      }

      List({ space: 8 }) {
        ForEach(this.visibleNodes(), (item: XrayNode) => {
          ListItem() {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(item.name).fontSize(15)
                    .fontWeight(item.id === this.selectedId ? FontWeight.Bold : FontWeight.Normal)
                  if (item.group.length > 0) {
                    Text(item.group).fontSize(10).fontColor('#5C6BC0')
                      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                      .backgroundColor('#E8EAF6').borderRadius(4)
                  }
                }
                Text(`${item.protocol} · ${item.address}:${item.port}`).fontSize(11).fontColor('#777777')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('↑').fontSize(14).fontColor('#546E7A')
                .onClick(() => {
                  this.doMove(item.id, -1);
                })
              Text('↓').fontSize(14).fontColor('#546E7A')
                .onClick(() => {
                  this.doMove(item.id, 1);
                })

              Text(item.id === this.selectedId ? '已选中' : '选择')
                .fontSize(12)
                .fontColor(item.id === this.selectedId ? '#2E7D32' : '#1976D2')
                .onClick(() => this.pick(item.id))

              Text('编辑')
                .fontSize(12)
                .fontColor('#1976D2')
                .onClick(() => this.openEdit(item.id))

              Text('删除')
                .fontSize(12)
                .fontColor('#C62828')
                .onClick(() => this.confirmDelete(item))
            }
            .width('100%')
            .padding(12)
            .backgroundColor(item.id === this.selectedId ? '#E8F5E9' : '#FAFAFA')
            .borderRadius(8)
            .onClick(() => this.pick(item.id))
          }
        }, (item: XrayNode) => `${item.id}-${item.group}-${item.name}`)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
