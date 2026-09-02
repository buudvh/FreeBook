import * as vscode from 'vscode';
import { ExtDebugClient } from './client';
import {
  buildDraftBundle,
  discoverWorkspaceExtensions,
  readExtensionFromFolder,
  stageDraft,
  WorkspaceExtensionInfo
} from './draft';
import { DebugEvent, ExtensionInfo, ServerTarget, parseTarget } from './protocol';
import { SidebarViewProvider, SidebarState } from './sidebarView';

/**
 * Client VS Code của FreeBook debug server kèm Sidebar UI & Quét thư mục Extension.
 */

let client: ExtDebugClient | undefined;
let target: ServerTarget | undefined;
let output: vscode.OutputChannel;
let diagnostics: vscode.DiagnosticCollection;
let statusBar: vscode.StatusBarItem;
let sidebarProvider: SidebarViewProvider | undefined;

let appExtensions: ExtensionInfo[] = [];
let workspaceExtensions: WorkspaceExtensionInfo[] = [];
let selectedWorkspaceExt: WorkspaceExtensionInfo | undefined;
let selectedAppExt: ExtensionInfo | undefined;

let currentRunId: string | undefined;
let stagedRevisions = new Map<string, string>();
let installedRevision: string | undefined;
const TARGET_KEY = 'freebook.extdebug.target';

export function activate(context: vscode.ExtensionContext): void {
  output = vscode.window.createOutputChannel('FreeBook ExtDebug');
  diagnostics = vscode.languages.createDiagnosticCollection('freebook-extdebug');
  statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  statusBar.command = 'freebook.extdebug.openTrace';
  updateStatusBar('chưa kết nối');
  statusBar.show();

  const remembered = context.workspaceState.get<string>(TARGET_KEY) ?? 'ws://192.168.88.146:17772';

  const initialState: SidebarState = {
    isConnected: false,
    targetAddress: remembered,
    appExtensions: [],
    workspaceExtensions: [],
    selectedEntrypoint: 'search',
    mode: 'draft',
    isRunning: false
  };

  sidebarProvider = new SidebarViewProvider(context.extensionUri, initialState, {
    onConnect: async (address) => {
      await connectWithAddress(address, context);
    },
    onDisconnect: async () => {
      await disconnect();
    },
    onBrowseFolder: async () => {
      await browseExtensionFolder();
    },
    onRefreshWorkspace: async () => {
      await refreshWorkspaceExtensions();
    },
    onSelectExtension: (selection) => {
      if (selection.type === 'workspace') {
        const found = workspaceExtensions.find(
          (e) => e.folderUri.toString() === selection.folderUriStr || e.folderPath === selection.folderUriStr
        );
        if (found) {
          selectedWorkspaceExt = found;
          selectedAppExt = undefined;
          updateStatusBar(`đã chọn ${found.packageId} [${found.folderName}]`);
          syncSidebar({
            selectedKey: 'ws:' + (found.folderUri ? (found.folderUri.path || found.folderUri.toString()) : found.folderPath),
            selectedPackageId: found.packageId,
            mode: 'draft'
          });
        }
      } else {
        const found = appExtensions.find((e) => e.packageId === selection.packageId);
        if (found) {
          selectedAppExt = found;
          selectedWorkspaceExt = undefined;
          updateStatusBar(`đã chọn ${found.packageId}`);
          syncSidebar({
            selectedKey: 'app:' + found.packageId,
            selectedPackageId: found.packageId,
            mode: 'installed'
          });
        }
      }
    },
    onRun: async (entrypoint, mode, params) => {
      await startRun(entrypoint, mode, params);
    },
    onCancelRun: async () => {
      await cancelRun();
    },
    onStageDraft: async () => {
      await stageWorkspaceDraft();
    },
    onInstallDraft: async () => {
      await installStagedDraft();
    },
    onRollback: async () => {
      await rollbackInstalled();
    },
    onOpenTrace: () => {
      output.show(true);
    }
  });

  context.subscriptions.push(
    output,
    diagnostics,
    statusBar,
    vscode.window.registerWebviewViewProvider(SidebarViewProvider.viewType, sidebarProvider)
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('freebook.extdebug.connect', () => connect(context)),
    vscode.commands.registerCommand('freebook.extdebug.selectExtension', selectExtensionInteractive),
    vscode.commands.registerCommand('freebook.extdebug.browseFolder', browseExtensionFolder),
    vscode.commands.registerCommand('freebook.extdebug.refreshWorkspace', refreshWorkspaceExtensions),
    vscode.commands.registerCommand('freebook.extdebug.runCurrent', runCurrentDocument),
    vscode.commands.registerCommand('freebook.extdebug.runScript', () => runInteractive('installed')),
    vscode.commands.registerCommand('freebook.extdebug.runProfile', () => runInteractive('draft')),
    vscode.commands.registerCommand('freebook.extdebug.stageDraft', stageWorkspaceDraft),
    vscode.commands.registerCommand('freebook.extdebug.installDraft', installStagedDraft),
    vscode.commands.registerCommand('freebook.extdebug.rollback', rollbackInstalled),
    vscode.commands.registerCommand('freebook.extdebug.cancelRun', cancelRun),
    vscode.commands.registerCommand('freebook.extdebug.openTrace', () => output.show(true))
  );

  // Quét workspace khi kích hoạt
  refreshWorkspaceExtensions();

  // Watcher khi tạo/xoá plugin.json
  const watcher = vscode.workspace.createFileSystemWatcher('**/plugin.json');
  watcher.onDidCreate(() => refreshWorkspaceExtensions());
  watcher.onDidDelete(() => refreshWorkspaceExtensions());
  watcher.onDidChange(() => refreshWorkspaceExtensions());
  context.subscriptions.push(watcher);

  // Tự động nhận diện extension khi mở file
  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor((editor) => {
      if (editor && editor.document.languageId === 'javascript') {
        autoDetectExtensionFromDocument(editor.document);
      }
    })
  );
}

