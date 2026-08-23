import * as vscode from "vscode";

import {
    declaredScriptKey,
    ExtensionManifest,
    isJsonValue,
    type JsonValue,
    ResolvedExtensionScript,
} from "./manifest";
import {
    type DebugRunMode,
    type RunProfile,
} from "./profiles";

/** Prompts only for the typed inputs that ExtensionManager passes to execute(...). */
export async function promptRunProfile(
    manifest: ExtensionManifest,
    script: ResolvedExtensionScript,
): Promise<RunProfile | undefined> {
    const scriptKey = script.manifestKey ?? await declaredScriptKey(manifest, script);

    switch (scriptKey) {
        case "search":
            return promptSearchProfile();
        case "detail":
        case "toc":
        case "chap":
        case "page":
            return promptUrlProfile(scriptKey);
        case "genre":
        case "home":
            return { kind: scriptKey };
        case "custom":
            return promptCustomProfile(script.relativePath);
        default:
            return scriptKey
                ? promptDeclaredCustomOrDraftProfile(script.relativePath)
                : promptDraftScriptProfile(script.relativePath);
    }
}

export async function selectRunMode(
    installedAvailable: boolean,
    draftOnly: boolean,
): Promise<DebugRunMode | undefined> {
    if (draftOnly) {
        await vscode.window.showInformationMessage(
            "Script không khai trong plugin.json chỉ chạy được ở chế độ draft.",
        );
        return "draft";
    }

    const choices: vscode.QuickPickItem[] = [
        {
            label: "Draft",
            description: "Stage toàn bộ file đã lưu rồi chạy bản nháp",
        },
    ];
    if (installedAvailable) {
        choices.unshift({
            label: "Installed",
            description: "Chạy extension đã cài có package ID khớp",
        });
    }

    const picked = await vscode.window.showQuickPick(choices, {
        title: "FreeBook Ext Debug: Chọn đích chạy",
        placeHolder: installedAvailable
            ? "Installed dùng extension trên app; Draft stage file đã lưu."
            : "Không có extension đã cài khớp package ID; chỉ có Draft.",
    });
    return picked?.label === "Installed" ? "installed" : picked ? "draft" : undefined;
}

export function isDraftOnlyProfile(profile: RunProfile): boolean {
    return profile.kind === "draftScript";
}

export function describeRunProfile(profile: RunProfile): string {
    switch (profile.kind) {
        case "search":
            return `search: ${profile.query} (page ${profile.page})`;
        case "detail":
        case "toc":
        case "chap":
        case "page":
            return `${profile.kind}: ${profile.url}`;
        case "genre":
        case "home":
            return `${profile.kind}: execute()`;
        case "custom":
            return `custom: ${profile.scriptPath} (page ${profile.page})`;
        case "draftScript":
            return `draft script: ${profile.scriptPath}`;
    }
}

function promptSearchProfile(): Promise<RunProfile | undefined> {
    return (async () => {
        const query = await requiredInput("Từ khóa tìm kiếm", "Nhập query truyền vào execute(query, String(page)).");
        if (query === undefined) {
            return undefined;
        }
        const page = await positivePage("Trang tìm kiếm", "Trang được gửi dưới dạng chuỗi cho execute(query, String(page)).");
        return page === undefined ? undefined : { kind: "search", query, page };
    })();
}

function promptUrlProfile(kind: "detail" | "toc" | "chap" | "page"): Promise<RunProfile | undefined> {
    return (async () => {
        const url = await requiredInput(
            `${kind}: URL hoặc path`,
            "Giữ nguyên URL/path; FreeBook App sẽ tự resolve theo host.",
        );
        if (url === undefined) {
            return undefined;
        }
        const host = await vscode.window.showInputBox({
            title: `FreeBook Ext Debug: ${kind}`,
            prompt: "Host tùy chọn để app tự resolve URL/path",
            placeHolder: "https://example.com",
        });
        if (host === undefined) {
            return undefined;
        }
        const normalizedHost = host.trim();
        return { kind, url, ...(normalizedHost ? { host: normalizedHost } : {}) };
    })();
}

