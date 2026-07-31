import Foundation
import SwiftData

@MainActor
public final class GetTextSTVManager {
    public static let shared = GetTextSTVManager()

    private init() {}

    /// Kiểm tra URL có thuộc dải tên miền/IP của SangTacViet hay không
    public func isSangTacVietURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        let matches = [
            "sangtacviet.com",
            "sangtacviet.vn",
            "sangtacviet.vip",
            "sangtacviet.app",
            "14.225.254.182",
            "103.82.20.93"
        ]
        return matches.contains { host.contains($0) || urlString.contains($0) }
    }

    /// Nạp kịch bản content.css và content.js từ Resources dự án kèm bộ Polyfill Safari iPhone (WKWebView)
    public func loadExtensionScripts() -> (css: String, js: String) {
        var cssContent = ""
        var jsContent = ""

        // 1. Thử nạp độc lập từ Bundle ứng dụng
        if let cssUrl = Bundle.main.url(forResource: "content", withExtension: "css", subdirectory: "GetTextSTV")
            ?? Bundle.main.url(forResource: "content", withExtension: "css") {
            cssContent = (try? String(contentsOf: cssUrl, encoding: .utf8)) ?? ""
        }

        if let jsUrl = Bundle.main.url(forResource: "content", withExtension: "js", subdirectory: "GetTextSTV")
            ?? Bundle.main.url(forResource: "content", withExtension: "js") {
            jsContent = (try? String(contentsOf: jsUrl, encoding: .utf8)) ?? ""
        }

        // 2. Dự phòng nạp từ các đường dẫn tương đối dự án nếu Bundle chưa có
        if cssContent.isEmpty {
            let candidatesCss = [
                "Sources/Resources/GetTextSTV/content.css",
                "content.css"
            ]
            for path in candidatesCss {
                if let str = try? String(contentsOfFile: path, encoding: .utf8), !str.isEmpty {
                    cssContent = str
                    break
                }
            }
        }

        if jsContent.isEmpty {
            let candidatesJs = [
                "Sources/Resources/GetTextSTV/content.js",
                "content.js"
            ]
            for path in candidatesJs {
                if let str = try? String(contentsOfFile: path, encoding: .utf8), !str.isEmpty {
                    jsContent = str
                    break
                }
            }
        }

        let polyfillHeader = """

        // --- SAFARI IPHONE (WKWEBVIEW) POLYFILL & NATIVE BRIDGE ---
        (function() {
            var host = location.hostname.toLowerCase();
            var href = location.href.toLowerCase();
            var stvMatches = ["sangtacviet.com", "sangtacviet.vn", "sangtacviet.vip", "sangtacviet.app", "14.225.254.182", "103.82.20.93"];
            var isSTV = stvMatches.some(function(m) { return host.indexOf(m) !== -1 || href.indexOf(m) !== -1; });
            if (!isSTV) return;

            if (typeof window.chrome === "undefined" || !window.chrome.storage) {
                window.chrome = window.chrome || {};
                window.chrome.runtime = window.chrome.runtime || {
                    lastError: null,
                    sendMessage: function(msg, cb) {
                        try {
                            var payload = Object.assign({}, msg || {});
                            if (payload.type === "GETTEXT_STV_SAVE_CHAPTER") {
                                payload.action = "saveChapterContent";
                            } else if (payload.type === "GETTEXT_STV_TOC_LOADED" || payload.toc) {
                                payload.action = "syncTOC";
                                payload.tocChapters = payload.toc || payload.chapters || [];
                            } else if (!payload.action) {
                                payload.action = payload.type || "syncTOC";
                            }
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gettextSTVBridge) {
                                window.webkit.messageHandlers.gettextSTVBridge.postMessage(payload);
                            }
                        } catch(e) {
                            console.error("STV Bridge Post Error:", e);
                        }
                        if (cb) cb({ ok: true });
                    },
                    onMessage: {
                        addListener: function() {}
                    }
                };
                window.chrome.storage = {
                    local: {
                        get: function(keys, callback) {
                            var res = {};
                            try {
                                if (typeof keys === "string") keys = [keys];
                                if (Array.isArray(keys)) {
                                    keys.forEach(function(k) {
                                        var val = localStorage.getItem("stv_" + k);
                                        if (val !== null) {
                                            try { res[k] = JSON.parse(val); } catch(e) { res[k] = val; }
                                        }
                                    });
                                } else if (keys && typeof keys === "object") {
                                    Object.keys(keys).forEach(function(k) {
                                        var val = localStorage.getItem("stv_" + k);
                                        res[k] = (val !== null) ? JSON.parse(val) : keys[k];
                                    });
                                }
                            } catch(e) {}
                            if (callback) callback(res);
                            return Promise.resolve(res);
                        },
                        set: function(items, callback) {
                            try {
                                Object.keys(items).forEach(function(k) {
                                    localStorage.setItem("stv_" + k, JSON.stringify(items[k]));
                                });
                            } catch(e) {}
                            if (callback) callback();
                            return Promise.resolve();
                        },
                        remove: function(keys, callback) {
                            try {
                                if (typeof keys === "string") keys = [keys];
                                if (Array.isArray(keys)) {
                                    keys.forEach(function(k) { localStorage.removeItem("stv_" + k); });
                                }
                            } catch(e) {}
                            if (callback) callback();
                            return Promise.resolve();
                        }
                    }
                };
            }

            // Gửi dữ liệu về Native FreeBook qua WKScriptMessageHandler
            window.sendFreeBookPayload = function(actionType, extraData) {
                try {
                    var info = (typeof getChapterInfo === 'function') ? getChapterInfo() : {};
                    var payload = Object.assign({
                        action: actionType || "syncTOC",
                        bookId: info.bookId || info.host || "stv_novel",
                        bookTitle: info.bookTitle || document.title,
                        chapterTitle: info.chapterTitle || "",
                        chapterId: info.chapterId || "",
                        host: info.host || location.hostname,
                        url: info.url || location.href
                    }, extraData || {});

                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gettextSTVBridge) {
                        window.webkit.messageHandlers.gettextSTVBridge.postMessage(payload);
                    }
                } catch(e) {
                    console.error("FreeBook Bridge Error:", e);
                }
            };

            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gettextSTVBridge) {
                    window.webkit.messageHandlers.gettextSTVBridge.postMessage({
                        action: "log",
                        message: "✅ [GetTextSTV] Khởi tạo thành công Polyfill + content.js + content.css trên trang: " + location.href
                    });
                }
            } catch(e) {}
        })();
        """

        jsContent = polyfillHeader + "\n" + jsContent
        return (cssContent, jsContent)
    }

    /// Bước 1: Nạp Mục lục & Cập nhật Metadata các chương mới vào SwiftData Local DB (`syncTOC`)
    public func syncTOCFromExtension(
        bookId: String,
        title: String,
        author: String = "Sáng Tác Việt",
        coverUrl: String = "",
        desc: String = "",
        sourceUrl: String,
        host: String? = nil,
        tocChapters: [[String: Any]],
        container: ModelContainer
    ) async throws -> String {
        let cleanBookId = "stv_" + (bookId.isEmpty ? String(sourceUrl.hashValue) : bookId)
        let sourceName = "Sáng Tác Việt"
        let extensionPackageId = "local_stv"

        var snapshots: [ChapterMetadataSnapshot] = []
        for (idx, dict) in tocChapters.enumerated() {
            let chapTitle = (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Chương \(idx + 1)"
            let chapUrl = (dict["url"] as? String) ?? "\(sourceUrl)#chap_\(idx + 1)"
            snapshots.append(ChapterMetadataSnapshot(
                title: chapTitle,
                url: chapUrl,
                index: idx,
                host: host
            ))
        }

        let createSnapshot = TOCBookCreateSnapshot(
            bookId: cleanBookId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            desc: desc,
            detailUrl: sourceUrl,
            sourceName: sourceName,
            sourceUrl: sourceUrl,
            extensionPackageId: extensionPackageId,
            currentChapterIndex: 0,
            currentChapterPage: 0,
            currentChapterTitle: snapshots.first?.title ?? "",
            isOnShelf: true,
            isHistory: true,
            host: host
        )

        _ = try await ChapterContentRepository.shared.saveChapterList(
            bookId: cleanBookId,
            createSnapshot: createSnapshot,
            chapters: snapshots,
            mode: .replaceFullTOC
        )

        return cleanBookId
    }

    /// Bước 2: Lưu nội dung từng chương chưa có vào đĩa nhị phân `.bin` (`saveChapterContent`)
    public func saveChapterContentFromExtension(
        bookId: String,
        chapterIndex: Int,
        chapterTitle: String,
        chapterUrl: String,
        content: String,
        container: ModelContainer
    ) async throws {
        let cleanBookId = bookId.hasPrefix("stv_") ? bookId : "stv_" + bookId
        let metadata = ChapterMetadataSnapshot(
            title: chapterTitle,
            url: chapterUrl,
            index: chapterIndex
        )

        let key = Chapter.generateId(bookId: cleanBookId, url: chapterUrl, index: chapterIndex)
        let store = ChapterPersistenceStore(container: container)
        let noBookSnapshot: BookMetadataSnapshot? = nil
        await store.enqueueWrite(
            key: key,
            bookId: cleanBookId,
            book: noBookSnapshot,
            chapter: metadata,
            content: content
        )
        await store.flush(bookId: cleanBookId)
    }
}
