/**
 * service/SubscriptionService.ets — 订阅导入（FR-02）
 *
 * 流程：拉取 → 判断编码（明文 / Base64）→ 逐行解析 → 去重入库。
 *
 * 三条刻意的设计：
 *   1. **失败不整体回滚**：一行坏链接不该让整份订阅作废。逐条统计成功/失败，
 *      首条错误原因回传给 UI，让用户知道"是一部分失败"还是"完全失败"。
 *   2. **不把 URL 与节点混为一谈**：URL 里常带 token，只进安全存储；
 *      节点表只存别名（与 FR-35/NFR-06 同一原则）。
 *   3. **不做后台自动更新**（FR-45 的同类约束）：本模块只提供"用户点了才拉"的入口。
 */

import { http as httpClient } from '@kit.NetworkKit';
import { Bytes } from '../platform/Bytes';
import { Logger } from '../platform/Logger';
import { ConfigService } from './ConfigService';
import { ShareLinkParser } from './ShareLinkParser';
import { SubRecord, SubscriptionStore } from './SubscriptionStore';
import { XrayNode } from '../model/AppConfig';

/** 导入结果：UI 只需要这几个数字 + 一句话 */
export class SubscriptionImportResult {
  /** 解析出的节点总数 */
  total: number = 0;
  /** 真正新增的（去重后） */
  added: number = 0;
  /** 已存在而跳过的（不是失败：重新导入同一份订阅的正常结果） */
  skipped: number = 0;
  /** 解析或入库失败的条数 */
  failed: number = 0;
  /** 空串 = 无错误；否则为可读原因（取第一条） */
  error: string = '';
  /** 订阅记录 id（用于后续"更新订阅"） */
  subId: string = '';
}

export class SubscriptionService {
  /**
   * 导入订阅。
   * @param url 订阅地址（含协议头）
   * @param name 用户可见名称；留空则用 host
   */
  static async importFromUrl(url: string, name: string): Promise<SubscriptionImportResult> {
    const result = new SubscriptionImportResult();
    const trimmed: string = (url || '').trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      result.error = '订阅地址必须以 http:// 或 https:// 开头';
      return result;
    }

    let body: string = '';
    try {
      body = await SubscriptionService.fetchText(trimmed);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      result.error = `拉取失败：${msg}`;
      return result;
    }
    if (body.length === 0) {
      result.error = '订阅内容为空';
      return result;
    }

    // 明文订阅通常能直接看到 "://"；否则按 Base64 处理（v2ray 系客户端的通用做法）
    let text: string = body;
    if (text.indexOf('://') < 0) {
      const decoded: string = Bytes.base64ToText(text);
      if (decoded.length > 0 && decoded.indexOf('://') >= 0) {
        text = decoded;
        Logger.info('subscription: body was base64, decoded ok');
      } else {
        result.error = '订阅内容既不是明文链接，也不是可解码的 Base64';
        return result;
      }
    }

    const lines: string[] = text.split('\n');
    let firstError: string = '';
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      result.total++;
      let node: XrayNode;
      try {
        node = ShareLinkParser.parse(line);
      } catch (e) {
        result.failed++;
        if (firstError.length === 0) {
          const msg: string = e instanceof Error ? e.message : String(e);
          firstError = `第 ${i + 1} 行：${msg}`;
        }
        continue;
      }
      const ok: boolean = await ConfigService.getInstance().addNodeSecure(node);
      if (ok) {
        result.added++;
      } else {
        // addNode 返回 false 目前只代表"同 protocol+address+port 已存在"。
        // 这不是失败——重新导入同一份订阅必然如此，所以单独计数，
        // 否则 UI 会把一次正常的"更新订阅"说成失败（实测踩到）。
        result.skipped++;
      }
    }

    // 订阅记录：URL 进安全存储，表里只留别名
    const subId: string = SubscriptionService.makeId(trimmed);
    const alias: string = await SubscriptionStore.putUrl(subId, trimmed);
    if (alias.length > 0) {
      const subs: SubRecord[] | null = SubscriptionStore.load();
      const list: SubRecord[] = subs === null ? [] : subs;
      let found: boolean = false;
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === subId) {
          list[i].lastUpdated = Date.now();
          list[i].nodeCount = result.total;
          found = true;
        }
      }
      if (!found) {
        const rec = new SubRecord();
        rec.id = subId;
        rec.name = name.length > 0 ? name : SubscriptionService.hostOf(trimmed);
        rec.urlRef = alias;
        rec.lastUpdated = Date.now();
        rec.nodeCount = result.total;
        list.push(rec);
      }
      SubscriptionStore.save(list);
      result.subId = subId;
    } else {
      Logger.warn('subscription: url could not be stored securely, record skipped');
    }

    result.error = firstError;
    Logger.info(`subscription import: total=${result.total} added=${result.added} skipped=${result.skipped} failed=${result.failed}`);
    return result;
  }

  /** 拉取文本。超时给定上限：订阅服务器卡住不该让 UI 无限转圈 */
  private static async fetchText(url: string): Promise<string> {
    const req: httpClient.HttpRequest = httpClient.createHttp();
    try {
      const resp: httpClient.HttpResponse = await req.request(url, {
        method: httpClient.RequestMethod.GET,
        expectDataType: httpClient.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingCache: false
      });
      if (resp.responseCode !== 200) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      if (typeof resp.result === 'string') {
        return resp.result as string;
      }
      // 服务端未按字符串返回（例如二进制）时，退化为按字节解码
      if (resp.result instanceof ArrayBuffer) {
        return Bytes.decode(new Uint8Array(resp.result as ArrayBuffer));
      }
      return '';
    } finally {
      req.destroy();
    }
  }

  private static makeId(url: string): string {
    // 只用于本地标识，不含语义；避免把 URL（可能含 token）当 id 用
    let h: number = 0;
    for (let i = 0; i < url.length; i++) {
      h = (h * 31 + url.charCodeAt(i)) | 0;
    }
    return `sub-${Math.abs(h).toString(16)}`;
  }

  private static hostOf(url: string): string {
    const s: string = url.replace('https://', '').replace('http://', '');
    const slash: number = s.indexOf('/');
    return slash > 0 ? s.substring(0, slash) : s;
  }

  /** 现有订阅（不含 URL，只有别名与统计） */
  static listSubscriptions(): SubRecord[] {
    const subs: SubRecord[] | null = SubscriptionStore.load();
    return subs === null ? [] : subs;
  }
}
