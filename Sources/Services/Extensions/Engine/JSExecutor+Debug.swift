import Foundation
import JavaScriptCore

/// Điểm phát trace của `JSExecutor`. Tách file riêng để `JSExecutor.swift` (đã vượt baseline dòng) chỉ
/// nhận thêm một stored property và các lời gọi một dòng.
///
/// Mọi hàm ở đây `guard let sink = debugSink else { return }` ngay đầu, nên luồng production (sink
/// `nil`) chỉ trả thêm một lần kiểm tra `nil` — không cấp phát, không format chuỗi.
extension JSExecutor {
    internal func emitDebugConsole(_ message: String) {
        guard let sink = debugSink else { return }
        sink.emit(.console, level: .debug, message: message, location: nil, details: [:])
    }

    /// `exceptionHandler` của JSC trả line/column dạng chuỗi nên phải parse; giữ `nil` khi không có.
    internal func emitDebugException(
        description: String,
        line: String?,
        column: String?,
        stack: String?
    ) {
        guard let sink = debugSink else { return }
        let location = sink.location(line: line.flatMap { Int($0) }, column: column.flatMap { Int($0) }, stack: stack)
        sink.emitError(.exception, message: description, location: location)
    }

    internal func emitDebugCompileFailed(_ description: String) {
        guard let sink = debugSink else { return }
        sink.emitError(
            .compileFailed,
            message: description,
            location: sink.location(line: nil, column: nil, stack: nil)
        )
    }

    internal func emitDebugCancelled() {
        guard let sink = debugSink else { return }
        sink.emit(.cancelled, level: .warning, message: "Huỷ execution: dừng fetch và browser đang chạy", location: nil, details: [:])
    }

    internal func emitDebugFetchStarted(taskID: Int, url: String, method: String) {
        guard let sink = debugSink else { return }
        sink.emit(
            .fetchStarted,
            message: ExtensionDebugRedactor.url(url),
            details: ["taskId": String(taskID), "method": method]
        )
    }

    /// Một điểm phát cho cả thành công và thất bại: `status >= 400` hoặc có `error` thì thành
    /// `fetchFailed`. Gộp lại để không tồn tại ca "fetch xong mà trace không có dòng kết".
    internal func emitDebugFetchFinished(
        taskID: Int,
        url: String,
        status: Int,
        statusText: String,
        bytes: Int,
        startedAt: Date
    ) {
        guard let sink = debugSink else { return }
        let details: [String: String] = [
            "taskId": String(taskID),
            "status": String(status),
            "statusText": ExtensionDebugRedactor.truncate(statusText, limit: 80),
            "bytes": String(bytes),
            "durationMs": String(Int(Date().timeIntervalSince(startedAt) * 1000))
        ]
        let failed = status >= 400 || status == 0
        sink.emit(
            failed ? .fetchFailed : .fetchFinished,
            level: failed ? .error : .debug,
            message: ExtensionDebugRedactor.url(url),
            location: nil,
            details: details
        )
    }
}
