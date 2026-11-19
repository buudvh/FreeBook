import Foundation

/// Kết quả một lượt nhập theo `DataImportMode` — số đếm cho toast "Đã nhập: thêm X, cập nhật Y" ở màn gọi.
///
/// Chỉ là số liệu thuần (không SwiftUI, không toast): tầng service trả về, View tự hiện `message`.
public struct KeyedImportSummary: Equatable, Sendable {
    public let mode: DataImportMode
    /// Số mục trong file sau khi bỏ khoá lặp.
    public let importedCount: Int
    /// Khoá mới (chưa có trên máy) đã thêm.
    public let added: Int
    /// Khoá trùng đã lấy giá trị mới và giá trị **khác** bản cũ (`.overwriteExisting`).
    public let updated: Int
    /// Khoá trùng mà giá trị mới y hệt bản cũ (`.overwriteExisting`) — không đổi gì.
    public let unchanged: Int
    /// Khoá trùng giữ bản cũ, bỏ qua bản trong file (`.keepExisting`).
    public let skipped: Int
    /// Số mục trước khi nhập.
    public let previousCount: Int
    /// Số mục sau khi nhập.
    public let totalCount: Int

    public init(
        mode: DataImportMode,
        importedCount: Int,
        added: Int = 0,
        updated: Int = 0,
        unchanged: Int = 0,
        skipped: Int = 0,
        previousCount: Int,
        totalCount: Int
    ) {
        self.mode = mode
        self.importedCount = importedCount
        self.added = added
        self.updated = updated
        self.unchanged = unchanged
        self.skipped = skipped
        self.previousCount = previousCount
        self.totalCount = totalCount
    }

    /// Câu toast kết quả. Thứ tự mới là chọn chế độ **trước** khi chọn file nên số đếm báo sau khi nhập (thay cho
    /// phần "xem trước số đếm" trong hộp thoại Gộp / Ghi đè cũ).
    public var message: String {
        switch mode {
        case .replaceAll:
            return "Đã thay thế toàn bộ: \(totalCount) mục (trước có \(previousCount))."
        case .overwriteExisting:
            let same = unchanged > 0 ? ", \(unchanged) mục trùng y hệt" : ""
            return "Đã nhập: thêm \(added), cập nhật \(updated)\(same)."
        case .keepExisting:
            return "Đã nhập: thêm \(added), bỏ qua \(skipped) key đã có."
        }
    }
}
