import Foundation

/// Gom danh sách truyện của tab Lịch sử thành **từng ngày**, mỗi ngày một `Section` của `List`.
///
/// Thuần, không state: nhận mảng đã sắp và trả các nhóm theo đúng thứ tự vào. Vì `historyBooks` lấy từ
/// `@Query(sort: \Book.lastReadDate, order: .reverse)` nên các ngày **liền khối** — chỉ cần một pass,
/// không cần sắp lại lần nữa.
///
/// Gom **sau** khi đã `prefix(historyLimit)`, nên nhóm cuối có thể là một ngày dở. Đó là đúng hành vi
/// phân trang +50 sẵn có, không phải lỗi.
enum HistoryDayGrouper {
    struct Day: Identifiable {
        /// Vị trí nhóm, không phải ngày: hai nhóm trùng ngày (nếu đầu vào chưa sắp) vẫn có `id` khác.
        let id: Int
        let start: Date
        let label: String
        let books: [Book]
    }

    /// Một formatter dùng lại cho mọi nhóm — dựng `DateFormatter` trong vòng lặp là chi phí thật.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    static func group(
        _ books: [Book],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [Day] {
        guard !books.isEmpty else { return [] }

        var days: [Day] = []
        var currentStart: Date?
        var bucket: [Book] = []

        func flush() {
            guard let start = currentStart, !bucket.isEmpty else { return }
            days.append(Day(
                id: days.count,
                start: start,
                label: label(for: start, calendar: calendar, now: now),
                books: bucket
            ))
            bucket = []
        }

        for book in books {
            let start = calendar.startOfDay(for: book.lastReadDate)
            if start != currentStart {
                flush()
                currentStart = start
            }
            bucket.append(book)
        }
        flush()

        return days
    }

    private static func label(for start: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDateInToday(start) { return "Hôm nay" }
        if calendar.isDateInYesterday(start) { return "Hôm qua" }
        return dayFormatter.string(from: start)
    }
}
