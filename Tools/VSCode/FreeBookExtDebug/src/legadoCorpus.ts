import * as vscode from 'vscode';
import { ExtDebugClient } from './client';
import {
  LEGADO_MIN_PROTOCOL_VERSION,
  LegadoCorpusReport,
  LegadoSourceInfo,
  Payload
} from './protocol';

/**
 * Ba lệnh VS Code cho bộ nghiệm thu nguồn Legado trên app (`legado.*`, protocol v2):
 * - **Chạy**: chọn phạm vi (mọi nguồn đang bật / chọn tay), từ khoá mặc định, giới hạn số nguồn → `legado.corpus.start`,
 *   rồi theo dõi tiến độ bằng cách hỏi `legado.corpus.status` mỗi 3 giây (không dùng event).
 * - **Xem kết quả**: lấy báo cáo đầy đủ (kèm từng nguồn), in tóm tắt ra kênh output và mở JSON trong một tài liệu chưa
 *   lưu — file báo cáo trên máy nằm trong `applicationSupport`, không mở được từ ứng dụng Tệp.
 * - **Huỷ**: `legado.corpus.cancel`; app ghi báo cáo dở dang.
 *
 * Client chỉ gửi `packageIds`/`allEnabled`, `keyword`, `limit`, `includeSources`, `runId` — app từ chối URL/tiền tố gỡ
 * lỗi trong từ khoá.
 */

export interface LegadoCorpusHost {
  client(): ExtDebugClient | undefined;
  log(message: string): void;
  showOutput(): void;
}

const POLL_INTERVAL_MS = 3000;
const TOP_FAILURES = 30;
let followingRunId: string | undefined;

export async function runLegadoCorpus(host: LegadoCorpusHost): Promise<void> {
  const client = requireLegadoClient(host);
  if (!client) {
    return;
  }

  const scope = await vscode.window.showQuickPick(
    [
      { label: 'Tất cả nguồn Legado đang bật', value: 'all' as const },
      { label: 'Chọn nguồn…', value: 'pick' as const }
    ],
    { title: 'Nghiệm thu nguồn Legado · phạm vi' }
  );
  if (!scope) {
    return;
  }

  const payload: Payload = {};
  if (scope.value === 'all') {
    payload.allEnabled = true;
  } else {
    const packageIds = await pickSources(client);
    if (!packageIds) {
      return;
    }
    payload.packageIds = packageIds;
  }

  const keyword = await vscode.window.showInputBox({
    title: 'Nghiệm thu nguồn Legado · từ khoá mặc định',
    prompt: 'Chỉ dùng cho nguồn không khai checkKeyWord. Để trống = 我的. Không nhận URL hay tiền tố ++/--.',
    placeHolder: '我的',
    ignoreFocusOut: true
  });
  if (keyword === undefined) {
    return;
  }
  if (keyword.trim()) {
    payload.keyword = keyword.trim();
  }

  const limitText = await vscode.window.showInputBox({
    title: 'Nghiệm thu nguồn Legado · giới hạn số nguồn',
    prompt: 'Để trống hoặc 0 = không giới hạn',
    ignoreFocusOut: true,
    validateInput: (value) => (/^\s*\d*\s*$/.test(value) ? undefined : 'Nhập số nguyên ≥ 0')
  });
  if (limitText === undefined) {
    return;
  }
  const limit = parseInt(limitText.trim() || '0', 10);
  if (limit > 0) {
    payload.limit = limit;
  }

  try {
    const reply = await client.request('legado.corpus.start', payload, 60000);
    host.showOutput();
    host.log(`--- nghiệm thu Legado ${reply.runId ?? '?'} · ${reply.message ?? ''} ---`);
    if (reply.runId) {
      await followProgress(host, client, reply.runId);
    }
  } catch (error) {
    vscode.window.showErrorMessage(`legado.corpus.start thất bại: ${describe(error)}`);
  }
}

