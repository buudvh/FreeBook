import {
    DEBUG_PROTOCOL_VERSION,
    createRequestId,
    type DebugMethod,
    type DebugTraceEvent,
    type DraftSnapshot,
    type ExtensionsListResponse,
    type HelloResponse,
    type InstalledExtension,
    type PairRequest,
    type PairResponse,
    type RunCancelResponse,
    type RunStartRequest,
    type RunStartResponse,
    type StagedDraft,
} from "./protocol";
import {
    DebugTransportError,
    assertValidRunRequest,
    assertValidSnapshot,
    type DebugDisconnectListener,
    type DebugEventSubscription,
    type DebugTraceListener,
    type DebugTransport,
} from "./transport";

export interface MockWireRequest {
    readonly protocol: typeof DEBUG_PROTOCOL_VERSION;
    readonly type: "request";
    readonly id: string;
    readonly method: DebugMethod;
    readonly params: unknown;
}

export interface MockBinaryFrame {
    readonly path: string;
    readonly offset: number;
    readonly byteLength: number;
    readonly final: boolean;
}

export interface MockDebugTransportOptions {
    readonly extensions?: readonly InstalledExtension[];
    readonly maxChunkBytes?: number;
}

/**
 * Protocol/UX fixture only. It never evaluates JavaScript or imitates an iOS
 * JSExecutor, so callers can never mistake its result for an app runtime run.
 */
export class MockDebugTransport implements DebugTransport {
    public readonly kind = "mock" as const;
    public readonly displayName = "Mock — không chạy JSExecutor iOS";
    private readonly requestLog: MockWireRequest[] = [];
    private readonly binaryLog: MockBinaryFrame[] = [];
    private readonly listeners = new Set<DebugTraceListener>();
    private readonly activeRuns = new Set<string>();
    private readonly extensions: readonly InstalledExtension[];
    private readonly maxChunkBytes: number;
    private connected = false;
    private disposed = false;
    private sequence = 0;

    public constructor(options: MockDebugTransportOptions = {}) {
        this.extensions = options.extensions ?? [];
        this.maxChunkBytes = Math.max(1, options.maxChunkBytes ?? 64 * 1024);
    }

    public get wireRequests(): readonly MockWireRequest[] {
        return this.requestLog;
    }

    public get binaryFrames(): readonly MockBinaryFrame[] {
        return this.binaryLog;
    }

    public async connect(): Promise<HelloResponse> {
        this.assertUsable();
        this.connected = true;
        this.record("hello", { client: { name: "FreeBook VS Code", kind: "vscode", platform: "desktop" } });
        return { server: { name: "Mock Debug Transport", version: "mock" }, pairingRequired: false };
    }

    public async pair(request: PairRequest): Promise<PairResponse> {
        this.assertConnected();
        if (!request.oneTimeToken.trim()) {
            throw new DebugTransportError("A pairing token is required.", "invalid_pairing");
        }
        this.record("pair", { oneTimeToken: "[redacted]" });
        return { session: `mock-session-${++this.sequence}` };
    }

    public async listExtensions(): Promise<ExtensionsListResponse> {
        this.assertConnected();
        this.record("extensions.list", {});
        return { extensions: this.extensions };
    }

    public async stageDraft(snapshot: DraftSnapshot): Promise<StagedDraft> {
        this.assertConnected();
        assertValidSnapshot(snapshot);

        const uploadId = `mock-upload-${++this.sequence}`;
        this.record("draft.stage", {
            phase: "manifest",
            packageId: snapshot.packageId,
            manifestHash: snapshot.manifestHash,
            files: snapshot.files.map((file) => ({ path: file.path, size: file.bytes.byteLength, sha256: file.sha256 })),
        });

        for (const file of snapshot.files) {
            if (file.bytes.byteLength === 0) {
                this.binaryLog.push({ path: file.path, offset: 0, byteLength: 0, final: true });
                continue;
            }
            for (let offset = 0; offset < file.bytes.byteLength; offset += this.maxChunkBytes) {
                const byteLength = Math.min(this.maxChunkBytes, file.bytes.byteLength - offset);
                this.binaryLog.push({ path: file.path, offset, byteLength, final: offset + byteLength === file.bytes.byteLength });
            }
        }

        this.record("draft.stage", { phase: "complete", uploadId });
        return { draftId: `mock-draft-${this.sequence}`, manifestHash: snapshot.manifestHash };
    }

    public async run(request: RunStartRequest): Promise<RunStartResponse> {
        this.assertConnected();
        assertValidRunRequest(request);
        const runId = `mock-run-${++this.sequence}`;
        this.activeRuns.add(runId);
        this.record("run.start", request);

        setTimeout(() => {
            if (!this.activeRuns.delete(runId) || this.disposed) {
                return;
            }
            this.emit({
                kind: "console",
                runtime: "mock",
                runId,
                message: "Mock — không chạy JSExecutor iOS; payload chỉ được kiểm tra theo protocol.",
            });
            this.emit({ kind: "result", runtime: "mock", runId, data: { mock: true } });
        }, 0);
        return { runId };
    }

    public async cancel(runId: string): Promise<RunCancelResponse> {
        this.assertConnected();
        const accepted = this.activeRuns.delete(runId);
        this.record("run.cancel", { runId });
        if (accepted) {
            this.emit({ kind: "cancelled", runtime: "mock", runId, message: "Mock run cancelled." });
        }
        return { runId, accepted };
    }

    public async subscribe(listener: DebugTraceListener, request: { readonly runId?: string } = {}): Promise<DebugEventSubscription> {
        this.assertConnected();
        this.record("events.subscribe", request);
        this.listeners.add(listener);
        return { dispose: () => this.listeners.delete(listener) };
    }

    public onDidDisconnect(_listener: DebugDisconnectListener): DebugEventSubscription {
        // The in-process mock has no socket lifecycle.
        return { dispose: () => undefined };
    }

    public dispose(): void {
        this.disposed = true;
        this.connected = false;
        this.activeRuns.clear();
        this.listeners.clear();
    }

    private record(method: DebugMethod, params: unknown): void {
        this.requestLog.push({ protocol: DEBUG_PROTOCOL_VERSION, type: "request", id: createRequestId(), method, params });
    }

    private emit(event: DebugTraceEvent): void {
        for (const listener of this.listeners) {
            listener(event);
        }
    }

    private assertUsable(): void {
        if (this.disposed) {
            throw new DebugTransportError("The debug transport has been disposed.", "disposed");
        }
    }

    private assertConnected(): void {
        this.assertUsable();
        if (!this.connected) {
            throw new DebugTransportError("Connect the debug transport before sending commands.", "not_connected");
        }
    }
}
