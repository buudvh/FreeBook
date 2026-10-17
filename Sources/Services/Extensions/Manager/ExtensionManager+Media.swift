import Foundation
import JavaScriptCore

/// Hàm script có **kiểu** cho tiện ích truyện tranh và video.
///
/// Tách khỏi `chap()` (bất biến 2 của plan comic/video): `chap()` trả `String` cho Reader chữ và
/// `BookDownloadWorker`, còn media cần danh sách ảnh/server/track có cấu trúc và **không** được đi qua
/// pipeline text (`ChapterContentRepository`, `ChapterTextNormalizer`, `cleanHTML`, JunkFilter, dịch, TTS).
///
/// Mỗi lần gọi tạo một `JSExecutor` mới rồi giải phóng, như mọi hàm script khác của `ExtensionManager`.
extension ExtensionManager {
    /// Danh sách ảnh của một chương truyện tranh — script `chap`, tham số là URL chương đã `cleanAndResolveUrl`.
    /// Ảnh có URL tương đối được ghép theo `host` (thiếu thì theo origin của URL chương).
    public func comicPages(
        localPath: String,
        downloadUrl: String = "",
        url: String,
        host: String? = nil,
        configJson: String = "{}"
    ) async throws -> [ComicPageSource] {
        let resolvedUrl = JSExecutor.cleanAndResolveUrl(url, host: host)
        let imageHost = Self.nonEmptyHost(host) ?? Self.origin(of: resolvedUrl)
        return try await runMediaScript(
            action: "chap",
            localPath: localPath,
            downloadUrl: downloadUrl,
            argument: resolvedUrl,
            logArguments: "arguments=[\(resolvedUrl)], url=\(url), host=\(host ?? "nil"), configJson=\(configJson)",
            diagnosticsInput: url,
            configJson: configJson
        ) { cleanVal in
            let pages = ComicPageMapper.map(cleanVal, host: imageHost)
            guard !pages.isEmpty else {
                throw Self.emptyMediaError("Chương truyện tranh không có ảnh nào", localPath: localPath, script: "chap")
            }
            return (pages, "Parsed \(pages.count) images")
        }
    }

    /// Danh sách server phát của một tập — script `chap`, tham số là URL tập đã `cleanAndResolveUrl`.
    public func videoServers(
        localPath: String,
        downloadUrl: String = "",
        url: String,
        host: String? = nil,
        configJson: String = "{}"
    ) async throws -> [VideoServer] {
        let resolvedUrl = JSExecutor.cleanAndResolveUrl(url, host: host)
        return try await runMediaScript(
            action: "chap",
            localPath: localPath,
            downloadUrl: downloadUrl,
            argument: resolvedUrl,
            logArguments: "arguments=[\(resolvedUrl)], url=\(url), host=\(host ?? "nil"), configJson=\(configJson)",
            diagnosticsInput: url,
            configJson: configJson
        ) { cleanVal in
            let servers = VideoTrackMapper.servers(from: cleanVal)
            guard !servers.isEmpty else {
                throw Self.emptyMediaError("Tập phim không có server phát nào", localPath: localPath, script: "chap")
            }
            return (servers, "Parsed \(servers.count) servers")
        }
    }

    /// Nguồn phát của một server — script `track`. `data` truyền **nguyên văn** (opaque), không
    /// `cleanAndResolveUrl`, không trim. Log chỉ ghi độ dài vì `data` có thể chứa token.
    public func videoTrack(
        localPath: String,
        downloadUrl: String = "",
        data: String,
        configJson: String = "{}"
    ) async throws -> VideoTrack {
        try await runMediaScript(
            action: "track",
            localPath: localPath,
            downloadUrl: downloadUrl,
            argument: data,
            logArguments: "arguments=[data: \(data.utf16.count) ký tự], configJson=\(configJson)",
            diagnosticsInput: "data: \(data.utf16.count) ký tự",
            configJson: configJson
        ) { cleanVal in
            let track = try VideoTrackMapper.track(from: cleanVal)
            return (track, "Track \(track.kind.rawValue), \(track.subtitles.count) subtitles, \(track.timeSkips.count) time skips")
        }
    }

    // MARK: - Helpers

    /// Chạy `execute(argument)` của script `action` rồi ánh xạ **trong lúc executor còn sống** (JSValue gắn với
    /// `JSContext` của executor). `map` trả kết quả kèm dòng chi tiết cho `AppDiagnostics`.
    private func runMediaScript<T>(
        action: String,
        localPath: String,
        downloadUrl: String,
        argument: String,
        logArguments: String,
        diagnosticsInput: String,
        configJson: String,
        map: (JSValue) throws -> (T, String)
    ) async throws -> T {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: action)
        let scriptName = scriptUrl.lastPathComponent
        AppLogger.shared.log("🔍 [ExtensionManager][\(scriptName)]: \(logArguments)")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)

        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)

        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [argument])
            let cleanVal = try verifyJSResponse(jsValue, extName: URL(fileURLWithPath: localPath).lastPathComponent, scriptName: action)
            let (result, details) = try map(cleanVal)
            updateDiagnostics(action: action, input: diagnosticsInput, status: "Success", details: details)
            return result
        } catch {
            updateDiagnostics(action: action, input: diagnosticsInput, status: "Error", details: error.localizedDescription)
            throw error
        }
    }

    private static func emptyMediaError(_ message: String, localPath: String, script: String) -> ExtensionManagerError {
        let extName = URL(fileURLWithPath: localPath).lastPathComponent
        AppLogger.shared.log("❌ [\(extName) - \(script)] \(message)")
        return ExtensionManagerError.sourceResponse(message: message)
    }

    private static func nonEmptyHost(_ host: String?) -> String? {
        guard let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// `https://a.com/x/y` → `https://a.com`; `nil` khi không parse được.
    private static func origin(of url: String) -> String? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              let host = components.host else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
