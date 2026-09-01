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

function sha256(data: Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

/**
 * Dựng snapshot từ workspace bằng `workspace.fs` (không giả định filesystem local).
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
    throw new Error('Không đọc được plugin.json ở gốc thư mục extension');
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

  // Revision là hash của (path + hash nội dung) đã sắp — đổi một byte ở bất kỳ file nào là đổi revision,
  // và cùng nội dung luôn cho cùng revision nên stage lại không tạo bản trùng lặp.
  const fingerprint = createHash('sha256');
  for (const entry of entries) {
    fingerprint.update(`${entry.relativePath}:${entry.sha256}\n`);
  }
  const revision = fingerprint.digest('hex').slice(0, 16);

  return { manifest: { packageId, revision, entries }, contents };
}

/**
 * Nạp snapshot lên app: `draft.stage` → nhiều `draft.chunk` → `draft.finish`.
 *
 * Trình tự này là hợp đồng: server chỉ nhận chunk cho file **đã khai** trong manifest, và `run.start`
 * với `sourceMode: 'draft'` chỉ chấp nhận revision đã qua `draft.finish` (tức đã khớp checksum và
 * validate cú pháp/`load(...)`).
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
