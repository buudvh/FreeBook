/**
 * Mirror TypeScript của contract `freebook-extdebug.v1`.
 *
 * Nguồn sự thật là Swift: `Sources/Services/Extensions/Debug/Server/ExtensionDebugProtocol.swift` và
 * `.../ExtensionDebugEvent.swift`. Sửa một bên phải sửa bên kia cùng lượt — app là thẩm quyền cuối
 * cùng về manifest, entrypoint và contract; file này chỉ để có kiểu lúc gõ.
 */

export const SUBPROTOCOL = 'freebook-extdebug.v1';
/**
 * v2 thêm lệnh `legado.*` (nghiệm thu nguồn Legado). App v2 vẫn nhận envelope v1 cho mọi lệnh cũ; app cũ chỉ nhận
 * đúng v1, nên client hạ xuống `MIN_PROTOCOL_VERSION` khi `hello` bị trả `UNSUPPORTED_VERSION` (xem `client.ts`).
 */
export const PROTOCOL_VERSION = 2;
export const MIN_PROTOCOL_VERSION = 1;
/** Lệnh `legado.*` chỉ có ở app nhận protocol v2. */
export const LEGADO_MIN_PROTOCOL_VERSION = 2;

export type CommandType =
  | 'hello'
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
  | 'draft.rollback'
  | 'legado.sources'
  | 'legado.corpus.start'
  | 'legado.corpus.status'
  | 'legado.corpus.cancel';

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
  /** Khoá khai ở mục `script` của `plugin.json`. */
  scripts: string[];
  /**
   * Path tương đối của mọi `.js` **có hàm `execute`** ở gốc extension và `src/` — tập file thật sự chạy
   * được, kể cả script phụ không khai trong `script`. App thêm ở 1.3.348; optional để client vẫn chạy
   * với app cũ hơn.
   */
  executableScripts?: string[];
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

/** Mirror `LegadoCorpusReport` (Swift, `Sources/Services/LegadoSource/Diagnostics/`). */
export type LegadoCorpusStep = 'search' | 'explore' | 'detail' | 'toc' | 'content';
export type LegadoCorpusFailureClass =
  | 'unsupportedSyntax'
  | 'http'
  | 'noMatch'
  | 'timeout'
  | 'javaScript'
  | 'network'
  | 'invalidSource'
  | 'other';
export type LegadoCorpusOutcome = 'passed' | 'failed' | 'skipped' | 'cancelled';
/** Mirror `LegadoFailureVerdict` (Swift) — kết luận "lỗi do ai" của nguồn lỗi. */
export type LegadoFailureVerdict = 'web' | 'sourceOutdated' | 'needsUser' | 'app' | 'unknown';
export type LegadoCorpusState = 'running' | 'finished' | 'cancelled';

export interface LegadoCorpusStepRecord {
  step: LegadoCorpusStep;
  durationMs: number;
  /** Số mục (tìm/khám phá/mục lục), 1/0 (chi tiết có tên), số ký tự (nội dung chương). */
  count: number;
  ok: boolean;
}

export interface LegadoCorpusSourceResult {
  packageId: string;
  name: string;
  outcome: LegadoCorpusOutcome;
  /** `keyword` | `explore` | `catalogExplore` | `bookUrl` | `tocUrl` | `contentUrl` | `-` */
  entry: string;
  /** Từ khoá hoặc URL lối vào (URL đã redact). */
  query: string;
  lastPassedStep?: LegadoCorpusStep;
  failedStep?: LegadoCorpusStep;
  failureClass?: LegadoCorpusFailureClass;
  httpStatus?: number;
  message?: string;
  durationMs: number;
  steps: LegadoCorpusStepRecord[];
  unsupportedHints: string[];
  abandonedSteps: number;
  /** Nguồn tranh/video: chi tiết bước media (nằm trong bước `content`); vắng với truyện chữ và app cũ. */
  media?: LegadoCorpusMediaCheck;
  /** Kết luận "lỗi do ai" — chỉ nguồn lỗi; vắng với nguồn khác và app cũ. */
  verdict?: LegadoFailureVerdict;
  /** Một câu lý do của kết luận (đã redact như `message`). */
  verdictReason?: string;
}

