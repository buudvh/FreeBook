import Foundation

/// Kết quả dịch một nhóm dòng bằng tiện ích (`TranslationExtensionRunner.translateLines`).
///
/// - `translations`: bản dịch theo `ChapterTextLine.id` (chỉ dòng dịch được).
/// - `failedLineIds`: dòng cần dịch mà tiện ích lỗi / trả rỗng / trả lệch dòng ⇒ caller lùi về QT (dòng có chữ Hán)
///   hoặc giữ chữ gốc. Dòng không có chữ (số, dấu câu) không nằm ở cả hai tập: caller giữ nguyên.
/// - `errorMessage`: lỗi đầu tiên, gọn một dòng, để báo cho người dùng.
public struct TranslationExtensionLineResult: Sendable {
    public let engineName: String
    public let translations: [Int: String]
    public let failedLineIds: Set<Int>
    public let errorMessage: String?
    /// Số dòng đã gửi (hoặc lấy từ cache) để dịch — mẫu số của "N/M đoạn".
    public let requestedLineCount: Int

    public var hasFailures: Bool { !failedLineIds.isEmpty }
}
