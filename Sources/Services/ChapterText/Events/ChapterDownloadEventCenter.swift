import Foundation

/// Báo cho các danh sách chương đang mở rằng **chương vừa có nội dung trên máy**, để icon "đã tải" đổi ngay — không
/// phải đóng/mở lại danh sách hay thoát màn đọc (1.3.713).
///
/// Khác `DownloadPresentationEventCenter` (đúng một subscriber là `AppLaunchRootView`): ở đây **nhiều** nơi nghe cùng
/// lúc (mục lục Reader, mục lục comic, tab Mục lục của Chi tiết), mỗi nơi một `AsyncStream` riêng đã lọc theo `bookId`.
/// Vòng `for await` kết thúc (Task bị huỷ) là tự gỡ đăng ký.
///
/// Nguồn phát — mỗi loại nội dung **một** chỗ, nên đường ghi mới không cần nhớ tự báo:
/// - truyện chữ: actor `ChapterStore`, ngay sau khi ghi cờ đã tải thành công (`upsertCachedChapter`,
///   `updateCacheMetadata`, `markChaptersCached`). Phủ tải cả truyện (mọi luồng), xuất có tải, tải lẻ, Reader/TTS
///   đọc trước, khôi phục backup, đổi nguồn;
/// - truyện tranh: `ComicOfflineStore.saveManifest` (manifest ghi sau cùng = chương đủ ảnh).
///
/// Giá trị là **chỉ số logic** của chương (`index` trong mục lục). Chỉ báo chiều "đã tải"; xoá bản tải không phát.
/// `send` đồng bộ và không chờ subscriber nên gọi được từ actor / luồng nền.
final class ChapterDownloadEventCenter: @unchecked Sendable {
    static let shared = ChapterDownloadEventCenter()

    private struct Subscriber {
        let bookId: String
        let continuation: AsyncStream<[Int]>.Continuation
    }

    private let lock = NSLock()
    private var subscribers: [UUID: Subscriber] = [:]

    private init() {}

    func send(bookId: String, chapterIndices: [Int]) {
        guard !bookId.isEmpty, !chapterIndices.isEmpty else { return }
        lock.lock()
        let targets = subscribers.values.filter { $0.bookId == bookId }.map(\.continuation)
        lock.unlock()
        for continuation in targets {
            continuation.yield(chapterIndices)
        }
    }

    /// Mỗi lần gọi là một subscriber mới, chỉ nhận chương của `bookId`. Sự kiện tới trước khi bắt đầu `for await` vẫn
    /// được giữ trong stream — tạo stream **trước** khi đọc trạng thái gốc từ đĩa/DB thì không lọt sự kiện nào.
    func chapterIndices(bookId: String) -> AsyncStream<[Int]> {
        let (stream, continuation) = AsyncStream<[Int]>.makeStream()
        let key = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.removeSubscriber(key)
        }
        lock.lock()
        subscribers[key] = Subscriber(bookId: bookId, continuation: continuation)
        lock.unlock()
        return stream
    }

    private func removeSubscriber(_ key: UUID) {
        lock.lock()
        subscribers.removeValue(forKey: key)
        lock.unlock()
    }
}
