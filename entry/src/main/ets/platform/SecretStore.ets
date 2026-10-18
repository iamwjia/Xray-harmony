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
import { util } from '@kit.ArkTS';
import { Logger } from './Logger';

export class SecretStore {
  private static encoder: util.TextEncoder = new util.TextEncoder();
  private static decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  /** 别名约定：节点凭据用 `node:<nodeId>`；别把 secret 放进别名 */
  static aliasForNode(nodeId: string): string {
    return `node:${nodeId}`;
  }

  private static toBytes(v: string): Uint8Array {
    return SecretStore.encoder.encodeInto(v);
  }

  private static fromBytes(v: Uint8Array): string {
    return SecretStore.decoder.decodeToString(v);
  }

  /**
   * 写入 secret。已存在同别名时**覆盖**（先删后加），
   * 这样重复导入同一节点不会因为"别名冲突"而失败。
   */
  static async put(alias: string, secret: string): Promise<boolean> {
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
      return SecretStore.fromBytes(secret);
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
