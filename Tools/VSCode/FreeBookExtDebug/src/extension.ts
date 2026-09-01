import * as vscode from 'vscode';
import { ExtDebugClient } from './client';
import { buildDraftBundle, stageDraft } from './draft';
import { DebugEvent, ExtensionInfo, ServerTarget, parseTarget } from './protocol';

/**
 * Client VS Code của FreeBook debug server (Phase 2–4 của plan).
 *
 * Ba ranh giới cố ý:
 * 1. **App là thẩm quyền cuối cùng.** Client validate hình dạng input để báo lỗi sớm, nhưng manifest,
 *    entrypoint và contract do app quyết; client không bao giờ gửi filesystem path tuỳ ý.
 * 2. **Không có bí mật nào để giữ.** Từ 1.3.305 server không ghép nối: client chỉ cần `ws://ip:port`,
 *    và địa chỉ đó nằm trong `workspaceState` chứ không phải `SecretStorage`.
 * 3. **Diagnostic chỉ gắn khi revision còn khớp.** Event của bản cũ chỉ hiện trong trace kèm chữ
 *    `(stale)`, không được đè lỗi của mã hiện tại.
 */

let client: ExtDebugClient | undefined;
let target: ServerTarget | undefined;
let output: vscode.OutputChannel;
let diagnostics: vscode.DiagnosticCollection;
let statusBar: vscode.StatusBarItem;
let selected: ExtensionInfo | undefined;
let currentRunId: string | undefined;
let stagedRevisions = new Map<string, string>();
let installedRevision: string | undefined;

export function activate(context: vscode.ExtensionContext): void {
  output = vscode.window.createOutputChannel('FreeBook ExtDebug');
  diagnostics = vscode.languages.createDiagnosticCollection('freebook-extdebug');
  statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  statusBar.command = 'freebook.extdebug.openTrace';
  updateStatusBar('chưa kết nối');
  statusBar.show();

  context.subscriptions.push(output, diagnostics, statusBar);
  context.subscriptions.push(
    vscode.commands.registerCommand('freebook.extdebug.connect', () => connect(context)),
    vscode.commands.registerCommand('freebook.extdebug.selectExtension', selectExtension),
    vscode.commands.registerCommand('freebook.extdebug.runCurrent', runCurrentDocument),
    vscode.commands.registerCommand('freebook.extdebug.runScript', () => runInteractive('installed')),
    vscode.commands.registerCommand('freebook.extdebug.runProfile', () => runInteractive('draft')),
    vscode.commands.registerCommand('freebook.extdebug.stageDraft', stageWorkspaceDraft),
    vscode.commands.registerCommand('freebook.extdebug.installDraft', installStagedDraft),
    vscode.commands.registerCommand('freebook.extdebug.rollback', rollbackInstalled),
    vscode.commands.registerCommand('freebook.extdebug.cancelRun', cancelRun),
    vscode.commands.registerCommand('freebook.extdebug.openTrace', () => output.show(true))
  );
}

export async function deactivate(): Promise<void> {
  await client?.disconnect();
}

// MARK: - Ket noi

async function connect(context: vscode.ExtensionContext): Promise<void> {
  if (!vscode.workspace.isTrusted) {
    vscode.window.showErrorMessage('FreeBook ExtDebug cần workspace tin cậy.');
    return;
  }

  const remembered = context.workspaceState.get<string>(TARGET_KEY) ?? 'ws://192.168.1.5:17772';
  const raw = await vscode.window.showInputBox({
    title: 'Địa chỉ debug server hiện trên app',
    prompt: 'Dán chuỗi ws://ip:port trong Cài Đặt → Nhà Phát Triển → Debug Server (LAN)',
    value: remembered,
    ignoreFocusOut: true
  });
  if (!raw) {
    return;
  }
  const parsed = parseTarget(raw);
  if (!parsed) {
    vscode.window.showErrorMessage('Địa chỉ không đúng dạng. Ví dụ: ws://192.168.1.5:17772');
    return;
  }

  target = parsed;
  await context.workspaceState.update(TARGET_KEY, `ws://${parsed.host}:${parsed.port}`);

  client = new ExtDebugClient(handleEvent, onClosed);
  try {
    await client.connect(parsed);
    const hello = await client.request('hello', { clientName: clientName() });
    log(`hello: app ${hello.appVersion ?? '?'} · contract v${hello.contractVersion ?? '?'}`);
    updateStatusBar('đã kết nối');
    await client.subscribeEvents();
    await selectExtension();
  } catch (error) {
    updateStatusBar('lỗi kết nối');
    vscode.window.showErrorMessage(`Không kết nối được: ${describe(error)}`);
  }
}