export async function deactivate(): Promise<void> {
  await disconnect();
}

// MARK: - Quét & Chọn Folder Extension

async function refreshWorkspaceExtensions(): Promise<void> {
  try {
    workspaceExtensions = await discoverWorkspaceExtensions();
    if (workspaceExtensions.length > 0 && !selectedWorkspaceExt && !selectedAppExt) {
      selectedWorkspaceExt = workspaceExtensions[0];
    }
    syncSidebar({
      workspaceExtensions,
      selectedKey: selectedWorkspaceExt
        ? 'ws:' + (selectedWorkspaceExt.folderUri ? (selectedWorkspaceExt.folderUri.path || selectedWorkspaceExt.folderUri.toString()) : selectedWorkspaceExt.folderPath)
        : undefined,
      selectedPackageId: getActivePackageId()
    });
  } catch (error) {
    log(`Lỗi quét workspace extensions: ${describe(error)}`);
  }
}

async function browseExtensionFolder(): Promise<void> {
  const folders = await vscode.window.showOpenDialog({
    canSelectFiles: false,
    canSelectFolders: true,
    canSelectMany: false,
    title: 'Chọn thư mục Extension (chứa plugin.json)'
  });
  if (!folders || folders.length === 0) {
    return;
  }
  const folderUri = folders[0];
  const info = await readExtensionFromFolder(folderUri);
  if (!info) {
    vscode.window.showErrorMessage(`Thư mục '${folderUri.fsPath}' không chứa plugin.json hợp lệ.`);
    return;
  }

  // Thêm vào danh sách nếu chưa có
  if (!workspaceExtensions.some((e) => e.folderUri.toString() === info.folderUri.toString())) {
    workspaceExtensions.unshift(info);
  }
  selectedWorkspaceExt = info;
  selectedAppExt = undefined;
  updateStatusBar(`đã chọn ${info.packageId} [${info.folderName}]`);
  syncSidebar({
    workspaceExtensions,
    selectedKey: 'ws:' + (info.folderUri ? (info.folderUri.path || info.folderUri.toString()) : info.folderPath),
    selectedPackageId: info.packageId,
    mode: 'draft'
  });
  vscode.window.showInformationMessage(`Đã chọn extension '${info.name}' (${info.packageId}) từ ${info.folderPath}`);
}

