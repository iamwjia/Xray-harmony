import { FontSize, LineHeight, Space, Height, Radius, IconSize } from '../common/Token';
import { PageHeader } from '../components/PageHeader';
import { router } from '@kit.ArkUI';

/**
 * pages/Licenses.ets — 开源许可与第三方组件声明
 *
 * 这不是"放一段 LICENSE 文本"就完事的页面。里面有三种必须准确的东西：
 *   1. **事实**：组件、版本、许可证类型、是否被我们修改；
 *   2. **义务**：MPL-2.0 要求以可执行形式分发时提供源码获取方式；MIT/Apache 要求保留声明；
 *   3. **归属**：明确"不隶属上游项目、不使用其商标"，避免被误认为官方客户端。
 *
 * 写错任何一条都是合规风险，所以这里只写能核对到原文的结论；
 * 核对不到的上游数据许可，明确标注"以上游发布页为准"，不猜。
 */

interface Component {
  name: string;
  version: string;
  license: string;
  usage: string;
  modified: string;
}

@Entry
@Component
struct Licenses {
  private components: Component[] = [
    {
      name: 'Xray-core',
      version: 'v1.260327.1（经 libXray 集成）',
      license: 'MPL-2.0',
      usage: '代理协议与出站实现（内核）',
      modified: '未修改，按上游构建产物集成'
    },
    {
      name: 'libXray',
      version: 'v26.7.28',
      license: 'MIT',
      usage: 'Xray-core 的移动端封装与调用桥',
      modified: '未修改'
    },
    {
      name: 'tun2socks',
      version: 'v2 系列（规划集成）',
      license: 'MIT',
      usage: 'tun 流量转发（尚未接入）',
      modified: '未修改'
    },
    {
      name: 'gVisor netstack',
      version: '随 tun2socks 引入',
      license: 'Apache-2.0',
      usage: '用户态 TCP/IP 协议栈',
      modified: '未修改'
    },
    {
      name: 'geoip / geosite 数据',
      version: 'v2fly 官方发布构建',
      license: '以上游发布页为准',
      usage: '分流规则数据（按原样分发，未修改）',
      modified: '未修改'
    }
  ];

  build() {
    Column({ space: 12 }) {
      Row() {
        PageHeader({
          title: '开源许可',
          onBack: () => {
            router.back();
          }
        })
      }
      .width('100%')

      Scroll() {
        Column({ space: 14 }) {
          this.section('本应用包含的第三方组件')
          ForEach(this.components, (c: Component) => {
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(c.name).fontSize(FontSize.bodySm).fontWeight(FontWeight.Medium)
                Text(c.license).fontSize(FontSize.fontChip).fontColor($r('app.color.accent'))
              }
              Text(`版本：${c.version}`).fontSize(FontSize.fontChip).fontColor($r('app.color.text_secondary'))
              Text(`用途：${c.usage}`).fontSize(FontSize.fontChip).fontColor($r('app.color.text_secondary'))
              Text(`修改情况：${c.modified}`).fontSize(FontSize.fontChip)
                .fontColor(c.modified.startsWith('未修改') ? $r('app.color.success') : $r('app.color.danger'))
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(10)
            .backgroundColor($r('app.color.bg_surface_alt'))
            .borderRadius(6)
          }, (c: Component) => c.name)

          this.section('MPL-2.0 相关义务（Xray-core）')
          Text('本应用以**未经修改**的编译产物形式集成 Xray-core。MPL-2.0 要求：' +
            '以可执行形式分发时，须告知接收者如何获取对应源码。')
            .fontSize(FontSize.fontChip).fontColor($r('app.color.text_primary')).width('100%')
          Text('• 上游源码：github.com/XTLS/Xray-core\n' +
            '• 本应用对应版本：v1.260327.1（commit 80263da 构建链）\n' +
            '• 本应用未修改其源码，因此无需公开自有代码；' +
            '若日后修改，相应文件须以 MPL-2.0 公开')
            .fontSize(FontSize.fontChip).fontColor($r('app.color.text_primary')).width('100%')

          this.section('MIT / Apache-2.0 相关义务')
          Text('libXray、tun2socks 为 MIT；gVisor 为 Apache-2.0。' +
            '本应用保留其版权声明与许可证文本，不改变其许可条款。')
            .fontSize(FontSize.fontChip).fontColor($r('app.color.text_primary')).width('100%')

          this.section('商标与归属')
          Text('本应用是独立第三方项目，与 XTLS、Xray-core、v2fly 等项目**无隶属关系**，' +
            '亦未获得其背书。应用名称与图标为原创，不使用上游项目的名称或标识作为品牌。')
            .fontSize(FontSize.fontChip).fontColor($r('app.color.text_primary')).width('100%')

          this.section('数据来源')
          Text('分流用的 geoip / geosite 数据取自 v2fly 官方发布构建，按原样分发、未作修改。' +
            '该数据的具体许可条款以上游项目发布页为准；如上游调整许可，本应用将随之更新。')
            .fontSize(FontSize.fontChip).fontColor($r('app.color.text_primary')).width('100%')

          this.section('如何获取源码')
          Text('本应用自身代码与其依赖清单公开在项目仓库中；内核部分请见上文的 Xray-core 上游地址。' +
            '构建脚本随仓库提供，可按脚本复现内核与数据文件的生成过程。')
            .fontSize(FontSize.fontChip).fontColor($r('app.color.text_primary')).width('100%')

          Text('说明：本页随依赖变化更新。若发现此处信息与实际分发不一致，以仓库中的依赖清单为准。')
            .fontSize(FontSize.fontChip).fontColor($r('app.color.text_tertiary')).width('100%')
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  @Builder
  section(title: string) {
    Text(title).fontSize(FontSize.body).fontWeight(FontWeight.Medium)
      .width('100%').margin({ top: 6 })
  }
}
