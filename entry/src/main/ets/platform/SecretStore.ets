/**
 * platform/SecretStore.ets — 凭据安全存储（Asset Store 适配层）
 *
 * 为什么用 Asset Store 而不是 HUKS：
 *   HUKS 管的是**密钥**（生成/派生/加解密），要自己设计"加密后存哪里"；
 *   Asset Store 直接管**短secret**，自带别名索引与可访问性策略，正好是
 *   "存一个节点 UUID/密码，按别名取回"这个场景。少一层自研加密，少一层出错面。
 *
 * 关键设计（FR-35 / NFR-06）：
 *   1. **别名不敏感**：别名形如 `node:<id>`，可以明文落盘；secret 只在 Asset Store 里；
 *   2. **DEVICE_FIRST_UNLOCKED**：开机首次解锁后即可读 —— VPN 常在前台服务里启动，
 *      用 DEVICE_UNLOCKED 会在锁屏时让连接直接失败，对用户是"莫名其妙连不上"；
 *   3. **任何失败都不静默**：put/get 失败必须返回明确的失败值并记日志，
 *      由调用方决定"降级/阻断"，不允许假装成功。
 *
 * 安全边界：本模块不打印 secret，任何日志只允许出现 alias。
 */

import { asset } from '@kit.AssetStoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Logger } from './Logger';

export class SecretStore {

  /**
   * 别名：`node:<nodeId 的 SHA-256 前 16 hex>`。
   *
   * 为什么哈希：早期版本直接用 `node:<protocol@host:port>` 做别名，
   * 而**每次凭据读写都会把别名打进日志**——等于把服务器地址写进了日志。
   * 哈希后别名不可反推，日志里只剩一串无意义 hex。
   */
  static aliasForNode(nodeId: string): string {
    return `node:${SecretStore.shortHash(nodeId)}`;
  }

  /** 旧版别名（明文 host:port），仅用于兼容迁移，不要在新代码里使用 */
  static legacyAliasForNode(nodeId: string): string {
    return `node:${nodeId}`;
  }

  private static shortHash(v: string): string {
    try {
      const bytes: Uint8Array = SecretStore.toBytes(v);
      // 注意：必须用**带类型注解**的字节块。用 `{ data: ... } as DataBlob` 的断言写法
      // 在 ArkTS 下会让 update() 拿到空输入，SHA-256("") = e3b0c442… 全节点撞同一个别名
      // （已在模拟器上实测到这个 bug，见 commit message）。
      const input: cryptoFramework.DataBlob = { data: bytes };
      const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
      // 必须用 updateSync 配 digestSync。`update()` 返回 Promise，不 await 就直接
      // digestSync 会拿到 SHA-256("") = e3b0c442…，全节点撞同一个别名（实测踩过）。
      md.updateSync(input);
      const digest: cryptoFramework.DataBlob = md.digestSync();
      const alphabet: string = '0123456789abcdef';
      let hex: string = '';
      const take: number = digest.data.length < 8 ? digest.data.length : 8;
      for (let i = 0; i < take; i++) {
        hex += alphabet.charAt((digest.data[i] >> 4) & 0x0f);
        hex += alphabet.charAt(digest.data[i] & 0x0f);
      }
      if (hex === 'e3b0c44298fc1c14') {
        // SHA-256("") 的前 8 字节：出现它说明输入是空的，别名会全节点碰撞
        Logger.error('secretStore: hash input was empty (alias would collide); using prefixed raw alias');
        return `raw:${v}`;
      }
      return hex;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      // 兜底也要带前缀：直接返回 v 会退回旧别名 `node:<host:port>` 的形态，
      // 而 resolveCredential 先查哈希别名、命中即返回，re-key 永远走不到 —— 这个退回是永久的。
      Logger.error(`secretStore: hash failed, using prefixed raw alias: ${msg}`);
      return `raw:${v}`;
    }
  }

