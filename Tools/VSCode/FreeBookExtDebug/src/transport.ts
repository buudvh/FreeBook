import {
    DebugProtocolError,
    type DebugTraceEvent,
    type DraftSnapshot as ProtocolDraftSnapshot,
    type EventsSubscribeRequest,
    type ExtensionsListResponse,
    type HelloResponse,
    type PairRequest,
    type PairResponse,
    type RunCancelResponse,
    type RunStartRequest,
    type RunStartResponse,
    type StagedDraft,
    isSafeExtensionRelativePath,
} from "./protocol";

export type DebugTransportKind = "mock" | "websocket";
export type DebugTraceListener = (event: DebugTraceEvent) => void;
export type DebugDisconnectListener = (message: string) => void;

export interface DebugEventSubscription {
    dispose(): void;
}

export interface DebugTransport {
    readonly kind: DebugTransportKind;
    readonly displayName: string;

    connect(): Promise<HelloResponse>;
    pair(request: PairRequest): Promise<PairResponse>;
    listExtensions(): Promise<ExtensionsListResponse>;
    stageDraft(snapshot: ProtocolDraftSnapshot): Promise<StagedDraft>;
    run(request: RunStartRequest): Promise<RunStartResponse>;
    cancel(runId: string): Promise<RunCancelResponse>;
    subscribe(listener: DebugTraceListener, request?: EventsSubscribeRequest): Promise<DebugEventSubscription>;
    onDidDisconnect(listener: DebugDisconnectListener): DebugEventSubscription;
    dispose(): void;
}

export class DebugTransportError extends Error {
    public constructor(message: string, public readonly code = "transport_error") {
        super(message);
        this.name = "DebugTransportError";
    }
}

/** Structural adapter keeps the transport independent from VS Code snapshot code. */
export interface SavedDraftSnapshotInput {
    readonly manifest: Readonly<{ hash: string }>;
    readonly files: readonly Readonly<{
        path: string;
        revision?: string;
        contents: Uint8Array;
    }>[];
}

export function toDraftTransportSnapshot(packageId: string, snapshot: SavedDraftSnapshotInput): ProtocolDraftSnapshot {
    return {
        packageId,
        manifestHash: snapshot.manifest.hash,
        files: snapshot.files.map((file) => ({
            path: file.path,
            bytes: file.contents,
            sha256: file.revision,
        })),
    };
}

export function assertValidSnapshot(snapshot: ProtocolDraftSnapshot): void {
    if (!snapshot.packageId.trim() || !snapshot.manifestHash.trim()) {
        throw new DebugProtocolError("Draft snapshots require a package ID and manifest hash.", "invalid_draft");
    }

    const paths = new Set<string>();
    for (const file of snapshot.files) {
        if (!isSafeExtensionRelativePath(file.path) || !(file.bytes instanceof Uint8Array) || paths.has(file.path)) {
            throw new DebugProtocolError("Draft snapshots contain an invalid or duplicate relative file path.", "invalid_draft");
        }
        paths.add(file.path);
    }
}

export function assertValidRunRequest(request: RunStartRequest): void {
    if (!request.target.packageId.trim()) {
        throw new DebugProtocolError("A run target requires a package ID.", "invalid_run");
    }
    if (request.target.mode === "draft" && !request.target.draftId.trim()) {
        throw new DebugProtocolError("A draft run target requires a staged draft ID.", "invalid_run");
    }

    const invocation = request.invocation;
    if (invocation.kind === "search" && typeof invocation.page !== "string") {
        throw new DebugProtocolError("Search page must be sent as a string for execute(query, String(page)).", "invalid_run");
    }
    if ((invocation.kind === "custom" || invocation.kind === "script") && !isSafeExtensionRelativePath(invocation.scriptPath)) {
        throw new DebugProtocolError("Script paths must be safe relative extension paths.", "invalid_run");
    }
    if (invocation.kind === "script" && request.target.mode !== "draft") {
        throw new DebugProtocolError("Manifest-unlisted scripts can run only from a staged draft.", "invalid_run");
    }
}
