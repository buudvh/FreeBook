import Foundation
import JavaScriptCore

/// Runner nội bộ của Phase 1: chạy đúng `execute(...)` của extension đã cài, qua **cùng** bootstrap và
/// contract mà `ExtensionManager` dùng, nhưng có sink trace.
///
/// Hai điều kiện thiết kế:
/// 1. **Không có shared executor.** Mỗi run tạo một `JSExecutor` mới rồi thả — đúng kiến trúc hiện
///    tại; `ExtTTSRuntime` (executor sống lâu) không nằm trong phạm vi debug ở Phase 1.
/// 2. **Không sửa đường production.** Runner gọi lại `ExtensionManager.getScriptPath` /
///    `getCombinedConfigs` / `verifyJSResponse` (đều `internal`, cùng module) thay vì thêm tham số sink
///    cho 9 hàm public của manager. Nhờ vậy `search`/`detail`/… production không đổi một dòng nào.
public actor ExtensionDebugRunner {
    public static let shared = ExtensionDebugRunner()

    private var activeRuns: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public var activeRunIds: [UUID] {
        Array(activeRuns.keys)
    }

    /// Bắt đầu một run và trả `runId` ngay; trace đi qua `ExtensionDebugEventHub`.
    public func start(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        configJson: String,
        host: String?,
        entrypoint: ExtensionDebugEntrypoint,
        hub: ExtensionDebugEventHub = .shared
    ) -> UUID {
        let runId = UUID()
        let task = Task { [weak self] in
            await self?.execute(
                runId: runId,
                packageId: packageId,
                localPath: localPath,
                downloadUrl: downloadUrl,
                configJson: configJson,
                host: host,
                entrypoint: entrypoint,
                hub: hub
            )
            await self?.finish(runId: runId)
        }
        activeRuns[runId] = task
        return runId
    }

    public func cancel(runId: UUID) {
        activeRuns[runId]?.cancel()
    }

    public func cancelAll() {
        for task in activeRuns.values { task.cancel() }
    }

    private func finish(runId: UUID) {
        activeRuns.removeValue(forKey: runId)
    }

    // MARK: - Thân của một run

    private func execute(
        runId: UUID,
        packageId: String,
        localPath: String,
        downloadUrl: String,
        configJson: String,
        host: String?,
        entrypoint: ExtensionDebugEntrypoint,
        hub: ExtensionDebugEventHub
    ) async {
        let manager = ExtensionManager.shared
        let scriptKey = entrypoint.scriptKey

        // Giai đoạn resolve chưa có session (chưa biết revision) nên lỗi ở đây được báo bằng một
        // session tối thiểu — vẫn đúng runId để UI ghép được vào cùng một run.
        let scriptUrl: URL
        let scriptContent: String
        do {
            scriptUrl = try Self.resolveScript(entrypoint: entrypoint, localPath: localPath, manager: manager)
            scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        } catch {
            let session = ExtensionDebugSession(
                runId: runId,
                packageId: packageId,
                script: scriptKey,
                scriptPath: scriptKey,
                sourceRevision: "unresolved",
                hub: hub
            )
            session.emitError(.runFinished, message: "Không resolve được script: \(error.localizedDescription)")
            return
        }

        let session = ExtensionDebugSession(
            runId: runId,
            packageId: packageId,
            script: scriptKey,
            scriptPath: Self.relativePath(of: scriptUrl, under: localPath),
            sourceRevision: ExtensionDebugRedactor.revision(of: scriptContent),
            hub: hub
        )

        session.emit(
            .runStarted,
            message: entrypoint.displayName,
            details: [
                "input": ExtensionDebugRedactor.message(entrypoint.inputSummary),
                "revision": session.sourceRevision,
                "script": session.scriptPath
            ]
        )

        let startedAt = Date()
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl, debugSink: session)
        executor.injectGlobals(manager.getCombinedConfigs(localPath: localPath, configJson: configJson))

        do {
            let jsValue = try await executor.runAsync(
                scriptContent: scriptContent,
                functionName: "execute",
                arguments: entrypoint.jsArguments(localPath: localPath, host: host)
            )
            let clean = try manager.verifyJSResponse(
                jsValue,
                extName: URL(fileURLWithPath: localPath).lastPathComponent,
                scriptName: scriptKey
            )
            // `compactRepresentation` chứ không `stringify`: summary chỉ được có hình dạng, tuyệt đối
            // không có nội dung chương hay payload thật.
            session.emit(
                .responseValidated,
                message: manager.compactRepresentation(clean),
                details: Self.durationDetails(from: startedAt)
            )
            session.emit(.runFinished, message: "Hoàn tất", details: Self.durationDetails(from: startedAt))
        } catch is CancellationError {
            session.emit(
                .cancelled,
                level: .warning,
                message: "Run bị huỷ",
                location: nil,
                details: Self.durationDetails(from: startedAt)
            )
        } catch let error as ExtensionManagerError {
            session.emitError(
                .responseError,
                message: error.localizedDescription,
                details: Self.durationDetails(from: startedAt)
            )
            session.emitError(.runFinished, message: "Kết thúc với lỗi", details: Self.durationDetails(from: startedAt))
        } catch {
            session.emitError(
                .runFinished,
                message: error.localizedDescription,
                details: Self.durationDetails(from: startedAt)
            )
        }
    }

    private static func durationDetails(from startedAt: Date) -> [String: String] {
        ["durationMs": String(Int(Date().timeIntervalSince(startedAt) * 1000))]
    }

    /// Hai đường resolve, đúng như production: sáu entrypoint chuẩn tra khoá `script` trong
    /// `plugin.json`, còn custom script tìm theo **tên file** ở gốc extension rồi `src/`.
    private static func resolveScript(
        entrypoint: ExtensionDebugEntrypoint,
        localPath: String,
        manager: ExtensionManager
    ) throws -> URL {
        guard entrypoint.resolvesByFileName else {
            return try manager.getScriptPath(extensionPath: localPath, scriptKey: entrypoint.scriptKey)
        }
        let fileName = entrypoint.scriptKey
        guard !fileName.isEmpty else {
            throw NSError(
                domain: "ExtensionDebugRunner",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Chưa nhập tên file script"]
            )
        }
        let extUrl = URL(fileURLWithPath: localPath)
        let rootUrl = extUrl.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: rootUrl.path) { return rootUrl }
        let srcUrl = extUrl.appendingPathComponent("src").appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: srcUrl.path) { return srcUrl }
        throw NSError(
            domain: "ExtensionDebugRunner",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "Script file '\(fileName)' not found in root or src/"]
        )
    }

    /// Path tương đối so với gốc extension. Không bao giờ trả path tuyệt đối ra event.
    private static func relativePath(of scriptUrl: URL, under localPath: String) -> String {
        let root = localPath.hasSuffix("/") ? localPath : localPath + "/"
        let full = scriptUrl.path
        guard full.hasPrefix(root) else { return scriptUrl.lastPathComponent }
        return String(full.dropFirst(root.count))
    }
}
