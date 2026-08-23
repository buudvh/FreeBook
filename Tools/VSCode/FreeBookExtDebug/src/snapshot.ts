import { createHash } from "node:crypto";
import * as vscode from "vscode";

import {
    ExtensionManifest,
    ExtensionWorkspaceError,
    isUriWithinRoot,
    normalizeRelativeExtensionPath,
    relativePathFromRoot,
    sameUri,
} from "./manifest";

const EXCLUDED_DIRECTORY_NAMES = new Set([".git", "node_modules", "out", ".vscode"]);

export interface DraftSnapshotFileDescriptor {
    readonly path: string;
    readonly size: number;
    /** SHA-256 of the saved file bytes; used as the source revision in traces. */
    readonly revision: string;
}

export interface DraftSnapshotFile extends DraftSnapshotFileDescriptor {
    readonly uri: vscode.Uri;
    /** Raw bytes only; the transport is responsible for binary framing. */
    readonly contents: Uint8Array;
}

export interface DraftSnapshotManifest {
    readonly version: 1;
    readonly algorithm: "sha256";
    /** SHA-256 of the deterministic list of file descriptors. */
    readonly hash: string;
    readonly files: readonly DraftSnapshotFileDescriptor[];
}

export interface DraftSnapshot {
    readonly root: vscode.Uri;
    readonly manifest: DraftSnapshotManifest;
    readonly files: readonly DraftSnapshotFile[];
}

export interface DraftSnapshotChunk {
    readonly path: string;
    readonly revision: string;
    readonly offset: number;
    readonly totalBytes: number;
    readonly index: number;
    readonly count: number;
    readonly data: Uint8Array;
}

/** Raised before staging so the user can save changes explicitly. */
export class DirtyExtensionDocumentsError extends Error {
    public constructor(public readonly documents: readonly vscode.Uri[]) {
        super("Extension có file chưa lưu. Hãy lưu tất cả file trước khi stage hoặc chạy draft.");
        this.name = "DirtyExtensionDocumentsError";
    }
}

/** Lists open, unsaved text documents that belong to an extension root. */
export function dirtyExtensionDocuments(root: vscode.Uri): readonly vscode.TextDocument[] {
    return vscode.workspace.textDocuments
        .filter((document) => document.isDirty && isUriWithinRoot(document.uri, root))
        .sort((left, right) => compareText(left.uri.toString(), right.uri.toString()));
}

/** Does not save anything. It only reports the documents that must be saved. */
export function assertNoDirtyExtensionDocuments(root: vscode.Uri): void {
    const dirtyDocuments = dirtyExtensionDocuments(root);
    if (dirtyDocuments.length > 0) {
        throw new DirtyExtensionDocumentsError(dirtyDocuments.map((document) => document.uri));
    }
}

/**
 * Builds a deterministic snapshot from saved workspace files. Directories that
 * are tool/build metadata are intentionally not sent to the app.
 */
export async function createDraftSnapshot(manifest: ExtensionManifest): Promise<DraftSnapshot> {
    assertNoDirtyExtensionDocuments(manifest.root);

    const files: DraftSnapshotFile[] = [];
    await collectFiles(manifest.root, manifest.root, files);
    files.sort((left, right) => compareText(left.path, right.path));

    // Recheck after I/O: this avoids silently staging disk bytes when a document
    // became dirty while the extension tree was being traversed.
    assertNoDirtyExtensionDocuments(manifest.root);

    const descriptors = files.map(({ path, size, revision }) => ({ path, size, revision }));
    const manifestHashInput = descriptors
        .map((file) => `${file.path}\0${file.size}\0${file.revision}\n`)
        .join("");

    return {
        root: manifest.root,
        manifest: {
            version: 1,
            algorithm: "sha256",
            hash: sha256Hex(new TextEncoder().encode(manifestHashInput)),
            files: descriptors,
        },
        files,
    };
}

/**
 * Splits raw file bytes after the app has supplied its allowed binary quota.
 * Empty files deliberately produce one empty chunk so they are staged too.
 */
