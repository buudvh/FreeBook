/** Wire contract shared by the VS Code client and the future FreeBook debug server. */

export const DEBUG_PROTOCOL_VERSION = 1 as const;
export const DRAFT_BINARY_MAGIC = "FBD1";

export type JsonPrimitive = boolean | number | string | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonArray;
export type JsonObject = { readonly [key: string]: JsonValue };
export type JsonArray = readonly JsonValue[];

export type DebugMethod =
    | "hello"
    | "pair"
    | "extensions.list"
    | "draft.stage"
    | "run.start"
    | "run.cancel"
    | "events.subscribe";

export interface WireRequest<TParams = JsonValue> {
    readonly protocol: typeof DEBUG_PROTOCOL_VERSION;
    readonly type: "request";
    readonly id: string;
    readonly method: DebugMethod;
    readonly params: TParams;
    /** Opaque session secret returned by pair; never write it to logs or settings. */
    readonly session?: string;
}

export interface ProtocolErrorPayload {
    readonly code: string;
    readonly message: string;
    readonly details?: JsonValue;
}

export interface WireResponse<TResult = JsonValue> {
    readonly protocol: typeof DEBUG_PROTOCOL_VERSION;
    readonly type: "response";
    readonly id: string;
    readonly ok: boolean;
    readonly result?: TResult;
    readonly error?: ProtocolErrorPayload;
}

export interface WireEvent {
    readonly protocol: typeof DEBUG_PROTOCOL_VERSION;
    readonly type: "event";
    readonly event: DebugTraceEvent;
}

export type WireMessage = WireResponse | WireEvent;

export interface DebugClientInfo {
    readonly name: string;
    readonly kind: "vscode";
    readonly version?: string;
    readonly platform: "desktop";
}

export interface HelloRequest {
    readonly client: DebugClientInfo;
}

export interface HelloResponse {
    readonly server: {
        readonly name: string;
        readonly version?: string;
    };
    readonly pairingRequired: boolean;
    readonly sessionAccepted?: boolean;
}

export interface PairRequest {
    readonly oneTimeToken: string;
}

export interface PairResponse {
    /** Store this opaque value only through VS Code SecretStorage. */
    readonly session: string;
    readonly expiresAt?: string;
}

export interface InstalledExtension {
    readonly packageId: string;
    readonly name?: string;
    readonly version?: string;
    readonly scriptKeys?: readonly string[];
}

export interface ExtensionsListResponse {
    readonly extensions: readonly InstalledExtension[];
}

export interface DraftSnapshotFile {
    /** Slash-separated path, relative to the extension root. */
    readonly path: string;
    readonly bytes: Uint8Array;
    readonly sha256?: string;
}

export interface DraftSnapshot {
    readonly packageId: string;
    readonly manifestHash: string;
    readonly files: readonly DraftSnapshotFile[];
}

export interface DraftFileDescriptor {
    readonly path: string;
    readonly size: number;
    readonly sha256?: string;
}

export interface DraftStageManifestRequest {
    readonly phase: "manifest";
    readonly packageId: string;
    readonly manifestHash: string;
    readonly files: readonly DraftFileDescriptor[];
}

export interface DraftStageManifestResponse {
    readonly uploadId: string;
    /** Maximum payload bytes per binary draft frame. */
    readonly maxChunkBytes: number;
    /** Omit to request every file. */
    readonly requiredPaths?: readonly string[];
}

export interface DraftStageCompleteRequest {
    readonly phase: "complete";
    readonly uploadId: string;
}

export interface DraftStageCompleteResponse {
    readonly draftId: string;
    readonly manifestHash: string;
}

export interface DraftBinaryFrameHeader {
    readonly protocol: typeof DEBUG_PROTOCOL_VERSION;
    readonly type: "binary";
    readonly channel: "draft.stage";
    readonly uploadId: string;
    readonly path: string;
    readonly offset: number;
    readonly byteLength: number;
    readonly final: boolean;
}

export interface StagedDraft {
    readonly draftId: string;
    readonly manifestHash: string;
}

export type RunTarget = InstalledRunTarget | DraftRunTarget;

export interface InstalledRunTarget {
    readonly mode: "installed";
    readonly packageId: string;
}

export interface DraftRunTarget {
    readonly mode: "draft";
    readonly packageId: string;
    readonly draftId: string;
}

/**
 * These discriminators deliberately mirror ExtensionManager rather than sending
 * already-resolved positional JS arguments. The app owns URL resolution and
 * invokes JSExecutor.runAsync(..., functionName: "execute").
 */
export type DebugInvocation =
    | SearchInvocation
    | UrlInvocation
    | NoArgumentInvocation
    | CustomInvocation
    | GenericScriptInvocation;

export interface SearchInvocation {
    readonly kind: "search";
    readonly query: string;
    /** String by contract: JS receives execute(query, String(page)). */
    readonly page: string;
}

export interface UrlInvocation {
    readonly kind: "detail" | "toc" | "chap" | "page";
    readonly url: string;
    readonly host?: string;
}

export interface NoArgumentInvocation {
    readonly kind: "genre" | "home";
}

export interface CustomInvocation {
    readonly kind: "custom";
    readonly scriptPath: string;
    readonly input: string;
    readonly page: number;
    readonly pageUrl?: string;
}

/** A manifest-unlisted script; client validation must allow this only for draft targets. */
export interface GenericScriptInvocation {
    readonly kind: "script";
    readonly scriptPath: string;
    readonly arguments: readonly JsonValue[];
}

