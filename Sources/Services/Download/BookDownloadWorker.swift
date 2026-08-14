import Foundation
import JavaScriptCore

/// Quản lý một worker tải tuần tự cho mỗi tác vụ tải/xuất sách.
/// Tái sử dụng một thực thể `JSExecutor` duy nhất xuyên suốt toàn bộ quá trình
/// để tránh khởi tạo lại `JSContext` liên tục và hỗ trợ hủy tác vụ ngay lập tức.
public actor BookDownloadWorker {
    private let localPath: String
    private let downloadUrl: String
    private let configJson: String
    private var executor: JSExecutor?
    private var isPrepared: Bool = false
    private var isCancelled: Bool = false

    public init(localPath: String, downloadUrl: String = "", configJson: String = "{}") {
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
    }

    private func prepareIfNeeded() throws {
        guard !isPrepared else { return }
        guard !isCancelled else { throw CancellationError() }

        let scriptUrl = try ExtensionManager.shared.getScriptPath(extensionPath: localPath, scriptKey: "chap")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)

        let newExecutor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = ExtensionManager.shared.getCombinedConfigs(localPath: localPath, configJson: configJson)
        newExecutor.injectGlobals(configs)
        try newExecutor.prepareScript(scriptContent)

        self.executor = newExecutor
        self.isPrepared = true
    }

    public func fetchChapterContent(url: String, host: String?) async throws -> String {
        try Task.checkCancellation()
        guard !isCancelled else { throw CancellationError() }

        try prepareIfNeeded()
        guard let executor = self.executor else {
            throw CancellationError()
        }

        let resolvedUrl = JSExecutor.cleanAndResolveUrl(url, host: host)

        do {
            let jsValue = try await executor.callAsync(functionName: "execute", arguments: [resolvedUrl])
            try Task.checkCancellation()
            guard !isCancelled else { throw CancellationError() }

            let extName = URL(fileURLWithPath: localPath).lastPathComponent
            let cleanVal = try ExtensionManager.shared.verifyJSResponse(jsValue, extName: extName, scriptName: "chap")

            var resultStr = ""
            if cleanVal.isArray {
                if let array = cleanVal.toArray() as? [String] {
                    resultStr = array.joined(separator: "\n")
                }
            } else {
                resultStr = cleanVal.toString() ?? ""
            }

            return resultStr
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Khi gặp lỗi JS/network, reset executor để chương kế tiếp có thể thử lại với context sạch
            executor.cancelCurrentExecution()
            self.executor = nil
            self.isPrepared = false
            throw error
        }
    }

    public func cancel() {
        self.isCancelled = true
        executor?.cancelCurrentExecution()
        self.executor = nil
        self.isPrepared = false
    }

    public func cleanup() {
        executor?.cancelCurrentExecution()
        self.executor = nil
        self.isPrepared = false
    }
}
