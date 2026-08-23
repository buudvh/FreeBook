import { createHash } from "node:crypto";
import * as vscode from "vscode";

import {
    declaredScriptKey,
    discoverExtensionManifest,
    ExtensionManifest,
    ExtensionWorkspaceError,
    isJsonValue,
    readExtensionManifest,
    relativePathFromRoot,
    resolveExtensionScript,
    resolveManifestScript,
    ResolvedExtensionScript,
} from "./manifest";
import { MockDebugTransport } from "./mockTransport";
import {
    type DebugInvocation,
    type DebugTraceEvent,
    type JsonObject as ProtocolJsonObject,
    parsePairingUri,
    redactSecrets,
    type RunStartRequest,
} from "./protocol";
import {
    type DebugRunMode,
    type ResolvedRunProfile,
    resolveRunProfile,
    RunProfile,
    RunProfileError,
    RunProfileStore,
    SavedRunProfile,
} from "./profiles";
import {
    describeRunProfile,
    isDraftOnlyProfile,
    promptRunProfile,
    selectRunMode,
} from "./runInputs";
import { createDraftSnapshot } from "./snapshot";
import {
    FreeBookDebugSidebarProvider,
    type SidebarField,
    type SidebarMessage,
    type SidebarMode,
    type SidebarScript,
    type SidebarState,
} from "./sidebarView";
import { TracePresenter } from "./trace";
import {
    type DebugEventSubscription,
    type DebugTransport,
    DebugTransportError,
    toDraftTransportSnapshot,
} from "./transport";
import { WebSocketDebugTransport } from "./webSocketTransport";

const SELECTED_ROOT_STORAGE_KEY = "freebookExtDebug.selectedRoot.v1";
const LAST_ENDPOINT_STORAGE_KEY = "freebookExtDebug.lastEndpoint.v1";
const SECRET_KEY_PREFIX = "freebookExtDebug.session.v1.";

interface CurrentRun {
    readonly runId: string;
}

interface CurrentScript {
    readonly manifest: ExtensionManifest;
    readonly script: ResolvedExtensionScript;
}

interface SidebarScriptCollection {
    readonly scripts: readonly SidebarScript[];
    readonly choices: ReadonlyMap<string, CurrentScript>;
    readonly preferredScriptId?: string;
}

/** VS Code entry point. The app, never this extension, executes VBook JavaScript. */
export function activate(context: vscode.ExtensionContext): void {
    const controller = new FreeBookExtDebugController(context);
    context.subscriptions.push(controller);
}

export function deactivate(): void {
    // The controller is disposed by ExtensionContext.
}

class FreeBookExtDebugController implements vscode.Disposable {
    private readonly trace = new TracePresenter();
    private readonly profiles: RunProfileStore;
    private readonly disposables: vscode.Disposable[] = [];
    private readonly sessionsByEndpoint = new Map<string, string>();
    private readonly sidebar: FreeBookDebugSidebarProvider;
    /** Sidebar ids are opaque values produced by the extension host, never paths from the webview. */
    private readonly sidebarRoots = new Map<string, ExtensionManifest>();
    private readonly sidebarScripts = new Map<string, ReadonlyMap<string, CurrentScript>>();
    private readonly installedPackageIds = new Set<string>();
    private transport: DebugTransport | undefined;
    private eventSubscription: DebugEventSubscription | undefined;
    private disconnectSubscription: DebugEventSubscription | undefined;
    private endpoint: string | undefined;
    private activeRun: CurrentRun | undefined;
    private isStartingRun = false;
    /** Keeps a fast server event from racing the run.start response. */
    private awaitingRunContext = false;
    private readonly pendingRunEvents: DebugTraceEvent[] = [];
    private selectedSidebarRootId: string | undefined;
    private selectedSidebarScriptId: string | undefined;
    /** A root deliberately chosen from the sidebar/native picker wins over editor auto-detect. */
    private explicitSidebarRootId: string | undefined;
    /** A manually selected script wins until the user changes the active editor. */
    private explicitSidebarScript: Readonly<{ rootId: string; scriptId: string }> | undefined;
    private sidebarMode: DebugRunMode = "draft";
    private sidebarRefreshGeneration = 0;

    public constructor(private readonly context: vscode.ExtensionContext) {
        this.profiles = new RunProfileStore(context.workspaceState);
        this.sidebar = new FreeBookDebugSidebarProvider((message) => this.handleSidebarMessage(message));
        this.disposables.push(
            this.sidebar,
            vscode.window.registerWebviewViewProvider(
                FreeBookDebugSidebarProvider.viewType,
                this.sidebar,
                { webviewOptions: { retainContextWhenHidden: true } },
            ),
            this.trace.onDidAppendLine((line) => this.sidebar.appendTrace(line)),
            vscode.window.onDidChangeActiveTextEditor(() => {
                this.explicitSidebarScript = undefined;
                void this.refreshSidebar();
            }),
            vscode.workspace.onDidSaveTextDocument((document) => {
                if (document.uri.scheme === "file" && (document.uri.path.endsWith(".js") || document.fileName.endsWith("plugin.json"))) {
                    void this.refreshSidebar();
                }
            }),
            vscode.commands.registerCommand("freebookExtDebug.openPanel", () => this.runCommand(() => this.openSidebar())),
            vscode.commands.registerCommand("freebookExtDebug.pair", () => this.runCommand(() => this.pairWithApp())),
            vscode.commands.registerCommand("freebookExtDebug.selectExtensionRoot", () => this.runCommand(() => this.selectExtensionRoot())),
            vscode.commands.registerCommand("freebookExtDebug.runCurrent", (uri?: vscode.Uri) => this.runCommand(() => this.runCurrent(uri))),
            vscode.commands.registerCommand("freebookExtDebug.runSavedProfile", () => this.runCommand(() => this.runSavedProfile())),
            vscode.commands.registerCommand("freebookExtDebug.useMockTransport", () => this.runCommand(() => this.useMockTransport())),
            vscode.commands.registerCommand("freebookExtDebug.cancelRun", () => this.runCommand(() => this.cancelCurrentRun())),
            vscode.commands.registerCommand("freebookExtDebug.openTrace", () => this.trace.show()),
        );
        this.trace.appendNotice("FreeBook Ext Debug sẵn sàng. Client không chạy JavaScript VBook bằng Node.");
        void this.refreshSidebar();
    }

    public dispose(): void {
        this.eventSubscription?.dispose();
        this.disconnectSubscription?.dispose();
        this.transport?.dispose();
        this.trace.dispose();
        for (const disposable of this.disposables) {
            disposable.dispose();
        }
    }

