import * as vscode from 'vscode';
import { DebugEvent, ExtensionInfo } from './protocol';
import { WorkspaceExtensionInfo } from './draft';

export interface SidebarState {
  isConnected: boolean;
  targetAddress: string;
  clientName?: string;
  appVersion?: string;
  appExtensions: ExtensionInfo[];
  workspaceExtensions: WorkspaceExtensionInfo[];
  selectedKey?: string; // "ws:<folderUriStr>" | "app:<packageId>"
  selectedPackageId?: string;
  selectedEntrypoint: string;
  mode: 'installed' | 'draft';
  isRunning: boolean;
  currentRunId?: string;
  stagedRevision?: string;
  installedRevision?: string;
  statusMessage?: string;
}

export interface SidebarActions {
  onConnect: (address: string) => Promise<void>;
  onDisconnect: () => Promise<void>;
  onBrowseFolder: () => Promise<void>;
  onRefreshWorkspace: () => Promise<void>;
  onSelectExtension: (selection: { type: 'workspace' | 'app'; packageId: string; folderUriStr?: string }) => void;
  onRun: (entrypoint: string, mode: 'installed' | 'draft', params: Record<string, string>) => Promise<void>;
  onCancelRun: () => Promise<void>;
  onStageDraft: () => Promise<void>;
  onInstallDraft: () => Promise<void>;
  onRollback: () => Promise<void>;
  onOpenTrace: () => void;
}

