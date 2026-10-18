/**
 * service/GeoAssets.ets — geoip/geosite 资源落地与内核挂载
 *
 * 为什么不能"直接从 rawfile 读"：
 *   xray-core 用**普通文件 IO** 打开 geoip.dat / geosite.dat，路径来自
 *   `xray.location.asset` 目录。rawfile 在 HAP 内，内核看不到，必须先解出来。
 *
 * 为什么 rawfile 里放的是 zip 而不是两个 .dat：
 *   HAP 内的 rawfile **不做压缩存储**。实测直接把 geoip.dat(23.3MB)+geosite.dat(2.3MB)
 *   放进 rawfile，HAP 从 16.0MB 涨到 41.7MB（+25.6MB）。打成 zip 后只有 5.37MB，
 *   HAP 涨幅降到约 5.4MB —— 同一份资源，体积差 20MB，纯粹是打包方式差异。
 *
 * 顺序约束：
 *   `setAssetPath` 必须在 `runXrayFromJson` **之前**调用。规则里的 `geosite:cn`
 *   是在实例创建时解析的，那一刻目录不对就是硬性配置错误，不会延迟重试。
 *
 * 资源来源与实测体积（v2fly 官方构建，2026-10-18）：
 *   geoip.dat   23,258,601 B
 *   geosite.dat  2,328,878 B
 *   geo.zip      5,371,683 B（= HAP 实际增量）
 */

import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { http as httpClient } from '@kit.NetworkKit';
import nativeEntry from 'libentry.so';
import { Logger } from '../platform/Logger';

const GEO_DIR: string = 'geo';
const ZIP_NAME: string = 'geo.zip';
const GEOIP: string = 'geoip.dat';
const GEOSITE: string = 'geosite.dat';
const VERSION_FILE: string = '.version';
/** 手动更新的数据源：v2fly 官方 releases（与内置资源同源，避免口径不一致） */
const GEOIP_URL: string = 'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat';
const GEOSITE_URL: string = 'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat';

/** 一次下载任务：临时文件 → 目标文件 */
class GeoDownload {
  name: string = '';
  url: string = '';
  temp: string = '';
  target: string = '';

  constructor(url: string, target: string, temp: string) {
    this.url = url;
    this.target = target;
    this.temp = temp;
    this.name = target.substring(target.lastIndexOf('/') + 1);
  }
}
/**
 * 资源版本标记。**更新 geo 数据时必须同步改这个常量**，否则老用户不会重新解包。
 * 格式：来源-日期，与设置页显示的值保持一致。
 */
const GEO_VERSION: string = 'v2fly-2026-10-18';
/** 低于此大小说明解包不完整（真实文件都在 MB 级），防止把半截文件当成功 */
const MIN_EXPECTED_BYTES: number = 100 * 1024;

export class GeoAssets {
  private static ready: boolean = false;
  private static dir: string = '';
  private static version: string = '';

  static getDir(): string {
    return GeoAssets.dir;
  }

  /** 资源版本（设置页展示用）；未就绪时为空串 */
  static getVersion(): string {
    return GeoAssets.version;
  }

  static isReady(): boolean {
    return GeoAssets.ready;
  }