function promptCustomProfile(scriptPath: string): Promise<RunProfile | undefined> {
    return (async () => {
        const input = await requiredInput(
            "Custom input",
            "{0} sẽ được app thay bằng page trước khi gọi execute(input, pageUrl).",
        );
        if (input === undefined) {
            return undefined;
        }
        const page = await positivePage("Custom page", "Page dùng cho {0}; page 1 gửi pageUrl rỗng.");
        if (page === undefined) {
            return undefined;
        }
        const pageUrl = await vscode.window.showInputBox({
            title: "FreeBook Ext Debug: Custom",
            prompt: "pageUrl tùy chọn (page > 1)",
        });
        if (pageUrl === undefined) {
            return undefined;
        }
        const normalizedPageUrl = pageUrl.trim();
        return {
            kind: "custom",
            scriptPath,
            input,
            page,
            ...(normalizedPageUrl ? { pageUrl: normalizedPageUrl } : {}),
        };
    })();
}

function promptDraftScriptProfile(scriptPath: string): Promise<RunProfile | undefined> {
    return (async () => {
        const rawArguments = await vscode.window.showInputBox({
            title: "FreeBook Ext Debug: Draft script",
            prompt: "Mảng JSON arguments truyền nguyên vẹn vào execute(...)",
            value: "[]",
            validateInput: (value) => parseArguments(value) ? undefined : "Nhập một mảng JSON hợp lệ.",
        });
        if (rawArguments === undefined) {
            return undefined;
        }
        const argumentsValue = parseArguments(rawArguments);
        if (!argumentsValue) {
            return undefined;
        }
        return { kind: "draftScript", scriptPath, arguments: argumentsValue };
    })();
}

async function promptDeclaredCustomOrDraftProfile(scriptPath: string): Promise<RunProfile | undefined> {
    const choice = await vscode.window.showQuickPick([
        {
            label: "Custom pagination",
            description: "execute(input thay {0}, pageUrl) theo ExtensionManager",
        },
        {
            label: "Draft generic JSON",
            description: "Chỉ stage draft; gửi arguments JSON nguyên vẹn vào execute(...)",
        },
    ], {
        title: "FreeBook Ext Debug: Chọn contract chạy script",
    });
    if (!choice) {
        return undefined;
    }
    return choice.label === "Custom pagination"
        ? promptCustomProfile(scriptPath)
        : promptDraftScriptProfile(scriptPath);
}

async function requiredInput(title: string, prompt: string): Promise<string | undefined> {
    const value = await vscode.window.showInputBox({
        title: `FreeBook Ext Debug: ${title}`,
        prompt,
        validateInput: (input) => input.trim() ? undefined : "Không được để trống.",
    });
    return value === undefined ? undefined : value.trim();
}

async function positivePage(title: string, prompt: string): Promise<number | undefined> {
    const value = await vscode.window.showInputBox({
        title: `FreeBook Ext Debug: ${title}`,
        prompt,
        value: "1",
        validateInput: (input) => parsePositivePage(input) === undefined ? "Nhập số nguyên dương." : undefined,
    });
    return value === undefined ? undefined : parsePositivePage(value);
}

function parsePositivePage(value: string): number | undefined {
    if (!/^\d+$/.test(value.trim())) {
        return undefined;
    }
    const page = Number(value.trim());
    return Number.isSafeInteger(page) && page >= 1 ? page : undefined;
}

function parseArguments(value: string): readonly JsonValue[] | undefined {
    try {
        const parsed: unknown = JSON.parse(value);
        return Array.isArray(parsed) && parsed.every(isJsonValue) ? parsed : undefined;
    } catch {
        return undefined;
    }
}
