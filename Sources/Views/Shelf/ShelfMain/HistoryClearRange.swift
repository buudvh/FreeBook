import Foundation

/// Khoảng thời gian của lệnh "Xóa lịch sử" ở tab Lịch sử (`ShelfView`): xoá các truyện **đang hiển thị** trong tab
/// có `lastReadDate` nằm trong khoảng. Danh sách đầu vào là `ShelfBookPartition.history` — đã bỏ sách trên kệ và
/// sách lịch sử của nguồn NSFW đang bị ẩn, nên những sách đó không bao giờ bị đụng tới.
enum HistoryClearRange: CaseIterable, Hashable {
    case lastHour
    case lastDay
    case last30Days
    case all

    var title: String {
        switch self {
        case .lastHour: return "Trong 1 giờ qua"
        case .lastDay: return "Trong 1 ngày qua"
        case .last30Days: return "Trong 30 ngày qua"
        case .all: return "Tất cả"
        }
    }

    /// Mốc đọc cũ nhất còn bị xoá; `nil` = không giới hạn (`all`).
    func cutoff(now: Date) -> Date? {
        switch self {
        case .lastHour: return now.addingTimeInterval(-3_600)
        case .lastDay: return now.addingTimeInterval(-86_400)
        case .last30Days: return now.addingTimeInterval(-30 * 86_400)
        case .all: return nil
        }
    }

    /// `bookId` của các truyện trong `history` đọc lần cuối trong khoảng này.
    func bookIds(in history: [Book], now: Date = Date()) -> [String] {
        guard let cutoff = cutoff(now: now) else { return history.map(\.bookId) }
        return history.filter { $0.lastReadDate >= cutoff }.map(\.bookId)
    }
}
