import { Buffer } from "node:buffer";
import WebSocket = require("ws");

import {
    DEBUG_PROTOCOL_VERSION,
    DRAFT_BINARY_MAGIC,
    createRequestId,
    isWireMessage,
    redactSecrets,
    validateWebSocketEndpoint,
    type DebugClientInfo,
    type DebugMethod,
    type DebugTraceEvent,
    type DraftBinaryFrameHeader,
    type DraftSnapshot,
    type DraftStageCompleteResponse,
    type DraftStageManifestResponse,
    type EventsSubscribeRequest,
    type ExtensionsListResponse,
    type HelloResponse,
    type PairRequest,
    type PairResponse,
    type RunCancelResponse,
    type RunStartRequest,
    type RunStartResponse,
    type StagedDraft,
    type WireRequest,
    type WireResponse,
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

interface PendingRequest {
    readonly resolve: (value: unknown) => void;
    readonly reject: (reason: Error) => void;
    readonly timeout: ReturnType<typeof setTimeout>;
    readonly secrets: readonly (string | undefined)[];
}

/** WebSocket client for protocol v1. It never evaluates extension JavaScript locally. */
export class WebSocketDebugTransport implements DebugTransport {
    public readonly kind = "websocket" as const;
    public readonly displayName = "FreeBook App";
    public readonly endpoint: string;
    private readonly listeners = new Set<DebugTraceListener>();
    private readonly subscriptionRequests = new Map<DebugTraceListener, EventsSubscribeRequest>();
    private readonly disconnectListeners = new Set<DebugDisconnectListener>();
    private readonly pending = new Map<string, PendingRequest>();
    private readonly client: DebugClientInfo = {
        name: "FreeBook Extension Debug",
        kind: "vscode",
        platform: "desktop",
    };
    private socket: WebSocket | undefined;
    private hello: HelloResponse | undefined;
    private connecting: Promise<HelloResponse> | undefined;
    private disposed = false;

    public constructor(endpoint: string, private readonly getSession: () => string | undefined, private readonly requestTimeoutMs = 20_000) {
        this.endpoint = validateWebSocketEndpoint(endpoint);
    }

    public async connect(): Promise<HelloResponse> {
        this.assertUsable();
        if (this.hello && this.socket?.readyState === WebSocket.OPEN) {
            return this.hello;
        }
        if (!this.connecting) {
            this.connecting = this.openAndHello().finally(() => {
                this.connecting = undefined;
            });
        }
        return this.connecting;
    }

    public async pair(request: PairRequest): Promise<PairResponse> {
        if (!request.oneTimeToken.trim()) {
            throw new DebugTransportError("A pairing token is required.", "invalid_pairing");
        }
        await this.ensureConnected();
        return this.request<PairResponse>("pair", { oneTimeToken: request.oneTimeToken }, [request.oneTimeToken], false);
    }

    public async listExtensions(): Promise<ExtensionsListResponse> {
        await this.ensureConnected();
        return this.request<ExtensionsListResponse>("extensions.list", {});
    }

    public async stageDraft(snapshot: DraftSnapshot): Promise<StagedDraft> {
        await this.ensureConnected();
        assertValidSnapshot(snapshot);

        const manifest = await this.request<DraftStageManifestResponse>("draft.stage", {
            phase: "manifest",
            packageId: snapshot.packageId,
            manifestHash: snapshot.manifestHash,
            files: snapshot.files.map((file) => ({ path: file.path, size: file.bytes.byteLength, sha256: file.sha256 })),
        });
        if (!manifest.uploadId || !Number.isSafeInteger(manifest.maxChunkBytes) || manifest.maxChunkBytes < 1) {
            throw new DebugTransportError("The app returned an invalid draft upload quota.", "invalid_stage_response");
        }

        const filesByPath = new Map(snapshot.files.map((file) => [file.path, file]));
        const requiredPaths = manifest.requiredPaths ?? snapshot.files.map((file) => file.path);
        for (const path of requiredPaths) {
            const file = filesByPath.get(path);
            if (!file) {
                throw new DebugTransportError("The app requested a draft file that is not in the submitted manifest.", "invalid_stage_response");
            }
            await this.sendFile(manifest.uploadId, file.path, file.bytes, manifest.maxChunkBytes);
        }

        const complete = await this.request<DraftStageCompleteResponse>("draft.stage", { phase: "complete", uploadId: manifest.uploadId });
        if (!complete.draftId || !complete.manifestHash) {
            throw new DebugTransportError("The app returned an invalid staged draft result.", "invalid_stage_response");
        }
        return { draftId: complete.draftId, manifestHash: complete.manifestHash };
    }

    public async run(request: RunStartRequest): Promise<RunStartResponse> {
        await this.ensureConnected();
        assertValidRunRequest(request);
        return this.request<RunStartResponse>("run.start", request);
    }

    public async cancel(runId: string): Promise<RunCancelResponse> {
        await this.ensureConnected();
        if (!runId.trim()) {
            throw new DebugTransportError("A run ID is required to cancel a run.", "invalid_run");
        }
        return this.request<RunCancelResponse>("run.cancel", { runId });
    }

    public async subscribe(listener: DebugTraceListener, request: EventsSubscribeRequest = {}): Promise<DebugEventSubscription> {
        await this.ensureConnected();
        this.listeners.add(listener);
        this.subscriptionRequests.set(listener, request);
        try {
            await this.request("events.subscribe", request);
        } catch (error) {
            this.listeners.delete(listener);
            this.subscriptionRequests.delete(listener);
            throw error;
        }
        return {
            dispose: () => {
                this.listeners.delete(listener);
                this.subscriptionRequests.delete(listener);
            },
        };
    }

    public onDidDisconnect(listener: DebugDisconnectListener): DebugEventSubscription {
        this.disconnectListeners.add(listener);
        return { dispose: () => this.disconnectListeners.delete(listener) };
    }

    public dispose(): void {
        if (this.disposed) {
            return;
        }
        this.disposed = true;
        this.hello = undefined;
        this.listeners.clear();
        this.subscriptionRequests.clear();
        this.disconnectListeners.clear();
        this.rejectPending(new DebugTransportError("The debug transport was disposed.", "disposed"));
        const socket = this.socket;
        this.socket = undefined;
        if (socket) {
            socket.removeAllListeners();
            socket.terminate();
        }
    }

    private async openAndHello(): Promise<HelloResponse> {
        await this.openSocket();
        const hello = await this.request<HelloResponse>("hello", { client: this.client });
        this.hello = hello;
        try {
            await this.restoreEventSubscriptions();
        } catch (error) {
            this.hello = undefined;
            throw error;
        }
        return hello;
    }

    private async ensureConnected(): Promise<void> {
        this.assertUsable();
        if (!this.hello || this.socket?.readyState !== WebSocket.OPEN) {
            await this.connect();
        }
    }

    private async openSocket(): Promise<void> {
        if (this.socket?.readyState === WebSocket.OPEN) {
            return;
        }
        if (this.socket) {
            this.socket.terminate();
            this.socket = undefined;
            this.rejectPending(new DebugTransportError("The previous debug connection closed.", "connection_closed"));
        }

        const socket = new WebSocket(this.endpoint, { handshakeTimeout: this.requestTimeoutMs });
        this.socket = socket;
        socket.on("message", (data: WebSocket.RawData, isBinary: boolean) => this.handleMessage(data, isBinary));
        socket.on("close", () => this.handleClose(socket));
        socket.on("error", () => undefined);

        await new Promise<void>((resolve, reject) => {
            const onOpen = (): void => {
                clearTimeout(timeout);
                socket.off("error", onError);
                resolve();
            };
            const onError = (): void => {
                clearTimeout(timeout);
                socket.off("open", onOpen);
                reject(new DebugTransportError("Could not connect to the FreeBook debug server.", "connection_failed"));
            };
            const timeout = setTimeout(() => {
                socket.off("open", onOpen);
                socket.off("error", onError);
                socket.terminate();
                reject(new DebugTransportError("The FreeBook debug server did not accept the connection in time.", "connection_timeout"));
            }, this.requestTimeoutMs);
            socket.once("open", onOpen);
            socket.once("error", onError);
        });
    }

    private request<TResult>(method: DebugMethod, params: unknown, secrets: readonly (string | undefined)[] = [], includeSession = true): Promise<TResult> {
        const socket = this.socket;
        if (!socket || socket.readyState !== WebSocket.OPEN) {
            return Promise.reject(new DebugTransportError("The debug transport is not connected.", "not_connected"));
        }

        const id = createRequestId();
        const session = includeSession ? this.currentSession() : undefined;
        const message: WireRequest<unknown> = {
            protocol: DEBUG_PROTOCOL_VERSION,
            type: "request",
            id,
            method,
            params,
            ...(session ? { session } : {}),
        };
        const payload = JSON.stringify(message);

        return new Promise<TResult>((resolve, reject) => {
            const timeout = setTimeout(() => {
                this.settleReject(id, new DebugTransportError("The FreeBook debug server did not respond in time.", "request_timeout"));
            }, this.requestTimeoutMs);
            this.pending.set(id, {
                resolve: (result) => resolve(result as TResult),
                reject,
                timeout,
                secrets: [...secrets, session],
            });
            socket.send(payload, (error?: Error) => {
                if (error) {
                    this.settleReject(id, new DebugTransportError("The debug request could not be sent.", "send_failed"));
                }
            });
        });
    }

    private async sendFile(uploadId: string, path: string, bytes: Uint8Array, maxChunkBytes: number): Promise<void> {
        if (bytes.byteLength === 0) {
            await this.sendDraftChunk(uploadId, path, bytes, 0, 0, true);
            return;
        }
        for (let offset = 0; offset < bytes.byteLength; offset += maxChunkBytes) {
            const byteLength = Math.min(maxChunkBytes, bytes.byteLength - offset);
            await this.sendDraftChunk(uploadId, path, bytes, offset, byteLength, offset + byteLength === bytes.byteLength);
        }
    }

    private async sendDraftChunk(
        uploadId: string,
        path: string,
        bytes: Uint8Array,
        offset: number,
        byteLength: number,
        final: boolean,
    ): Promise<void> {
        const header: DraftBinaryFrameHeader = {
            protocol: DEBUG_PROTOCOL_VERSION,
            type: "binary",
            channel: "draft.stage",
            uploadId,
            path,
            offset,
            byteLength,
            final,
        };
        const headerBytes = Buffer.from(JSON.stringify(header), "utf8");
        const frame = Buffer.allocUnsafe(8 + headerBytes.byteLength + byteLength);
        frame.write(DRAFT_BINARY_MAGIC, 0, 4, "ascii");
        frame.writeUInt32BE(headerBytes.byteLength, 4);
        headerBytes.copy(frame, 8);
        if (byteLength > 0) {
            Buffer.from(bytes.buffer, bytes.byteOffset + offset, byteLength).copy(frame, 8 + headerBytes.byteLength);
        }
        await this.sendBinary(frame);
    }

    private sendBinary(frame: Buffer): Promise<void> {
        const socket = this.socket;
        if (!socket || socket.readyState !== WebSocket.OPEN) {
            return Promise.reject(new DebugTransportError("The debug transport is not connected.", "not_connected"));
        }
        return new Promise<void>((resolve, reject) => {
            socket.send(frame, { binary: true }, (error?: Error) => {
                if (error) {
                    reject(new DebugTransportError("A draft chunk could not be sent.", "send_failed"));
                } else {
                    resolve();
                }
            });
        });
    }

    private handleMessage(data: WebSocket.RawData, isBinary: boolean): void {
        if (isBinary) {
            return;
        }
        let value: unknown;
        try {
            const text = typeof data === "string"
                ? data
                : rawDataBuffer(data).toString("utf8");
            value = JSON.parse(text);
        } catch {
            return;
        }
        if (!isWireMessage(value)) {
            return;
        }
        if (value.type === "event") {
            this.emit({ ...value.event, runtime: "ios" });
            return;
        }
        this.handleResponse(value);
    }

    private handleResponse(response: WireResponse): void {
        const pending = this.pending.get(response.id);
        if (!pending) {
            return;
        }
        this.pending.delete(response.id);
        clearTimeout(pending.timeout);
        if (response.ok) {
            pending.resolve(response.result);
            return;
        }
        const message = redactSecrets(response.error?.message ?? "The FreeBook debug server rejected the request.", pending.secrets);
        pending.reject(new DebugTransportError(message, response.error?.code ?? "server_error"));
    }

    private handleClose(socket: WebSocket): void {
        if (this.socket !== socket) {
            return;
        }
        this.socket = undefined;
        this.hello = undefined;
        this.rejectPending(new DebugTransportError("The FreeBook debug connection closed.", "connection_closed"));
        this.emitDisconnect("The FreeBook debug connection closed.");
    }

    private emit(event: DebugTraceEvent): void {
        for (const listener of this.listeners) {
            listener(event);
        }
    }

    private async restoreEventSubscriptions(): Promise<void> {
        for (const request of this.subscriptionRequests.values()) {
            await this.request("events.subscribe", request);
        }
    }

    private emitDisconnect(message: string): void {
        for (const listener of this.disconnectListeners) {
            try {
                listener(message);
            } catch {
                // A presentation listener must never break transport cleanup.
            }
        }
    }

    private settleReject(id: string, error: Error): void {
        const pending = this.pending.get(id);
        if (!pending) {
            return;
        }
        this.pending.delete(id);
        clearTimeout(pending.timeout);
        pending.reject(error);
    }

    private rejectPending(error: Error): void {
        for (const id of this.pending.keys()) {
            this.settleReject(id, error);
        }
    }

    private currentSession(): string | undefined {
        try {
            return this.getSession()?.trim() || undefined;
        } catch {
            throw new DebugTransportError("The stored debug session could not be read.", "session_unavailable");
        }
    }

    private assertUsable(): void {
        if (this.disposed) {
            throw new DebugTransportError("The debug transport has been disposed.", "disposed");
        }
    }
}

function rawDataBuffer(data: WebSocket.RawData): Buffer {
    if (Array.isArray(data)) {
        return Buffer.concat(data);
    }
    if (data instanceof ArrayBuffer) {
        return Buffer.from(new Uint8Array(data));
    }
    return Buffer.from(data);
}
