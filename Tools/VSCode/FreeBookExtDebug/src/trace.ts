import * as vscode from "vscode";

import {
    redactSecrets,
    type DebugTraceEvent,
} from "./protocol";
import { isUriWithinRoot, normalizeRelativeExtensionPath } from "./manifest";
import { isSavedSourceRevisionCurrent } from "./snapshot";

/**
 * Renders server events without treating the mock transport as evidence that
 * JavaScriptCore has actually run.
 */
export class TracePresenter implements vscode.Disposable {
    private readonly output = vscode.window.createOutputChannel("FreeBook Ext Debug");
    private readonly diagnostics = vscode.languages.createDiagnosticCollection("freebook-ext-debug");
    private readonly lineEmitter = new vscode.EventEmitter<string>();
    private readonly recentLines: string[] = [];
    private sourceRevisions = new Map<string, string>();
    private root: vscode.Uri | undefined;
    private currentRunId: string | undefined;
    /** Invalidates asynchronous diagnostic work when the next run begins. */
    private runGeneration = 0;
    private readonly documentChangeSubscription: vscode.Disposable;
    public readonly onDidAppendLine = this.lineEmitter.event;

    public constructor() {
        this.documentChangeSubscription = vscode.workspace.onDidChangeTextDocument((change) => {
            if (this.root && this.isWithinRoot(change.document.uri) && change.document.isDirty) {
                this.diagnostics.delete(change.document.uri);
            }
        });
    }

    public beginRun(runId: string, root: vscode.Uri, sourceRevisions: ReadonlyMap<string, string>): void {
        this.runGeneration += 1;
        this.currentRunId = runId;
        this.root = root;
        this.sourceRevisions = new Map(sourceRevisions);
        this.diagnostics.clear();
        this.appendLine(`▶ Run ${runId}`);
    }

    public show(): void {
        this.output.show(true);
    }

    public appendNotice(message: string): void {
        this.appendLine(message);
    }

    public getRecentLines(): readonly string[] {
        return this.recentLines;
    }

    public handle(event: DebugTraceEvent, secrets: readonly (string | undefined)[] = []): void {
        const runPrefix = event.runId ? `[${event.runId}] ` : "";
        const runtimePrefix = event.runtime === "mock" ? "[Mock — không chạy JSExecutor iOS] " : "";
        const message = redactSecrets(this.describe(event, secrets), secrets);
        this.appendLine(`${runtimePrefix}${runPrefix}${message}`);

        if (event.runtime === "ios") {
            void this.publishDiagnostic(event);
        }
    }

    public endRun(runId: string): void {
        if (this.currentRunId === runId) {
            this.appendLine(`■ Run ${runId} finished`);
            this.currentRunId = undefined;
        }
    }

    public dispose(): void {
        this.documentChangeSubscription.dispose();
        this.lineEmitter.dispose();
        this.output.dispose();
        this.diagnostics.dispose();
    }

    private describe(event: DebugTraceEvent, secrets: readonly (string | undefined)[]): string {
        const message = event.message?.trim() || event.kind;
        const location = event.sourcePath
            ? ` (${event.sourcePath}${event.line ? `:${event.line}` : ""}${event.column ? `:${event.column}` : ""})`
            : "";
        const data = event.data === undefined ? "" : `\n${formatData(event.data, secrets)}`;
        return `${event.kind}: ${message}${location}${data}`;
    }

    private async publishDiagnostic(event: DebugTraceEvent): Promise<void> {
        if (
            (event.kind !== "compile_error" && event.kind !== "runtime_error") ||
            !event.sourcePath ||
            !event.sourceRevision ||
            !this.root ||
            !event.runId ||
            event.runId !== this.currentRunId
        ) {
            return;
        }
        const generation = this.runGeneration;

        const safeSourcePath = normalizeRelativeExtensionPath(event.sourcePath);
        if (!safeSourcePath) {
            this.appendLine("[stale diagnostic] Server sent an unsafe source path.");
            return;
        }

        const root = this.root;
        const expectedRevision = this.sourceRevisions.get(safeSourcePath);
        if (this.sourceRevisions.size > 0 && expectedRevision !== event.sourceRevision) {
            this.appendLine(`[stale diagnostic] ${safeSourcePath}: source revision no longer matches the run.`);
            return;
        }

        if (!(await isSavedSourceRevisionCurrent(root, safeSourcePath, event.sourceRevision))) {
            this.appendLine(`[stale diagnostic] ${safeSourcePath}: saved source no longer matches the run.`);
            return;
        }

        // Awaiting the document gives VS Code a valid, clamped source range
        // even when the file was not open when the server emitted the event.
        const uri = vscode.Uri.joinPath(root, ...safeSourcePath.split("/"));
        let document: vscode.TextDocument;
        try {
            document = await vscode.workspace.openTextDocument(uri);
        } catch {
            this.appendLine(`[stale diagnostic] ${safeSourcePath}: source file is no longer available.`);
            return;
        }
        if (document.isDirty || !this.root || !isUriWithinRoot(uri, this.root)) {
            this.appendLine(`[stale diagnostic] ${safeSourcePath}: document has unsaved changes.`);
            return;
        }
        if (generation !== this.runGeneration || root !== this.root) {
            return;
        }

        const line = Math.min(Math.max(0, (event.line ?? 1) - 1), Math.max(0, document.lineCount - 1));
        const column = Math.min(
            Math.max(0, (event.column ?? 1) - 1),
            document.lineAt(line).range.end.character,
        );
        const position = new vscode.Position(line, column);
        const diagnostic = new vscode.Diagnostic(
            new vscode.Range(position, position),
            event.message || "JavaScript execution error",
            event.kind === "compile_error" ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning,
        );
        diagnostic.source = "FreeBook Ext Debug";
        this.diagnostics.set(uri, [diagnostic]);
    }

    private appendLine(message: string): void {
        this.output.appendLine(message);
        this.recentLines.push(message);
        if (this.recentLines.length > 160) {
            this.recentLines.splice(0, this.recentLines.length - 160);
        }
        this.lineEmitter.fire(message);
    }

    private isWithinRoot(uri: vscode.Uri): boolean {
        return Boolean(this.root && isUriWithinRoot(uri, this.root));
    }
}

function formatData(data: unknown, secrets: readonly (string | undefined)[]): string {
    try {
        const rendered = JSON.stringify(redactTraceData(data, secrets), null, 2);
        if (!rendered) {
            return "";
        }
        return rendered.length > 16_384 ? `${rendered.slice(0, 16_384)}\n…[truncated]` : rendered;
    } catch {
        return String(data);
    }
}

function redactTraceData(value: unknown, secrets: readonly (string | undefined)[]): unknown {
    if (typeof value === "string") {
        return redactSecrets(value, secrets);
    }
    if (Array.isArray(value)) {
        return value.map((item) => redactTraceData(item, secrets));
    }
    if (typeof value !== "object" || value === null) {
        return value;
    }

    const result: Record<string, unknown> = {};
    for (const [key, nested] of Object.entries(value)) {
        result[key] = isSensitiveKey(key)
            ? "[redacted]"
            : redactTraceData(nested, secrets);
    }
    return result;
}

function isSensitiveKey(key: string): boolean {
    return /(?:authorization|cookie|token|session|password|secret|credential|api[_ -]?key)/i.test(key);
}