    private async pairWithApp(): Promise<void> {
        if (!this.ensureDesktopTrusted()) {
            return;
        }

        const rawUri = await vscode.window.showInputBox({
            title: "Pair with FreeBook App",
            prompt: "Dán pairing URI do FreeBook App tạo.",
            password: true,
            ignoreFocusOut: true,
        });
        if (rawUri === undefined) {
            return;
        }

        let pairing: ReturnType<typeof parsePairingUri>;
        try {
            pairing = parsePairingUri(rawUri);
        } catch (error) {
            throw this.asSafeError(error, [rawUri]);
        }

        const endpoint = pairing.endpoint;
        const storedSession = await this.context.secrets.get(this.secretKey(endpoint));
        if (storedSession) {
            this.sessionsByEndpoint.set(endpoint, storedSession);
        }

        const candidate = new WebSocketDebugTransport(endpoint, () => this.sessionsByEndpoint.get(endpoint));
        let hello: Awaited<ReturnType<WebSocketDebugTransport["connect"]>>;
        let session: string | undefined;
        try {
            hello = await candidate.connect();
            session = this.sessionsByEndpoint.get(endpoint);
            if (hello.pairingRequired && !hello.sessionAccepted) {
                const paired = await candidate.pair({ oneTimeToken: pairing.oneTimeToken });
                session = paired.session;
                this.sessionsByEndpoint.set(endpoint, session);
                await this.context.secrets.store(this.secretKey(endpoint), session);
            }

        } catch (error) {
            candidate.dispose();
            throw this.asSafeError(error, [rawUri, pairing.oneTimeToken, storedSession]);
        }

        await this.installTransport(candidate, endpoint, true);
        // Never persist the URI itself: it contains a one-time pairing token.
        await this.context.workspaceState.update(LAST_ENDPOINT_STORAGE_KEY, endpoint);
        this.trace.appendNotice(`Paired with FreeBook App at ${endpoint}.`);
        if (!session && hello.pairingRequired) {
            this.trace.appendNotice("App yêu cầu pairing nhưng chưa trả session; lệnh run sẽ bị app từ chối cho tới khi pair thành công.");
        }
        void this.refreshSidebar();
    }

    private async openSidebar(): Promise<void> {
        if (!this.ensureDesktopTrusted()) {
            return;
        }
        await vscode.commands.executeCommand(`${FreeBookDebugSidebarProvider.viewType}.focus`);
        await this.refreshSidebar();
    }

    private async selectExtensionRoot(): Promise<void> {
        if (!this.ensureDesktopTrusted()) {
            return;
        }

        const selected = await this.pickRootCandidate();
        if (!selected) {
            return;
        }
        this.ensureLocalUri(selected);
        const manifest = await discoverExtensionManifest(selected);
        this.ensureLocalUri(manifest.root);
        await this.rememberManifest(manifest);
        this.selectedSidebarRootId = this.sidebarRootId(manifest);
        this.explicitSidebarRootId = this.selectedSidebarRootId;
        this.selectedSidebarScriptId = undefined;
        this.explicitSidebarScript = undefined;
        if (this.transport?.kind === "mock") {
            await this.configureMockExtension(manifest);
        }
        vscode.window.showInformationMessage(`Đã chọn extension ${manifest.name} (${manifest.packageId}).`);
        void this.refreshSidebar();
    }

    private async useMockTransport(): Promise<void> {
        if (!this.ensureDesktopTrusted()) {
            return;
        }
        await this.installTransport(new MockDebugTransport(), undefined);
        const selectedManifest = this.selectedSidebarRootId
            ? this.sidebarRoots.get(this.selectedSidebarRootId)
            : undefined;
        if (selectedManifest) {
            await this.configureMockExtension(selectedManifest);
        }
        this.trace.appendNotice("Mock — không chạy JSExecutor iOS. Kết quả chỉ xác nhận UX và protocol v1.");
        vscode.window.showInformationMessage("Đang dùng Mock Transport — không chạy JSExecutor iOS.");
        void this.refreshSidebar();
    }

    private async runCurrent(uri?: vscode.Uri): Promise<void> {
        if (!this.ensureDesktopTrusted() || !this.ensureNoActiveRun()) {
            return;
        }

        const { manifest, script } = await this.resolveCurrentScript(uri);
        const profile = await promptRunProfile(manifest, script);
        if (!profile) {
            return;
        }

        await this.startProfileRun(manifest, profile);
        await this.offerSaveProfile(manifest, profile);
    }

    private async runSavedProfile(): Promise<void> {
        if (!this.ensureDesktopTrusted() || !this.ensureNoActiveRun()) {
            return;
        }

        const manifest = await this.resolveSelectedManifest();
        const saved = await this.pickSavedProfile(manifest);
        if (!saved) {
            return;
        }
        await this.startProfileRun(manifest, saved.profile);
    }

    private async cancelCurrentRun(): Promise<void> {
        if (!this.ensureDesktopTrusted()) {
            return;
        }
        if (!this.transport || !this.activeRun) {
            vscode.window.showInformationMessage("Không có run đang hoạt động để hủy.");
            return;
        }

        const response = await this.transport.cancel(this.activeRun.runId);
        this.trace.appendNotice(`Cancel ${response.runId}: ${response.accepted ? "accepted" : "not accepted"}.`);
        if (!response.accepted) {
            this.trace.endRun(this.activeRun.runId);
            this.activeRun = undefined;
            vscode.window.showWarningMessage("App không còn nhận run này; hãy xem Trace để biết trạng thái cuối.");
        }
        void this.refreshSidebar();
    }

