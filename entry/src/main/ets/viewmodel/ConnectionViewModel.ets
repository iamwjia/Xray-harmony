/**
 * viewmodel/ConnectionViewModel.ets — 连接状态机（应用服务层的 UI 侧投影）
 *
 * 职责：定义 Disconnected / Connecting / Connected / Error 四态与**合法迁移表**，
 *       并把状态**单向派生**成 UI 需要的展示信息（文案 / 颜色 / 是否忙碌）。
 *
 * 边界（对应 FR-13「UI 状态不说谎」）：
 *   - UI **不得**自行置位状态，只能调用 requestConnect / requestDisconnect；
 *   - UI **不得**自己判断"看起来连上了"，一律读 deriveView()；
 *   - 本层目前是**占位实现**：尚未接内核，因此 requestConnect 只做状态迁移，
 *     真实连接由后续 service/KernelService 驱动（见 APP-SKELETON.md 的下一步）。
 */

export enum ConnState {
  DISCONNECTED = 'DISCONNECTED',
  CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED',
  ERROR = 'ERROR'
}

/** UI 视图对象：由状态派生，页面只读它 */
export class ConnectionView {
  label: string = '';
  hint: string = '';
  colorHex: string = '#888888';
  busy: boolean = false;
  canToggle: boolean = true;
}

export class ConnectionViewModel {
  private state: ConnState = ConnState.DISCONNECTED;
  private lastError: string = '';

  getState(): ConnState {
    return this.state;
  }

  getLastError(): string {
    return this.lastError;
  }

  /** 合法迁移表：只允许相邻/明确的边，避免"任意跳转" */
  private isAllowed(from: ConnState, to: ConnState): boolean {
    if (from === ConnState.DISCONNECTED) {
      return to === ConnState.CONNECTING;
    }
    if (from === ConnState.CONNECTING) {
      return to === ConnState.CONNECTED || to === ConnState.ERROR || to === ConnState.DISCONNECTED;
    }
    if (from === ConnState.CONNECTED) {
      return to === ConnState.DISCONNECTED || to === ConnState.ERROR;
    }
    if (from === ConnState.ERROR) {
      return to === ConnState.DISCONNECTED || to === ConnState.CONNECTING;
    }
    return false;
  }

  /** 唯一的迁移入口：非法迁移被拒绝（返回 false），而不是被静默接受 */
  private transition(to: ConnState, reason: string = ''): boolean {
    if (!this.isAllowed(this.state, to)) {
      return false;
    }
    this.state = to;
    if (to === ConnState.ERROR) {
      this.lastError = reason;
    } else if (to === ConnState.DISCONNECTED) {
      this.lastError = '';
    }
    return true;
  }

  /** UI 点击「连接」 */
  requestConnect(): boolean {
    return this.transition(ConnState.CONNECTING);
  }

  /** 内核/服务回报连接成功（将来由 KernelService 调用） */
  onKernelConnected(): boolean {
    return this.transition(ConnState.CONNECTED);
  }

  /** 内核/服务回报失败 */
  onKernelError(reason: string): boolean {
    return this.transition(ConnState.ERROR, reason);
  }

  /** UI 点击「断开」或取消 */
  requestDisconnect(): boolean {
    const ok: boolean = this.transition(ConnState.DISCONNECTED);
    if (!ok && this.state === ConnState.ERROR) {
      return this.transition(ConnState.DISCONNECTED);
    }
    return ok;
  }

  /** 状态 → 展示信息（UI 只读这个结果） */
  deriveView(): ConnectionView {
    const v = new ConnectionView();
    if (this.state === ConnState.DISCONNECTED) {
      v.label = '未连接';
      v.hint = '点击开关启动内核（当前仅本地 SOCKS，未接节点）';
      v.colorHex = '#888888';
      v.busy = false;
      v.canToggle = true;
    } else if (this.state === ConnState.CONNECTING) {
      v.label = '连接中…';
      v.hint = '正在启动内核并确认状态（最多等待 8 秒）';
      v.colorHex = '#FFA726';
      v.busy = true;
      v.canToggle = true;
    } else if (this.state === ConnState.CONNECTED) {
      v.label = '已连接';
      v.hint = '内核已启动（本地 SOCKS 监听中，尚未接入节点）';
      v.colorHex = '#2E7D32';
      v.busy = false;
      v.canToggle = true;
    } else {
      v.label = '连接异常';
      v.hint = this.lastError.length > 0 ? this.lastError : '未知错误';
      v.colorHex = '#C62828';
      v.busy = false;
      v.canToggle = true;
    }
    return v;
  }
}
