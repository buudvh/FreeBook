import { randomBytes } from "node:crypto";
import * as vscode from "vscode";

/** The two destinations supported by the debug protocol. */
export type SidebarMode = "draft" | "installed";

/** A root that the controller has discovered or remembers for this workspace. */
export interface SidebarRoot {
    /** Opaque controller-owned id. It is never interpreted by the webview. */
    readonly id: string;
    readonly label: string;
    readonly description?: string;
}

/** A text field rendered below the selected execute(...) script. */
export interface SidebarField {
    /** Opaque id returned unchanged in the `run` message. */
    readonly id: string;
    readonly label: string;
    readonly kind: "text" | "url" | "number" | "json" | "textarea";
    readonly placeholder?: string;
    readonly hint?: string;
    readonly value?: string;
    readonly required?: boolean;
    readonly min?: number;
    readonly rows?: number;
}

/** A script available in the selected VBook extension. */
export interface SidebarScript {
    /** Usually the extension-relative path, but owned by the controller. */
    readonly id: string;
    readonly label: string;
    readonly description?: string;
    readonly manifestKey?: string;
    /** True for a saved JS file that is not declared in plugin.json. */
    readonly draftOnly?: boolean;
    /** Present when protocol v1 cannot faithfully invoke this app-specific script. */
    readonly disabled?: boolean;
    readonly disabledReason?: string;
    readonly fields: readonly SidebarField[];
}

export interface SidebarConnection {
    readonly kind: "disconnected" | "mock" | "app";
    readonly label: string;
    readonly detail?: string;
}

/**
 * The complete, JSON-only presentation model for the sidebar. The controller
 * owns this state; the webview may only request changes through SidebarMessage.
 */
export interface SidebarState {
    readonly roots: readonly SidebarRoot[];
    readonly selectedRootId?: string;
    readonly scripts: readonly SidebarScript[];
    readonly selectedScriptId?: string;
    readonly mode: SidebarMode;
    /** Installed is disabled unless the app lists an identical package ID. */
    readonly installedAvailable: boolean;
    readonly isRunning: boolean;
    readonly connection?: SidebarConnection;
    /** Short, already-redacted status copy for the compact status row. */
    readonly status?: string;
}

/**
 * Messages emitted by the trusted sidebar UI. All values are revalidated by
 * the provider before the controller sees them; the controller must still
 * enforce its own filesystem and protocol invariants.
 */
export type SidebarMessage =
    | { readonly type: "ready" }
    | { readonly type: "browseRoot" }
    | { readonly type: "selectRoot"; readonly rootId: string }
    | { readonly type: "selectScript"; readonly scriptId: string }
    | { readonly type: "selectMode"; readonly mode: SidebarMode }
    | {
        readonly type: "run";
        readonly rootId?: string;
        readonly scriptId?: string;
        readonly mode: SidebarMode;
        readonly values: Readonly<Record<string, string>>;
    }
    | { readonly type: "pair" }
    | { readonly type: "useMock" }
    | { readonly type: "cancel" }
    | { readonly type: "openTrace" };

type SidebarHostMessage =
    | { readonly type: "state"; readonly state: SidebarState }
    | { readonly type: "trace"; readonly line: string }
    | { readonly type: "traceReset"; readonly lines: readonly string[] }
    | { readonly type: "notice"; readonly message: string };

const MAX_TRACE_LINES = 160;
const MAX_TRACE_LINE_LENGTH = 16_384;

/**
 * Compact, CSP-restricted sidebar UI. It intentionally owns no debug state or
 * protocol logic: all operations are sent to the supplied async controller.
 */
export class FreeBookDebugSidebarProvider implements vscode.WebviewViewProvider, vscode.Disposable {
    public static readonly viewType = "freebookExtDebug.sidebar";

    private view: vscode.WebviewView | undefined;
    private state: SidebarState | undefined;
    private readonly traceLines: string[] = [];
    private viewDisposables: vscode.Disposable[] = [];
    private isDisposed = false;