    private async startProfileRun(
        manifest: ExtensionManifest,
        profile: RunProfile,
        requestedMode?: DebugRunMode,
    ): Promise<void> {
        if (!this.ensureNoActiveRun()) {
            return;
        }
        this.isStartingRun = true;
        void this.refreshSidebar();
        try {
            const transport = await this.ensureTransport(manifest);
            if (!transport) {
                return;
            }

            const installedAvailable = await this.hasMatchingInstalledExtension(transport, manifest);
            const mode = requestedMode ?? await selectRunMode(installedAvailable, isDraftOnlyProfile(profile));
            if (!mode) {
                return;
            }
            if (isDraftOnlyProfile(profile) && mode !== "draft") {
                throw new RunProfileError("Script không khai trong plugin.json chỉ có thể chạy ở chế độ draft.");
            }
            if (mode === "installed" && !installedAvailable) {
                throw new RunProfileError("App chưa có extension đã cài với package ID trùng khớp; hãy dùng Draft hoặc Pair lại app.");
            }

            const resolved = await resolveRunProfile(manifest, mode, profile);
            const invocation = makeInvocation(profile, resolved);
            const staged = mode === "draft"
                ? await this.stageSavedDraft(transport, manifest)
                : undefined;

            const request: RunStartRequest = {
                target: staged
                    ? { mode: "draft", packageId: manifest.packageId, draftId: staged.draftId }
                    : { mode: "installed", packageId: manifest.packageId },
                invocation,
                config: resolved.config as ProtocolJsonObject,
            };
            const sourceRevisions = staged?.sourceRevisions ?? new Map<string, string>();
            this.trace.appendNotice(`${mode === "draft" ? "Staged draft" : "Installed"}: ${manifest.packageId} / ${resolved.script.relativePath}`);
            this.awaitingRunContext = true;
            const response = await transport.run(request);
            this.awaitingRunContext = false;
            this.activeRun = { runId: response.runId };
            this.trace.beginRun(response.runId, manifest.root, sourceRevisions);
            this.flushPendingRunEvents();
        } finally {
            this.awaitingRunContext = false;
            this.pendingRunEvents.length = 0;
            this.isStartingRun = false;
            void this.refreshSidebar();
        }
    }