export async function showLegadoCorpusReport(host: LegadoCorpusHost): Promise<void> {
  const client = requireLegadoClient(host);
  if (!client) {
    return;
  }
  try {
    const report = await fetchFullReport(host, client, undefined);
    if (report?.state === 'running') {
      await followProgress(host, client, report.runId);
    }
  } catch (error) {
    vscode.window.showErrorMessage(`legado.corpus.status thất bại: ${describe(error)}`);
  }
}

export async function cancelLegadoCorpus(host: LegadoCorpusHost): Promise<void> {
  const client = requireLegadoClient(host);
  if (!client) {
    return;
  }
  try {
    const reply = await client.request('legado.corpus.cancel', {});
    host.log(`legado.corpus.cancel: ${reply.message ?? 'đã gửi'}`);
    vscode.window.showInformationMessage(reply.message ?? 'Đã gửi yêu cầu huỷ');
  } catch (error) {
    vscode.window.showErrorMessage(`legado.corpus.cancel thất bại: ${describe(error)}`);
  }
}

// MARK: - Nội bộ

function requireLegadoClient(host: LegadoCorpusHost): ExtDebugClient | undefined {
  const client = host.client();
  if (!client?.isConnected) {
    vscode.window.showWarningMessage('Chưa kết nối. Chạy “FreeBook: Connect to App” trước.');
    return undefined;
  }
  if (client.negotiatedVersion < LEGADO_MIN_PROTOCOL_VERSION) {
    vscode.window.showWarningMessage(
      `App đang chạy debug server protocol v${client.negotiatedVersion} — chưa có lệnh nghiệm thu nguồn Legado. Cập nhật app.`
    );
    return undefined;
  }
  return client;
}

async function pickSources(client: ExtDebugClient): Promise<string[] | undefined> {
  let sources: LegadoSourceInfo[];
  try {
    const reply = await client.request('legado.sources', {}, 60000);
    sources = reply.legadoSources ?? [];
  } catch (error) {
    vscode.window.showErrorMessage(`legado.sources thất bại: ${describe(error)}`);
    return undefined;
  }
  if (sources.length === 0) {
    vscode.window.showInformationMessage('App chưa có nguồn Legado chữ nào.');
    return undefined;
  }
  const items = sources.map((source) => ({
    label: source.name,
    description: source.packageId,
    detail: [
      source.enabled ? 'đang bật' : 'đang tắt — sẽ bị bỏ qua',
      source.hasSearchRules ? 'có tìm kiếm' : source.hasExploreRules ? 'chỉ khám phá' : 'không có lối vào'
    ].join(' · '),
    packageId: source.packageId
  }));
  const picked = await vscode.window.showQuickPick(items, {
    title: `Chọn nguồn Legado (${sources.length})`,
    canPickMany: true,
    matchOnDescription: true,
    ignoreFocusOut: true
  });
  if (!picked || picked.length === 0) {
    return undefined;
  }
  return picked.map((item) => item.packageId);
}

/** Hỏi trạng thái tới khi lượt xong (hoặc mất kết nối), rồi in + mở báo cáo đầy đủ. Một vòng theo dõi mỗi lượt. */
async function followProgress(host: LegadoCorpusHost, client: ExtDebugClient, runId: string): Promise<void> {
  if (followingRunId === runId) {
    vscode.window.showInformationMessage('Đang theo dõi lượt này ở thông báo tiến độ.');
    return;
  }
  followingRunId = runId;
  let finished = false;
  try {
    await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: 'Nghiệm thu nguồn Legado', cancellable: true },
      async (progress, token) => {
        token.onCancellationRequested(() => {
          void client
            .request('legado.corpus.cancel', { runId })
            .then((reply) => host.log(`legado.corpus.cancel: ${reply.message ?? 'đã gửi'}`))
            .catch((error) => host.log(`legado.corpus.cancel lỗi: ${describe(error)}`));
        });
        let reported = 0;
        while (client.isConnected) {
          const reply = await client.request('legado.corpus.status', { runId });
          const report = reply.legadoCorpus;
          if (!report) {
            break;
          }
          const percent = report.totalSources > 0 ? (report.completed / report.totalSources) * 100 : 100;
          progress.report({ increment: Math.max(0, percent - reported), message: progressMessage(report) });
          reported = Math.max(reported, percent);
          if (report.state !== 'running') {
            finished = true;
            break;
          }
          await sleep(POLL_INTERVAL_MS);
        }
      }
    );
  } catch (error) {
    host.log(`Ngừng theo dõi lượt ${runId}: ${describe(error)}. Lượt vẫn chạy trên app — nối lại rồi chạy “Xem kết quả”.`);
  } finally {
    followingRunId = undefined;
  }
  if (finished && client.isConnected) {
    try {
      await fetchFullReport(host, client, runId);
    } catch (error) {
      vscode.window.showErrorMessage(`Không lấy được báo cáo: ${describe(error)}`);
    }
  }
}

