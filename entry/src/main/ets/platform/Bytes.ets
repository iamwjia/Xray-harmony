/**
 * platform/Bytes.ets — 字节与字符串互转（显式实现，不依赖 TextEncoder/TextDecoder）
 *
 * 为什么不用 `util.TextEncoder().encodeInto()`：
 * 实测在 ArkTS 下它会返回**空数组**（见 commit a686761 的排查记录），
 * 导致"secret 存成空串""哈希输入为空"这类静默错误。
 * 编解码是基础操作，用 20 行确定性代码换掉一个不可靠的 API 是值得的。
 */

import { util } from '@kit.ArkTS';

export class Bytes {
  /** UTF-8 编码 */
  static encode(v: string): Uint8Array {
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

  /** UTF-8 解码；遇到非法起始字节直接跳过，不让整段解析失败 */
  static decode(v: Uint8Array): string {
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
   * Base64 解码为字符串。
   * 订阅链接常见两种形态：明文多行链接，或整段 Base64（v2ray 系客户端通用做法），
   * 后者解出来仍是 UTF-8 文本，所以解码后再走同一个解析路径。
   * 失败返回空串，由调用方判断「不是 Base64」还是「URL 本身有问题」。
   */
  static base64ToText(b64: string): string {
    try {
      const helper = new util.Base64Helper();
      // 允许 URL 安全变体与缺失填充
      const normalized: string = b64.replace(/-/g, '+').replace(/_/g, '/').replace(/\s/g, '');
      const padded: string = normalized + '='.repeat((4 - normalized.length % 4) % 4);
      const raw: Uint8Array = helper.decodeSync(padded);
      return Bytes.decode(raw);
    } catch (e) {
      return '';
    }
  }
}