    private async stageSavedDraft(
        transport: DebugTransport,
        manifest: ExtensionManifest,
    ): Promise<Readonly<{ draftId: string; sourceRevisions: ReadonlyMap<string, string> }>> {
        return vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: "FreeBook Ext Debug: staging saved draft",
                cancellable: false,
            },
            async () => {
                const snapshot = await createDraftSnapshot(manifest);
                const sourceRevisions = new Map(snapshot.files.map((file) => [file.path, file.revision]));
                const result = await transport.stageDraft(toDraftTransportSnapshot(manifest.packageId, snapshot));
                if (result.manifestHash !== snapshot.manifest.hash) {
                    throw new DebugTransportError("App returned a staged manifest hash that does not match the saved draft.", "stale_stage");
                }
                return { draftId: result.draftId, sourceRevisions };
            },
        );
    }

    private async ensureTransport(manifest: ExtensionManifest): Promise<DebugTransport | undefined> {
        if (!this.transport) {
            const restored = await this.restoreLastAppTransport();
            if (!restored) {
                const choice = await vscode.window.showWarningMessage(
                    "Chưa có FreeBook debug transport.",
                    "Use Mock Transport",
                    "Pair with FreeBook App",
                );
                if (choice === "Use Mock Transport") {
                    await this.useMockTransport();
                } else if (choice === "Pair with FreeBook App") {
                    await this.pairWithApp();
                } else {
                    return undefined;
                }
            }
        }

        if (this.transport?.kind === "mock") {
            await this.configureMockExtension(manifest);
        }
        return this.transport;
    }

    private async restoreLastAppTransport(): Promise<boolean> {
        const endpoint = this.context.workspaceState.get<string>(LAST_ENDPOINT_STORAGE_KEY);
        if (!endpoint) {
            return false;
        }

        let candidate: WebSocketDebugTransport | undefined;
        try {
            candidate = new WebSocketDebugTransport(endpoint, () => this.sessionsByEndpoint.get(endpoint));
            const session = await this.context.secrets.get(this.secretKey(candidate.endpoint));
            if (session) {
                this.sessionsByEndpoint.set(candidate.endpoint, session);
            }
            const hello = await candidate.connect();
            if (hello.pairingRequired && !hello.sessionAccepted) {
                candidate.dispose();
                return false;
            }
            await this.installTransport(candidate, candidate.endpoint, true);
            this.trace.appendNotice(`Reconnected to FreeBook App at ${candidate.endpoint}.`);
            return true;
        } catch {
            candidate?.dispose();
            return false;
        }
    }

    private async configureMockExtension(manifest: ExtensionManifest): Promise<void> {
        const current = this.transport;
        if (!current || current.kind !== "mock") {
            return;
        }
        const installed = await current.listExtensions();
        if (installed.extensions.some((extension) => extension.packageId === manifest.packageId)) {
            return;
        }
        await this.installTransport(
            new MockDebugTransport({
                extensions: [{
                    packageId: manifest.packageId,
                    name: manifest.name,
                    scriptKeys: Object.keys(manifest.scripts),
                }],
            }),
            undefined,
        );
        this.trace.appendNotice(`Mock fixture added installed extension ${manifest.packageId}.`);
        await this.refreshInstalledExtensions();
    }

    private async hasMatchingInstalledExtension(transport: DebugTransport, manifest: ExtensionManifest): Promise<boolean> {
        const extensions = await transport.listExtensions();
        if (transport === this.transport) {
            this.installedPackageIds.clear();
            for (const extension of extensions.extensions) {
                this.installedPackageIds.add(extension.packageId);
            }
        }
        return extensions.extensions.some((extension) => extension.packageId === manifest.packageId);
    }

    private async refreshInstalledExtensions(transport = this.transport): Promise<void> {
        if (!transport) {
            this.installedPackageIds.clear();
            return;
        }

        try {
            const extensions = await transport.listExtensions();
            if (transport !== this.transport) {
                return;
            }
            this.installedPackageIds.clear();
            for (const extension of extensions.extensions) {
                this.installedPackageIds.add(extension.packageId);
            }
        } catch {
            // A transient list failure should not tear down an otherwise usable
            // transport. The next explicit run checks package ID again.
            if (transport === this.transport) {
                this.installedPackageIds.clear();
            }
        }
    }

    private async installTransport(transport: DebugTransport, endpoint: string | undefined, alreadyConnected = false): Promise<void> {
        const oldTransport = this.transport;
        const oldSubscription = this.eventSubscription;
        const oldDisconnectSubscription = this.disconnectSubscription;
        this.transport = transport;
        this.endpoint = endpoint;
        this.eventSubscription = undefined;
        this.disconnectSubscription = undefined;
        try {
            if (!alreadyConnected) {
                await transport.connect();
            }
            this.eventSubscription = await transport.subscribe((event) => this.handleTraceEvent(event));
            this.disconnectSubscription = transport.onDidDisconnect((message) => this.handleTransportDisconnect(message));
            await this.refreshInstalledExtensions(transport);
        } catch (error) {
            this.transport = oldTransport;
            this.eventSubscription = oldSubscription;
            this.disconnectSubscription = oldDisconnectSubscription;
            this.endpoint = oldTransport instanceof WebSocketDebugTransport ? oldTransport.endpoint : undefined;
            transport.dispose();
            throw error;
        }

        oldSubscription?.dispose();
        oldDisconnectSubscription?.dispose();
        oldTransport?.dispose();
        void this.refreshSidebar();
    }

    private handleTraceEvent(event: DebugTraceEvent): void {
        if (this.awaitingRunContext && event.runId) {
            this.pendingRunEvents.push(event);
            return;
        }
        const currentSession = this.endpoint ? this.sessionsByEndpoint.get(this.endpoint) : undefined;
        this.trace.handle(event, [currentSession]);
        if (event.runId && event.runId === this.activeRun?.runId && isTerminalEvent(event)) {
            this.trace.endRun(event.runId);
            this.activeRun = undefined;
            void this.refreshSidebar();
        }
    }

    private flushPendingRunEvents(): void {
        const events = this.pendingRunEvents.splice(0, this.pendingRunEvents.length);
        for (const event of events) {
            this.handleTraceEvent(event);
        }
    }

    private handleTransportDisconnect(message: string): void {
        this.trace.appendNotice(message);
        if (this.activeRun) {
            this.trace.endRun(this.activeRun.runId);
            this.activeRun = undefined;
        }
        this.installedPackageIds.clear();
        void this.refreshSidebar();
    }

    /** Routes only whitelisted webview actions back to the extension host. */
    private async handleSidebarMessage(message: SidebarMessage): Promise<void> {
        if (message.type === "ready") {
            this.sidebar.replaceTrace(this.trace.getRecentLines());
            await this.refreshSidebar();
            return;
        }

        await this.runCommand(async () => {
            if (!this.ensureDesktopTrusted()) {
                return;
            }

            switch (message.type) {
                case "browseRoot":
                    await this.selectExtensionRoot();
                    return;
                case "selectRoot":
                    await this.selectSidebarRoot(message.rootId);
                    return;
                case "selectScript":
                    await this.selectSidebarScript(message.scriptId);
                    return;
                case "selectMode":
                    await this.selectSidebarMode(message.mode);
                    return;
                case "run":
                    await this.runSidebar(message);
                    return;
                case "pair":
                    await this.pairWithApp();
                    return;
                case "useMock":
                    await this.useMockTransport();
                    return;
                case "cancel":
                    await this.cancelCurrentRun();
                    return;
                case "openTrace":
                    this.trace.show();
                    return;
            }
        });
    }

    private async selectSidebarRoot(rootId: string): Promise<void> {
        const manifest = this.sidebarRoots.get(rootId);
        if (!manifest) {
            throw new ExtensionWorkspaceError("manifest-not-found", "Extension root trong sidebar không còn hợp lệ. Hãy chọn lại.");
        }
        this.selectedSidebarRootId = rootId;
        this.explicitSidebarRootId = rootId;
        this.selectedSidebarScriptId = undefined;
        this.explicitSidebarScript = undefined;
        await this.rememberManifest(manifest);
        if (this.transport?.kind === "mock") {
            await this.configureMockExtension(manifest);
        }
        await this.refreshSidebar();
    }

    private async selectSidebarScript(scriptId: string): Promise<void> {
        const rootId = this.selectedSidebarRootId;
        const selection = rootId ? this.sidebarScripts.get(rootId)?.get(scriptId) : undefined;
        if (!rootId || !selection) {
            throw new ExtensionWorkspaceError("missing-script", "Script trong sidebar không còn hợp lệ. Hãy refresh và chọn lại.");
        }
        this.selectedSidebarScriptId = scriptId;
        this.explicitSidebarScript = { rootId, scriptId };
        if (!selection.script.manifestKey) {
            this.sidebarMode = "draft";
        }
        await this.refreshSidebar();
    }

    private async selectSidebarMode(mode: SidebarMode): Promise<void> {
        const selected = this.currentSidebarScript();
        this.sidebarMode = selected?.script.manifestKey ? mode : "draft";
        await this.refreshSidebar();
    }

    private async runSidebar(message: Extract<SidebarMessage, { readonly type: "run" }>): Promise<void> {
        const rootId = message.rootId ?? this.selectedSidebarRootId;
        const scriptId = message.scriptId ?? this.selectedSidebarScriptId;
        const remembered = rootId ? this.sidebarRoots.get(rootId) : undefined;
        const choice = rootId && scriptId ? this.sidebarScripts.get(rootId)?.get(scriptId) : undefined;
        if (!remembered || !choice || !rootId || !scriptId) {
            throw new ExtensionWorkspaceError("missing-script", "Hãy chọn extension root và script hợp lệ trước khi chạy.");
        }

        // Re-read both manifest and selected script. The browser is never a
        // trusted source for paths or execute contracts.
        const manifest = await readExtensionManifest(remembered.root);
        const current = await this.revalidateSidebarScript(manifest, choice);
        if (isUnsupportedDebugScript(current.script.manifestKey)) {
            throw new RunProfileError(unsupportedDebugScriptReason(current.script.manifestKey));
        }
        const mode: DebugRunMode = current.script.manifestKey ? message.mode : "draft";
        if (!current.script.manifestKey && message.mode !== "draft") {
            throw new RunProfileError("Script không khai trong plugin.json chỉ có thể chạy ở chế độ draft.");
        }
        const profile = profileFromSidebar(current.script, message.values);

        this.selectedSidebarRootId = rootId;
        this.selectedSidebarScriptId = scriptId;
        this.explicitSidebarScript = { rootId, scriptId };
        this.sidebarMode = mode;
        await this.rememberManifest(manifest);
        await this.startProfileRun(manifest, profile, mode);
    }

    private async revalidateSidebarScript(
        manifest: ExtensionManifest,
        choice: CurrentScript,
    ): Promise<CurrentScript> {
        if (choice.script.manifestKey) {
            return {
                manifest,
                script: await resolveManifestScript(manifest, choice.script.manifestKey),
            };
        }
        return {
            manifest,
            script: await resolveExtensionScript(manifest.root, choice.script.relativePath),
        };
    }

    /**
     * Builds the sidebar view model from saved workspace files. A version gate
     * prevents a slow refresh for an old editor from replacing the new state.
     */
    private async refreshSidebar(): Promise<void> {
        const generation = ++this.sidebarRefreshGeneration;
        const manifests = await this.collectSidebarManifests();
        if (generation !== this.sidebarRefreshGeneration) {
            return;
        }

        const rootMap = new Map(manifests.map((manifest) => [this.sidebarRootId(manifest), manifest]));
        if (this.explicitSidebarRootId && !rootMap.has(this.explicitSidebarRootId)) {
            this.explicitSidebarRootId = undefined;
        }
        const activeRootId = this.explicitSidebarRootId ? undefined : await this.activeSidebarRootId(rootMap);
        if (generation !== this.sidebarRefreshGeneration) {
            return;
        }
        let selectedRootId = this.explicitSidebarRootId
            ?? activeRootId
            ?? (this.selectedSidebarRootId && rootMap.has(this.selectedSidebarRootId) ? this.selectedSidebarRootId : undefined)
            ?? this.rememberedSidebarRootId(rootMap)
            ?? (manifests[0] ? this.sidebarRootId(manifests[0]) : undefined);
        if (!selectedRootId || !rootMap.has(selectedRootId)) {
            selectedRootId = undefined;
        }
        const selectedManifest = selectedRootId ? rootMap.get(selectedRootId) : undefined;
        const scriptCollection = selectedManifest
            ? await this.collectSidebarScripts(selectedManifest)
            : { scripts: [], choices: new Map<string, CurrentScript>() } satisfies SidebarScriptCollection;
        if (generation !== this.sidebarRefreshGeneration) {
            return;
        }

        let selectedScriptId = this.selectedSidebarScriptId;
        if (!selectedScriptId || !scriptCollection.choices.has(selectedScriptId)) {
            selectedScriptId = scriptCollection.preferredScriptId ?? scriptCollection.scripts[0]?.id;
        }
        const selectedScript = selectedScriptId ? scriptCollection.choices.get(selectedScriptId) : undefined;
        const installedAvailable = Boolean(
            selectedManifest
            && selectedScript?.script.manifestKey
            && !isUnsupportedDebugScript(selectedScript.script.manifestKey)
            && this.installedPackageIds.has(selectedManifest.packageId),
        );
        const mode: DebugRunMode = selectedScript?.script.manifestKey && this.sidebarMode === "installed" && installedAvailable
            ? "installed"
            : "draft";

        this.sidebarRoots.clear();
        for (const [rootId, manifest] of rootMap) {
            this.sidebarRoots.set(rootId, manifest);
        }
        this.sidebarScripts.clear();
        if (selectedRootId) {
            this.sidebarScripts.set(selectedRootId, scriptCollection.choices);
        }
        this.selectedSidebarRootId = selectedRootId;
        this.selectedSidebarScriptId = selectedScriptId;
        this.sidebarMode = mode;

        const state: SidebarState = {
            roots: manifests.map((manifest) => ({
                id: this.sidebarRootId(manifest),
                label: `${manifest.name} (${manifest.packageId})`,
                description: manifest.root.fsPath,
            })),
            ...(selectedRootId ? { selectedRootId } : {}),
            scripts: scriptCollection.scripts,
            ...(selectedScriptId ? { selectedScriptId } : {}),
            mode,
            installedAvailable,
            isRunning: Boolean(this.activeRun || this.isStartingRun),
            connection: this.sidebarConnection(),
            status: this.sidebarStatus(selectedManifest),
        };
        this.sidebar.postState(state);
    }

    private async collectSidebarManifests(): Promise<readonly ExtensionManifest[]> {
        const candidates: vscode.Uri[] = [];
        const stored = this.context.workspaceState.get<string>(SELECTED_ROOT_STORAGE_KEY);
        if (stored) {
            try {
                const uri = vscode.Uri.parse(stored);
                if (uri.scheme === "file") {
                    candidates.push(uri);
                }
            } catch {
                // A malformed old Memento value should not stop the sidebar.
            }
        }

        const active = vscode.window.activeTextEditor?.document.uri;
        if (active?.scheme === "file" && active.path.toLowerCase().endsWith(".js")) {
            candidates.push(active);
        }

        try {
            const manifests = await vscode.workspace.findFiles(
                "**/plugin.json",
                "**/{.git,node_modules,out,.vscode}/**",
                80,
            );
            candidates.push(...manifests.filter((uri) => uri.scheme === "file"));
        } catch {
            // Empty folders and remote-only workspaces simply have no candidates.
        }

        const collected = new Map<string, ExtensionManifest>();
        for (const candidate of candidates) {
            try {
                const manifest = await discoverExtensionManifest(candidate);
                this.ensureLocalUri(manifest.root);
                collected.set(this.sidebarRootId(manifest), manifest);
            } catch {
                // The sidebar must remain usable when unrelated plugin.json files
                // are malformed or a workspace folder is temporarily unavailable.
            }
        }

        return [...collected.values()].sort((left, right) => {
            const labelLeft = `${left.name}\u0000${left.root.fsPath}`.toLocaleLowerCase();
            const labelRight = `${right.name}\u0000${right.root.fsPath}`.toLocaleLowerCase();
            return labelLeft.localeCompare(labelRight);
        });
    }

    private async collectSidebarScripts(manifest: ExtensionManifest): Promise<SidebarScriptCollection> {
        const choices = new Map<string, CurrentScript>();
        const scripts: SidebarScript[] = [];
        const rootId = this.sidebarRootId(manifest);

        for (const scriptKey of Object.keys(manifest.scripts).sort()) {
            try {
                const resolved = await resolveManifestScript(manifest, scriptKey);
                const script: ResolvedExtensionScript = { ...resolved, manifestKey: scriptKey };
                const id = `manifest:${scriptKey}`;
                choices.set(id, { manifest, script });
                scripts.push({
                    id,
                    label: scriptKey,
                    description: script.relativePath,
                    manifestKey: scriptKey,
                    ...(isUnsupportedDebugScript(scriptKey)
                        ? { disabled: true, disabledReason: unsupportedDebugScriptReason(scriptKey) }
                        : {}),
                    fields: sidebarFieldsFor(script),
                });
            } catch {
                // Broken declarations are omitted; resolving an unrelated script
                // must not prevent a valid execute entry point from being shown.
            }
        }

        const declaredUris = new Set([...choices.values()].map((current) => current.script.uri.toString()));
        for (const uri of await this.extensionJavaScriptFiles(manifest.root)) {
            try {
                if (declaredUris.has(uri.toString())) {
                    continue;
                }
                const relativePath = relativePathFromRoot(manifest.root, uri);
                const resolved = await resolveExtensionScript(manifest.root, relativePath);
                const declared = await declaredScriptKey(manifest, resolved);
                if (!declared) {
                    const id = `draft:${resolved.relativePath}`;
                    choices.set(id, { manifest, script: resolved });
                    scripts.push({
                        id,
                        label: resolved.relativePath,
                        description: "Chưa khai trong plugin.json; chỉ chạy Draft với JSON arguments",
                        draftOnly: true,
                        fields: sidebarFieldsFor(resolved),
                    });
                }
            } catch {
                // An unusual file entry must not prevent the remaining scripts
                // from being offered as saved Draft candidates.
            }
        }

        const preferredScriptId = this.preferredSidebarScriptId(rootId, choices);
        return { scripts, choices, ...(preferredScriptId ? { preferredScriptId } : {}) };
    }

    /** Lists saved, ordinary JS files that can be staged with an extension Draft. */
    private async extensionJavaScriptFiles(root: vscode.Uri, maximum = 160): Promise<readonly vscode.Uri[]> {
        const excludedDirectories = new Set([".git", "node_modules", "out", ".vscode"]);
        const directories: vscode.Uri[] = [root];
        const files: vscode.Uri[] = [];

        while (directories.length > 0 && files.length < maximum) {
            const directory = directories.shift();
            if (!directory) {
                continue;
            }
            let entries: [string, vscode.FileType][];
            try {
                entries = await vscode.workspace.fs.readDirectory(directory);
            } catch {
                continue;
            }

            for (const [name, type] of entries.sort(([left], [right]) => left.localeCompare(right))) {
                if (files.length >= maximum) {
                    break;
                }
                if ((type & vscode.FileType.SymbolicLink) !== 0) {
                    continue;
                }
                const uri = vscode.Uri.joinPath(directory, name);
                if ((type & vscode.FileType.Directory) !== 0) {
                    if (!excludedDirectories.has(name)) {
                        directories.push(uri);
                    }
                    continue;
                }
                if ((type & vscode.FileType.File) !== 0 && name.toLowerCase().endsWith(".js")) {
                    files.push(uri);
                }
            }
        }

        return files;
    }

    private preferredSidebarScriptId(
        rootId: string,
        choices: ReadonlyMap<string, CurrentScript>,
    ): string | undefined {
        if (this.explicitSidebarScript?.rootId === rootId && choices.has(this.explicitSidebarScript.scriptId)) {
            return this.explicitSidebarScript.scriptId;
        }
        const active = vscode.window.activeTextEditor?.document.uri;
        if (active?.scheme === "file") {
            for (const [id, current] of choices) {
                if (current.script.uri.toString() === active.toString()) {
                    return id;
                }
            }
        }
        if (rootId === this.selectedSidebarRootId && this.selectedSidebarScriptId && choices.has(this.selectedSidebarScriptId)) {
            return this.selectedSidebarScriptId;
        }
        return choices.keys().next().value;
    }

    private rememberedSidebarRootId(roots: ReadonlyMap<string, ExtensionManifest>): string | undefined {
        const stored = this.context.workspaceState.get<string>(SELECTED_ROOT_STORAGE_KEY);
        if (!stored) {
            return undefined;
        }
        for (const [id, manifest] of roots) {
            if (manifest.root.toString() === stored) {
                return id;
            }
        }
        return undefined;
    }

    private async activeSidebarRootId(roots: ReadonlyMap<string, ExtensionManifest>): Promise<string | undefined> {
        const active = vscode.window.activeTextEditor?.document.uri;
        if (active?.scheme !== "file" || !active.path.toLowerCase().endsWith(".js")) {
            return undefined;
        }
        try {
            const manifest = await discoverExtensionManifest(active);
            const rootId = this.sidebarRootId(manifest);
            return roots.has(rootId) ? rootId : undefined;
        } catch {
            return undefined;
        }
    }

    private currentSidebarScript(): CurrentScript | undefined {
        return this.selectedSidebarRootId && this.selectedSidebarScriptId
            ? this.sidebarScripts.get(this.selectedSidebarRootId)?.get(this.selectedSidebarScriptId)
            : undefined;
    }

    private sidebarRootId(manifest: ExtensionManifest): string {
        return manifest.root.toString();
    }

    private sidebarConnection(): SidebarState["connection"] {
        if (!this.transport) {
            return { kind: "disconnected", label: "Chưa kết nối" };
        }
        if (this.transport.kind === "mock") {
            return {
                kind: "mock",
                label: "Mock",
                detail: "Mock — không chạy JSExecutor iOS.",
            };
        }
        return {
            kind: "app",
            label: "Paired",
            ...(this.endpoint ? { detail: this.endpoint } : {}),
        };
    }

    private sidebarStatus(manifest: ExtensionManifest | undefined): string {
        if (this.isStartingRun || this.activeRun) {
            return "Đang chạy execute(...). Bạn có thể bấm Cancel nếu app hỗ trợ hủy run này.";
        }
        if (!manifest) {
            return "Mở một file .js trong extension hoặc bấm Chọn… để chọn thư mục có plugin.json.";
        }
        if (!this.transport) {
            return "Chọn Use Mock để kiểm tra protocol, hoặc Pair App khi FreeBook Debug Server đã sẵn sàng.";
        }
        if (this.transport.kind === "mock") {
            return "Mock — không chạy JSExecutor iOS; kết quả chỉ kiểm tra UX và protocol v1.";
        }
        return "Đã pair với FreeBook App. Installed chỉ bật khi package ID trên app trùng khớp.";
    }

    private async resolveCurrentScript(uri?: vscode.Uri): Promise<CurrentScript> {
        const candidate = uri ?? vscode.window.activeTextEditor?.document.uri;
        if (candidate?.path.toLowerCase().endsWith(".js")) {
            this.ensureLocalUri(candidate);
            const manifest = await discoverExtensionManifest(candidate);
            this.ensureLocalUri(manifest.root);
            const relativePath = relativePathFromRoot(manifest.root, candidate);
            const resolved = await resolveExtensionScript(manifest.root, relativePath);
            const manifestKey = await declaredScriptKey(manifest, resolved);
            const script = manifestKey ? { ...resolved, manifestKey } : resolved;
            await this.rememberManifest(manifest);
            return { manifest, script };
        }

        const manifest = await this.resolveSelectedManifest();
        const script = await this.pickManifestScript(manifest);
        return { manifest, script };
    }

    private async resolveSelectedManifest(): Promise<ExtensionManifest> {
        const stored = this.context.workspaceState.get<string>(SELECTED_ROOT_STORAGE_KEY);
        if (stored) {
            try {
                const manifest = await discoverExtensionManifest(vscode.Uri.parse(stored));
                this.ensureLocalUri(manifest.root);
                return manifest;
            } catch {
                // A deleted/moved root must not make the command unusable.
                await this.context.workspaceState.update(SELECTED_ROOT_STORAGE_KEY, undefined);
            }
        }

        const active = vscode.window.activeTextEditor?.document.uri;
        if (active?.scheme === "file") {
            try {
                const manifest = await discoverExtensionManifest(active);
                this.ensureLocalUri(manifest.root);
                await this.rememberManifest(manifest);
                return manifest;
            } catch {
                // The active file may belong to an unrelated workspace.
            }
        }

        await this.selectExtensionRoot();
        const selected = this.context.workspaceState.get<string>(SELECTED_ROOT_STORAGE_KEY);
        if (!selected) {
            throw new ExtensionWorkspaceError("manifest-not-found", "Chưa chọn thư mục extension.");
        }
        return discoverExtensionManifest(vscode.Uri.parse(selected));
    }

    private async pickManifestScript(manifest: ExtensionManifest): Promise<ResolvedExtensionScript> {
        const candidates: Array<vscode.QuickPickItem & { script: ResolvedExtensionScript }> = [];
        for (const scriptKey of Object.keys(manifest.scripts).sort()) {
            try {
                const script = await resolveManifestScript(manifest, scriptKey);
                candidates.push({
                    label: scriptKey,
                    description: script.relativePath,
                    script,
                });
            } catch (error) {
                this.trace.appendNotice(`Không thể resolve ${scriptKey}: ${messageFor(error)}`);
            }
        }
        if (candidates.length === 0) {
            throw new ExtensionWorkspaceError("missing-script", "plugin.json không có script hợp lệ để chạy.");
        }
        const picked = await vscode.window.showQuickPick(candidates, {
            title: "FreeBook Ext Debug: Chọn script",
            placeHolder: "Script khai trong plugin.json",
        });
        if (!picked) {
            throw new vscode.CancellationError();
        }
        return picked.script;
    }

    private async pickRootCandidate(): Promise<vscode.Uri | undefined> {
        const choices: Array<vscode.QuickPickItem & { uri?: vscode.Uri; browse?: boolean }> = [];
        const active = vscode.window.activeTextEditor?.document.uri;
        if (active?.scheme === "file") {
            choices.push({ label: "Active editor", description: active.fsPath, uri: active });
        }
        for (const folder of vscode.workspace.workspaceFolders ?? []) {
            if (folder.uri.scheme === "file") {
                choices.push({ label: folder.name, description: folder.uri.fsPath, uri: folder.uri });
            }
        }
        choices.push({ label: "Browse…", description: "Chọn thư mục hoặc plugin.json trên máy local", browse: true });

        const picked = await vscode.window.showQuickPick(choices, {
            title: "Select Extension Root",
            placeHolder: "Chọn thư mục extension, plugin.json, hoặc file trong extension",
        });
        if (!picked) {
            return undefined;
        }
        if (picked.uri) {
            return picked.uri;
        }
        const browsed = await vscode.window.showOpenDialog({
            canSelectFiles: true,
            canSelectFolders: true,
            canSelectMany: false,
            openLabel: "Chọn extension",
        });
        return browsed?.[0];
    }

    private async pickSavedProfile(manifest: ExtensionManifest): Promise<SavedRunProfile | undefined> {
        const profiles = this.profiles.list(manifest.packageId);
        if (profiles.length === 0) {
            vscode.window.showInformationMessage("Chưa có saved profile cho extension này. Hãy chạy Run Current execute rồi lưu profile.");
            return undefined;
        }
        const choices = profiles.map((entry) => ({
            label: entry.name,
            description: describeRunProfile(entry.profile),
            detail: entry.packageId ? `packageId: ${entry.packageId}` : "Profile dùng chung",
            entry,
        }));
        const picked = await vscode.window.showQuickPick(choices, {
            title: "FreeBook Ext Debug: Run Saved Profile",
            placeHolder: "Chọn profile lưu trong workspaceState",
        });
        return picked?.entry;
    }

    private async offerSaveProfile(manifest: ExtensionManifest, profile: RunProfile): Promise<void> {
        const action = await vscode.window.showInformationMessage("Lưu input này thành profile?", "Lưu", "Không");
        if (action !== "Lưu") {
            return;
        }
        const name = await vscode.window.showInputBox({
            title: "FreeBook Ext Debug: Save Profile",
            prompt: "Tên profile",
            validateInput: (value) => value.trim() ? undefined : "Không được để trống.",
        });
        if (!name) {
            return;
        }
        await this.profiles.save(name, profile, { packageId: manifest.packageId });
        vscode.window.showInformationMessage(`Đã lưu profile '${name.trim()}'.`);
    }

    private async rememberManifest(manifest: ExtensionManifest): Promise<void> {
        this.selectedSidebarRootId = this.sidebarRootId(manifest);
        await this.context.workspaceState.update(SELECTED_ROOT_STORAGE_KEY, manifest.root.toString());
    }

    private ensureDesktopTrusted(): boolean {
        if (vscode.env.uiKind !== vscode.UIKind.Desktop) {
            void vscode.window.showErrorMessage("FreeBook Ext Debug chỉ hỗ trợ VS Code Desktop local.");
            return false;
        }
        if (!vscode.workspace.isTrusted) {
            void vscode.window.showErrorMessage("Hãy trust workspace trước khi dùng FreeBook Ext Debug.");
            return false;
        }
        return true;
    }

    private ensureLocalUri(uri: vscode.Uri): void {
        if (uri.scheme !== "file") {
            throw new ExtensionWorkspaceError("manifest-not-found", "MVP chỉ hỗ trợ workspace/file local, không hỗ trợ WSL, SSH hoặc Codespaces.");
        }
    }

    private ensureNoActiveRun(): boolean {
        if (this.activeRun || this.isStartingRun) {
            void vscode.window.showWarningMessage("Đang có run hoạt động. Hãy Cancel Current Run hoặc chờ kết quả.");
            return false;
        }
        return true;
    }

    private secretKey(endpoint: string): string {
        return `${SECRET_KEY_PREFIX}${createHash("sha256").update(endpoint).digest("hex")}`;
    }

    private async runCommand(action: () => Promise<void>): Promise<void> {
        try {
            await action();
        } catch (error) {
            if (error instanceof vscode.CancellationError) {
                return;
            }
            const message = redactSecrets(messageFor(error), [...this.sessionsByEndpoint.values()]);
            this.trace.appendNotice(`Error: ${message}`);
            void vscode.window.showErrorMessage(`FreeBook Ext Debug: ${message}`);
            void this.refreshSidebar();
        }
    }

    private asSafeError(error: unknown, secrets: readonly (string | undefined)[]): Error {
        const source = error instanceof Error ? error : new Error(String(error));
        return new Error(redactSecrets(source.message, secrets));
    }
}

