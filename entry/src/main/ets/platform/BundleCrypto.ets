import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Logger } from './Logger';

/**
 * platform/BundleCrypto.ets — 备份文件的加解密（PBKDF2 + AES-256-GCM）
 *
 * 为什么用口令加密而不是把凭据明文写进文件：导出的文件会被微信、邮件、网盘传走，
 * 明文凭据一旦落地就等于泄露。用口令加密后，**文件可以随便传，口令另走一条渠道**。
 *
 * 参数选择（都写进文件头，便于将来升级）：
 *   - KDF：PBKDF2-SHA256，200000 次迭代；迭代数随文件走，旧文件仍可解；
 *   - 加密：AES-256-GCM，12 字节 nonce，16 字节 tag；
 *   - salt 每次导出随机 16 字节 —— 同一口令导两次，密文也不同。
 *
 * 明确的能力边界：
 *   - **没有找回机制**：口令忘了就是打不开，不存在后门；
 *   - 安全强度等于口令强度：弱口令（123456）等于没加密，UI 必须做强度提示；
 *   - 口令不能与文件同一渠道传递，否则加密等于装饰。
 */
export class BundleCrypto {
  static readonly ITERATIONS: number = 200000;
  static readonly SALT_LEN: number = 16;
  static readonly NONCE_LEN: number = 12;
  static readonly TAG_LEN: number = 16;

  /** 口令强度判定：只做最少的三条，不搞花哨评分 */
  static isWeak(passphrase: string): boolean {
    return passphrase.length < 8;
  }

  /** 口令强度提示文案（空串 = 通过） */
  static weaknessHint(passphrase: string): string {
    if (passphrase.length === 0) {
      return '请输入口令';
    }
    if (passphrase.length < 8) {
      return '口令至少 8 位：这个口令是备份文件的唯一保护';
    }
    return '';
  }

  static randomBytes(len: number): Uint8Array {
    const blob: cryptoFramework.DataBlob = cryptoFramework.createRandom().generateRandomSync(len);
    return blob.data;
  }

  static toBase64(data: Uint8Array): string {
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.encodeToStringSync(data);
  }

  static fromBase64(text: string): Uint8Array {
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.decodeSync(text);
  }

  private static async deriveKey(passphrase: string, salt: Uint8Array): Promise<cryptoFramework.SymKey> {
    const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: passphrase,
      salt: salt,
      iterations: BundleCrypto.ITERATIONS,
      keySize: 32
    };
    const secret: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
    const gen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    return await gen.convertKey(secret);
  }

  /** 加密：返回 salt / nonce / 密文（含 tag）三段 Base64 */
  static async encrypt(plainText: string, passphrase: string): Promise<BundleCipher> {
    const salt: Uint8Array = BundleCrypto.randomBytes(BundleCrypto.SALT_LEN);
    const nonce: Uint8Array = BundleCrypto.randomBytes(BundleCrypto.NONCE_LEN);
    const key: cryptoFramework.SymKey = await BundleCrypto.deriveKey(passphrase, salt);

    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const gcm: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: nonce },
      aad: { data: new Uint8Array(0) },
      authTag: { data: new Uint8Array(BundleCrypto.TAG_LEN) }
    };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, gcm);
    const out: cryptoFramework.DataBlob =
      await cipher.doFinal({ data: new util.TextEncoder().encodeInto(plainText) });

    const res: BundleCipher = new BundleCipher();
    res.salt = BundleCrypto.toBase64(salt);
    res.nonce = BundleCrypto.toBase64(nonce);
    res.body = BundleCrypto.toBase64(out.data);
    return res;
  }

  /**
   * 解密。口令错 / 文件被改过 / 版本不符都会抛异常——
   * 不做"尽量恢复"：GCM 校验失败就是失败，硬解出来的内容不可信。
   */
  static async decrypt(body: BundleCipher, passphrase: string): Promise<string> {
    const salt: Uint8Array = BundleCrypto.fromBase64(body.salt);
    const nonce: Uint8Array = BundleCrypto.fromBase64(body.nonce);
    const raw: Uint8Array = BundleCrypto.fromBase64(body.body);
    if (raw.length <= BundleCrypto.TAG_LEN) {
      throw new Error('文件内容不完整');
    }
    // GCM 的 16 字节 tag 在密文尾部：切出来单独交给 cipher
    const cipherText: Uint8Array = raw.slice(0, raw.length - BundleCrypto.TAG_LEN);
    const tag: Uint8Array = raw.slice(raw.length - BundleCrypto.TAG_LEN);

    const key: cryptoFramework.SymKey = await BundleCrypto.deriveKey(passphrase, salt);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const gcm: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: nonce },
      aad: { data: new Uint8Array(0) },
      authTag: { data: tag }
    };
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, gcm);
    let plain: cryptoFramework.DataBlob;
    try {
      plain = await cipher.doFinal({ data: cipherText });
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      Logger.warn(`bundle decrypt failed (wrong passphrase or tampered file): ${m}`);
      throw new Error('口令不正确，或文件已损坏');
    }
    return new util.TextDecoder().decodeToString(plain.data);
  }
}

/** 加密结果的三段式，序列化进文件头 */
export class BundleCipher {
  salt: string = '';
  nonce: string = '';
  body: string = '';
}