function autoDetectExtensionFromDocument(document: vscode.TextDocument): void {
  const docPath = document.uri.fsPath;
  for (const ext of workspaceExtensions) {
    if (docPath.startsWith(ext.folderPath) || docPath.startsWith(ext.folderUri.fsPath)) {
      if (selectedWorkspaceExt?.folderUri.toString() !== ext.folderUri.toString()) {
        selectedWorkspaceExt = ext;
        selectedAppExt = undefined;
        updateStatusBar(`đã chọn ${ext.packageId} [${ext.folderName}]`);
        syncSidebar({
          selectedKey: 'ws:' + (ext.folderUri ? (ext.folderUri.path || ext.folderUri.toString()) : ext.folderPath),
          selectedPackageId: ext.packageId,
          mode: 'draft'
        });
      }
      break;
    }
  }
}

function getActivePackageId(): string | undefined {
  return selectedWorkspaceExt?.packageId || selectedAppExt?.packageId;
}

function getActiveFolderUri(): vscode.Uri | undefined {
  if (selectedWorkspaceExt) {
    return selectedWorkspaceExt.folderUri;
  }
  return vscode.workspace.workspaceFolders?.[0]?.uri;
}

// MARK: - Kết nối

async function connect(context: vscode.ExtensionContext): Promise<void> {
  if (!vscode.workspace.isTrusted) {
    vscode.window.showErrorMessage('FreeBook ExtDebug cần workspace tin cậy.');
    return;
  }

  const remembered = context.workspaceState.get<string>(TARGET_KEY) ?? 'ws://192.168.88.146:17772';
  const raw = await vscode.window.showInputBox({
    title: 'Địa chỉ debug server hiện trên app',
    prompt: 'Dán chuỗi ws://ip:port trong Cài Đặt → Nhà Phát Triển → Debug Server (LAN)',
    value: remembered,
    ignoreFocusOut: true
  });
  if (!raw) {
    return;
  }
  await connectWithAddress(raw, context);
}

async function connectWithAddress(raw: string, context: vscode.ExtensionContext): Promise<void> {
  const parsed = parseTarget(raw);
  if (!parsed) {
    vscode.window.showErrorMessage('Địa chỉ không đúng dạng. Ví dụ: ws://192.168.88.146:17772');
    return;
  }

  target = parsed;
  const address = `ws://${parsed.host}:${parsed.port}`;
  await context.workspaceState.update(TARGET_KEY, address);

  client = new ExtDebugClient(handleEvent, onClosed);
  try {
    await client.connect(parsed);
    const hello = await client.request('hello', { clientName: clientName() });
    log(`hello: app ${hello.appVersion ?? '?'} · contract v${hello.contractVersion ?? '?'}`);
    updateStatusBar('đã kết nối');
    await client.subscribeEvents();
    await fetchAppExtensions();

    syncSidebar({
      isConnected: true,
      targetAddress: address,
      clientName: clientName(),
      appVersion: hello.appVersion
    });
    vscode.window.showInformationMessage(`FreeBook: Đã kết nối ${address}`);
  } catch (error) {
    updateStatusBar('lỗi kết nối');
    syncSidebar({ isConnected: false });
    vscode.window.showErrorMessage(`Không kết nối được: ${describe(error)}`);
  }
}

async function disconnect(): Promise<void> {
  await client?.disconnect();
  client = undefined;
  target = undefined;
  updateStatusBar('chưa kết nối');
  syncSidebar({ isConnected: false });
}

function clientName(): string {
  const folder = vscode.workspace.workspaceFolders?.[0]?.name ?? 'workspace';
  return `VS Code · ${folder}`;
}

function onClosed(reason: string): void {
  updateStatusBar('mất kết nối');
  log(`kết nối đóng: ${reason}`);
  currentRunId = undefined;
  syncSidebar({ isConnected: false, isRunning: false, currentRunId: undefined });
}

// MARK: - App Extensions & Interactive Pick

async function fetchAppExtensions(): Promise<void> {
  if (!client?.isConnected) {
    return;
  }
  try {
    const payload = await client.request('extensions.list');
    appExtensions = payload.extensions ?? [];
    syncSidebar({
      appExtensions,
      selectedPackageId: getActivePackageId()
    });
  } catch (error) {
    log(`lỗi fetch app extensions: ${describe(error)}`);
  }
}

