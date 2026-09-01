import Foundation

/// Đầu ra trace của **một** lượt chạy debug. `JSExecutor` giữ một `ExtensionDebugEventSink?`; luồng
/// đọc/tải production truyền `nil` và vì thế không đổi hành vi một chút nào.
///
/// **Hợp đồng bắt buộc: `emit` không được blocking.** Nó bị gọi từ chính thread đang chạy JavaScript
/// (bên trong `@convention(block)` của JavaScriptCore) và từ callback của `URLSession`. Vì vậy đây là
/// giao thức đồng bộ, không `async`: người cài đặt phải nhận event, gán số thứ tự, rồi đẩy sang chỗ
/// khác — mọi việc nặng thuộc `ExtensionDebugEventHub`.
public protocol ExtensionDebugEventSink: AnyObject, Sendable {
    /// Định danh run — dùng để cancel và để nhóm event.
    var runId: UUID { get }
    /// Path tương đối của script đang chạy, để dựng `ExtensionDebugSourceLocation`.
    var scriptPath: String { get }
    /// Hash nội dung script lúc chạy.
    var sourceRevision: String { get }

    func emit(
        _ category: ExtensionDebugEvent.Category,
        level: ExtensionDebugEvent.Level,
        message: String,
        location: ExtensionDebugSourceLocation?,
        details: [String: String]
    )
}

public extension ExtensionDebugEventSink {
    /// Dựng location cho script của run này. Ở protocol chứ không ở `ExtensionDebugSession` để
    /// `JSExecutor` không phải downcast về kiểu cụ thể.
    func location(line: Int?, column: Int?, stack: String?) -> ExtensionDebugSourceLocation {
        ExtensionDebugSourceLocation(
            script: scriptPath,
            line: line,
            column: column,
            revision: sourceRevision,
            stack: stack.map { ExtensionDebugRedactor.stack($0) }
        )
    }

    func emit(_ category: ExtensionDebugEvent.Category, message: String) {
        emit(category, level: .info, message: message, location: nil, details: [:])
    }

    func emit(
        _ category: ExtensionDebugEvent.Category,
        message: String,
        details: [String: String]
    ) {
        emit(category, level: .info, message: message, location: nil, details: details)
    }

    func emitError(
        _ category: ExtensionDebugEvent.Category,
        message: String,
        location: ExtensionDebugSourceLocation? = nil,
        details: [String: String] = [:]
    ) {
        emit(category, level: .error, message: message, location: location, details: details)
    }
}
