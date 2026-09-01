import WebSocket from 'ws';
import { randomUUID } from 'crypto';
import {
  DebugEvent,
  Envelope,
  Payload,
  PROTOCOL_VERSION,
  ServerTarget,
  SUBPROTOCOL
} from './protocol';

/**
 * Client WebSocket của debug server trên app.
 *
 * Một kết nối, một request-in-flight-map. Mọi lệnh đều `request()` (chờ `reply`/`error`); event của
 * server (`type: 'event'`) đi qua callback riêng vì nó không thuộc request nào.
 *
 * Không có bước ghép nối: server bật là nối được bằng `ws://host:port`.
 */
export class ExtDebugClient {
  private socket: WebSocket | undefined;
  private pending = new Map<string, { resolve: (p: Payload) => void; reject: (e: Error) => void }>();
  private subscriptionId: string | undefined;

  constructor(
    private readonly onEvent: (event: DebugEvent) => void,
    private readonly onClosed: (reason: string) => void
  ) {}

  get isConnected(): boolean {
    return this.socket?.readyState === WebSocket.OPEN;
  }

  async connect(target: ServerTarget, timeoutMs = 8000): Promise<void> {
    await this.disconnect();
    const url = `ws://${target.host}:${target.port}`;
    const socket = new WebSocket(url, [SUBPROTOCOL], { handshakeTimeout: timeoutMs });
    this.socket = socket;

    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Hết ${timeoutMs} ms mà không kết nối được ${url}`)), timeoutMs);
      socket.once('open', () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once('error', (error: Error) => {
        clearTimeout(timer);
        reject(error);
      });
    });

    socket.on('message', (data: WebSocket.RawData) => this.handleMessage(data.toString()));
    socket.on('close', () => {
      this.failAllPending(new Error('Kết nối đã đóng'));
      this.socket = undefined;
      this.onClosed('Kết nối đã đóng');
    });
  }

  async disconnect(): Promise<void> {
    const socket = this.socket;
    this.socket = undefined;
    this.failAllPending(new Error('Đã ngắt kết nối'));
    if (!socket) {
      return;
    }
    await new Promise<void>((resolve) => {
      socket.once('close', () => resolve());
      socket.close();
      setTimeout(resolve, 1000);
    });
  }

  /** Gửi lệnh và chờ `reply`. `error` từ server thành `Error` có `code` ở đầu message. */
  request(type: string, payload: Payload = {}, timeoutMs = 30000): Promise<Payload> {
    const socket = this.socket;
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error('Chưa kết nối tới app'));
    }
    const requestId = randomUUID();
    const envelope: Envelope = { version: PROTOCOL_VERSION, requestId, type, payload };
    return new Promise<Payload>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        reject(new Error(`Lệnh '${type}' không có phản hồi sau ${timeoutMs} ms`));
      }, timeoutMs);
      this.pending.set(requestId, {
        resolve: (value) => {
          clearTimeout(timer);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        }
      });
      socket.send(JSON.stringify(envelope));
    });
  }

  /**
   * Một subscription duy nhất cho cả phiên; server phát mọi run và client tự lọc theo `runId`.
   * `draft.install`/`draft.rollback` chờ người dùng bấm trên thiết bị nên timeout của chúng phải dài.
   */
  async subscribeEvents(): Promise<void> {
    const payload = await this.request('events.subscribe');
    this.subscriptionId = payload.message ?? 'events';
  }

  get currentSubscriptionId(): string | undefined {
    return this.subscriptionId;
  }

  private handleMessage(raw: string): void {
    let envelope: Envelope;
    try {
      envelope = JSON.parse(raw) as Envelope;
    } catch {
      return;
    }

    if (envelope.type === 'event') {
      for (const event of envelope.payload?.events ?? []) {
        this.onEvent(event);
      }
      return;
    }
    const waiter = this.pending.get(envelope.requestId);
    if (!waiter) {
      return;
    }
    this.pending.delete(envelope.requestId);
    if (envelope.type === 'error') {
      const code = envelope.payload?.code ?? 'INTERNAL_ERROR';
      const detail = envelope.payload?.issues?.join('\n') ?? envelope.payload?.message ?? 'Lỗi không rõ';
      waiter.reject(new Error(`[${code}] ${detail}`));
      return;
    }
    waiter.resolve(envelope.payload ?? {});
  }

  private failAllPending(error: Error): void {
    for (const waiter of this.pending.values()) {
      waiter.reject(error);
    }
    this.pending.clear();
  }
}