async function selectExtensionInteractive(): Promise<void> {
  await refreshWorkspaceExtensions();
  if (client?.isConnected) {
    await fetchAppExtensions();
  }

  interface QuickPickExtItem extends vscode.QuickPickItem {
    extType: 'workspace' | 'app';
    pkgId: string;
    folderUri?: vscode.Uri;
  }

  const items: QuickPickExtItem[] = [];

  for (const ext of workspaceExtensions) {
    items.push({
      label: `$(folder) ${ext.name}`,
      description: `${ext.packageId} · v${ext.version}`,
      detail: `Thư mục: ${ext.folderPath} · scripts: ${ext.scripts.join(', ')}`,
      extType: 'workspace',
      pkgId: ext.packageId,
      folderUri: ext.folderUri
    });
  }

  for (const ext of appExtensions) {
    items.push({
      label: `$(device-mobile) ${ext.name} (Trên App)`,
      description: `${ext.packageId} · v${ext.version}`,
      detail: `Đã cài trên app · scripts: ${ext.scripts.join(', ')}`,
      extType: 'app',
      pkgId: ext.packageId
    });
  }

  if (items.length === 0) {
    vscode.window.showWarningMessage('Không tìm thấy extension nào trong thư mục làm việc hoặc trên app.');
    return;
  }

  const picked = await vscode.window.showQuickPick(items, { title: 'Chọn extension để debug' });
  if (!picked) {
    return;
  }

  if (picked.extType === 'workspace') {
    const found = workspaceExtensions.find((e) => e.packageId === picked.pkgId && e.folderUri === picked.folderUri);
    if (found) {
      selectedWorkspaceExt = found;
      selectedAppExt = undefined;
      updateStatusBar(`đã chọn ${found.packageId} [${found.folderName}]`);
      syncSidebar({
        selectedKey: 'ws:' + (found.folderUri ? (found.folderUri.path || found.folderUri.toString()) : found.folderPath),
        selectedPackageId: found.packageId,
        mode: 'draft'
      });
    }
  } else {
    const found = appExtensions.find((e) => e.packageId === picked.pkgId);
    if (found) {
      selectedAppExt = found;
      selectedWorkspaceExt = undefined;
      updateStatusBar(`đã chọn ${found.packageId}`);
      syncSidebar({
        selectedKey: 'app:' + found.packageId,
        selectedPackageId: found.packageId,
        mode: 'installed'
      });
    }
  }
}

// MARK: - Execution

async function runCurrentDocument(): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  const document = vscode.window.activeTextEditor?.document;
  if (!document || document.languageId !== 'javascript') {
    vscode.window.showWarningMessage('Hãy mở một file JavaScript của extension.');
    return;
  }
  const fileName = document.fileName.split(/[\\/]/).pop() ?? '';
  const key = fileName.replace(/\.js$/, '');
  const scripts = selectedWorkspaceExt?.scripts || selectedAppExt?.scripts || [];

  if (scripts.length > 0 && !scripts.includes(key)) {
    // Nếu file chưa có trong scripts, vẫn cho phép chạy dạng custom
    await startRun('custom', 'draft', { scriptFileName: fileName });
    return;
  }

  const mode = selectedWorkspaceExt ? 'draft' : 'installed';
  await startRun(key, mode);
}

async function runInteractive(mode: 'installed' | 'draft'): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  const pkgId = getActivePackageId()!;
  if (mode === 'draft' && !stagedRevisions.get(pkgId)) {
    vscode.window.showWarningMessage('Chưa stage bản nháp nào. Chạy “Stage Workspace Draft” trước.');
    return;
  }
  const entrypoint = await vscode.window.showQuickPick(
    ['search', 'detail', 'toc', 'chap', 'genre', 'home', 'custom'],
    { title: `Entrypoint (${mode})` }
  );
  if (!entrypoint) {
    return;
  }

  const params: Record<string, string> = {};
  const page = vscode.workspace.getConfiguration('freebook.extdebug').get<number>('defaultPage', 1);
  if (entrypoint === 'search') {
    const keyword = await vscode.window.showInputBox({ title: 'keyword' });
    if (keyword === undefined) {
      return;
    }
    params.keyword = keyword;
    params.page = String(page);
  } else if (['detail', 'toc', 'chap'].includes(entrypoint)) {
    const url = await vscode.window.showInputBox({ title: 'url' });
    if (!url) {
      return;
    }
    params.url = url;
  } else if (entrypoint === 'custom') {
    const fileName = await vscode.window.showInputBox({ title: 'tên file script (vd: list.js)' });
    if (!fileName) {
      return;
    }
    const input = await vscode.window.showInputBox({ title: 'input (dùng {0} cho số trang)' });
    params.scriptFileName = fileName;
    params.input = input ?? '';
    params.page = String(page);
  }

  await startRun(entrypoint, mode, params);
}