function makeInvocation(profile: RunProfile, resolved: ResolvedRunProfile): DebugInvocation {
    switch (profile.kind) {
        case "search":
            return { kind: "search", query: profile.query, page: String(profile.page) };
        case "detail":
        case "toc":
        case "chap":
        case "page":
            return {
                kind: profile.kind,
                url: profile.url,
                ...(profile.host?.trim() ? { host: profile.host.trim() } : {}),
            };
        case "genre":
        case "home":
            return { kind: profile.kind };
        case "custom":
            return {
                kind: "custom",
                scriptPath: resolved.script.relativePath,
                input: profile.input,
                page: profile.page,
                ...(profile.pageUrl?.trim() ? { pageUrl: profile.pageUrl.trim() } : {}),
            };
        case "draftScript":
            return {
                kind: "script",
                scriptPath: resolved.script.relativePath,
                arguments: resolved.arguments as readonly import("./protocol").JsonValue[],
            };
    }
}

/** These paths use an app-specific TTS runtime, not the debug runner contract. */
function isUnsupportedDebugScript(scriptKey: string | undefined): boolean {
    return scriptKey === "voice" || scriptKey === "tts";
}

function unsupportedDebugScriptReason(scriptKey: string | undefined): string {
    if (scriptKey === "voice") {
        return "voice dùng execute([]) riêng của TTS; protocol debug v1 chưa có profile tương ứng.";
    }
    if (scriptKey === "tts") {
        return "tts dùng ExtTTSRuntime riêng của app; protocol debug v1 chưa hỗ trợ.";
    }
    return "Script này chưa được protocol debug v1 hỗ trợ.";
}