async function fetchFullReport(
  host: LegadoCorpusHost,
  client: ExtDebugClient,
  runId: string | undefined
): Promise<LegadoCorpusReport | undefined> {
  const payload: Payload = { includeSources: true };
  if (runId) {
    payload.runId = runId;
  }
  const reply = await client.request('legado.corpus.status', payload, 60000);
  const report = reply.legadoCorpus;
  if (!report) {
    vscode.window.showInformationMessage(reply.message ?? 'Chưa có lượt nghiệm thu nào.');
    return undefined;
  }
  host.showOutput();
  for (const line of summaryLines(report)) {
    host.log(line);
  }
  const document = await vscode.workspace.openTextDocument({
    language: 'json',
    content: JSON.stringify(report, null, 2)
  });
  await vscode.window.showTextDocument(document, { preview: false });
  return report;
}

function progressMessage(report: LegadoCorpusReport): string {
  const running = report.inFlight.length > 0 ? ` · đang chạy: ${report.inFlight.slice(0, 2).join(', ')}` : '';
  return `${report.completed}/${report.totalSources} · qua ${report.passed}/${report.attempted} (${report.passPercent}%)${running}`;
}

function summaryLines(report: LegadoCorpusReport): string[] {
  const lines = [
    `=== Nghiệm thu Legado ${report.runId} · ${report.state} ===`,
    `Bắt đầu ${report.startedAt}${report.finishedAt ? ` · xong ${report.finishedAt}` : ''} · từ khoá mặc định '${report.defaultKeyword}'`,
    `Nguồn: chọn ${report.totalSources} · đã chạy ${report.attempted} · qua ${report.passed} (${report.passPercent}%) · ` +
      `bỏ qua ${report.skipped} · huỷ dở ${report.cancelledSources} · bước bỏ chờ ${report.abandonedSteps}`,
    `Lớp lỗi: ${formatCounts(report.byFailureClass)}`,
    `Bước qua cuối: ${formatCounts(report.byLastPassedStep)}`,
    `Bước hỏng: ${formatCounts(report.byFailedStep)}`,
    `HTTP: ${formatCounts(report.httpStatusCounts)}`,
    `Gợi ý chưa hỗ trợ (trên nguồn lỗi): ${formatCounts(report.unsupportedHintCounts)}`,
    `Báo cáo trên máy: applicationSupport/${report.reportPath ?? '(chưa ghi)'}`
  ];
  const failures = (report.sources ?? []).filter((source) => source.outcome === 'failed');
  if (failures.length > 0) {
    lines.push(`Nguồn lỗi (${Math.min(TOP_FAILURES, failures.length)}/${failures.length} đầu):`);
    for (const source of failures.slice(0, TOP_FAILURES)) {
      const http = source.httpStatus !== undefined ? ` ${source.httpStatus}` : '';
      lines.push(
        `  ✗ ${source.name} (${source.packageId}) · ${source.failedStep ?? '?'} · ${source.failureClass ?? '?'}${http} · ` +
          `${source.message ?? ''}`
      );
    }
  }
  return lines;
}

function formatCounts(counts: Record<string, number>): string {
  const entries = Object.entries(counts).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  return entries.length === 0 ? '—' : entries.map(([key, value]) => `${key} ${value}`).join(', ');
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