export function* createDraftSnapshotChunks(
    snapshot: DraftSnapshot,
    maximumChunkBytes: number,
): Iterable<DraftSnapshotChunk> {
    if (!Number.isSafeInteger(maximumChunkBytes) || maximumChunkBytes < 1) {
        throw new RangeError("maximumChunkBytes phải là số nguyên dương.");
    }

    for (const file of snapshot.files) {
        const count = Math.max(1, Math.ceil(file.contents.byteLength / maximumChunkBytes));
        for (let index = 0; index < count; index += 1) {
            const offset = index * maximumChunkBytes;
            const end = Math.min(offset + maximumChunkBytes, file.contents.byteLength);
            yield {
                path: file.path,
                revision: file.revision,
                offset,
                totalBytes: file.contents.byteLength,
                index,
                count,
                data: file.contents.slice(offset, end),
            };
        }
    }
}

/** Reads the hash of a saved staged path without reading unsaved editor buffers. */
export async function savedFileRevision(
    root: vscode.Uri,
    sourcePath: string,
): Promise<string | undefined> {
    const uri = stagedFileUri(root, sourcePath);
    if (!uri || !(await isRegularFile(uri))) {
        return undefined;
    }

    return sha256Hex(await vscode.workspace.fs.readFile(uri));
}

/**
 * A trace source revision is usable only if the matching on-disk file has not
 * changed and the open editor is not currently dirty.
 */
export async function isSavedSourceRevisionCurrent(
    root: vscode.Uri,
    sourcePath: string,
    sourceRevision: string,
): Promise<boolean> {
    const uri = stagedFileUri(root, sourcePath);
    if (!uri || dirtyExtensionDocuments(root).some((document) => sameUri(document.uri, uri))) {
        return false;
    }

    return (await savedFileRevision(root, sourcePath)) === sourceRevision;
}

function stagedFileUri(root: vscode.Uri, sourcePath: string): vscode.Uri | undefined {
    const safePath = normalizeRelativeExtensionPath(sourcePath);
    if (!safePath) {
        return undefined;
    }

    return vscode.Uri.joinPath(root, ...safePath.split("/"));
}

async function collectFiles(
    root: vscode.Uri,
    directory: vscode.Uri,
    files: DraftSnapshotFile[],
): Promise<void> {
    let entries: [string, vscode.FileType][];
    try {
        entries = await vscode.workspace.fs.readDirectory(directory);
    } catch (error) {
        const detail = error instanceof Error ? error.message : String(error);
        throw new ExtensionWorkspaceError("manifest-not-found", `Không thể đọc ${directory.fsPath}: ${detail}`);
    }

    for (const [name, type] of entries.sort(([left], [right]) => compareText(left, right))) {
        const uri = vscode.Uri.joinPath(directory, name);
        if ((type & vscode.FileType.Directory) !== 0) {
            if (!isExcludedDirectory(name) && (type & vscode.FileType.SymbolicLink) === 0) {
                await collectFiles(root, uri, files);
            }
            continue;
        }

        if ((type & vscode.FileType.File) === 0 || (type & vscode.FileType.SymbolicLink) !== 0) {
            continue;
        }

        const contents = await vscode.workspace.fs.readFile(uri);
        files.push({
            uri,
            path: relativePathFromRoot(root, uri),
            size: contents.byteLength,
            revision: sha256Hex(contents),
            contents,
        });
    }
}

function isExcludedDirectory(name: string): boolean {
    return EXCLUDED_DIRECTORY_NAMES.has(name.toLowerCase());
}

async function isRegularFile(uri: vscode.Uri): Promise<boolean> {
    try {
        const stat = await vscode.workspace.fs.stat(uri);
        return (stat.type & vscode.FileType.File) !== 0
            && (stat.type & vscode.FileType.SymbolicLink) === 0;
    } catch {
        return false;
    }
}

function sha256Hex(bytes: Uint8Array): string {
    return createHash("sha256").update(bytes).digest("hex");
}

function compareText(left: string, right: string): number {
    return left < right ? -1 : left > right ? 1 : 0;
}
