import * as vscode from "vscode";

import {
    cloneJsonValue,
    declaredScriptKey,
    ExtensionManifest,
    isJsonObject,
    isJsonValue,
    JsonObject,
    JsonValue,
    ResolvedExtensionScript,
    resolveExtensionScript,
    resolveManifestScript,
} from "./manifest";

export type DebugRunMode = "installed" | "draft";
export type ManifestScriptKind = "search" | "detail" | "toc" | "chap" | "page" | "genre" | "home";

export interface SearchRunProfile {
    readonly kind: "search";
    readonly query: string;
    readonly page: number;
    readonly config?: JsonObject;
}

export interface UrlRunProfile {
    readonly kind: "detail" | "toc" | "chap" | "page";
    /** Kept raw so JSExecutor on the app can resolve it with host. */
    readonly url: string;
    readonly host?: string;
    readonly config?: JsonObject;
}

export interface NoArgumentRunProfile {
    readonly kind: "genre" | "home";
    readonly config?: JsonObject;
}

/** Mirrors ExtensionManager.executeCustomScript(input, page, pageUrl). */
export interface CustomRunProfile {
    readonly kind: "custom";
    readonly scriptPath: string;
    readonly input: string;
    readonly page: number;
    readonly pageUrl?: string;
    readonly config?: JsonObject;
}

/** A non-manifest script is always a draft and receives generic JSON arguments. */
export interface DraftScriptRunProfile {
    readonly kind: "draftScript";
    readonly scriptPath: string;
    readonly arguments: readonly JsonValue[];
    readonly config?: JsonObject;
}

export type RunProfile =
    | SearchRunProfile
    | UrlRunProfile
    | NoArgumentRunProfile
    | CustomRunProfile
    | DraftScriptRunProfile;

export interface SavedRunProfile {
    readonly id: string;
    readonly name: string;
    /** Allows the command layer to filter profiles for the selected extension. */
    readonly packageId?: string;
    readonly profile: RunProfile;
    readonly createdAt: number;
    readonly updatedAt: number;
}

export interface ResolvedRunProfile {
    readonly mode: DebugRunMode;
    readonly kind: RunProfile["kind"];
    readonly script: ResolvedExtensionScript;
    /** Exact execute(...) arguments, ready for a protocol payload. */
    readonly arguments: readonly JsonValue[];
    /** App-side URL resolution context; client never constructs an absolute URL. */
    readonly urlContext?: Readonly<{ url: string; host?: string }>;
    /** Retains app-level custom pagination fields alongside execute arguments. */
    readonly customContext?: Readonly<{ input: string; page: number; pageUrl?: string }>;
    /** Same shallow merge as ExtensionManager.getCombinedConfigs. */
    readonly config: JsonObject;
}

export class RunProfileError extends Error {
    public constructor(message: string) {
        super(message);
        this.name = "RunProfileError";
    }
}

/** Resolves a profile into the exact VBook execute contract. */
export async function resolveRunProfile(
    manifest: ExtensionManifest,
    mode: DebugRunMode,
    profile: RunProfile,
): Promise<ResolvedRunProfile> {
    const config = mergeConfigs(manifest.defaultConfig, profile.config);

    switch (profile.kind) {
        case "search":
            return {
                mode,
                kind: profile.kind,
                script: await resolveManifestScript(manifest, "search"),
                // ExtensionManager deliberately passes page as String(page).
                arguments: [profile.query, String(requirePage(profile.page))],
                config,
            };

        case "detail":
        case "toc":
        case "chap":
        case "page":
            return {
                mode,
                kind: profile.kind,
                script: await resolveManifestScript(manifest, profile.kind),
                arguments: [profile.url],
                urlContext: withoutEmptyHost(profile.url, profile.host),
                config,
            };

        case "genre":
        case "home":
            return {
                mode,
                kind: profile.kind,
                script: await resolveManifestScript(manifest, profile.kind),
                arguments: [],
                config,
            };

        case "custom":
            return resolveCustomRunProfile(manifest, mode, profile, config);

        case "draftScript":
            if (mode !== "draft") {
                throw new RunProfileError("Script không khai trong plugin.json chỉ có thể chạy ở chế độ draft.");
            }
            if (!profile.arguments.every(isJsonValue)) {
                throw new RunProfileError("Arguments của draft script phải là JSON hợp lệ.");
            }
            return {
                mode,
                kind: profile.kind,
                script: await resolveExtensionScript(manifest.root, profile.scriptPath),
                arguments: profile.arguments.map((argument) => cloneJsonValue(argument)),
                config,
            };
    }
}

/**
 * Memento-backed storage deliberately stores only profiles. Pairing tokens and
 * sessions belong in SecretStorage and must never enter this data structure.
 */
export class RunProfileStore {
    public constructor(
        private readonly workspaceState: vscode.Memento,
        private readonly storageKey = "freebookExtDebug.runProfiles.v1",
    ) {}

    public list(packageId?: string): readonly SavedRunProfile[] {
        return this.readAll()
            .filter((entry) => !packageId || !entry.packageId || entry.packageId === packageId)
            .sort((left, right) => left.name.localeCompare(right.name));
    }

    public get(id: string): SavedRunProfile | undefined {
        return this.readAll().find((entry) => entry.id === id);
    }

