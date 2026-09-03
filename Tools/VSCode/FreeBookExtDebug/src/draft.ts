import * as vscode from 'vscode';
import { createHash } from 'crypto';
import { DraftManifest, DraftManifestEntry } from './protocol';
import { ExtDebugClient } from './client';

/** Trần phía client, khớp `ExtensionDraftManifest` trong Swift. App vẫn là thẩm quyền cuối cùng. */
const MAX_FILE_COUNT = 200;
const MAX_FILE_BYTES = 1024 * 1024;
const MAX_TOTAL_BYTES = 4 * 1024 * 1024;
/** Base64 nở ~4/3; 48 KiB binary ≈ 64 KiB base64, an toàn dưới trần message 512 KiB của server. */
const CHUNK_BYTES = 48 * 1024;

export interface DraftBundle {
  manifest: DraftManifest;
  contents: Map<string, Uint8Array>;
}

export interface WorkspaceExtensionInfo {
  folderUri: vscode.Uri;
  folderPath: string;
  folderName: string;
  packageId: string;
  name: string;
  version: string;
  author?: string;
  description?: string;
  scripts: string[];
}

function sha256(data: Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

/**
 * Mirror của `ExtensionSyncCommandBuilder.packageId(forName:)` bên Swift: `name.lowercased()` rồi thay
 * dấu cách bằng `_`.
 *
 * Đây chỉ là **phỏng đoán**, không phải nguồn sự thật. App có ba đường cài extension và mỗi đường sinh
 * `packageId` theo một luật khác: repo sync dùng hàm trên, import zip dùng `metadata.packageId` hoặc
 * `name.lowercased()` **không** thay dấu cách (`ExtensionManager.installFromLocalZip`), còn restore
 * backup giữ nguyên id đã lưu. Vì vậy mọi lệnh có `packageId` phải đối chiếu lại với `extensions.list`
 * trước khi gửi — xem `resolvePackageId()` trong `extension.ts`.
 */
export function slugPackageId(name: string): string {
  return name.toLowerCase().split(' ').join('_').trim();
}

/** Bỏ dấu và mọi ký tự không phải chữ/số, để so tên hiển thị giữa app và thư mục nguồn. */
export function compactName(value: string): string {
  // NFD tách dấu thành ký tự riêng, rồi bước lọc `[^a-z0-9]` dọn luôn cả dấu và dấu cách.
  return value.normalize('NFD').toLowerCase().replace(/[^a-z0-9]/g, '');
}

/**
 * Đọc thông tin extension từ một thư mục bất kỳ chứa `plugin.json`.
 */
export async function readExtensionFromFolder(folderUri: vscode.Uri): Promise<WorkspaceExtensionInfo | undefined> {
  const pluginUri = vscode.Uri.joinPath(folderUri, 'plugin.json');
  try {
    const raw = await vscode.workspace.fs.readFile(pluginUri);
    const json = JSON.parse(Buffer.from(raw).toString('utf-8'));
    const metadata = json.metadata || {};
    const folderPath = folderUri.fsPath;
    const folderName = folderUri.path.split('/').filter(Boolean).pop() ?? 'extension';

    const scriptKeys = new Set<string>();
    if (json.script && typeof json.script === 'object') {
      for (const k of Object.keys(json.script)) {
        scriptKeys.add(k);
      }
    }
    for (const relativeDir of ['', 'src']) {
      const dirUri = relativeDir ? vscode.Uri.joinPath(folderUri, relativeDir) : folderUri;
      try {
        const items = await vscode.workspace.fs.readDirectory(dirUri);
        for (const [name, type] of items) {
          if (type === vscode.FileType.File && name.endsWith('.js')) {
            scriptKeys.add(name.replace(/\.js$/, ''));
          }
        }
      } catch {}
    }

    const packageId = String(metadata.packageId || json.packageId || slugPackageId(String(metadata.name || json.name || folderName)));
    const name = String(metadata.name || json.name || folderName);
    const version = String(metadata.version || json.version || '1.0');
    const author = metadata.author || json.author;
    const description = metadata.description || json.description;

    return {
      folderUri,
      folderPath,
      folderName,
      packageId,
      name,
      version,
      author,
      description,
      scripts: Array.from(scriptKeys)
    };
  } catch {
    return undefined;
  }
}

/**
 * Tự động tìm tất cả các extension nằm trong Workspace.
 */
export async function discoverWorkspaceExtensions(): Promise<WorkspaceExtensionInfo[]> {
  const results: WorkspaceExtensionInfo[] = [];
  const foundUris = await vscode.workspace.findFiles('**/plugin.json', '**/node_modules/**', 50);

  for (const uri of foundUris) {
    const folderUri = vscode.Uri.joinPath(uri, '..');
    const info = await readExtensionFromFolder(folderUri);
    if (info) {
      // Tránh trùng lặp
      if (!results.some((r) => r.folderUri.toString() === info.folderUri.toString())) {
        results.push(info);
      }
    }
  }

  results.sort((a, b) => a.name.localeCompare(b.name));
  return results;
}

/**
 * Dựng snapshot từ thư mục extension cụ thể bằng `workspace.fs` (không giả định filesystem local).
 *
 * Gom `plugin.json` + mọi `.js` ở gốc và trong `src/`. Cố ý **không** cố suy ra đúng tập phụ thuộc:
 * `load(...)` có thể động, nên gửi cả bộ `.js` rẻ hơn và không bao giờ thiếu file — app validate lại
 * containment và `load(...)` một lần nữa.
 */
export async function buildDraftBundle(
  folder: vscode.Uri,
  packageId: string
): Promise<DraftBundle> {
  const pluginUri = vscode.Uri.joinPath(folder, 'plugin.json');
  let pluginBytes: Uint8Array;
  try {
    pluginBytes = await vscode.workspace.fs.readFile(pluginUri);
  } catch {
    throw new Error(`Không đọc được plugin.json ở gốc thư mục: ${folder.fsPath}`);
  }

  const contents = new Map<string, Uint8Array>();
  contents.set('plugin.json', pluginBytes);

  for (const relativeDir of ['', 'src']) {
    const dirUri = relativeDir ? vscode.Uri.joinPath(folder, relativeDir) : folder;
    let items: [string, vscode.FileType][];
    try {
      items = await vscode.workspace.fs.readDirectory(dirUri);
    } catch {
      continue;
    }
    for (const [name, type] of items) {
      if (type !== vscode.FileType.File || !name.endsWith('.js')) {
        continue;
      }
      const relativePath = relativeDir ? `${relativeDir}/${name}` : name;
      const bytes = await vscode.workspace.fs.readFile(vscode.Uri.joinPath(dirUri, name));
      if (bytes.byteLength > MAX_FILE_BYTES) {
        throw new Error(`${relativePath} vượt ${MAX_FILE_BYTES} byte`);
      }
      contents.set(relativePath, bytes);
    }
  }

  if (contents.size > MAX_FILE_COUNT) {
    throw new Error(`Snapshot có ${contents.size} file, vượt trần ${MAX_FILE_COUNT}`);
  }
  let total = 0;
  const entries: DraftManifestEntry[] = [];
  for (const relativePath of [...contents.keys()].sort()) {
    const bytes = contents.get(relativePath)!;
    total += bytes.byteLength;
    entries.push({ relativePath, size: bytes.byteLength, sha256: sha256(bytes) });
  }
  if (total > MAX_TOTAL_BYTES) {
    throw new Error(`Snapshot ${total} byte, vượt trần ${MAX_TOTAL_BYTES}`);
  }

  const fingerprint = createHash('sha256');
  for (const entry of entries) {
    fingerprint.update(`${entry.relativePath}:${entry.sha256}\n`);
  }
  const revision = fingerprint.digest('hex').slice(0, 16);

  return { manifest: { packageId, revision, entries }, contents };
}

/**
 * Nạp snapshot lên app: `draft.stage` → nhiều `draft.chunk` → `draft.finish`.
 */
export async function stageDraft(
  client: ExtDebugClient,
  bundle: DraftBundle,
  progress: (message: string) => void
): Promise<string> {
  await client.request('draft.stage', { manifest: bundle.manifest });

  for (const entry of bundle.manifest.entries) {
    const bytes = bundle.contents.get(entry.relativePath)!;
    let offset = 0;
    let chunkIndex = 0;
    do {
      const slice = bytes.subarray(offset, Math.min(offset + CHUNK_BYTES, bytes.byteLength));
      offset += slice.byteLength;
      await client.request('draft.chunk', {
        relativePath: entry.relativePath,
        chunkIndex,
        chunkBase64: Buffer.from(slice).toString('base64'),
        isLastChunk: offset >= bytes.byteLength
      });
      chunkIndex += 1;
    } while (offset < bytes.byteLength);
    progress(`đã gửi ${entry.relativePath} (${entry.size} byte)`);
  }

  const finished = await client.request('draft.finish', {}, 60000);
  const revision = finished.sourceRevision ?? bundle.manifest.revision;
  progress(`bản nháp ${revision} đã được app validate`);
  return revision;
}