export class SidebarViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = 'freebook.extdebug.sidebar';

  private view?: vscode.WebviewView;
  private traceBuffer: string[] = [];
  private readonly maxTraceLines = 100;

  constructor(
    private readonly extensionUri: vscode.Uri,
    private state: SidebarState,
    private readonly actions: SidebarActions
  ) {}

  public resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri]
    };

    webviewView.webview.html = this.getHtml();

    webviewView.webview.onDidReceiveMessage(async (message: any) => {
      try {
        switch (message.type) {
          case 'ready':
            this.sendState();
            this.sendTraceReset();
            break;
          case 'connect':
            await this.actions.onConnect(message.address);
            break;
          case 'disconnect':
            await this.actions.onDisconnect();
            break;
          case 'browseFolder':
            await this.actions.onBrowseFolder();
            break;
          case 'refreshWorkspace':
            await this.actions.onRefreshWorkspace();
            break;
          case 'selectExtension':
            this.actions.onSelectExtension(message.selection);
            break;
          case 'run':
            await this.actions.onRun(message.entrypoint, message.mode, message.params || {});
            break;
          case 'cancelRun':
            await this.actions.onCancelRun();
            break;
          case 'stageDraft':
            await this.actions.onStageDraft();
            break;
          case 'installDraft':
            await this.actions.onInstallDraft();
            break;
          case 'rollback':
            await this.actions.onRollback();
            break;
          case 'openTrace':
            this.actions.onOpenTrace();
            break;
          case 'clearTrace':
            this.traceBuffer = [];
            this.sendTraceReset();
            break;
        }
      } catch (error) {
        vscode.window.showErrorMessage(`Lỗi thao tác: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  public updateState(newState: Partial<SidebarState>): void {
    this.state = { ...this.state, ...newState };
    this.sendState();
  }

  public appendTraceEvent(event: DebugEvent): void {
    const time = new Date(event.timestamp * 1000).toISOString().slice(11, 19);
    const loc = event.location ? ` [${event.location.script}:${event.location.line ?? '?'}]` : '';
    let line: string;
    if (event.category === 'responseValidated') {
      let formatted = event.message;
      try {
        const parsed = JSON.parse(event.message);
        formatted = JSON.stringify(parsed, null, 2);
      } catch {}
      line = `[${time}] ✅ [Response.success]:\n${formatted}`;
    } else if (event.category === 'responseError') {
      line = `[${time}] ❌ [Response.error]: ${event.message}`;
    } else {
      line = `[${time}] [${event.category}]${loc} ${event.message}`;
    }
    this.traceBuffer.push(line);
    if (this.traceBuffer.length > this.maxTraceLines) {
      this.traceBuffer.shift();
    }
    this.view?.webview.postMessage({ type: 'traceAppend', line });
  }

  private sendState(): void {
    this.view?.webview.postMessage({ type: 'state', state: this.state });
  }

  private sendTraceReset(): void {
    this.view?.webview.postMessage({ type: 'traceReset', lines: this.traceBuffer });
  }

  private getHtml(): string {
    return `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>FreeBook Debug</title>
  <style>
    :root {
      --font-family: var(--vscode-font-family, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif);
      --font-size: var(--vscode-font-size, 13px);
    }
    body {
      font-family: var(--font-family);
      font-size: var(--font-size);
      color: var(--vscode-foreground);
      background-color: var(--vscode-sideBar-background);
      padding: 10px;
      margin: 0;
      box-sizing: border-box;
      line-height: 1.4;
    }
    .card {
      background: var(--vscode-editorWidget-background, rgba(255,255,255,0.04));
      border: 1px solid var(--vscode-widget-border, rgba(128,128,128,0.2));
      border-radius: 6px;
      padding: 10px;
      margin-bottom: 12px;
    }
    .card-title {
      font-weight: 600;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: var(--vscode-descriptionForeground);
      margin-bottom: 8px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .status-badge {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      font-size: 11px;
      padding: 2px 6px;
      border-radius: 4px;
      background: var(--vscode-badge-background);
      color: var(--vscode-badge-foreground);
    }
    .status-dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: #888;
    }
    .status-dot.connected { background: #4caf50; box-shadow: 0 0 6px #4caf50; }
    .status-dot.running { background: #2196f3; box-shadow: 0 0 6px #2196f3; }
    .status-dot.error { background: #f44336; }

    .form-group {
      margin-bottom: 8px;
    }
    label {
      display: block;
      font-size: 11px;
      margin-bottom: 3px;
      color: var(--vscode-descriptionForeground);
    }
    input, select, textarea {
      width: 100%;
      box-sizing: border-box;
      background: var(--vscode-input-background);
      color: var(--vscode-input-foreground);
      border: 1px solid var(--vscode-input-border, rgba(128,128,128,0.3));
      border-radius: 3px;
      padding: 5px 7px;
      font-size: var(--font-size);
      font-family: inherit;
      outline: none;
    }
    input:focus, select:focus, textarea:focus {
      border-color: var(--vscode-focusBorder);
    }
    .btn-row {
      display: flex;
      gap: 6px;
      margin-top: 8px;
    }
    button {
      flex: 1;
      background: var(--vscode-button-background);
      color: var(--vscode-button-foreground);
      border: none;
      border-radius: 3px;
      padding: 6px 10px;
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 5px;
    }
    button:hover:not(:disabled) {
      background: var(--vscode-button-hoverBackground);
    }
    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }
    button.secondary {
      background: var(--vscode-button-secondaryBackground);
      color: var(--vscode-button-secondaryForeground);
    }
    button.secondary:hover:not(:disabled) {
      background: var(--vscode-button-secondaryHoverBackground);
    }
    button.danger {
      background: #d32f2f;
      color: #fff;
    }
    button.danger:hover:not(:disabled) {
      background: #b71c1c;
    }
    .btn-icon {
      padding: 5px 8px;
      flex: initial;
    }

    .trace-box {
      background: var(--vscode-terminal-background, #1e1e1e);
      color: var(--vscode-terminal-foreground, #cccccc);
      border: 1px solid var(--vscode-widget-border, rgba(128,128,128,0.2));
      border-radius: 4px;
      padding: 6px;
      font-family: var(--vscode-editor-font-family, Consolas, monospace);
      font-size: 11px;
      height: 160px;
      overflow-y: auto;
      white-space: pre-wrap;
      word-break: break-all;
    }
    .trace-line {
      margin-bottom: 2px;
      line-height: 1.3;
    }
    .trace-line.error { color: #f48771; }
    .trace-line.warn { color: #cca700; }
    .trace-line.info { color: #75beff; }
    .trace-line.success { color: #89d185; }

    .segmented-control {
      display: flex;
      background: var(--vscode-input-background);
      border: 1px solid var(--vscode-input-border, rgba(128,128,128,0.3));
      border-radius: 3px;
      padding: 2px;
      gap: 2px;
    }
    .segment-btn {
      flex: 1;
      padding: 3px;
      font-size: 11px;
      border: none;
      background: transparent;
      color: var(--vscode-foreground);
      border-radius: 2px;
    }
    .segment-btn.active {
      background: var(--vscode-button-background);
      color: var(--vscode-button-foreground);
    }
  </style>
</head>
<body>

  <!-- Card 1: Connection -->
  <div class="card">
    <div class="card-title">
      <span>Kết Nối LAN</span>
      <span id="connBadge" class="status-badge">
        <span id="connDot" class="status-dot"></span>
        <span id="connText">Chưa kết nối</span>
      </span>
    </div>
    <div class="form-group">
      <input type="text" id="targetAddr" placeholder="ws://192.168.1.5:17772" value="ws://192.168.88.146:17772" />
    </div>
    <div class="btn-row">
      <button id="btnConnect" onclick="toggleConnect()">⚡ Kết Nối</button>
    </div>
  </div>

  <!-- Card 2: Extension Selection -->
  <div class="card">
    <div class="card-title">
      <span>Extension Đang Chọn</span>
      <div>
        <a href="#" onclick="refreshWorkspace(); return false;" title="Quét lại workspace" style="font-size:11px; color:var(--vscode-textLink-foreground); margin-right:6px;">🔄 Quét</a>
        <a href="#" onclick="browseFolder(); return false;" title="Duyệt thư mục trên ổ đĩa" style="font-size:11px; color:var(--vscode-textLink-foreground);">📂 Mở...</a>
      </div>
    </div>
    <div class="form-group">
      <select id="extSelect" onchange="onExtensionChanged()">
        <option value="">(Đang tải danh sách...)</option>
      </select>
    </div>
    <div class="btn-row">
      <button class="secondary" onclick="stageDraft()" title="Đẩy các file JS của extension đang chọn lên app làm bản nháp">📦 Stage Nháp</button>
      <button class="secondary" onclick="installDraft()" title="Cài đặt đè bản nháp lên thiết bị">📥 Cài Nháp</button>
      <button class="secondary" onclick="rollback()" title="Khôi phục phiên bản trước đó">↩ Rollback</button>
    </div>
  </div>

  <!-- Card 3: Execution Control -->
  <div class="card">
    <div class="card-title">Chạy Script (Execute)</div>
    
    <div class="form-group">
      <label>Nguồn chạy:</label>
      <div class="segmented-control">
        <button id="modeInstalled" class="segment-btn active" onclick="setMode('installed')">Đã cài (App)</button>
        <button id="modeDraft" class="segment-btn" onclick="setMode('draft')">Bản nháp (Draft)</button>
      </div>
    </div>

    <div class="form-group">
      <label>Entrypoint:</label>
      <select id="entrypointSelect" onchange="onEntrypointChanged()">
        <option value="search">search (Tìm kiếm)</option>
        <option value="detail">detail (Chi tiết truyện)</option>
        <option value="toc">toc (Mục lục chương)</option>
        <option value="chap">chap (Nội dung chương)</option>
        <option value="genre">genre (Thể loại)</option>
        <option value="home">home (Trang chủ)</option>
        <option value="custom">custom (Tự chọn file)</option>
      </select>
    </div>

    <div id="paramKeyword" class="form-group">
      <label>Keyword:</label>
      <input type="text" id="inputKeyword" placeholder="Từ khoá tìm kiếm..." />
    </div>

    <div id="paramUrl" class="form-group" style="display:none;">
      <label>URL:</label>
      <input type="text" id="inputUrl" placeholder="https://..." />
    </div>

    <div id="paramPage" class="form-group">
      <label>Page:</label>
      <input type="number" id="inputPage" value="1" min="1" />
    </div>

    <div id="paramCustomScript" class="form-group" style="display:none;">
      <label>Tên file script:</label>
      <input type="text" id="inputCustomScript" placeholder="list.js" />
    </div>

    <div id="paramCustomInput" class="form-group" style="display:none;">
      <label>Input:</label>
      <input type="text" id="inputCustomInput" placeholder="Tham số truyền vào..." />
    </div>

    <div class="btn-row">
      <button id="btnRun" onclick="runScript()">▶ Run</button>
      <button id="btnCancel" class="danger" onclick="cancelRun()" disabled>⏹ Cancel</button>
    </div>
  </div>

  <!-- Card 4: Live Trace -->
  <div class="card">
    <div class="card-title">
      <span>Live Trace</span>
      <div>
        <a href="#" onclick="openTrace(); return false;" style="font-size:10px; color:var(--vscode-textLink-foreground); margin-right:8px;">Mở Output</a>
        <a href="#" onclick="clearTrace(); return false;" style="font-size:10px; color:var(--vscode-textLink-foreground);">Xoá</a>
      </div>
    </div>
    <div id="traceBox" class="trace-box"></div>
  </div>

  <script>
    const vscode = acquireVsCodeApi();
    let currentState = {
      isConnected: false,
      targetAddress: 'ws://192.168.88.146:17772',
      appExtensions: [],
      workspaceExtensions: [],
      mode: 'installed',
      selectedEntrypoint: 'search',
      isRunning: false
    };

    function toggleConnect() {
      if (currentState.isConnected) {
        vscode.postMessage({ type: 'disconnect' });
      } else {
        const addr = document.getElementById('targetAddr').value.trim();
        vscode.postMessage({ type: 'connect', address: addr });
      }
    }

    function browseFolder() {
      vscode.postMessage({ type: 'browseFolder' });
    }

    function refreshWorkspace() {
      vscode.postMessage({ type: 'refreshWorkspace' });
    }

    function setMode(mode) {
      currentState.mode = mode;
      document.getElementById('modeInstalled').classList.toggle('active', mode === 'installed');
      document.getElementById('modeDraft').classList.toggle('active', mode === 'draft');
    }

    function onExtensionChanged() {
      const val = document.getElementById('extSelect').value;
      if (!val) return;
      if (val.startsWith('ws:')) {
        const folderUriStr = val.substring(3);
        const ext = (currentState.workspaceExtensions || []).find(e => e.folderUri === folderUriStr || e.folderPath === folderUriStr);
        vscode.postMessage({
          type: 'selectExtension',
          selection: { type: 'workspace', packageId: ext ? ext.packageId : '', folderUriStr }
        });
        setMode('draft');
      } else if (val.startsWith('app:')) {
        const packageId = val.substring(4);
        vscode.postMessage({
          type: 'selectExtension',
          selection: { type: 'app', packageId }
        });
      }
    }

    function onEntrypointChanged() {
      const ep = document.getElementById('entrypointSelect').value;
      currentState.selectedEntrypoint = ep;
      
      document.getElementById('paramKeyword').style.display = (ep === 'search') ? 'block' : 'none';
      document.getElementById('paramUrl').style.display = (['detail', 'toc', 'chap'].includes(ep)) ? 'block' : 'none';
      document.getElementById('paramPage').style.display = (['search', 'custom'].includes(ep)) ? 'block' : 'none';
      document.getElementById('paramCustomScript').style.display = (ep === 'custom') ? 'block' : 'none';
      document.getElementById('paramCustomInput').style.display = (ep === 'custom') ? 'block' : 'none';
    }

    function runScript() {
      const ep = document.getElementById('entrypointSelect').value;
      const params = {
        keyword: document.getElementById('inputKeyword').value,
        url: document.getElementById('inputUrl').value,
        page: document.getElementById('inputPage').value,
        scriptFileName: document.getElementById('inputCustomScript').value,
        input: document.getElementById('inputCustomInput').value
      };
      vscode.postMessage({
        type: 'run',
        entrypoint: ep,
        mode: currentState.mode,
        params
      });
    }

    function cancelRun() {
      vscode.postMessage({ type: 'cancelRun' });
    }

    function stageDraft() {
      vscode.postMessage({ type: 'stageDraft' });
    }

    function installDraft() {
      vscode.postMessage({ type: 'installDraft' });
    }

    function rollback() {
      vscode.postMessage({ type: 'rollback' });
    }

    function openTrace() {
      vscode.postMessage({ type: 'openTrace' });
    }

    function clearTrace() {
      vscode.postMessage({ type: 'clearTrace' });
    }

    window.addEventListener('message', (event) => {
      const msg = event.data;
      if (msg.type === 'state') {
        currentState = { ...currentState, ...msg.state };
        updateUI();
      } else if (msg.type === 'traceAppend') {
        appendTraceLine(msg.line);
      } else if (msg.type === 'traceReset') {
        const box = document.getElementById('traceBox');
        box.innerHTML = '';
        for (const l of msg.lines || []) {
          appendTraceLine(l);
        }
      }
    });

    function updateUI() {
      const isConn = currentState.isConnected;
      const dot = document.getElementById('connDot');
      const text = document.getElementById('connText');
      const btn = document.getElementById('btnConnect');

      dot.className = 'status-dot ' + (isConn ? (currentState.isRunning ? 'running' : 'connected') : '');
      text.innerText = isConn ? (currentState.clientName ? 'Đã nối: ' + currentState.clientName : 'Đã kết nối') : 'Chưa kết nối';
      btn.innerText = isConn ? 'Ngắt Kết Nối' : '⚡ Kết Nối';
      btn.className = isConn ? 'secondary' : '';

      if (currentState.targetAddress) {
        document.getElementById('targetAddr').value = currentState.targetAddress;
      }

      const select = document.getElementById('extSelect');
      const prevVal = select.value;
      select.innerHTML = '';

      const wsList = currentState.workspaceExtensions || [];
      const appList = currentState.appExtensions || [];

      if (wsList.length > 0) {
        const groupWs = document.createElement('optgroup');
        groupWs.label = '📁 Thư Mục Trong Máy (Workspace)';
        for (const ext of wsList) {
          const opt = document.createElement('option');
          opt.value = 'ws:' + (ext.folderUri ? (ext.folderUri.path || ext.folderUri.toString()) : ext.folderPath);
          opt.innerText = ext.name + ' (' + ext.packageId + ') v' + ext.version + ' [' + ext.folderName + ']';
          groupWs.appendChild(opt);
        }
        select.appendChild(groupWs);
      }

      if (appList.length > 0) {
        const groupApp = document.createElement('optgroup');
        groupApp.label = '📱 Đã Cài Trên App (iOS)';
        for (const ext of appList) {
          const opt = document.createElement('option');
          opt.value = 'app:' + ext.packageId;
          opt.innerText = ext.name + ' (' + ext.packageId + ') v' + ext.version;
          groupApp.appendChild(opt);
        }
        select.appendChild(groupApp);
      }

      if (wsList.length === 0 && appList.length === 0) {
        const opt = document.createElement('option');
        opt.value = '';
        opt.innerText = '(Không tìm thấy extension trong folder & app)';
        select.appendChild(opt);
      }

      if (currentState.selectedKey) {
        select.value = currentState.selectedKey;
      } else if (prevVal && Array.from(select.options).some(o => o.value === prevVal)) {
        select.value = prevVal;
      } else if (select.options.length > 0) {
        select.selectedIndex = 0;
      }

      document.getElementById('btnRun').disabled = !isConn || currentState.isRunning;
      document.getElementById('btnCancel').disabled = !isConn || !currentState.isRunning;
    }

    function appendTraceLine(text) {
      const box = document.getElementById('traceBox');
      const div = document.createElement('div');
      div.className = 'trace-line';
      if (text.includes('[exception]') || text.includes('[compileFailed]') || text.includes('[fetchFailed]') || text.includes('[Response.error]') || text.includes('Error')) {
        div.className += ' error';
      } else if (text.includes('[Response.success]') || text.includes('✅')) {
        div.className += ' success';
      } else if (text.includes('[console]')) {
        div.className += ' info';
      }
      div.innerText = text;
      box.appendChild(div);
      box.scrollTop = box.scrollHeight;
    }

    vscode.postMessage({ type: 'ready' });
  </script>
</body>
</html>`;
  }
}
