import Foundation

/// Những gì `ReaderProgressCoordinator` cần đọc **tại thời điểm chạy** từ chủ sở hữu (`ReaderViewModel`):
/// vị trí đọc hiện tại (đọc lúc debounce **nổ**, không phải lúc đặt lịch) và tên chương gốc cho snapshot.
/// Giữ `weak` ở coordinator; gắn bằng `attach(host:)` **sau** khi VM xong pha 1 của `init`.
@MainActor
protocol ReaderProgressHost: AnyObject {
    var currentProgress: ReadingProgress { get }
    func originalChapterTitle(at index: Int) -> String?
}
