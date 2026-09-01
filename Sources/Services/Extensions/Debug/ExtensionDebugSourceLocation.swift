import Foundation

/// Vị trí trong source của một lỗi compile/exception JS.
///
/// `script` luôn là đường dẫn **tương đối so với gốc extension** (`search.js`, `src/detail.js`), không
/// bao giờ là path tuyệt đối trên thiết bị: client ở Phase 2 chỉ được biết những path có khai trong
/// `plugin.json`, và path tuyệt đối trong sandbox iOS cũng vô nghĩa với máy phát triển.
///
/// `revision` là hash nội dung script lúc chạy. Nó tồn tại để client Phase 2 chỉ gắn diagnostic khi
/// document trong editor còn khớp — event của bản cũ phải hiện là *stale* thay vì đè lỗi của mã mới.
public struct ExtensionDebugSourceLocation: Codable, Sendable, Equatable {
    public let script: String
    public let line: Int?
    public let column: Int?
    public let revision: String
    public let stack: String?

    public init(
        script: String,
        line: Int? = nil,
        column: Int? = nil,
        revision: String,
        stack: String? = nil
    ) {
        self.script = script
        self.line = line
        self.column = column
        self.revision = revision
        self.stack = stack
    }

    /// `search.js:12:5` — dạng một dòng cho danh sách event trong app.
    public var displayText: String {
        var text = script
        if let line { text += ":\(line)" }
        if let column { text += ":\(column)" }
        return text
    }
}