async function startRun(
  entrypoint: string,
  mode: 'installed' | 'draft',
  params: Record<string, string> = {}
): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }

  const pkgId = getActivePackageId()!;
  const payload: Record<string, unknown> = {
    packageId: pkgId,
    entrypoint,
    sourceMode: mode
  };
  if (mode === 'draft') {
    const rev = stagedRevisions.get(pkgId);
    if (!rev) {
      vscode.window.showWarningMessage(`Chưa stage bản nháp nào cho '${pkgId}'. Hãy bấm 'Stage Nháp' trước.`);
      return;
    }
    payload.sourceRevision = rev;
  }

  if (params.keyword !== undefined) payload.keyword = params.keyword;
  if (params.url !== undefined) payload.url = params.url;
  if (params.page !== undefined) payload.page = parseInt(params.page, 10) || 1;
  if (params.scriptFileName !== undefined) payload.scriptFileName = params.scriptFileName;
  if (params.input !== undefined) payload.input = params.input;

  diagnostics.clear();
  output.show(true);
  try {
    syncSidebar({ isRunning: true });
    const reply = await client!.request('run.start', payload);
    currentRunId = reply.runId;
    updateStatusBar(`đang chạy ${entrypoint}`);
    log(`--- run ${currentRunId} · ${entrypoint} · ${mode} ---`);
    syncSidebar({ isRunning: true, currentRunId });
  } catch (error) {
    syncSidebar({ isRunning: false, currentRunId: undefined });
    vscode.window.showErrorMessage(`run.start thất bại: ${describe(error)}`);
  }
}

async function cancelRun(): Promise<void> {
  if (!requireClient() || !currentRunId) {
    return;
  }
  await client!.request('run.cancel', { runId: currentRunId });
  log(`đã yêu cầu huỷ run ${currentRunId}`);
  syncSidebar({ isRunning: false, currentRunId: undefined });
}

// MARK: - Draft & Install

async function stageWorkspaceDraft(): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  const folderUri = getActiveFolderUri();
  if (!folderUri) {
    vscode.window.showErrorMessage('Không tìm thấy thư mục extension hợp lệ.');
    return;
  }
  const pkgId = getActivePackageId()!;

  await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: `Stage bản nháp [${pkgId}] lên app` },
    async (progress) => {
      try {
        const bundle = await buildDraftBundle(folderUri, pkgId);
        progress.report({ message: `${bundle.manifest.entries.length} file` });
        const revision = await stageDraft(client!, bundle, (message) => log(`draft: ${message}`));
        stagedRevisions.set(pkgId, revision);
        syncSidebar({ stagedRevision: revision });
        vscode.window.showInformationMessage(`Bản nháp ${revision} của '${pkgId}' đã được app validate.`);
      } catch (error) {
        vscode.window.showErrorMessage(`Stage thất bại: ${describe(error)}`);
      }
    }
  );
}

async function installStagedDraft(): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  const pkgId = getActivePackageId()!;
  const revision = stagedRevisions.get(pkgId);
  if (!revision) {
    vscode.window.showWarningMessage(`Chưa stage bản nháp nào cho '${pkgId}'.`);
    return;
  }
  log('draft.install: chờ bạn xác nhận trên thiết bị…');
  try {
    const reply = await client!.request(
      'draft.install',
      { packageId: pkgId, sourceRevision: revision },
      10 * 60 * 1000
    );
    installedRevision = revision;
    syncSidebar({ installedRevision: revision });
    vscode.window.showInformationMessage(reply.message ?? `Đã cài bản nháp cho '${pkgId}'.`);
  } catch (error) {
    vscode.window.showErrorMessage(`draft.install thất bại: ${describe(error)}`);
  }
}

