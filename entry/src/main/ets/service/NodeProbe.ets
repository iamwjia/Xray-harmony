import { socket } from '@kit.NetworkKit';
import { Logger } from '../platform/Logger';
import { XrayNode } from '../model/AppConfig';

/**
 * service/NodeProbe.ets — 节点可达性探测（TCP 握手）
 *
 * 只回答一个问题：**这个节点地址现在能不能建立 TCP 连接**。
 *
 * 刻意不做的事：
 *   - 不判断协议能否握手（那要起内核并真连一次，属于"连接测试"，成本与副作用都大得多）；
 *   - 不给"快/慢"评级：一次握手耗时不代表实际速度，把它包装成测速会误导用户；
 *   - 并发只做 1 个：批量探测在移动网络下既费流量又容易被打成"异常流量"。
 */

export class ProbeResult {
  ok: boolean = false;
  /** 握手耗时（毫秒）；失败时为 0 */
  ms: number = 0;
  /** 可读原因；成功时为空串 */
  error: string = '';
}

const CONNECT_TIMEOUT_MS: number = 5000;

export class NodeProbe {
  /** 对节点地址做一次 TCP 握手并立刻关闭 */
  static async probe(node: XrayNode): Promise<ProbeResult> {
    const res = new ProbeResult();
    if (node.address.length === 0 || node.port <= 0) {
      res.error = '节点地址或端口不完整';
      return res;
    }
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    const started: number = Date.now();
    try {
      await tcp.connect({
        address: { address: node.address, port: node.port },
        timeout: CONNECT_TIMEOUT_MS
      });
      res.ok = true;
      res.ms = Date.now() - started;
      // 只记结果与耗时，不记地址（地址可能含域名/内网信息）
      Logger.info(`node probe ok: ${res.ms}ms`);
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      res.error = NodeProbe.humanize(m);
      Logger.warn(`node probe failed: ${m}`);
    } finally {
      try {
        await tcp.close();
      } catch (e) {
        // 关闭失败无所谓：连接没建立或已断
      }
    }
    return res;
  }

  /** 把底层错误压成一句人话——用户不需要看 errno */
  private static humanize(raw: string): string {
    const s: string = raw.toLowerCase();
    if (s.indexOf('timeout') >= 0 || s.indexOf('timed out') >= 0) {
      return `${CONNECT_TIMEOUT_MS / 1000} 秒内连不上（地址不可达或被防火墙拦截）`;
    }
    if (s.indexOf('refused') >= 0) {
      return '连接被拒绝（端口没在监听）';
    }
    if (s.indexOf('unreachable') >= 0 || s.indexOf('network') >= 0) {
      return '网络不可达（本机可能没有可用网络）';
    }
    if (s.indexOf('resolve') >= 0 || s.indexOf('dns') >= 0) {
      return '域名解析失败';
    }
    return '连不上（详见日志）';
  }
}
