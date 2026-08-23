import * as vscode from "vscode";

/** Values that can safely cross the debug protocol as JSON. */
export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonValue[];
export interface JsonObject {
    [key: string]: JsonValue;
}

export type ExtensionWorkspaceErrorCode =
    | "manifest-not-found"
    | "invalid-manifest"
    | "ambiguous-root"
    | "invalid-script-path"
    | "missing-script"
    | "script-not-found"
    | "not-a-regular-file";

/** A user-facing error raised while inspecting a saved extension on disk. */
export class ExtensionWorkspaceError extends Error {
    public constructor(
        public readonly code: ExtensionWorkspaceErrorCode,
        message: string,
    ) {
        super(message);
        this.name = "ExtensionWorkspaceError";
    }
}

export interface ExtensionManifest {
    readonly root: vscode.Uri;
    readonly manifestUri: vscode.Uri;
    readonly raw: JsonObject;
    readonly metadata: JsonObject;
    readonly name: string;
    readonly packageId: string;
    readonly scripts: Readonly<Record<string, string>>;
    readonly defaultConfig: JsonObject;
}

export interface ResolvedExtensionScript {
    readonly root: vscode.Uri;
    readonly uri: vscode.Uri;
    /** POSIX-style path relative to the extension root; safe to put on the wire. */
    readonly relativePath: string;
    /** The file name/path declared by plugin.json or selected by the user. */
    readonly requestedPath: string;
    /** Present only when the script came from plugin.json. */
    readonly manifestKey?: string;
}

/** Returns true only for plain JSON values, including finite JSON numbers. */
export function isJsonValue(value: unknown): value is JsonValue {
    if (value === null || typeof value === "string" || typeof value === "boolean") {
        return true;
    }

    if (typeof value === "number") {
        return Number.isFinite(value);
    }

    if (Array.isArray(value)) {
        return value.every(isJsonValue);
    }

    if (!isJsonObject(value)) {
        return false;
    }

    return Object.values(value).every(isJsonValue);
}