function clientName(): string {
  const folder = vscode.workspace.workspaceFolders?.[0]?.name ?? 'workspace';
  return `VS Code · ${folder}`;
}

function onClosed(reason: string): void {
  updateStatusBar('mất kết nối');
  log(`kết nối đóng: ${reason}`);
  currentRunId = undefined;
}

// MARK: - Chọn extension và chạy

async function selectExtension(): Promise<void> {
  if (!requireClient()) {
    return;
  }
  const payload = await client!.request('extensions.list');
  const items = payload.extensions ?? [];
  if (items.length === 0) {
    vscode.window.showWarningMessage('App không có extension nào đã cài.');
    return;
  }
  const picked = await vscode.window.showQuickPick(
    items.map((item) => ({
      label: item.name,
      description: `${item.packageId} · v${item.version}`,
      detail: `script: ${item.scripts.join(', ')}`,
      item
    })),
    { title: 'Chọn extension để debug' }
  );
  if (!picked) {
    return;
  }
  selected = picked.item;
  updateStatusBar(`đã chọn ${selected.packageId}`);
}

/** Chạy entrypoint suy ra từ **tên file** của document đang mở, nếu nó thuộc manifest đã chọn. */
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
  if (!selected!.scripts.includes(key)) {
    vscode.window.showWarningMessage(
      `'${fileName}' không nằm trong manifest của ${selected!.packageId} (script: ${selected!.scripts.join(', ')}). Dùng “Run Script…” để chọn entrypoint.`
    );
    return;
  }
  await startRun(key, 'installed');
}

async function runInteractive(mode: 'installed' | 'draft'): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  if (mode === 'draft' && !stagedRevisions.get(selected!.packageId)) {
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
  await startRun(entrypoint, mode);
}

async function startRun(entrypoint: string, mode: 'installed' | 'draft'): Promise<void> {
  const payload: Record<string, unknown> = {
    packageId: selected!.packageId,
    entrypoint,
    sourceMode: mode
  };
  if (mode === 'draft') {
    payload.sourceRevision = stagedRevisions.get(selected!.packageId);
  }

  const page = vscode.workspace.getConfiguration('freebook.extdebug').get<number>('defaultPage', 1);
  if (entrypoint === 'search') {
    const keyword = await vscode.window.showInputBox({ title: 'keyword' });
    if (keyword === undefined) {
      return;
    }
    payload.keyword = keyword;
    payload.page = page;
  } else if (['detail', 'toc', 'chap'].includes(entrypoint)) {
    const url = await vscode.window.showInputBox({ title: 'url' });
    if (!url) {
      return;
    }
    payload.url = url;
  } else if (entrypoint === 'custom') {
    const fileName = await vscode.window.showInputBox({ title: 'tên file script (vd: list.js)' });
    if (!fileName) {
      return;
    }
    const input = await vscode.window.showInputBox({ title: 'input (dùng {0} cho số trang)' });
    payload.scriptFileName = fileName;
    payload.input = input ?? '';
    payload.page = page;
  }

  diagnostics.clear();
  output.show(true);
  try {
    const reply = await client!.request('run.start', payload);
    currentRunId = reply.runId;
    updateStatusBar(`đang chạy ${entrypoint}`);
    log(`--- run ${currentRunId} · ${entrypoint} · ${mode} ---`);
  } catch (error) {
    vscode.window.showErrorMessage(`run.start thất bại: ${describe(error)}`);
  }
}

