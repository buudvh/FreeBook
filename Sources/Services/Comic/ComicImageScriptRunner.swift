import Foundation
import JavaScriptCore

/// Chạy script ảnh của comic (`{link, script:"image.js"}`, vd cuutruyen ráp tile qua `Graphics`).
///
/// - Giữ **một** `JSExecutor` cho mỗi (thư mục tiện ích, script, cấu hình) tới khi `releaseAll()` — gọi khi rời
///   chương / đóng màn đọc, giống `BookDownloadWorker` giữ executor theo một tác vụ. Không dùng executor chung
///   giữa các tiện ích.
/// - Mọi lời gọi được **tuần tự hoá** (`acquireTurn`): actor tái nhập ở mỗi `await`, nên thiếu lượt khoá thì hai
///   ảnh có thể cùng lái một `JSContext` (trạng thái `beginExecution`/`exception`/huỷ giẫm lên nhau).
/// - `execute(link)` trả base64 trần, hoặc `Response.success(b64)`, hoặc chuỗi `data:…;base64,…`.
actor ComicImageScriptRunner {
    private struct Key: Hashable {
        let localPath: String
        let script: String
        let configJson: String
    }

    private var executors: [Key: JSExecutor] = [:]
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(
        script: String,
        link: String,
        localPath: String,
        downloadUrl: String,
        configJson: String
    ) async throws -> Data {
        await acquireTurn()
        defer { releaseTurn() }
        try Task.checkCancellation()

        // Nguồn Legado có `imageDecode` (spec §8.6): tải + giải mã bằng engine của nguồn, không có file script.
        if script == SourceRuntime.legadoImageDecodeScriptName {
            return try await SourceRuntime.shared.legadoDecodedImage(localPath: localPath, link: link)
        }

        let key = Key(localPath: localPath, script: script, configJson: configJson)
        let executor = try preparedExecutor(for: key, downloadUrl: downloadUrl)
        resetGraphics(of: executor)
        defer { resetGraphics(of: executor) }

        do {
            let value = try await executor.callAsync(functionName: "execute", arguments: [link])
            try Task.checkCancellation()
            let payload = try Self.extractPayload(from: value, script: script)
            guard let data = Self.decodeImagePayload(payload), !data.isEmpty else {
                throw Self.error("Script ảnh \(script) không trả về base64 ảnh hợp lệ")
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Lỗi JS/mạng: bỏ executor để ảnh kế tiếp chạy trên context sạch (giống `BookDownloadWorker`).
            if executors[key] === executor {
                executor.cancelCurrentExecution()
                executors[key] = nil
            }
            throw error
        }
    }

    /// Nhả mọi executor. Lời gọi đang chạy vẫn giữ tham chiếu riêng tới executor của nó nên chạy nốt bình thường;
    /// huỷ thật sự đi qua `Task.cancel()` của caller (`callAsync` tự `cancelCurrentExecution`).
    func releaseAll() {
        if !executors.isEmpty {
            AppLogger.shared.log("🧹 [ComicImageScriptRunner] Giải phóng \(executors.count) executor script ảnh")
        }
        executors.removeAll()
    }

    // MARK: - Executor

    private func preparedExecutor(for key: Key, downloadUrl: String) throws -> JSExecutor {
        if let existing = executors[key] {
            return existing
        }
        let scriptURL = try Self.scriptURL(localPath: key.localPath, fileName: key.script)
        let content = try String(contentsOf: scriptURL, encoding: .utf8)

        let executor = JSExecutor(localPath: key.localPath, downloadUrl: downloadUrl)
        executor.injectGlobals(ExtensionManager.shared.getCombinedConfigs(localPath: key.localPath, configJson: key.configJson))
        try executor.prepareScript(content)
        executors[key] = executor
        return executor
    }

    /// Ảnh/canvas `Graphics` chỉ sống trong một lượt `execute(link)`: không dọn thì mỗi trang để lại một ảnh đã giải mã.
    private func resetGraphics(of executor: JSExecutor) {
        executor.context.evaluateScript("if (typeof _nativeGraphicsReset === 'function') { _nativeGraphicsReset(); }")
    }

    /// Tìm script ở gốc tiện ích rồi `src/` — cùng quy tắc với `ExtensionManager.executeCustomScript`.
    static func scriptURL(localPath: String, fileName: String) throws -> URL {
        guard !fileName.contains(".."), !fileName.hasPrefix("/") else {
            throw error("Tên script ảnh không hợp lệ: \(fileName)")
        }
        let extUrl = URL(fileURLWithPath: localPath)
        let rootUrl = extUrl.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: rootUrl.path) {
            return rootUrl
        }
        let srcUrl = extUrl.appendingPathComponent("src").appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: srcUrl.path) {
            return srcUrl
        }
        throw error("Script file '\(fileName)' not found in root or src/")
    }

    // MARK: - Lượt chạy

    private func acquireTurn() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    /// Trao lượt thẳng cho người chờ kế tiếp (giữ `isBusy == true`) hoặc mở khoá khi không còn ai.
    private func releaseTurn() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    // MARK: - Kết quả

    /// Không đi qua `ExtensionManager.verifyJSResponse`: hàm đó log nguyên `data` khi tắt chế độ log gọn — ở đây là
    /// base64 ảnh. Bóc tay như `ExtTTSRuntime.extractAudioBase64`.
    private static func extractPayload(from value: JSValue, script: String) throws -> String {
        if value.isNull || value.isUndefined {
            throw error("Script ảnh \(script) trả về null/undefined")
        }
        if value.isObject {
            if let successValue = value.objectForKeyedSubscript("success"),
               !successValue.isUndefined, !successValue.isNull {
                guard successValue.toBool() else {
                    let messageValue = value.objectForKeyedSubscript("message")
                    let message = (messageValue != nil && !messageValue!.isUndefined && !messageValue!.isNull)
                        ? messageValue!.toString() ?? "Lỗi từ nguồn truyện"
                        : "Lỗi từ nguồn truyện"
                    AppLogger.shared.log("❌ [ComicImageScriptRunner][\(script)] Response.error: \(message)")
                    throw ExtensionManagerError.sourceResponse(message: message)
                }
                if let dataValue = value.objectForKeyedSubscript("data"),
                   !dataValue.isUndefined, !dataValue.isNull {
                    return dataValue.toString() ?? ""
                }
                return ""
            }
            if let errorValue = value.objectForKeyedSubscript("error"),
               !errorValue.isUndefined, !errorValue.isNull,
               let message = errorValue.toString(), !message.isEmpty {
                AppLogger.shared.log("❌ [ComicImageScriptRunner][\(script)] Response.error (field): \(message)")
                throw ExtensionManagerError.sourceResponse(message: message)
            }
        }
        return value.toString() ?? ""
    }

    /// Base64 trần hoặc URI `data:` → byte. Dùng chung cho kết quả script và phần tử `data:` trong `chap()`.
    static func decodeImagePayload(_ payload: String) -> Data? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.lowercased().hasPrefix("data:") else {
            return Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters)
        }
        guard let comma = trimmed.firstIndex(of: ",") else { return nil }
        let header = trimmed[trimmed.startIndex..<comma].lowercased()
        let body = String(trimmed[trimmed.index(after: comma)...])
        if header.contains(";base64") {
            return Data(base64Encoded: body, options: .ignoreUnknownCharacters)
        }
        return body.removingPercentEncoding.map { Data($0.utf8) }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "ComicImageScriptRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