/** Labels are based on the app's execute contracts, never inferred from JS text. */
function sidebarFieldsFor(script: ResolvedExtensionScript): readonly SidebarField[] {
    if (isUnsupportedDebugScript(script.manifestKey)) {
        return [];
    }
    switch (script.manifestKey) {
        case "search":
            return [
                {
                    id: "query",
                    label: "Query",
                    kind: "text",
                    placeholder: "Từ khóa tìm kiếm",
                    hint: "App gọi execute(query, String(page)).",
                    required: true,
                },
                {
                    id: "page",
                    label: "Page",
                    kind: "number",
                    value: "1",
                    min: 1,
                    required: true,
                },
            ];
        case "detail":
        case "toc":
        case "chap":
        case "page":
            return [
                {
                    id: "url",
                    label: "URL hoặc path",
                    kind: "url",
                    placeholder: "/truyen/chuong-1 hoặc https://example.com/...",
                    hint: "Giữ nguyên URL/path; FreeBook App tự resolve theo host.",
                    required: true,
                },
                {
                    id: "host",
                    label: "Host (tùy chọn)",
                    kind: "url",
                    placeholder: "https://example.com",
                },
            ];
        case "genre":
        case "home":
            return [];
        default:
            if (!script.manifestKey) {
                return [
                    {
                        id: "arguments",
                        label: "JSON arguments",
                        kind: "json",
                        value: "[]",
                        placeholder: "[\"input\", 1]",
                        hint: "Script không khai trong plugin.json; chỉ stage Draft và truyền mảng này nguyên vẹn vào execute(...).",
                        required: true,
                        rows: 4,
                    },
                ];
            }
            return [
                {
                    id: "input",
                    label: "Input",
                    kind: "textarea",
                    placeholder: "{0} được app thay bằng page",
                    hint: "App gọi execute(input thay {0}, pageUrl).",
                    required: true,
                    rows: 3,
                },
                {
                    id: "page",
                    label: "Page",
                    kind: "number",
                    value: "1",
                    min: 1,
                    required: true,
                },
                {
                    id: "pageUrl",
                    label: "pageUrl (tùy chọn, page > 1)",
                    kind: "url",
                    placeholder: "https://example.com/page/2",
                },
            ];
    }
}

