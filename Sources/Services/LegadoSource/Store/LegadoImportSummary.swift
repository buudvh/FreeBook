import Foundation

/// Tổng kết một lượt nhập nguồn Legado — View dựng alert "Đã nhập N nguồn" từ đây.
public struct LegadoImportSummary: Sendable {
    public var added = 0
    public var updated = 0
    /// Nội dung trùng khít bản đang có — không ghi lại, không tăng `version`.
    public var unchanged = 0
    public var skipped: [LegadoImportSkipReason: Int] = [:]
    /// Lỗi ghi từng nguồn (tên + thông báo), tối đa vài dòng đầu được hiện.
    public var writeErrors: [String] = []
    /// Lỗi ghi index tiện ích (sau khi file đã ghi) — nguồn có file nhưng có thể chưa hiện.
    public var indexError: String?

    public init() {}

    public var importedCount: Int { added + updated + unchanged }

    public var skippedCount: Int { skipped.values.reduce(0, +) }

    mutating func skip(_ reason: LegadoImportSkipReason) {
        skipped[reason, default: 0] += 1
    }

    /// `"audio: 11"`, `"thiếu rule tối thiểu: 536"`… theo thứ tự cố định của `LegadoImportSkipReason`.
    public var skippedLines: [String] {
        LegadoImportSkipReason.allCases.compactMap { reason in
            guard let count = skipped[reason], count > 0 else { return nil }
            return "\(reason.label): \(count)"
        }
    }
}