    public async save(
        name: string,
        profile: RunProfile,
        options: Readonly<{ id?: string; packageId?: string }> = {},
    ): Promise<SavedRunProfile> {
        const normalizedName = name.trim();
        if (!normalizedName) {
            throw new RunProfileError("Tên profile không được để trống.");
        }

        const all = this.readAll();
        const existing = options.id ? all.find((entry) => entry.id === options.id) : undefined;
        const now = Date.now();
        const entry: SavedRunProfile = {
            id: existing?.id ?? createProfileId(),
            name: normalizedName,
            packageId: options.packageId,
            profile: cloneRunProfile(profile),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
        };

        const next = existing
            ? all.map((candidate) => candidate.id === existing.id ? entry : candidate)
            : [...all, entry];
        await this.workspaceState.update(this.storageKey, next);
        return entry;
    }

    public async delete(id: string): Promise<boolean> {
        const all = this.readAll();
        const next = all.filter((entry) => entry.id !== id);
        if (next.length === all.length) {
            return false;
        }
        await this.workspaceState.update(this.storageKey, next);
        return true;
    }

    private readAll(): SavedRunProfile[] {
        const stored = this.workspaceState.get<unknown>(this.storageKey, []);
        if (!Array.isArray(stored)) {
            return [];
        }
        return stored.flatMap((value) => {
            const parsed = parseSavedRunProfile(value);
            return parsed ? [parsed] : [];
        });
    }
}

/** Parses untrusted Memento data into a JSON-safe profile. */
export function parseRunProfile(value: unknown): RunProfile | undefined {
    if (!isJsonObject(value) || typeof value.kind !== "string") {
        return undefined;
    }

    const config = readConfig(value.config);
    switch (value.kind) {
        case "search":
            return typeof value.query === "string" && isPage(value.page)
                ? { kind: "search", query: value.query, page: value.page, config }
                : undefined;
        case "detail":
        case "toc":
        case "chap":
        case "page":
            return typeof value.url === "string" && optionalString(value.host)
                ? { kind: value.kind, url: value.url, host: value.host as string | undefined, config }
                : undefined;
        case "genre":
        case "home":
            return { kind: value.kind, config };
        case "custom":
            return typeof value.scriptPath === "string"
                && typeof value.input === "string"
                && isPage(value.page)
                && optionalString(value.pageUrl)
                ? {
                    kind: "custom",
                    scriptPath: value.scriptPath,
                    input: value.input,
                    page: value.page,
                    pageUrl: value.pageUrl as string | undefined,
                    config,
                }
                : undefined;
        case "draftScript":
            return typeof value.scriptPath === "string"
                && Array.isArray(value.arguments)
                && value.arguments.every(isJsonValue)
                ? { kind: "draftScript", scriptPath: value.scriptPath, arguments: value.arguments, config }
                : undefined;
        default:
            return undefined;
    }
}

async function resolveCustomRunProfile(
    manifest: ExtensionManifest,
    mode: DebugRunMode,
    profile: CustomRunProfile,
    config: JsonObject,
): Promise<ResolvedRunProfile> {
    const script = await resolveExtensionScript(manifest.root, profile.scriptPath);
    const key = await declaredScriptKey(manifest, script);
    if (mode === "installed" && !key) {
        throw new RunProfileError("Script không khai trong plugin.json chỉ có thể chạy ở chế độ draft.");
    }

    const page = requirePage(profile.page);
    const formattedInput = profile.input.replace(/\{0\}/g, String(page));
    const pageArgument = page === 1 ? "" : (profile.pageUrl ?? "");
    return {
        mode,
        kind: profile.kind,
        script: key ? { ...script, manifestKey: key } : script,
        arguments: [formattedInput, pageArgument],
        customContext: { input: profile.input, page, pageUrl: profile.pageUrl },
        config,
    };
}

function mergeConfigs(defaultConfig: JsonObject, override: JsonObject | undefined): JsonObject {
    const merged = cloneJsonValue(defaultConfig);
    if (!override) {
        return merged;
    }
    for (const [key, value] of Object.entries(override)) {
        merged[key] = cloneJsonValue(value);
    }
    return merged;
}

function withoutEmptyHost(url: string, host: string | undefined): Readonly<{ url: string; host?: string }> {
    return host ? { url, host } : { url };
}

function requirePage(page: number): number {
    if (!isPage(page)) {
        throw new RunProfileError("Page phải là số nguyên dương.");
    }
    return page;
}

function isPage(value: unknown): value is number {
    return typeof value === "number" && Number.isSafeInteger(value) && value >= 1;
}

function readConfig(value: unknown): JsonObject | undefined {
    return isJsonObject(value) ? cloneJsonValue(value) : undefined;
}

function optionalString(value: unknown): boolean {
    return value === undefined || typeof value === "string";
}

function parseSavedRunProfile(value: unknown): SavedRunProfile | undefined {
    if (!isJsonObject(value)
        || typeof value.id !== "string"
        || typeof value.name !== "string"
        || !optionalString(value.packageId)
        || typeof value.createdAt !== "number"
        || typeof value.updatedAt !== "number") {
        return undefined;
    }

    const profile = parseRunProfile(value.profile);
    if (!profile) {
        return undefined;
    }
    return {
        id: value.id,
        name: value.name,
        packageId: value.packageId as string | undefined,
        profile,
        createdAt: value.createdAt,
        updatedAt: value.updatedAt,
    };
}

function cloneRunProfile(profile: RunProfile): RunProfile {
    return parseRunProfile(JSON.parse(JSON.stringify(profile))) ?? profile;
}

function createProfileId(): string {
    return `run-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}