function profileFromSidebar(
    script: ResolvedExtensionScript,
    values: Readonly<Record<string, string>>,
): RunProfile {
    if (isUnsupportedDebugScript(script.manifestKey)) {
        throw new RunProfileError(unsupportedDebugScriptReason(script.manifestKey));
    }
    switch (script.manifestKey) {
        case "search":
            return {
                kind: "search",
                query: requiredSidebarValue(values, "query", "Query"),
                page: sidebarPage(values.page),
            };
        case "detail":
        case "toc":
        case "chap":
        case "page": {
            const host = optionalSidebarValue(values, "host");
            return {
                kind: script.manifestKey,
                url: requiredSidebarValue(values, "url", "URL hoặc path"),
                ...(host ? { host } : {}),
            };
        }
        case "genre":
        case "home":
            return { kind: script.manifestKey };
        default:
            if (!script.manifestKey) {
                const rawArguments = optionalSidebarValue(values, "arguments") ?? "[]";
                let argumentsValue: unknown;
                try {
                    argumentsValue = JSON.parse(rawArguments);
                } catch {
                    throw new RunProfileError("JSON arguments phải là một mảng JSON hợp lệ.");
                }
                if (!Array.isArray(argumentsValue) || !argumentsValue.every(isJsonValue)) {
                    throw new RunProfileError("JSON arguments phải là một mảng JSON hợp lệ.");
                }
                return {
                    kind: "draftScript",
                    scriptPath: script.relativePath,
                    arguments: argumentsValue,
                };
            }

            const pageUrl = optionalSidebarValue(values, "pageUrl");
            return {
                kind: "custom",
                scriptPath: script.relativePath,
                input: requiredSidebarValue(values, "input", "Input"),
                page: sidebarPage(values.page),
                ...(pageUrl ? { pageUrl } : {}),
            };
    }
}