export interface RunStartRequest {
    readonly target: RunTarget;
    readonly invocation: DebugInvocation;
    /** Resolved plugin defaults, optionally overridden by the saved profile. */
    readonly config: JsonObject;
}

export interface RunStartResponse {
    readonly runId: string;
    readonly acceptedAt?: string;
}

export interface RunCancelRequest {
    readonly runId: string;
}

export interface RunCancelResponse {
    readonly runId: string;
    readonly accepted: boolean;
}

export type DebugTraceKind =
    | "console"
    | "compile_error"
    | "runtime_error"
    | "fetch"
    | "load"
    | "browser"
    | "result"
    | "cancelled"
    | "timed_out";

export interface DebugTraceEvent {
    readonly kind: DebugTraceKind;
    readonly runtime: "ios" | "mock";
    readonly timestamp?: string;
    readonly runId?: string;
    readonly message?: string;
    readonly data?: JsonValue;
    /** Relative extension path supplied by the app when it can determine it. */
    readonly sourcePath?: string;
    /** Saved-file SHA-256 captured by the draft snapshot. */
    readonly sourceRevision?: string;
    readonly line?: number;
    readonly column?: number;
}

export interface EventsSubscribeRequest {
    readonly runId?: string;
}

export interface EventsSubscribeResponse {
    readonly subscriptionId?: string;
}

export interface PairingUri {
    readonly endpoint: string;
    readonly oneTimeToken: string;
}

export class DebugProtocolError extends Error {
    public constructor(message: string, public readonly code = "protocol_error") {
        super(message);
        this.name = "DebugProtocolError";
    }
}

let requestSequence = 0;

export function createRequestId(): string {
    requestSequence = (requestSequence + 1) % Number.MAX_SAFE_INTEGER;
    return `vscode-${Date.now().toString(36)}-${requestSequence.toString(36)}`;
}

export function makeSearchInvocation(query: string, page: string | number): SearchInvocation {
    return { kind: "search", query, page: String(page) };
}

export function isSafeExtensionRelativePath(path: string): boolean {
    if (!path || path.includes("\\") || path.includes("\0") || path.startsWith("/")) {
        return false;
    }
    return path.split("/").every((part) => part !== "" && part !== "." && part !== "..");
}

export function validateWebSocketEndpoint(endpoint: string): string {
    let parsed: URL;
    try {
        parsed = new URL(endpoint);
    } catch {
        throw new DebugProtocolError("Pairing URI has an invalid WebSocket endpoint.", "invalid_endpoint");
    }
    if (
        (parsed.protocol !== "ws:" && parsed.protocol !== "wss:")
        || !parsed.hostname
        || parsed.username
        || parsed.password
        || parsed.search
    ) {
        throw new DebugProtocolError("Pairing URI must contain a ws:// or wss:// endpoint without credentials or query secrets.", "invalid_endpoint");
    }
    parsed.hash = "";
    return parsed.toString();
}

/** Parses `freebook-debug://pair?endpoint=ws%3A...&token=...` without logging its secret. */
export function parsePairingUri(value: string): PairingUri {
    let parsed: URL;
    try {
        parsed = new URL(value.trim());
    } catch {
        throw new DebugProtocolError("The pairing URI is invalid.", "invalid_pairing_uri");
    }

    const supportedSchemes = new Set(["freebook-debug:", "freebook-ext-debug:", "freebook:"]);
    const isPairRoute = parsed.hostname === "pair" || parsed.pathname.replace(/\/$/, "").endsWith("/pair");
    const endpoint = parsed.searchParams.get("endpoint");
    const oneTimeToken = parsed.searchParams.get("token");
    if (!supportedSchemes.has(parsed.protocol) || !isPairRoute || !endpoint || !oneTimeToken) {
        throw new DebugProtocolError("The pairing URI must contain a FreeBook pair route, endpoint, and token.", "invalid_pairing_uri");
    }

    return { endpoint: validateWebSocketEndpoint(endpoint), oneTimeToken };
}

export function redactSecrets(value: string, secrets: readonly (string | undefined)[] = []): string {
    let redacted = value;
    for (const secret of secrets) {
        if (secret) {
            redacted = redacted.split(secret).join("[redacted]");
        }
    }
    return redacted
        .replace(/([?&](?:[^=&]*?(?:token|secret|password|api[_-]?key)|authorization|cookie|session)=)[^&\s]+/gi, "$1[redacted]")
        .replace(/((?:["']?)(?:[\w-]*?(?:token|secret|password|credential|api[_ -]?key)|authorization|cookie|set-cookie)(?:["']?)\s*[:=]\s*)(?:["'][^"']*["']|[^,}\]\s]+)/gi, "$1[redacted]")
        .replace(/\b(?:authorization|cookie|set-cookie|x-api-key)\s*:\s*[^\r\n,}]+/gi, (match) => `${match.slice(0, match.indexOf(":"))}: [redacted]`);
}

export function isWireMessage(value: unknown): value is WireMessage {
    if (!isRecord(value) || value.protocol !== DEBUG_PROTOCOL_VERSION) {
        return false;
    }
    if (value.type === "response") {
        return typeof value.id === "string" && typeof value.ok === "boolean";
    }
    return value.type === "event" && isRecord(value.event) && typeof value.event.kind === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null;
}
