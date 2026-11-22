import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Logger } from './Logger';

/**
 * platform/VpnStateFile.ets — 扩展进程 → 应用进程的状态回传
 *
 * 为什么用文件而不是 CommonEvent / 内存共享：
 *   - 两个进程各有自己的内存，`KernelService` 的内核实例也各是一个（tun fd 只在扩展进程有效）；
 *   - 应用进程**没有**任何直接手段查询扩展进程里的内核状态；
 *   - 沙箱目录（`filesDir`）是同应用两进程共享的，写一个状态文件是最小可信通道：
 *     不引入新权限、不依赖事件总线是否跨进程、也不用把 fd 或凭据带出去。
 *
 * 代价是**轮询**。所以只在"正在连接"这种短窗口里轮询（250ms），
 * 拿到结果就停，不做常驻定时器。
 */

export class VpnState {
  /** starting | running | error | stopped */
  state: string = 'stopped';
  /** 仅 error 时有意义（系统错误码） */
  code: number = 0;
  /** 可读原因，不含凭据与地址 */
  msg: string = '';
  /** 写入时间戳（ms）。用来判断状态是否已经过期（扩展进程被系统杀掉不会写 stopped） */
  at: number = 0;
}

const FILE_NAME: string = '/vpn_state.json';

export class VpnStateFile {
  /** 过期阈值：超过这个时长的 running 视为不可信（扩展进程可能已被杀） */
  static readonly STALE_MS: number = 15000;

  static path(ctx: common.Context): string {
    return `${ctx.filesDir}${FILE_NAME}`;
  }

  /** 写状态；失败只记日志，不影响调用方主流程 */
  static write(ctx: common.Context, st: VpnState): void {
    const json: string = JSON.stringify(st);
    try {
      const p: string = VpnStateFile.path(ctx);
      const f = fileIo.openSync(p,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(f.fd, json);
      } finally {
        fileIo.closeSync(f);
      }
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      Logger.error(`vpnState write failed: ${m}`);
    }
  }

  /** 便捷写入 */
  static put(ctx: common.Context, state: string, code: number = 0, msg: string = ''): void {
    const st = new VpnState();
    st.state = state;
    st.code = code;
    st.msg = msg;
    st.at = Date.now();
    VpnStateFile.write(ctx, st);
  }

  /**
   * 读状态；文件不存在返回 null。
   * 不做"猜"：过期与否由调用方判断（读到的 `at` 一并返回）。
   */
  static read(ctx: common.Context): VpnState | null {
    const p: string = VpnStateFile.path(ctx);
    try {
      if (!fileIo.accessSync(p)) {
        return null;
      }
      const stat = fileIo.statSync(p);
      const buf = new ArrayBuffer(stat.size);
      const f = fileIo.openSync(p, fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.readSync(f.fd, buf);
      } finally {
        fileIo.closeSync(f);
      }
      const text: string = new util.TextDecoder().decodeToString(new Uint8Array(buf));
      const st: VpnState = JSON.parse(text) as VpnState;
      if (st === null || st.state === undefined) {
        return null;
      }
      return st;
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      Logger.warn(`vpnState read failed: ${m}`);
      return null;
    }
  }

  static isStale(st: VpnState): boolean {
    return st.at > 0 && (Date.now() - st.at) > VpnStateFile.STALE_MS;
  }

  static clear(ctx: common.Context): void {
    try {
      const p: string = VpnStateFile.path(ctx);
      if (fileIo.accessSync(p)) {
        fileIo.unlinkSync(p);
      }
    } catch (e) {
      const m: string = e instanceof Error ? e.message : String(e);
      Logger.warn(`vpnState clear failed: ${m}`);
    }
  }
}