    public constructor(
        private readonly handleMessage: (message: SidebarMessage) => Promise<void>,
    ) {}

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        _context: vscode.WebviewViewResolveContext,
        token: vscode.CancellationToken,
    ): void {
        this.releaseView();
        this.view = webviewView;

        webviewView.webview.options = {
            enableScripts: true,
            // The sidebar has no images, fonts, or scripts on disk. Keeping the
            // resource allow-list empty prevents accidental local-file access.
            localResourceRoots: [],
        };
        webviewView.webview.html = this.createHtml();

        this.viewDisposables.push(
            webviewView.webview.onDidReceiveMessage((rawMessage: unknown) => {
                void this.receiveMessage(rawMessage);
            }),
            webviewView.onDidDispose(() => this.releaseView(webviewView)),
            token.onCancellationRequested(() => this.releaseView(webviewView)),
        );
    }

    /** Replaces the sidebar presentation model; safe to call before it is visible. */
    public postState(state: SidebarState): void {
        this.state = state;
        this.post({ type: "state", state });
    }

    /** Adds one already-redacted trace line to the sidebar's compact trace area. */
    public appendTrace(line: string): void {
        const safeLine = line.length > MAX_TRACE_LINE_LENGTH
            ? `${line.slice(0, MAX_TRACE_LINE_LENGTH)} …[truncated]`
            : line;
        this.traceLines.push(safeLine);
        if (this.traceLines.length > MAX_TRACE_LINES) {
            this.traceLines.splice(0, this.traceLines.length - MAX_TRACE_LINES);
        }
        this.post({ type: "trace", line: safeLine });
    }

    /** Rehydrates the visible panel after it is opened or reconstructed. */
    public replaceTrace(lines: readonly string[]): void {
        this.traceLines.length = 0;
        for (const line of lines.slice(-MAX_TRACE_LINES)) {
            const safeLine = line.length > MAX_TRACE_LINE_LENGTH
                ? `${line.slice(0, MAX_TRACE_LINE_LENGTH)} …[truncated]`
                : line;
            this.traceLines.push(safeLine);
        }
        this.post({ type: "traceReset", lines: this.traceLines });
    }

    public dispose(): void {
        this.isDisposed = true;
        this.releaseView();
        this.state = undefined;
        this.traceLines.length = 0;
    }

    private async receiveMessage(rawMessage: unknown): Promise<void> {
        const message = parseSidebarMessage(rawMessage);
        if (!message || this.isDisposed) {
            return;
        }

        if (message.type === "ready") {
            this.postCachedPresentation();
        }

        try {
            await this.handleMessage(message);
        } catch {
            // Never relay arbitrary controller error strings into the webview:
            // pairing URIs and server errors may contain sensitive material.
            this.post({
                type: "notice",
                message: "Không thể xử lý yêu cầu. Hãy xem FreeBook Ext Debug Trace để biết trạng thái.",
            });
        }
    }

    private postCachedPresentation(): void {
        if (this.state) {
            this.post({ type: "state", state: this.state });
        }
        this.post({ type: "traceReset", lines: this.traceLines });
    }

    private post(message: SidebarHostMessage): void {
        const view = this.view;
        if (!view || this.isDisposed) {
            return;
        }
        try {
            void view.webview.postMessage(message).then(undefined, () => {
                // A hidden/disposed view can reject a post. Cached state will be
                // resent when its next document sends the `ready` message.
            });
        } catch {
            // WebviewView can be disposed between the guard and postMessage.
        }
    }

    private releaseView(expected?: vscode.WebviewView): void {
        if (expected && this.view !== expected) {
            return;
        }
        this.view = undefined;
        const disposables = this.viewDisposables;
        this.viewDisposables = [];
        for (const disposable of disposables) {
            disposable.dispose();
        }
    }

    private createHtml(): string {
        const nonce = randomBytes(16).toString("base64");
        const csp = [
            "default-src 'none'",
            `style-src 'nonce-${nonce}'`,
            `script-src 'nonce-${nonce}'`,
            "img-src data:",
            "font-src 'none'",
            "connect-src 'none'",
        ].join("; ");

        return `<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="${csp}">
    <title>FreeBook Debug</title>
    <style nonce="${nonce}">
        :root {
            color: var(--vscode-foreground);
            font-family: var(--vscode-font-family);
            font-size: var(--vscode-font-size);
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            padding: 10px;
            color: var(--vscode-foreground);
            background: var(--vscode-sideBar-background);
        }

        button, input, select, textarea {
            width: 100%;
            color: var(--vscode-input-foreground);
            background: var(--vscode-input-background);
            border: 1px solid var(--vscode-input-border, transparent);
            border-radius: 3px;
            font: inherit;
        }

        button {
            min-height: 28px;
            padding: 4px 8px;
            cursor: pointer;
            color: var(--vscode-button-foreground);
            background: var(--vscode-button-background);
            border-color: transparent;
        }

        button:hover:not(:disabled) { background: var(--vscode-button-hoverBackground); }
        button.secondary {
            color: var(--vscode-button-secondaryForeground);
            background: var(--vscode-button-secondaryBackground);
        }
        button.secondary:hover:not(:disabled) { background: var(--vscode-button-secondaryHoverBackground); }
        button:disabled, select:disabled, input:disabled, textarea:disabled {
            cursor: default;
            opacity: 0.55;
        }

        input, select, textarea { padding: 5px 7px; }
        textarea { min-height: 64px; resize: vertical; }
        input:focus, select:focus, textarea:focus, button:focus-visible {
            outline: 1px solid var(--vscode-focusBorder);
            outline-offset: 1px;
        }

        .header {
            display: flex;
            align-items: flex-start;
            justify-content: space-between;
            gap: 8px;
            margin: 0 0 10px;
        }
        .title { font-size: 13px; font-weight: 600; }
        .subtitle { margin-top: 2px; color: var(--vscode-descriptionForeground); font-size: 11px; }
        .badge {
            flex: none;
            max-width: 124px;
            overflow: hidden;
            padding: 2px 6px;
            border-radius: 10px;
            color: var(--vscode-badge-foreground);
            background: var(--vscode-badge-background);
            font-size: 10px;
            line-height: 15px;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .badge.mock { color: var(--vscode-editorWarning-foreground); }
        .badge.disconnected { color: var(--vscode-descriptionForeground); }

        .card {
            margin: 0 0 10px;
            padding: 9px;
            border: 1px solid var(--vscode-widget-border, var(--vscode-panel-border));
            border-radius: 5px;
            background: var(--vscode-sideBarSectionHeader-background, transparent);
        }
        .field { margin: 0 0 9px; }
        .field:last-child { margin-bottom: 0; }
        label { display: block; margin: 0 0 4px; font-size: 11px; font-weight: 600; }
        .hint { margin: 4px 0 0; color: var(--vscode-descriptionForeground); font-size: 10px; line-height: 1.35; }
        .root-row { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 6px; }
        .root-row button { width: auto; white-space: nowrap; }
        .mode-row { display: grid; grid-template-columns: 1fr; gap: 5px; }
        .mode-note { color: var(--vscode-descriptionForeground); font-size: 10px; line-height: 1.35; }
        .actions { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
        .actions .run { grid-column: 1 / -1; font-weight: 600; }
        .actions .trace { grid-column: 1 / -1; }
        .status {
            min-height: 17px;
            margin: -2px 0 9px;
            color: var(--vscode-descriptionForeground);
            font-size: 11px;
            line-height: 1.4;
        }
        .status:empty { display: none; }
        .trace-title { margin: 0 0 5px; font-size: 11px; font-weight: 600; }
        .trace {
            max-height: 182px;
            overflow: auto;
            padding: 6px;
            border: 1px solid var(--vscode-textBlockQuote-border);
            border-radius: 3px;
            color: var(--vscode-editor-foreground);
            background: var(--vscode-textCodeBlock-background);
            font-family: var(--vscode-editor-font-family);
            font-size: 10px;
            line-height: 1.45;
            white-space: pre-wrap;
            word-break: break-word;
        }
        .trace-line { margin: 0 0 3px; }
        .trace-line:last-child { margin-bottom: 0; }
        .empty { color: var(--vscode-descriptionForeground); font-style: italic; }
        .script-detail { margin: 4px 0 0; color: var(--vscode-descriptionForeground); font-size: 10px; }
    </style>
</head>
<body>
    <main id="app" aria-live="polite"></main>
    <script nonce="${nonce}">
        (() => {
            const vscode = acquireVsCodeApi();
            const app = document.getElementById("app");
            const maxTraceLines = ${MAX_TRACE_LINES};
            let sidebarState = undefined;
            let traceLines = [];
            let uiState = readUiState();
            let isChangingRoot = false;

            function readUiState() {
                const value = vscode.getState();
                if (!value || typeof value !== "object") {
                    return { values: Object.create(null) };
                }
                const values = value.values && typeof value.values === "object" && !Array.isArray(value.values)
                    ? value.values
                    : Object.create(null);
                return {
                    rootId: typeof value.rootId === "string" ? value.rootId : undefined,
                    scriptId: typeof value.scriptId === "string" ? value.scriptId : undefined,
                    mode: value.mode === "installed" || value.mode === "draft" ? value.mode : undefined,
                    values: values,
                };
            }

            function saveUiState() {
                vscode.setState(uiState);
            }

            function post(message) {
                vscode.postMessage(message);
            }

            function selectedRoot() {
                const roots = sidebarState && Array.isArray(sidebarState.roots) ? sidebarState.roots : [];
                const local = roots.find((root) => root && root.id === uiState.rootId);
                const host = roots.find((root) => root && sidebarState && root.id === sidebarState.selectedRootId);
                return local || host || roots[0];
            }

            function selectedScript() {
                const scripts = sidebarState && Array.isArray(sidebarState.scripts) ? sidebarState.scripts : [];
                const local = scripts.find((script) => script && script.id === uiState.scriptId);
                const host = scripts.find((script) => script && sidebarState && script.id === sidebarState.selectedScriptId);
                return local || host || scripts[0];
            }

            function selectedMode() {
                const requested = uiState.mode || (sidebarState && sidebarState.mode) || "draft";
                const script = selectedScript();
                return requested === "installed" && (
                    !(sidebarState && sidebarState.installedAvailable)
                    || Boolean(script && script.draftOnly)
                )
                    ? "draft"
                    : requested;
            }

            function resetValuesForScript(script) {
                const next = Object.create(null);
                if (script && Array.isArray(script.fields)) {
                    for (const field of script.fields) {
                        if (field && typeof field.id === "string") {
                            next[field.id] = typeof field.value === "string" ? field.value : "";
                        }
                    }
                }
                uiState.values = next;
            }

            function syncUiSelection() {
                const root = selectedRoot();
                const script = selectedScript();
                const scriptChanged = uiState.scriptId !== (script && script.id);
                uiState.rootId = root && typeof root.id === "string" ? root.id : undefined;
                uiState.scriptId = script && typeof script.id === "string" ? script.id : undefined;
                uiState.mode = selectedMode();
                if (scriptChanged) {
                    resetValuesForScript(script);
                } else if (script && Array.isArray(script.fields)) {
                    for (const field of script.fields) {
                        if (field && typeof field.id === "string" && typeof uiState.values[field.id] !== "string") {
                            uiState.values[field.id] = typeof field.value === "string" ? field.value : "";
                        }
                    }
                }
                saveUiState();
            }

            function element(tag, className, text) {
                const node = document.createElement(tag);
                if (className) {
                    node.className = className;
                }
                if (typeof text === "string") {
                    node.textContent = text;
                }
                return node;
            }

            function addOption(select, value, label, description, selected, disabled) {
                const option = document.createElement("option");
                option.value = value;
                option.textContent = description ? label + " — " + description : label;
                option.selected = Boolean(selected);
                option.disabled = Boolean(disabled);
                select.appendChild(option);
            }

            function createField(field) {
                const wrapper = element("div", "field");
                const label = element("label", "", field.label || field.id || "Input");
                const inputId = "field-" + String(field.id || "value").replace(/[^A-Za-z0-9_-]/g, "_");
                label.htmlFor = inputId;
                wrapper.appendChild(label);

                const multiline = field.kind === "json" || field.kind === "textarea";
                const input = document.createElement(multiline ? "textarea" : "input");
                input.id = inputId;
                input.name = String(field.id || "");
                input.required = Boolean(field.required);
                input.placeholder = typeof field.placeholder === "string" ? field.placeholder : "";
                input.value = typeof uiState.values[field.id] === "string"
                    ? uiState.values[field.id]
                    : (typeof field.value === "string" ? field.value : "");
                if (multiline) {
                    input.rows = Number.isInteger(field.rows) && field.rows > 0 ? field.rows : (field.kind === "json" ? 4 : 3);
                    if (field.kind === "json") {
                        input.spellcheck = false;
                        const validateJson = () => {
                            if (!input.value.trim()) {
                                input.setCustomValidity("");
                                return;
                            }
                            try {
                                JSON.parse(input.value);
                                input.setCustomValidity("");
                            } catch {
                                input.setCustomValidity("Nhập JSON hợp lệ.");
                            }
                        };
                        input.addEventListener("input", validateJson);
                        validateJson();
                    }
                } else {
                    // ExtensionManager accepts both absolute URLs and relative
                    // paths that the app resolves against host. type=url
                    // would reject the latter before the app can apply that
                    // contract, so URL fields use a text input with URL hints.
                    input.type = field.kind === "number" ? "number" : "text";
                    if (field.kind === "url") {
                        input.inputMode = "url";
                        input.autocapitalize = "none";
                    }
                    if (field.kind === "number" && Number.isFinite(field.min)) {
                        input.min = String(field.min);
                        input.step = "1";
                        input.inputMode = "numeric";
                    }
                }
                input.addEventListener("input", () => {
                    uiState.values[field.id] = input.value;
                    saveUiState();
                });
                wrapper.appendChild(input);

                if (typeof field.hint === "string" && field.hint) {
                    wrapper.appendChild(element("p", "hint", field.hint));
                }
                return wrapper;
            }

            function renderTrace() {
                const trace = document.getElementById("trace");
                if (!trace) {
                    return;
                }
                trace.textContent = "";
                if (traceLines.length === 0) {
                    trace.appendChild(element("div", "empty", "Chưa có trace. Mock chỉ kiểm tra protocol, không chạy JSExecutor iOS."));
                    return;
                }
                for (const line of traceLines) {
                    trace.appendChild(element("div", "trace-line", String(line)));
                }
                trace.scrollTop = trace.scrollHeight;
            }

            function render() {
                syncUiSelection();
                app.textContent = "";

                const connection = sidebarState && sidebarState.connection;
                const header = element("header", "header");
                const copy = element("div", "");
                copy.appendChild(element("div", "title", "FreeBook Debug"));
                copy.appendChild(element("div", "subtitle", "Chạy execute(...) qua FreeBook App"));
                header.appendChild(copy);
                const connectionKind = connection && (connection.kind === "app" || connection.kind === "mock" || connection.kind === "disconnected")
                    ? connection.kind
                    : "disconnected";
                header.appendChild(element("div", "badge " + connectionKind, connection && connection.label ? connection.label : "Chưa kết nối"));
                app.appendChild(header);

                const configuration = element("section", "card");
                const rootField = element("div", "field");
                rootField.appendChild(element("label", "", "Extension root"));
                const rootRow = element("div", "root-row");
                const rootSelect = document.createElement("select");
                rootSelect.setAttribute("aria-label", "Extension root");
                const roots = sidebarState && Array.isArray(sidebarState.roots) ? sidebarState.roots : [];
                const root = selectedRoot();
                if (roots.length === 0) {
                    addOption(rootSelect, "", "Chưa chọn extension", "", true, true);
                    rootSelect.disabled = true;
                } else {
                    for (const candidate of roots) {
                        addOption(rootSelect, candidate.id, candidate.label || candidate.id, candidate.description || "", root && candidate.id === root.id, false);
                    }
                    rootSelect.disabled = isChangingRoot;
                }
                rootSelect.addEventListener("change", () => {
                    isChangingRoot = true;
                    uiState.rootId = rootSelect.value;
                    uiState.scriptId = undefined;
                    uiState.values = Object.create(null);
                    saveUiState();
                    post({ type: "selectRoot", rootId: rootSelect.value });
                    render();
                });
                rootRow.appendChild(rootSelect);
                const browseButton = element("button", "secondary", "Chọn…");
                browseButton.type = "button";
                browseButton.addEventListener("click", () => post({ type: "browseRoot" }));
                rootRow.appendChild(browseButton);
                rootField.appendChild(rootRow);
                configuration.appendChild(rootField);

                const scriptField = element("div", "field");
                scriptField.appendChild(element("label", "", "Script / execute"));
                const scriptSelect = document.createElement("select");
                scriptSelect.setAttribute("aria-label", "Script execute");
                const scripts = sidebarState && Array.isArray(sidebarState.scripts) ? sidebarState.scripts : [];
                const script = selectedScript();
                if (scripts.length === 0) {
                    addOption(scriptSelect, "", "Chưa có script", "Chọn extension root trước", true, true);
                    scriptSelect.disabled = true;
                } else {
                    for (const candidate of scripts) {
                        const suffix = candidate.disabled
                            ? (candidate.disabledReason || "Chưa hỗ trợ")
                            : (candidate.draftOnly ? "Draft only" : (candidate.manifestKey || ""));
                        addOption(scriptSelect, candidate.id, candidate.label || candidate.id, suffix, script && candidate.id === script.id, Boolean(candidate.disabled));
                    }
                    scriptSelect.disabled = isChangingRoot;
                }
                scriptSelect.addEventListener("change", () => {
                    uiState.scriptId = scriptSelect.value;
                    const next = scripts.find((candidate) => candidate && candidate.id === scriptSelect.value);
                    resetValuesForScript(next);
                    saveUiState();
                    post({ type: "selectScript", scriptId: scriptSelect.value });
                    render();
                });
                scriptField.appendChild(scriptSelect);
                if (script && script.description) {
                    scriptField.appendChild(element("div", "script-detail", script.description));
                }
                configuration.appendChild(scriptField);

                if (script && Array.isArray(script.fields)) {
                    for (const field of script.fields) {
                        if (field && typeof field.id === "string") {
                            configuration.appendChild(createField(field));
                        }
                    }
                }

                const modeField = element("div", "field");
                modeField.appendChild(element("label", "", "Run mode"));
                const modeWrap = element("div", "mode-row");
                const modeSelect = document.createElement("select");
                modeSelect.setAttribute("aria-label", "Run mode");
                const mode = selectedMode();
                addOption(modeSelect, "draft", "Draft", "Stage file đã lưu", mode === "draft", false);
                addOption(
                    modeSelect,
                    "installed",
                    "Installed",
                    "Extension đã cài trên app",
                    mode === "installed",
                    !(sidebarState && sidebarState.installedAvailable) || Boolean(script && script.draftOnly),
                );
                modeSelect.addEventListener("change", () => {
                    uiState.mode = modeSelect.value === "installed" ? "installed" : "draft";
                    saveUiState();
                    post({ type: "selectMode", mode: uiState.mode });
                    render();
                });
                modeWrap.appendChild(modeSelect);
                const modeNote = script && script.disabled
                    ? (script.disabledReason || "Script này chưa được protocol debug v1 hỗ trợ.")
                    : script && script.draftOnly
                    ? "Script này không khai trong plugin.json nên chỉ chạy Draft."
                    : (sidebarState && sidebarState.installedAvailable
                        ? "Installed chỉ dùng khi package ID trên app khớp."
                        : "Draft chỉ stage file đã lưu; Installed chưa có package ID khớp.");
                modeWrap.appendChild(element("div", "mode-note", modeNote));
                modeField.appendChild(modeWrap);
                configuration.appendChild(modeField);
                app.appendChild(configuration);

                const status = element(
                    "div",
                    "status",
                    isChangingRoot
                        ? "Đang đổi extension root…"
                        : (sidebarState && sidebarState.status ? sidebarState.status : ""),
                );
                app.appendChild(status);

                const actions = element("section", "actions");
                const runButton = element("button", "run", sidebarState && sidebarState.isRunning ? "Đang chạy…" : "Run execute");
                runButton.type = "button";
                runButton.disabled = Boolean(!root || !script || script.disabled || isChangingRoot || (sidebarState && sidebarState.isRunning));
                runButton.addEventListener("click", () => {
                    const inputs = configuration.querySelectorAll("input, textarea");
                    for (const input of inputs) {
                        if (!input.checkValidity()) {
                            input.reportValidity();
                            input.focus();
                            return;
                        }
                    }
                    const values = Object.create(null);
                    if (script && Array.isArray(script.fields)) {
                        for (const field of script.fields) {
                            if (field && typeof field.id === "string") {
                                values[field.id] = typeof uiState.values[field.id] === "string" ? uiState.values[field.id] : "";
                            }
                        }
                    }
                    post({
                        type: "run",
                        rootId: root && root.id,
                        scriptId: script && script.id,
                        mode: selectedMode(),
                        values: values,
                    });
                });
                actions.appendChild(runButton);

                const pairButton = element("button", "secondary", "Pair App");
                pairButton.type = "button";
                pairButton.addEventListener("click", () => post({ type: "pair" }));
                actions.appendChild(pairButton);

                const mockButton = element("button", "secondary", "Use Mock");
                mockButton.type = "button";
                mockButton.addEventListener("click", () => post({ type: "useMock" }));
                actions.appendChild(mockButton);

                const cancelButton = element("button", "secondary", "Cancel");
                cancelButton.type = "button";
                cancelButton.disabled = !(sidebarState && sidebarState.isRunning);
                cancelButton.addEventListener("click", () => post({ type: "cancel" }));
                actions.appendChild(cancelButton);

                const traceButton = element("button", "secondary trace", "Open Trace");
                traceButton.type = "button";
                traceButton.addEventListener("click", () => post({ type: "openTrace" }));
                actions.appendChild(traceButton);
                app.appendChild(actions);

                const traceCard = element("section", "card");
                traceCard.appendChild(element("div", "trace-title", "Trace"));
                const trace = element("div", "trace");
                trace.id = "trace";
                trace.setAttribute("role", "log");
                traceCard.appendChild(trace);
                app.appendChild(traceCard);
                renderTrace();
            }

            window.addEventListener("message", (event) => {
                const message = event.data;
                if (!message || typeof message !== "object" || typeof message.type !== "string") {
                    return;
                }
                if (message.type === "state" && message.state && typeof message.state === "object") {
                    const priorScriptId = uiState.scriptId;
                    sidebarState = message.state;
                    isChangingRoot = false;
                    if (typeof sidebarState.selectedRootId === "string") {
                        uiState.rootId = sidebarState.selectedRootId;
                    }
                    if (typeof sidebarState.selectedScriptId === "string") {
                        uiState.scriptId = sidebarState.selectedScriptId;
                    }
                    if (sidebarState.mode === "draft" || sidebarState.mode === "installed") {
                        uiState.mode = sidebarState.mode;
                    }
                    if (priorScriptId !== uiState.scriptId) {
                        uiState.values = Object.create(null);
                    }
                    saveUiState();
                    render();
                } else if (message.type === "trace" && typeof message.line === "string") {
                    traceLines.push(message.line);
                    if (traceLines.length > maxTraceLines) {
                        traceLines.splice(0, traceLines.length - maxTraceLines);
                    }
                    renderTrace();
                } else if (message.type === "traceReset" && Array.isArray(message.lines)) {
                    traceLines = message.lines.filter((line) => typeof line === "string").slice(-maxTraceLines);
                    renderTrace();
                } else if (message.type === "notice" && typeof message.message === "string") {
                    isChangingRoot = false;
                    if (!sidebarState) {
                        sidebarState = {
                            roots: [],
                            scripts: [],
                            mode: "draft",
                            installedAvailable: false,
                            isRunning: false,
                        };
                    }
                    sidebarState = Object.assign({}, sidebarState, { status: message.message });
                    render();
                }
            });

            render();
            post({ type: "ready" });
        })();
    </script>
</body>
</html>`;
    }
}

