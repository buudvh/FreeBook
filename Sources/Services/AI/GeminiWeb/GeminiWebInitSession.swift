import Foundation

/// Các giá trị đọc từ `window.WIZ_global_data` của trang gemini.google.com/app — tương đương bộ
/// regex `SNlM0e`/`cfb2h`/`FdrFJe`/`TuX5cc` của thư viện tham chiếu (`gemini-webapi`), nhưng đọc
/// thẳng object trong trang nên không phụ thuộc cách Google in HTML.
public struct GeminiWebInitSession: Sendable, Equatable {
    /// `SNlM0e` — token `at=` của mọi POST. Rỗng là chưa đăng nhập (phiên khách).
    public let accessToken: String
    /// `cfb2h` — build label, tham số `bl=`.
    public let buildLabel: String?
    /// `FdrFJe` — session id, tham số `f.sid=`.
    public let sessionId: String?
    /// `TuX5cc` — ngôn ngữ giao diện, tham số `hl=`.
    public let language: String
    /// UUID hoa gắn đuôi mọi header model trong vòng đời một trang đã nạp.
    public let sessionUUID: String
    public let capturedAt: Date

    public init(
        accessToken: String,
        buildLabel: String?,
        sessionId: String?,
        language: String,
        sessionUUID: String = UUID().uuidString.uppercased(),
        capturedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.buildLabel = buildLabel
        self.sessionId = sessionId
        self.language = language.isEmpty ? "en" : language
        self.sessionUUID = sessionUUID
        self.capturedAt = capturedAt
    }

    /// Token quá 30 phút coi là đáng nạp lại trang trước khi dùng.
    public var isStale: Bool {
        Date().timeIntervalSince(capturedAt) > 30 * 60
    }
}