function requiredSidebarValue(
    values: Readonly<Record<string, string>>,
    key: string,
    label: string,
): string {
    const value = optionalSidebarValue(values, key);
    if (!value) {
        throw new RunProfileError(`${label} không được để trống.`);
    }
    return value;
}

function optionalSidebarValue(values: Readonly<Record<string, string>>, key: string): string | undefined {
    const value = values[key];
    if (typeof value !== "string" || value.length > 65_536) {
        return undefined;
    }
    const normalized = value.trim();
    return normalized || undefined;
}

function sidebarPage(value: string | undefined): number {
    const normalized = value?.trim() ?? "";
    if (!/^\d+$/.test(normalized)) {
        throw new RunProfileError("Page phải là số nguyên dương.");
    }
    const page = Number(normalized);
    if (!Number.isSafeInteger(page) || page < 1) {
        throw new RunProfileError("Page phải là số nguyên dương.");
    }
    return page;
}

function isTerminalEvent(event: DebugTraceEvent): boolean {
    return event.kind === "result"
        || event.kind === "compile_error"
        || event.kind === "runtime_error"
        || event.kind === "cancelled"
        || event.kind === "timed_out";
}

function messageFor(error: unknown): string {
    if (error instanceof RunProfileError || error instanceof ExtensionWorkspaceError || error instanceof DebugTransportError) {
        return error.message;
    }
    return error instanceof Error ? error.message : String(error);
}
