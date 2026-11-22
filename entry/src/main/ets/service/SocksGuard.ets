/**
 * service/SocksGuard.ets — 本地 SOCKS 入站的端口与鉴权凭据（会话级）
 *
 * 为什么需要它：
 *   原来入站固定 `127.0.0.1:18080` + `auth:"noauth"`。HarmonyOS 的 loopback 是
 *   **设备内共享**的——同设备任何应用都能连 127.0.0.1，等于给本机所有应用开了一个
 *   免鉴权的出网口（走用户的节点）。固定端口还让"猜端口"变成零成本。
 *
 * 策略：
 *   1. **每次启动内核轮换端口与口令**（rotate），不跨会话复用；
 *   2. 端口落在动态端口段，不用 18080 这类约定俗成的高可猜值；
 *   3. 口令只用随机十六进制，不包含任何用户/节点信息；
 *   4. 口令**只进配置、不进日志**（日志只打端口）。
 *
 * 后续 tun2socks 接入时，通过 `SocksGuard.get()` 拿到当前端口的账号口令即可。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Logger } from '../platform/Logger';

/** 端口范围：避开知名端口与常见开发端口，降低被本机其他应用"顺手扫到"的概率 */
const PORT_MIN: number = 20000;
const PORT_MAX: number = 40000;
/** 口令长度（hex 字符数）：32 hex = 128 bit，远超暴力破解成本 */
const SECRET_HEX_LEN: number = 32;
/** 固定用户名：SOCKS5 用户名本身不是秘密，真正的秘密是口令 */
const SOCKS_USER: string = 'tunnelix';

export class SocksEndpoint {
  port: number = PORT_MIN;
  user: string = SOCKS_USER;
  password: string = '';
  /** 是否启用鉴权（口令为空时回落 noauth，仅用于极早期调试配置） */
  authEnabled: boolean = true;
}

/** 当前代理端点的只读快照：给 Logs 页显示"最近一次代理地址"用 */
export class LastEndpoint {
  host: string = '';
  port: number = 0;
}

export class SocksGuard {
  private static current: SocksEndpoint | null = null;
  /**
   * 最近一次的端点快照（只读用途）。
   *
   * 刻意**不**在断开时清空：用户报障往往发生在断开之后，"断了就查不到"等于把线索删掉。
   * 只活在进程内存里——不写盘、不进日志缓冲、不参与端口轮换决策；进程死亡自然为空。
   */
  private static last: LastEndpoint | null = null;

  /** 生成新的一组端口 + 口令（每次连接内核前调用） */
  static rotate(): SocksEndpoint {
    const ep = new SocksEndpoint();
    ep.port = PORT_MIN + SocksGuard.randomUint32() % (PORT_MAX - PORT_MIN);
    ep.user = SOCKS_USER;
    ep.password = SocksGuard.randomHex(SECRET_HEX_LEN);
    ep.authEnabled = true;
    SocksGuard.current = ep;
    // 绑定成功即记下快照：断开后 Logs 仍要能读到"最近一次用过哪个地址"
    const snap: LastEndpoint = new LastEndpoint();
    snap.host = '127.0.0.1';
    snap.port = ep.port;
    SocksGuard.last = snap;
    // 只记录端口：口令进日志就等于没有口令
    Logger.info(`socks endpoint rotated: 127.0.0.1:${ep.port} (auth=password)`);
    return ep;
  }

  /**
   * 最近一次的代理端点（只读、进程内）。
   *
   * 返回**副本**：调用方改了返回值也影响不到 SocksGuard 内部状态；
   * 本次启动从未连接时返回 null（Logs 页据此显示第三态）。
   * 幂等：连续调用返回等值快照，不改变任何状态。
   */
  static lastEndpoint(): LastEndpoint | null {
    const cur: LastEndpoint | null = SocksGuard.last;
    if (cur === null) {
      return null;
    }
    const copy: LastEndpoint = new LastEndpoint();
    copy.host = cur.host;
    copy.port = cur.port;
    return copy;
  }

  private static randomUint32(): number {
    const blob: cryptoFramework.DataBlob = cryptoFramework.createRandom().generateRandomSync(4);
    const v: number = ((blob.data[0] << 24) | (blob.data[1] << 16) | (blob.data[2] << 8) | blob.data[3]);
    return v < 0 ? -v : v;
  }

  /** 当前会话的端点；未初始化时惰性生成 */
  static get(): SocksEndpoint {
    if (SocksGuard.current === null) {
      return SocksGuard.rotate();
    }
    return SocksGuard.current;
  }

  private static randomHex(len: number): string {
    // 口令必须是密码学随机：`Math.random()` 是可预测的 PRNG，
    // 用它生成的口令等于没有口令——本机其他应用只要能预测就能借道出网。
    const bytes: number = Math.ceil(len / 2);
    const blob: cryptoFramework.DataBlob = cryptoFramework.createRandom().generateRandomSync(bytes);
    const alphabet: string = '0123456789abcdef';
    let out: string = '';
    for (let i = 0; i < blob.data.length; i++) {
      out += alphabet.charAt((blob.data[i] >> 4) & 0x0f);
      out += alphabet.charAt(blob.data[i] & 0x0f);
    }
    return out.substring(0, len);
  }
}
