import Foundation

/// Giai đoạn hiện tại của một tác vụ **xuất truyện** — để người dùng biết đang chờ gì.
///
/// Trước 1.3.253 tác vụ xuất chỉ có một thanh tiến độ: chương cuối cùng chạy xong là im lặng vài giây (lúc
/// đó renderer đang đóng file, EPUB/MOBI còn phải dựng mục lục và copy lại text), rồi share sheet bật ra.
/// Stage này là trạng thái **tạm thời** trên `DownloadTask`, không lưu vào CSDL: app khởi động lại thì tác
/// vụ đang chạy đã bị đánh `failed` nên không có stage nào cần khôi phục.
public enum ExportStage: String, Sendable {
    case fetchingChapters
    case renderingFile
    case readyToShare

    public var displayName: String {
        switch self {
        case .fetchingChapters: return "Đang lấy chương"
        case .renderingFile: return "Đang tạo file"
        case .readyToShare: return "Sẵn sàng chia sẻ"
        }
    }
}