export function isJsonObject(value: unknown): value is JsonObject {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function cloneJsonValue<T extends JsonValue>(value: T): T {
    if (Array.isArray(value)) {
        return value.map((entry) => cloneJsonValue(entry)) as T;
    }

    if (isJsonObject(value)) {
        const clone: JsonObject = {};
        for (const [key, entry] of Object.entries(value)) {
            clone[key] = cloneJsonValue(entry);
        }
        return clone as T;
    }

    return value;
}

/**
 * Mirrors ExtensionManager's package-ID fallback exactly: lower case, replace
 * literal spaces with underscores, then trim surrounding whitespace.
 */
export function fallbackPackageId(name: string): string {
    return name.toLowerCase().replace(/ /g, "_").trim();
}

/** Reads a saved plugin.json through VS Code's filesystem abstraction. */
export async function readExtensionManifest(root: vscode.Uri): Promise<ExtensionManifest> {
    const manifestUri = vscode.Uri.joinPath(root, "plugin.json");
    if (!(await isRegularFile(manifestUri))) {
        throw new ExtensionWorkspaceError(
            "manifest-not-found",
            `Không tìm thấy plugin.json trong ${displayUri(root)}.`,
        );
    }

    let parsed: unknown;
    try {
        const contents = await vscode.workspace.fs.readFile(manifestUri);
        const text = new TextDecoder("utf-8", { fatal: true }).decode(contents).replace(/^\uFEFF/, "");
        parsed = JSON.parse(text);
    } catch (error) {
        const detail = error instanceof Error ? error.message : String(error);
        throw new ExtensionWorkspaceError("invalid-manifest", `plugin.json không hợp lệ: ${detail}`);
    }

    if (!isJsonObject(parsed)) {
        throw new ExtensionWorkspaceError("invalid-manifest", "plugin.json phải là một JSON object.");
    }

    const raw = parsed;
    // This is intentionally the same fallback as ExtensionManager: when a
    // metadata object exists, fields do not fall back to the root object.
    const metadata = isJsonObject(raw.metadata) ? raw.metadata : raw;
    const metadataName = typeof metadata.name === "string" ? metadata.name : undefined;
    const rootName = typeof raw.name === "string" ? raw.name : undefined;
    const name = metadataName ?? rootName ?? "Tiện ích Import";
    const declaredPackageId = typeof metadata.packageId === "string" ? metadata.packageId : undefined;
    const packageId = declaredPackageId && declaredPackageId.length > 0
        ? declaredPackageId
        : fallbackPackageId(name);

    return {
        root,
        manifestUri,
        raw,
        metadata,
        name,
        packageId,
        scripts: extractScripts(raw.script),
        defaultConfig: extractDefaultConfig(raw.config),
    };
}

/**
 * Resolves a root selected as the extension directory, plugin.json, or a file
 * inside the extension. It also matches the app's one-level archive-root
 * fallback when the selected directory contains exactly one child extension.
 */
export async function discoverExtensionManifest(candidate: vscode.Uri): Promise<ExtensionManifest> {
    const start = await directoryFor(candidate);
    const workspaceBoundary = vscode.workspace.getWorkspaceFolder(start)?.uri;

    let current = start;
    while (true) {
        if (await isRegularFile(vscode.Uri.joinPath(current, "plugin.json"))) {
            return readExtensionManifest(current);
        }

        if (workspaceBoundary && sameUri(current, workspaceBoundary)) {
            break;
        }

        const parent = parentUri(current);
        if (sameUri(parent, current)) {
            break;
        }
        current = parent;
    }

    const childRoots = await immediateChildExtensionRoots(start);
    if (childRoots.length === 1) {
        return readExtensionManifest(childRoots[0]);
    }
    if (childRoots.length > 1) {
        throw new ExtensionWorkspaceError(
            "ambiguous-root",
            `Có nhiều thư mục extension trong ${displayUri(start)}. Hãy chọn đúng thư mục chứa plugin.json.`,
        );
    }

    throw new ExtensionWorkspaceError(
        "manifest-not-found",
        `Không tìm thấy plugin.json từ ${displayUri(candidate)}.`,
    );
}

/** Resolves a script declared by plugin.json, first at root and then src/. */
export async function resolveManifestScript(
    manifest: ExtensionManifest,
    scriptKey: string,
): Promise<ResolvedExtensionScript> {
    const requestedPath = manifest.scripts[scriptKey];
    if (typeof requestedPath !== "string" || requestedPath.length === 0) {
        throw new ExtensionWorkspaceError(
            "missing-script",
            `plugin.json không khai script '${scriptKey}'.`,
        );
    }

    return resolveExtensionScript(manifest.root, requestedPath, scriptKey);
}

/**
 * Resolves an explicit, stage-safe script path using the same root/src lookup
 * as ExtensionManager. This does not require the file to be declared in the
 * manifest; callers must enforce draft-only policy where appropriate.
 */
export async function resolveExtensionScript(
    root: vscode.Uri,
    requestedPath: string,
    manifestKey?: string,
): Promise<ResolvedExtensionScript> {
    const safePath = normalizeRelativeExtensionPath(requestedPath);
    if (!safePath) {
        throw new ExtensionWorkspaceError(
            "invalid-script-path",
            `Đường dẫn script không hợp lệ: '${requestedPath}'.`,
        );
    }

    const segments = safePath.split("/");
    const candidates = [
        vscode.Uri.joinPath(root, ...segments),
        vscode.Uri.joinPath(root, "src", ...segments),
    ];

    for (const uri of candidates) {
        if (await isRegularFile(uri)) {
            return {
                root,
                uri,
                relativePath: relativePathFromRoot(root, uri),
                requestedPath: safePath,
                manifestKey,
            };
        }
    }

    throw new ExtensionWorkspaceError(
        "script-not-found",
        `Không tìm thấy script '${requestedPath}' ở thư mục gốc hoặc src/.`,
    );
}

/** Returns the manifest key for a resolved script, if any. */
export async function declaredScriptKey(
    manifest: ExtensionManifest,
    script: ResolvedExtensionScript,
): Promise<string | undefined> {
    for (const key of Object.keys(manifest.scripts).sort(compareText)) {
        try {
            const declared = await resolveManifestScript(manifest, key);
            if (sameUri(declared.uri, script.uri)) {
                return key;
            }
        } catch {
            // A broken unrelated manifest declaration must not prevent an
            // explicit, valid script from being resolved.
        }
    }
    return undefined;
}

/**
 * Normalizes a relative protocol path without Node's path module. It rejects
 * traversal and absolute paths so a staged source path can never escape root.
 */
export function normalizeRelativeExtensionPath(value: string): string | undefined {
    const normalized = value.replace(/\\/g, "/");
    if (!normalized || normalized.startsWith("/") || /^[A-Za-z]:\//.test(normalized)) {
        return undefined;
    }

    const segments: string[] = [];
    for (const segment of normalized.split("/")) {
        if (segment === "" || segment === ".") {
            continue;
        }
        if (segment === ".." || segment.includes("\0")) {
            return undefined;
        }
        segments.push(segment);
    }

    return segments.length > 0 ? segments.join("/") : undefined;
}

export function isUriWithinRoot(uri: vscode.Uri, root: vscode.Uri): boolean {
    if (uri.scheme !== root.scheme || uri.authority !== root.authority) {
        return false;
    }

    const targetPath = comparablePath(uri);
    const rootPath = comparablePath(root);
    return rootPath === "/"
        ? targetPath.startsWith("/")
        : targetPath === rootPath || targetPath.startsWith(`${rootPath}/`);
}

export function relativePathFromRoot(root: vscode.Uri, uri: vscode.Uri): string {
    if (!isUriWithinRoot(uri, root)) {
        throw new ExtensionWorkspaceError(
            "invalid-script-path",
            `${displayUri(uri)} không nằm trong extension đã chọn.`,
        );
    }

    const rootPath = trimmedUriPath(root);
    const uriPath = trimmedUriPath(uri);
    const relative = uriPath.slice(rootPath.length).replace(/^\/+/, "");
    const normalized = normalizeRelativeExtensionPath(relative);
    if (!normalized) {
        throw new ExtensionWorkspaceError("invalid-script-path", "Đường dẫn tương đối của script không hợp lệ.");
    }
    return normalized;
}

export function sameUri(left: vscode.Uri, right: vscode.Uri): boolean {
    return left.scheme === right.scheme
        && left.authority === right.authority
        && comparablePath(left) === comparablePath(right);
}

async function directoryFor(candidate: vscode.Uri): Promise<vscode.Uri> {
    try {
        const stat = await vscode.workspace.fs.stat(candidate);
        if ((stat.type & vscode.FileType.Directory) !== 0) {
            return candidate;
        }
        return parentUri(candidate);
    } catch (error) {
        const detail = error instanceof Error ? error.message : String(error);
        throw new ExtensionWorkspaceError(
            "manifest-not-found",
            `Không thể đọc ${displayUri(candidate)}: ${detail}`,
        );
    }
}

async function immediateChildExtensionRoots(directory: vscode.Uri): Promise<vscode.Uri[]> {
    let entries: [string, vscode.FileType][];
    try {
        entries = await vscode.workspace.fs.readDirectory(directory);
    } catch {
        return [];
    }

    const roots: vscode.Uri[] = [];
    for (const [name, type] of entries.sort(([left], [right]) => compareText(left, right))) {
        if (name.startsWith(".") || (type & vscode.FileType.Directory) === 0) {
            continue;
        }
        const child = vscode.Uri.joinPath(directory, name);
        if (await isRegularFile(vscode.Uri.joinPath(child, "plugin.json"))) {
            roots.push(child);
        }
    }
    return roots;
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

function extractScripts(value: JsonValue | undefined): Readonly<Record<string, string>> {
    if (!isJsonObject(value)) {
        return {};
    }

    const scripts: Record<string, string> = {};
    for (const [key, scriptPath] of Object.entries(value)) {
        if (typeof scriptPath === "string") {
            scripts[key] = scriptPath;
        }
    }
    return scripts;
}

function extractDefaultConfig(value: JsonValue | undefined): JsonObject {
    if (!isJsonObject(value)) {
        return {};
    }

    const defaults: JsonObject = {};
    for (const [key, configValue] of Object.entries(value)) {
        if (!isJsonObject(configValue)) {
            defaults[key] = cloneJsonValue(configValue);
            continue;
        }

        // Mirrors ExtensionManager.getCombinedConfigs: descriptor objects are
        // ignored unless they explicitly contain a `default` key (including
        // `default: null`).
        if (Object.prototype.hasOwnProperty.call(configValue, "default")) {
            defaults[key] = cloneJsonValue(configValue.default);
        }
    }
    return defaults;
}

function parentUri(uri: vscode.Uri): vscode.Uri {
    const path = trimmedUriPath(uri);
    const index = path.lastIndexOf("/");
    if (index <= 0) {
        return uri.with({ path: "/" });
    }
    return uri.with({ path: path.slice(0, index) });
}

function trimmedUriPath(uri: vscode.Uri): string {
    const path = uri.path.replace(/\/+$/, "");
    return path || "/";
}

function comparablePath(uri: vscode.Uri): string {
    const path = trimmedUriPath(uri);
    return uri.scheme === "file" ? path.toLowerCase() : path;
}

function compareText(left: string, right: string): number {
    return left < right ? -1 : left > right ? 1 : 0;
}

function displayUri(uri: vscode.Uri): string {
    return uri.fsPath || uri.toString(true);
}