/** Mirror `LegadoCorpusReport.MediaCheck` (Swift). */
export interface LegadoCorpusMediaCheck {
  /** `comic` | `video` */
  kind: string;
  items: number;
  firstItemBytes?: number;
  /** `native` | `webview` | `auto` (video) */
  trackKind?: string;
  decoded: boolean;
  /** `list` | `item` | `track` | `probe`; vắng khi qua. */
  failedStage?: string;
}

export interface LegadoCorpusReport {
  schemaVersion: number;
  runId: string;
  state: LegadoCorpusState;
  /** ISO 8601. */
  startedAt: string;
  finishedAt?: string;
  selection: 'allEnabled' | 'packageIds';
  defaultKeyword: string;
  totalSources: number;
  completed: number;
  /** Mẫu số của tỉ lệ qua = passed + failed (không gồm bỏ qua / huỷ dở). */
  attempted: number;
  passed: number;
  skipped: number;
  cancelledSources: number;
  passPercent: number;
  byFailureClass: Record<string, number>;
  /** Số nguồn lỗi theo kết luận (`LegadoFailureVerdict`); vắng ở app cũ. */
  byVerdict?: Record<string, number>;
  byLastPassedStep: Record<string, number>;
  byFailedStep: Record<string, number>;
  httpStatusCounts: Record<string, number>;
  unsupportedHintCounts: Record<string, number>;
  abandonedSteps: number;
  inFlight: string[];
  /** Tương đối so với `applicationSupport` của app (vd `legado_reports/20261021-153000.json`). */
  reportPath?: string;
  /** Chỉ có khi `legado.corpus.status` gửi `includeSources: true`. */
  sources?: LegadoCorpusSourceResult[];
}

/** Mirror `LegadoCorpusSourceInfo` — nguồn Legado chữ đã cài (`legado.sources`). */
export interface LegadoSourceInfo {
  packageId: string;
  name: string;
  enabled: boolean;
  hasSearchRules: boolean;
  hasExploreRules: boolean;
}

export interface Payload {
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
  // v2 — legado.corpus.start (+ `keyword`) / legado.corpus.status / legado.sources
  packageIds?: string[];
  allEnabled?: boolean;
  limit?: number;
  includeSources?: boolean;
  legadoCorpus?: LegadoCorpusReport;
  legadoSources?: LegadoSourceInfo[];
}

export interface Envelope {
  version: number;
  requestId: string;
  /** Lệnh khi client gửi; `reply` | `error` | `event` khi server trả. */
  type: string;
  payload?: Payload;
}

export interface ServerTarget {
  host: string;
  port: number;
}

/**
 * Nhận cả ba dạng người dùng có thể dán:
 * - `ws://192.168.1.5:17772`
 * - `192.168.1.5:17772`
 * - `freebook-extdebug://pair?host=…&port=…` (dạng cũ; token nếu có sẽ bị bỏ qua)
 */
export function parseTarget(raw: string): ServerTarget | null {
  const text = raw.trim();
  if (!text) {
    return null;
  }

  if (text.startsWith('freebook-extdebug:')) {
    try {
      const url = new URL(text);
      const host = url.searchParams.get('host') ?? '';
      const port = Number(url.searchParams.get('port') ?? '0');
      return host && port ? { host, port } : null;
    } catch {
      return null;
    }
  }

  const withScheme = text.includes('://') ? text : `ws://${text}`;
  try {
    const url = new URL(withScheme);
    const port = Number(url.port);
    return url.hostname && port ? { host: url.hostname, port } : null;
  } catch {
    return null;
  }
}
