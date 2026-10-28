import Foundation

/// Kết quả AI của một truyện đã chạy xong trong lúc màn AI của truyện đó **không** mở — người dùng chưa xem (1.3.630).
///
/// Nút hub nổi giữ một dòng cho nó ở trang "Tác vụ AI"; chạm là mở thẳng màn AI của truyện, đúng phiên chứa kết
/// quả. Mở màn AI của truyện bằng bất kỳ đường nào là bỏ bản ghi. Lưu qua lần mở app (`AIUnseenResultStore`) nên chỉ
/// giữ những gì cần để dựng lại ngữ cảnh mở màn AI — **không** giữ nội dung chương (xem `AIRuntimeCoordinator+UnseenResults`).
public struct AIUnseenResult: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// Chạy xong bình thường (kể cả quét name còn lượt lỗi chờ "Thử lại").
        case finished
        /// Dừng vì lỗi — tin lỗi nằm trong phiên.
        case failed
    }

    public let bookId: String
    public var bookTitle: String
    public var outcome: Outcome
    public var finishedAt: Date
    /// Phiên chat chứa kết quả — màn AI mở đúng phiên này thay vì phiên mới nhất của truyện.
    public var sessionId: UUID?
    public var chapterIndex: Int
    public var chapterTitle: String
    public var translatesChapterTitles: Bool
    public var convertsTraditionalToSimplified: Bool
}