  private static toBytes(v: string): Uint8Array {
    // 自实现 UTF-8 编码，不用 util.TextEncoder：
    // 实测在 ArkTS 下 `new util.TextEncoder().encodeInto(v)` 会返回**空数组**，
    // 导致 SHA-256("") 别名全节点碰撞、且写入的 secret 也是空——这是数据完整性问题，
    // 不能靠"换个 API 试试"糊过去，宁可用 20 行确定性代码。
    const out: number[] = [];
    for (let i = 0; i < v.length; i++) {
      let cp: number = v.charCodeAt(i);
      // 代理对（emoji 等）：合并成一个码点
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < v.length) {
        const next: number = v.charCodeAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          cp = 0x10000 + ((cp - 0xD800) << 10) + (next - 0xDC00);
          i++;
        }
      }
      if (cp < 0x80) {
        out.push(cp);
      } else if (cp < 0x800) {
        out.push(0xC0 | (cp >> 6));
        out.push(0x80 | (cp & 0x3F));
      } else if (cp < 0x10000) {
        out.push(0xE0 | (cp >> 12));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      } else {
        out.push(0xF0 | (cp >> 18));
        out.push(0x80 | ((cp >> 12) & 0x3F));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      }
    }
    const bytes = new Uint8Array(out.length);
    for (let i = 0; i < out.length; i++) {
      bytes[i] = out[i];
    }
    return bytes;
  }

  private static fromBytes(v: Uint8Array): string {
    let out: string = '';
    let i: number = 0;
    while (i < v.length) {
      const b: number = v[i];
      let cp: number = 0;
      let extra: number = 0;
      if (b < 0x80) {
        cp = b;
      } else if ((b & 0xE0) === 0xC0) {
        cp = b & 0x1F;
        extra = 1;
      } else if ((b & 0xF0) === 0xE0) {
        cp = b & 0x0F;
        extra = 2;
      } else if ((b & 0xF8) === 0xF0) {
        cp = b & 0x07;
        extra = 3;
      } else {
        // 非法起始字节：跳过，避免整段解析失败
        i++;
        continue;
      }
      if (i + extra >= v.length) {
        break;
      }
      for (let k = 1; k <= extra; k++) {
        cp = (cp << 6) | (v[i + k] & 0x3F);
      }
      i += extra + 1;
      if (cp > 0xFFFF) {
        cp -= 0x10000;
        out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
      } else {
        out += String.fromCharCode(cp);
      }
    }
    return out;
  }

  /**
   * 写入 secret。已存在同别名时**覆盖**（先删后加），
   * 这样重复导入同一节点不会因为"别名冲突"而失败。
   */
  static async put(alias: string, secret: string): Promise<boolean> {
    // 空 secret 一律拒绝：写进去等于"节点没有凭据"，而调用方会以为存成功了
    if (secret.length === 0) {
      Logger.error(`secretStore put rejected: empty secret for ${alias}`);
      return false;
    }
    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.ALIAS, SecretStore.toBytes(alias));
    attr.set(asset.Tag.SECRET, SecretStore.toBytes(secret));
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attr);
      Logger.info(`secretStore put ok: ${alias}`);
      return true;
    } catch (e) {
      const err = e as BusinessErrorLike;
      // 24000003 = duplicated alias；此时走 remove + add 覆盖
      if (err.code === 24000003) {
        await SecretStore.remove(alias);
        try {
          await asset.add(attr);
          Logger.info(`secretStore put (overwrite) ok: ${alias}`);
          return true;
        } catch (e2) {
          const err2 = e2 as BusinessErrorLike;
          Logger.error(`secretStore put overwrite failed: ${alias} code=${err2.code} msg=${err2.message}`);
          return false;
        }
      }
      Logger.error(`secretStore put failed: ${alias} code=${err.code} msg=${err.message}`);
      return false;
    }
  }

  /** 读取 secret；返回 null 表示"没有/读不到"，调用方必须按"凭据不可用"处理，不得当成空凭据继续 */
  static async get(alias: string): Promise<string | null> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, SecretStore.toBytes(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const res: Array<asset.AssetMap> = await asset.query(query);
      if (res.length === 0) {
        Logger.warn(`secretStore get: no asset for ${alias}`);
        return null;
      }
      const secret = res[0].get(asset.Tag.SECRET) as Uint8Array;
      if (secret === undefined) {
        Logger.error(`secretStore get: asset ${alias} has no SECRET field`);
        return null;
      }
      const text: string = SecretStore.fromBytes(secret);
      if (text.length === 0) {
        // 空 secret 视为"不可用"：早期版本曾因编码器返回空数组写下空凭据
        Logger.error(`secretStore get: asset ${alias} holds an EMPTY secret (treated as missing)`);
        return null;
      }
      return text;
    } catch (e) {
      const err = e as BusinessErrorLike;
      Logger.error(`secretStore get failed: ${alias} code=${err.code} msg=${err.message}`);
      return null;
    }
  }

  /** 删除 secret；不存在视为成功（幂等） */
  static async remove(alias: string): Promise<boolean> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, SecretStore.toBytes(alias));
    try {
      await asset.remove(query);
      Logger.info(`secretStore remove ok: ${alias}`);
      return true;
    } catch (e) {
      const err = e as BusinessErrorLike;
      if (err.code === 24000002) {
        return true; // not found，幂等
      }
      Logger.error(`secretStore remove failed: ${alias} code=${err.code} msg=${err.message}`);
      return false;
    }
  }

  /** 只用于判断"这条凭据是否已经在安全存储里"（不读出明文） */
  static async exists(alias: string): Promise<boolean> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, SecretStore.toBytes(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    try {
      const res: Array<asset.AssetMap> = await asset.query(query);
      return res.length > 0;
    } catch (e) {
      return false;
    }
  }
}

/** Asset Store 的 BusinessError 形状（避免为了一个字段引入整套错误类型） */
interface BusinessErrorLike {
  code: number;
  message: string;
}