async function rollbackInstalled(): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  const pkgId = getActivePackageId()!;
  log('draft.rollback: chờ bạn xác nhận trên thiết bị…');
  try {
    await client!.request('draft.rollback', { packageId: pkgId }, 10 * 60 * 1000);
    installedRevision = undefined;
    syncSidebar({ installedRevision: undefined });
    vscode.window.showInformationMessage(`Đã rollback '${pkgId}' về bản trước lần cài gần nhất.`);
  } catch (error) {
    vscode.window.showErrorMessage(`draft.rollback thất bại: ${describe(error)}`);
  }
}

// MARK: - Trace & Events

function handleEvent(event: DebugEvent): void {
  const location = event.location ? ` ${event.location.script}:${event.location.line ?? '?'}` : '';
  const details = Object.entries(event.details)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join(' ');
  if (event.category === 'responseValidated') {
    let formatted = event.message;
    try {
      const parsed = JSON.parse(event.message);
      formatted = JSON.stringify(parsed, null, 2);
    } catch {}
    log(`✅ [Response.success]${details ? ' (' + details + ')' : ''}:\n${formatted}`);
  } else if (event.category === 'responseError') {
    log(`❌ [Response.error]${details ? ' (' + details + ')' : ''}: ${event.message}`);
  } else {
    log(`[${event.category}]${location} ${event.message}${details ? '  ' + details : ''}`);
  }

  sidebarProvider?.appendTraceEvent(event);

  if (
    event.category === 'runFinished' ||
    event.category === 'cancelled' ||
    event.category === 'compileFailed' ||
    event.category === 'responseValidated' ||
    event.category === 'responseError'
  ) {
    syncSidebar({ isRunning: false, currentRunId: undefined });
    updateStatusBar('đã kết nối');
  }

  if (event.level !== 'error' || !event.location) {
    return;
  }
  applyDiagnostic(event);
}

function applyDiagnostic(event: DebugEvent): void {
  const folder = getActiveFolderUri();
  if (!folder || !event.location) {
    return;
  }
  const pkgId = getActivePackageId();
  const staged = pkgId ? stagedRevisions.get(pkgId) : undefined;
  const knownRevisions = [staged, installedRevision].filter(Boolean);
  if (knownRevisions.length > 0 && !knownRevisions.includes(event.sourceRevision)) {
    log(`  (stale) revision ${event.sourceRevision} không khớp bản đang mở — không gắn diagnostic`);
    return;
  }

  const uri = vscode.Uri.joinPath(folder, event.location.script);
  const line = Math.max(0, (event.location.line ?? 1) - 1);
  const column = Math.max(0, (event.location.column ?? 1) - 1);
  const range = new vscode.Range(line, column, line, column + 1);
  const diagnostic = new vscode.Diagnostic(range, event.message, vscode.DiagnosticSeverity.Error);
  diagnostic.source = 'FreeBook';
  diagnostic.code = event.category;
  const existing = diagnostics.get(uri) ?? [];
  diagnostics.set(uri, [...existing, diagnostic]);
}

// MARK: - Helpers

function requireClient(): boolean {
  if (!client?.isConnected || !target) {
    vscode.window.showWarningMessage('Chưa kết nối. Bấm Kết Nối trong Sidebar hoặc chạy “FreeBook: Connect to App”.');
    return false;
  }
  return true;
}

function requireSelection(): boolean {
  if (!selectedWorkspaceExt && !selectedAppExt) {
    vscode.window.showWarningMessage('Chưa chọn extension. Chọn trong Sidebar hoặc chạy “FreeBook: Select Extension”.');
    return false;
  }
  return true;
}

function updateStatusBar(state: string): void {
  statusBar.text = `$(ladybug) FreeBook: ${state}`;
  statusBar.tooltip = 'FreeBook Extension Debug — bấm để mở trace';
}

function syncSidebar(partial: Partial<SidebarState> = {}): void {
  sidebarProvider?.updateState({
    isConnected: client?.isConnected ?? false,
    targetAddress: target ? `ws://${target.host}:${target.port}` : undefined,
    appExtensions,
    workspaceExtensions,
    selectedPackageId: getActivePackageId(),
    isRunning: Boolean(currentRunId),
    currentRunId,
    ...partial
  });
}

function log(message: string): void {
  const stamp = new Date().toISOString().slice(11, 23);
  output.appendLine(`[${stamp}] ${message}`);
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
