import { XrayNode } from '../model/AppConfig';
import { Bytes } from '../platform/Bytes';

/**
 * service/ShareLinkBuilder.ets — 把节点还原成分享链接
 *
 * 用途：节点行长按「复制分享链接」，把当前节点原样发给别人（换机、求助、群里问"这个能不能用"）。
 *
 * 约定：
 *   - 与 ShareLinkParser 对称：这里生成什么，解析器必须能读回来（有单测覆盖往返）。
 *   - **凭据只在内存里出现一次**：由调用方从安全存储取出后传进来，本类不落盘、不打日志。
 *   - 节点名要做 URL 编码：中文名、空格、`#` 都会破坏链接结构。
 */
export class ShareLinkBuilder {
  /**
   * @param node 节点元信息
   * @param credential 明文凭据（vless=uuid，trojan=密码，ss=`method:password`，vmess=uuid）
   */
  static build(node: XrayNode, credential: string): string {
    const shownName: string = node.name.length > 0 ? node.name : `${node.address}:${node.port}`;
    const name: string = encodeURIComponent(shownName);
    const host: string = `${node.address}:${node.port}`;

    if (node.protocol === 'trojan') {
      return `trojan://${encodeURIComponent(credential)}@${host}?security=${ShareLinkBuilder.security(node)}` +
        `${ShareLinkBuilder.sniParam(node)}#${name}`;
    }

    if (node.protocol === 'shadowsocks') {
      // ss 的凭据本身就是 method:password，整串 base64 之后放 userinfo 位
      return `ss://${Bytes.textToBase64(credential)}@${host}#${name}`;
    }

    if (node.protocol === 'vmess') {
      // vmess 用 v2rayN 的 JSON 变体：字段名是事实标准，改不了
      const tls: string = node.security === 'none' ? '' : 'tls';
      const json: string = '{"v":"2","ps":"' + ShareLinkBuilder.esc(shownName) + '","add":"' +
        ShareLinkBuilder.esc(node.address) + '","port":"' + node.port + '","id":"' +
        ShareLinkBuilder.esc(credential) + '","aid":"0","scy":"auto","net":"' +
        ShareLinkBuilder.esc(node.transport) + '","type":"none","host":"' +
        ShareLinkBuilder.esc(node.wsHost) + '","path":"' + ShareLinkBuilder.esc(node.wsPath) +
        '","tls":"' + tls + '","sni":"' + ShareLinkBuilder.esc(node.serverName) + '"}';
      return `vmess://${Bytes.textToBase64(json)}`;
    }

    // vless（含 REALITY 参数）
    let params: string = `?encryption=none&security=${ShareLinkBuilder.security(node)}&type=${node.transport}`;
    if (node.wsPath.length > 0 && node.transport !== 'tcp') {
      params += `&path=${encodeURIComponent(node.wsPath)}`;
    }
    if (node.wsHost.length > 0) {
      params += `&host=${encodeURIComponent(node.wsHost)}`;
    }
    if (node.grpcService.length > 0) {
      params += `&serviceName=${encodeURIComponent(node.grpcService)}`;
    }
    if (node.flow.length > 0) {
      params += `&flow=${encodeURIComponent(node.flow)}`;
    }
    if (node.security === 'reality') {
      if (node.publicKey.length > 0) {
        params += `&pbk=${encodeURIComponent(node.publicKey)}`;
      }
      if (node.shortId.length > 0) {
        params += `&sid=${encodeURIComponent(node.shortId)}`;
      }
      if (node.fingerprint.length > 0) {
        params += `&fp=${encodeURIComponent(node.fingerprint)}`;
      }
    }
    params += ShareLinkBuilder.sniParam(node);
    return `vless://${encodeURIComponent(credential)}@${host}${params}#${name}`;
  }

  private static security(node: XrayNode): string {
    if (node.security === 'reality') {
      return 'reality';
    }
    return node.security === 'none' ? 'none' : 'tls';
  }

  private static sniParam(node: XrayNode): string {
    return node.serverName.length > 0 ? `&sni=${encodeURIComponent(node.serverName)}` : '';
  }

  /** JSON 字符串里的引号与反斜杠必须转义，否则 vmess 链接会被解析器判为非法 */
  private static esc(v: string): string {
    return v.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }
}
