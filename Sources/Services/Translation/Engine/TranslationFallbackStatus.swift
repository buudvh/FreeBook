import Foundation

/// Báo "đang dịch bằng QT thay thế" của một chương: tiện ích dịch lỗi ở một số dòng (`TranslationFallbackStatusStore`).
public struct TranslationFallbackStatus: Equatable, Sendable {
    /// Tên tiện ích dịch bị lỗi.
    public let engineName: String
    /// Lỗi gọn một dòng.
    public let message: String
    /// Số dòng lỗi (đã lùi về QT hoặc giữ chữ gốc); tên chương lỗi tính là một dòng.
    public let failedLineCount: Int
    /// Số dòng đã gửi dịch (gồm tên chương nếu có gửi).
    public let requestedLineCount: Int
    /// Số dòng lỗi giữ chữ gốc vì không có chữ Hán để QT dịch.
    public let keptOriginalLineCount: Int

    /// "Tiện ích lỗi: <lỗi> · 12/48 đoạn" — dòng phụ của dải báo.
    public var detailText: String {
        let counts = requestedLineCount > 0 ? " · \(failedLineCount)/\(requestedLineCount) đoạn" : ""
        return "\(engineName) lỗi: \(message)\(counts)"
    }

    /// Dòng chính: lùi về QT khi có dòng QT dịch được, chỉ giữ chữ gốc khi mọi dòng lỗi đều không có chữ Hán.
    public var titleText: String {
        keptOriginalLineCount >= failedLineCount ? "Tiện ích dịch lỗi — đang giữ chữ gốc" : "Đang dịch bằng QT thay thế"
    }
}
