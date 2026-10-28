import Foundation

/// Chuỗi chương/tập tải lỗi **liên tiếp** của một tác vụ tải (1.3.634). Đủ `limit` thì tác vụ dừng và báo "Thất bại";
/// người dùng bấm Thử lại để tải tiếp, chương đã tải được bỏ qua nhanh.
///
/// - Trước đây chương lỗi bị bỏ qua và tác vụ tải tiếp tới hết phạm vi, nên nguồn hỏng/bị chặn làm tác vụ chạy hết
///   hàng nghìn chương mới báo lỗi.
/// - Đếm theo **thứ tự mục lục**. Truyện chữ đếm ở chỗ bộ tải nhiều luồng đã xếp kết quả đúng thứ tự
///   (`DownloadManager+ChapterLanes`); comic và video vốn tải tuần tự.
/// - Chương lấy được hoặc đã có sẵn trong máy thì đếm lại từ 0.
/// - Cùng ngưỡng với TTS (`TTSManager.maxConsecutiveChapterFailures`).
struct DownloadFailureStreak {
    static let limit = 5

    /// Lỗi ném ra để dừng vòng tải chữ/xuất khi chạm ngưỡng. `executeTask` bắt ở nhánh `catch` chung rồi
    /// `markFailed` với `message`, và bỏ file xuất dở.
    struct LimitReached: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private(set) var count = 0
    /// `index` mục lục của chương lỗi đầu và cuối trong chuỗi hiện tại — để lời báo nói rõ đoạn nào hỏng.
    private var firstFailedIndex: Int?
    private var lastFailedIndex: Int?

    /// Ghi một chương/tập lỗi; trả `true` khi chuỗi vừa chạm ngưỡng.
    mutating func recordFailure(chapterIndex: Int) -> Bool {
        if count == 0 {
            firstFailedIndex = chapterIndex
        }
        lastFailedIndex = chapterIndex
        count += 1
        return count >= Self.limit
    }

    mutating func recordSuccess() {
        count = 0
        firstFailedIndex = nil
        lastFailedIndex = nil
    }

    /// "Đã dừng: 5 chương liên tiếp tải lỗi (ch.12–16). …" — `noun` = "chương" hoặc "tập".
    func stopMessage(noun: String) -> String {
        let prefix = noun == "chương" ? "ch." : "\(noun) "
        var range = ""
        if let first = firstFailedIndex, let last = lastFailedIndex {
            range = first == last ? " (\(prefix)\(first + 1))" : " (\(prefix)\(first + 1)–\(last + 1))"
        }
        return "Đã dừng: \(count) \(noun) liên tiếp tải lỗi\(range). Kiểm tra nguồn rồi bấm Thử lại — \(noun) đã tải không phải tải lại."
    }
}
