/**
 * Mirror TypeScript của contract `freebook-extdebug.v1`.
 *
 * Nguồn sự thật là Swift: `Sources/Services/Extensions/Debug/Server/ExtensionDebugProtocol.swift` và
 * `.../ExtensionDebugEvent.swift`. Sửa một bên phải sửa bên kia cùng lượt — app là thẩm quyền cuối
 * cùng về manifest, entrypoint và contract; file này chỉ để có kiểu lúc gõ.
 */

export const SUBPROTOCOL = 'freebook-extdebug.v1';
export const PROTOCOL_VERSION = 1;

export type CommandType =
  | 'hello'
  | 'pair'
  | 'extensions.list'
  | 'run.start'
  | 'run.cancel'
  | 'run.get'
  | 'events.subscribe'
  | 'draft.stage'
  | 'draft.chunk'
  | 'draft.finish'
  | 'draft.discard'
  | 'draft.install'
  | 'draft.rollback';

export type EventCategory =
  | 'runStarted'
  | 'compileFailed'
  | 'runFinished'
  | 'cancelled'
  | 'console'
  | 'exception'
  | 'responseValidated'
  | 'responseError'
  | 'fetchStarted'
  | 'fetchFinished'
  | 'fetchFailed'
  | 'eventsDropped';

export type EventLevel = 'debug' | 'info' | 'warning' | 'error';

export interface SourceLocation {
  script: string;
  line?: number;
  column?: number;
  revision: string;
  stack?: string;
}

export interface DebugEvent {
  id: string;
  runId: string;
  sequence: number;
  /** Số giây theo reference date của Apple (2001-01-01), do JSONEncoder mặc định. */
  timestamp: number;
  packageId: string;
  script: string;
  sourceRevision: string;
  level: EventLevel;
  category: EventCategory;
  message: string;
  location?: SourceLocation;
  details: Record<string, string>;
}

export interface ExtensionInfo {
  packageId: string;
  name: string;
  version: number;
  type: string;
  scripts: string[];
}

export interface DraftManifestEntry {
  relativePath: string;
  size: number;
  sha256: string;
}

export interface DraftManifest {
  packageId: string;
  revision: string;
  entries: DraftManifestEntry[];
}

export interface Payload {
  token?: string;
  clientName?: string;
  extensions?: ExtensionInfo[];
  packageId?: string;
  entrypoint?: string;
  keyword?: string;
  page?: number;
  url?: string;
  scriptFileName?: string;
  input?: string;
  pageUrl?: string;
  sourceMode?: 'installed' | 'draft';
  sourceRevision?: string;
  runId?: string;
  events?: DebugEvent[];
  droppedCount?: number;
  manifest?: DraftManifest;
  relativePath?: string;
  chunkIndex?: number;
  chunkBase64?: string;
  isLastChunk?: boolean;
  issues?: string[];
  code?: string;
  message?: string;
  appVersion?: string;
  contractVersion?: number;
  requiresPairing?: boolean;
}

export interface Envelope {
  version: number;
  requestId: string;
  /** Lệnh khi client gửi; `reply` | `error` | `event` | `paired` khi server trả. */
  type: string;
  payload?: Payload;
}

export interface PairingURI {
  host: string;
  port: number;
  service: string;
  token: string;
}

/** Parse chuỗi hiện cạnh QR trên app. Trả `null` nếu không đúng dạng. */
export function parsePairingURI(raw: string): PairingURI | null {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    return null;
  }
  if (url.protocol !== 'freebook-extdebug:') {
    return null;
  }
  const host = url.searchParams.get('host') ?? '';
  const port = Number(url.searchParams.get('port') ?? '0');
  const service = url.searchParams.get('service') ?? '';
  const token = url.searchParams.get('token') ?? '';
  if (!host || !port || !token) {
    return null;
  }
  return { host, port, service, token };
}