  /**
   * 解出资源并挂到内核。幂等：版本一致时直接返回 true。
   * 返回 false 表示资源不可用 —— 调用方必须让 **RULE 模式降级**（不生成 geo 规则），
   * 而不是让内核带着 `geosite:cn` 去启动然后失败。
   */
  static async ensure(context: common.UIAbilityContext): Promise<boolean> {
    if (GeoAssets.ready) {
      return true;
    }
    const dir: string = `${context.filesDir}/${GEO_DIR}`;
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
      }
      if (GeoAssets.isUpToDate(dir)) {
        return GeoAssets.attach(dir);
      }
      if (!await GeoAssets.extractZip(context, dir)) {
        return false;
      }
      GeoAssets.writeVersion(dir);
      return GeoAssets.attach(dir);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`geo assets failed: ${msg}`);
      return false;
    }
  }

  /**
   * 版本标记 + 两个文件都在 + 大小不离谱，才算"已就绪"。
   * 只查文件存在是不够的：解包中断会留下一个截断的 .dat，内核读它会报"资源损坏"。
   */
  private static isUpToDate(dir: string): boolean {
    try {
      const vf: string = `${dir}/${VERSION_FILE}`;
      if (!fileIo.accessSync(vf) || !fileIo.accessSync(`${dir}/${GEOIP}`) ||
        !fileIo.accessSync(`${dir}/${GEOSITE}`)) {
        return false;
      }
      if (fileIo.statSync(`${dir}/${GEOIP}`).size < MIN_EXPECTED_BYTES ||
        fileIo.statSync(`${dir}/${GEOSITE}`).size < MIN_EXPECTED_BYTES) {
        Logger.warn('geo files too small, treating as incomplete');
        return false;
      }
      const f = fileIo.openSync(vf, fileIo.OpenMode.READ_ONLY);
      let text: string = '';
      try {
        const stat = fileIo.statSync(vf);
        if (stat.size > 0 && stat.size < 256) {
          const buf = new ArrayBuffer(stat.size);
          fileIo.readSync(f.fd, buf);
          text = GeoAssets.bytesToString(new Uint8Array(buf));
        }
      } finally {
        fileIo.closeSync(f);
      }
      if (text.trim() !== GEO_VERSION) {
        Logger.info(`geo version ${text.trim()} != ${GEO_VERSION}, re-extracting`);
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  private static writeVersion(dir: string): void {
    GeoAssets.writeVersionValue(dir, GEO_VERSION);
  }

  private static writeVersionValue(dir: string, value: string): void {
    try {
      const f = fileIo.openSync(`${dir}/${VERSION_FILE}`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(f.fd, value);
      } finally {
        fileIo.closeSync(f);
      }
    } catch (e) {
      Logger.warn('geo: failed to write version marker (will re-extract next launch)');
    }
  }

  private static todayTag(): string {
    const d = new Date();
    const m: string = d.getMonth() + 1 < 10 ? `0${d.getMonth() + 1}` : `${d.getMonth() + 1}`;
    const day: string = d.getDate() < 10 ? `0${d.getDate()}` : `${d.getDate()}`;
    return `v2fly-${d.getFullYear()}-${m}-${day}`;
  }

  /** 只用于读版本标记这类 ASCII 短文本；不用于解析 .dat */
  private static bytesToString(bytes: Uint8Array): string {
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] === 0 || bytes[i] === 10 || bytes[i] === 13) {
        continue;
      }
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  }

  /**
   * rawfile 的 zip 先落到 cache，再交给系统 unzip 解到目标目录。
   * 不直接读成一个大字符串：zip 里是 25MB 资源，ArkTS 侧没必要为它分配整块缓冲。
   */
  private static async extractZip(context: common.UIAbilityContext, dir: string): Promise<boolean> {
    const zipPath: string = `${context.cacheDir}/${ZIP_NAME}`;
    try {
      if (fileIo.accessSync(zipPath)) {
        fileIo.unlinkSync(zipPath);
      }
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(ZIP_NAME);
      const f = fileIo.openSync(zipPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(f.fd, bytes.buffer);
      } finally {
        fileIo.closeSync(f);
      }
      Logger.info(`geo zip staged to cache: ${bytes.length} bytes`);
      await zlib.unzipFile(zipPath, dir, {});
      Logger.info('geo zip unzipped');
      if (!fileIo.accessSync(`${dir}/${GEOIP}`) || !fileIo.accessSync(`${dir}/${GEOSITE}`)) {
        Logger.error('geo unzip finished but expected files are missing');
        return false;
      }
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Logger.error(`geo unzip failed: ${msg}`);
      return false;
    } finally {
      try {
        if (fileIo.accessSync(zipPath)) {
          fileIo.unlinkSync(zipPath);
        }
      } catch (e) {
        Logger.warn('geo: failed to remove cached zip');
      }
    }
  }

  private static attach(dir: string, version: string = GEO_VERSION): boolean {
    const resp: string = nativeEntry.setAssetPath(dir);
    if (resp !== 'ok') {
      Logger.error(`setAssetPath rejected: ${resp}`);
      return false;
    }
    GeoAssets.dir = dir;
    GeoAssets.version = version;
    GeoAssets.ready = true;
    Logger.info(`geo assets ready (${version})`);
    return true;
  }

  // -------------------------------------------------------------------------
  // 手动更新（用户显式发起，绝不后台自动下载）
  //
  // 为什么不做自动更新：VPN 类应用在用户不知情时联网下载，是信任问题，
  // 不值得为省一次点击去冒。所以只有这一个入口，且点击前必须告知体积。
  //
  // 失败策略：**任一步失败都保留旧文件**。宁可继续用旧规则，
  // 也不能留下"geoip 是新的、geosite 是旧的"这种半更新状态——那种状态
  // 内核能起但分流结果不可解释，排查成本远高于"更新失败请重试"。
  // -------------------------------------------------------------------------

  /** 返回空串 = 成功；否则为可读失败原因 */
  static async updateFromNetwork(onProgress: (msg: string) => void): Promise<string> {
    const dir: string = GeoAssets.dir;
    if (dir.length === 0) {
      return '资源目录未就绪，请先启动一次应用';
    }
    // 先下小的 geosite（2.3 MB）再下大的 geoip（23 MB）：
    // 网络差时能更快给出"到底通不通"的信号，也避免用户盯着一个巨型文件干等。
    const targets: GeoDownload[] = [
      new GeoDownload(GEOSITE_URL, `${dir}/${GEOSITE}`, `${dir}/${GEOSITE}.tmp`),
      new GeoDownload(GEOIP_URL, `${dir}/${GEOIP}`, `${dir}/${GEOIP}.tmp`)
    ];
    for (let i = 0; i < targets.length; i++) {
      const t: GeoDownload = targets[i];
      onProgress(`正在下载 ${t.name}（${i + 1}/${targets.length}）…`);
      const err: string = await GeoAssets.download(t);
      if (err.length > 0) {
        GeoAssets.cleanupTemps(targets);
        return `${t.name} 下载失败：${err}`;
      }
    }
    // 两个都下载完成后才替换：先落盘再原子改名，避免替换到一半
    try {
      for (let i = 0; i < targets.length; i++) {
        const t: GeoDownload = targets[i];
        if (fileIo.accessSync(t.target)) {
          fileIo.unlinkSync(t.target);
        }
        fileIo.renameSync(t.temp, t.target);
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      GeoAssets.cleanupTemps(targets);
      return `替换资源失败：${msg}`;
    }
    const tag: string = GeoAssets.todayTag();
    GeoAssets.writeVersionValue(dir, tag);
    GeoAssets.ready = false;
    const ok: boolean = GeoAssets.attach(dir, tag);
    if (!ok) {
      return '资源已更新但挂载内核失败，请重启应用';
    }
    onProgress('更新完成');
    return '';
  }

  private static cleanupTemps(targets: GeoDownload[]): void {
    for (let i = 0; i < targets.length; i++) {
      try {
        if (fileIo.accessSync(targets[i].temp)) {
          fileIo.unlinkSync(targets[i].temp);
        }
      } catch (e) {
        Logger.warn('geo update: temp cleanup failed');
      }
    }
  }

  /**
   * 流式下载到临时文件。
   * 用 requestInStream 而不是一次性 ARRAY_BUFFER：geoip 有 23 MB，
   * 整块读进内存对低端机不友好，而且失败时白占一次峰值。
   */
  private static async download(t: GeoDownload): Promise<string> {
    const req: httpClient.HttpRequest = httpClient.createHttp();
    const file = fileIo.openSync(t.temp,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    let received: number = 0;
    try {
      await new Promise<void>((resolve, reject) => {
        req.on('dataReceive', (data: ArrayBuffer) => {
          try {
            fileIo.writeSync(file.fd, data);
            received += data.byteLength;
          } catch (e) {
            reject(new Error('写入临时文件失败'));
          }
        });
        req.on('dataEnd', () => {
          resolve();
        });
        req.requestInStream(t.url, {
          method: httpClient.RequestMethod.GET,
          connectTimeout: 30000,
          // 600s：geoip 23 MB，弱网下 100 KB/s 也要约 4 分钟。
          // 超时设小了会表现成"更新永远失败"，而用户网络其实是能下完的。
          readTimeout: 600000
        }).then(() => {
        }).catch((err: Error) => {
          reject(new Error(err.message));
        });
      });
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      fileIo.closeSync(file);
      return msg;
    }
    fileIo.closeSync(file);
    req.destroy();
    if (received < MIN_EXPECTED_BYTES) {
      return `下载内容过小（${received} B），疑似失败`;
    }
    Logger.info(`geo ${t.name} downloaded: ${received} bytes`);
    return '';
  }
}