async function cancelRun(): Promise<void> {
  if (!requireClient() || !currentRunId) {
    return;
  }
  await client!.request('run.cancel', { runId: currentRunId });
  log(`đã yêu cầu huỷ run ${currentRunId}`);
}

// MARK: - Draft (Phase 3) và cài đặt (Phase 4)

async function stageWorkspaceDraft(): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) {
    vscode.window.showErrorMessage('Không có workspace folder nào đang mở.');
    return;
  }
  await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: 'Stage bản nháp lên app' },
    async (progress) => {
      try {
        const bundle = await buildDraftBundle(folder.uri, selected!.packageId);
        progress.report({ message: `${bundle.manifest.entries.length} file` });
        const revision = await stageDraft(client!, bundle, (message) => log(`draft: ${message}`));
        stagedRevisions.set(selected!.packageId, revision);
        vscode.window.showInformationMessage(`Bản nháp ${revision} đã được app validate.`);
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
  const revision = stagedRevisions.get(selected!.packageId);
  if (!revision) {
    vscode.window.showWarningMessage('Chưa stage bản nháp nào cho extension này.');
    return;
  }
  log('draft.install: chờ bạn xác nhận trên thiết bị…');
  try {
    // Timeout dài: lệnh này treo cho tới khi người dùng bấm trên máy.
    const reply = await client!.request(
      'draft.install',
      { packageId: selected!.packageId, sourceRevision: revision },
      10 * 60 * 1000
    );
    installedRevision = revision;
    vscode.window.showInformationMessage(reply.message ?? 'Đã cài bản nháp.');
  } catch (error) {
    vscode.window.showErrorMessage(`draft.install thất bại: ${describe(error)}`);
  }
}

async function rollbackInstalled(): Promise<void> {
  if (!requireClient() || !requireSelection()) {
    return;
  }
  log('draft.rollback: chờ bạn xác nhận trên thiết bị…');
  try {
    await client!.request('draft.rollback', { packageId: selected!.packageId }, 10 * 60 * 1000);
    installedRevision = undefined;
    vscode.window.showInformationMessage('Đã rollback về bản trước lần cài gần nhất.');
  } catch (error) {
    vscode.window.showErrorMessage(`draft.rollback thất bại: ${describe(error)}`);
  }
}

// MARK: - Trace và diagnostic

function handleEvent(event: DebugEvent): void {
  const location = event.location ? ` ${event.location.script}:${event.location.line ?? '?'}` : '';
  const details = Object.entries(event.details)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join(' ');
  log(`[${event.category}]${location} ${event.message}${details ? '  ' + details : ''}`);

  if (event.level !== 'error' || !event.location) {
    return;
  }
  applyDiagnostic(event);
}

/**
 * Gắn diagnostic **chỉ khi** revision còn khớp bản đang mở. Không khớp thì chỉ ghi vào trace: event của
 * mã cũ không được đè lỗi của mã hiện tại.
 */
function applyDiagnostic(event: DebugEvent): void {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder || !event.location) {
    return;
  }
  const staged = selected ? stagedRevisions.get(selected.packageId) : undefined;
  const knownRevisions = [staged, installedRevision].filter(Boolean);
  if (knownRevisions.length > 0 && !knownRevisions.includes(event.sourceRevision)) {
    log(`  (stale) revision ${event.sourceRevision} không khớp bản đang mở — không gắn diagnostic`);
    return;
  }

  const uri = vscode.Uri.joinPath(folder.uri, event.location.script);
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
    vscode.window.showWarningMessage('Chưa kết nối. Chạy “FreeBook: Connect to App”.');
    return false;
  }
  return true;
}

function requireSelection(): boolean {
  if (!selected) {
    vscode.window.showWarningMessage('Chưa chọn extension. Chạy “FreeBook: Select Extension”.');
    return false;
  }
  return true;
}

function updateStatusBar(state: string): void {
  statusBar.text = `$(ladybug) FreeBook: ${state}`;
  statusBar.tooltip = 'FreeBook Extension Debug — bấm để mở trace';
}

function log(message: string): void {
  const stamp = new Date().toISOString().slice(11, 23);
  output.appendLine(`[${stamp}] ${message}`);
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
