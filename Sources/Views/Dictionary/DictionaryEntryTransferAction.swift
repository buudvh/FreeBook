import Foundation

/// Thực thi COPY (không phải MOVE) một entry sang phạm vi/loại từ điển khác.
///
/// Bất biến:
/// - Nguồn **luôn được giữ nguyên** — hàm này chỉ ghi ở đích.
/// - Key chưa có ở đích → tạo mới; key đã có → **ghi đè hoàn toàn** giá trị cũ
///   (không trùng lặp, không gộp) vì cả hai API bên dưới đều xoá key cũ rồi
///   insert record mới ở đầu file custom.
/// - Không bao giờ chạm dữ liệu mặc định `.dat`; hướng Riêng → Chung chỉ ghi lớp
///   custom, entry custom đóng vai override theo thứ tự ưu tiên sẵn có.
@MainActor
enum DictionaryEntryTransferAction {
    static func copy(
        key: String,
        value: String,
        destinationType: DictType,
        target: DictionaryTransferTarget
    ) async throws {
        switch target {
        case .globalCustom:
            try await DictionaryCache.shared.upsertEntry(
                key: key,
                value: value,
                type: destinationType
            )
        case .privateBook(let bookId):
            try await TranslationManager.shared.saveCustomEntry(
                word: key,
                meaning: value,
                isName: destinationType == .names,
                bookId: bookId
            )
        }
    }

    /// Nhãn ngắn của đích, dùng cho toast xác nhận.
    static func destinationLabel(destinationType: DictType, target: DictionaryTransferTarget) -> String {
        let typeName = destinationType == .names ? "Name" : "VP"
        switch target {
        case .globalCustom:
            return "\(typeName) chung custom"
        case .privateBook:
            return "\(typeName) riêng"
        }
    }
}