function parseSidebarMessage(value: unknown): SidebarMessage | undefined {
    if (!isRecord(value) || typeof value.type !== "string") {
        return undefined;
    }

    switch (value.type) {
        case "ready":
        case "browseRoot":
        case "pair":
        case "useMock":
        case "cancel":
        case "openTrace":
            return { type: value.type };
        case "selectRoot":
            return isUiString(value.rootId, 4_096) ? { type: "selectRoot", rootId: value.rootId } : undefined;
        case "selectScript":
            return isUiString(value.scriptId, 4_096) ? { type: "selectScript", scriptId: value.scriptId } : undefined;
        case "selectMode":
            return isSidebarMode(value.mode) ? { type: "selectMode", mode: value.mode } : undefined;
        case "run": {
            if (!isSidebarMode(value.mode) || !isStringRecord(value.values)) {
                return undefined;
            }
            if (value.rootId !== undefined && !isUiString(value.rootId, 4_096)) {
                return undefined;
            }
            if (value.scriptId !== undefined && !isUiString(value.scriptId, 4_096)) {
                return undefined;
            }
            return {
                type: "run",
                ...(typeof value.rootId === "string" ? { rootId: value.rootId } : {}),
                ...(typeof value.scriptId === "string" ? { scriptId: value.scriptId } : {}),
                mode: value.mode,
                values: value.values,
            };
        }
        default:
            return undefined;
    }
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isSidebarMode(value: unknown): value is SidebarMode {
    return value === "draft" || value === "installed";
}

function isUiString(value: unknown, maxLength: number): value is string {
    return typeof value === "string" && value.length <= maxLength;
}

function isStringRecord(value: unknown): value is Readonly<Record<string, string>> {
    if (!isRecord(value)) {
        return false;
    }
    const entries = Object.entries(value);
    return entries.length <= 64 && entries.every(([key, nested]) => (
        isUiString(key, 256) && isUiString(nested, 65_536)
    ));
}
