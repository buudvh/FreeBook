import Foundation

/// Đọc log của **một** phiên cho màn **Xem log** (1.3.1015, anh Bửu: "nhấn giữ một phiên sẽ hiển thị các option xem log,
/// xoá log, xuất log"). Như đường xuất `.txt`: ghi nốt dòng đang chờ trên `queue` rồi đọc bằng **kết nối riêng** ngoài
/// `queue` (WAL đọc song song được) ⇒ cuộn xem log không chặn việc ghi log. Kết quả trả trên main.
extension AppLogger {
    public struct LogLineItem: Identifiable, Sendable {
        public let id: Int64
        public let ts: Date
        public let isError: Bool
        public let text: String
    }

    /// Số dòng mỗi lượt nạp của màn Xem log.
    public static let browsePageSize = 500

    /// Một trang dòng: `cursor` = id dòng cuối của trang trước (`nil` = trang đầu); `newestFirst` ⇒ mới nhất trước;
    /// `onlyErrors` ⇒ chỉ dòng ❌; `contains` ⇒ chỉ dòng chứa chữ đó (rỗng = không lọc).
    public func loadLines(
        sessionId: Int64,
        cursor: Int64?,
        newestFirst: Bool,
        onlyErrors: Bool,
        contains: String,
        limit: Int = AppLogger.browsePageSize,
        completion: @escaping ([LogLineItem]) -> Void
    ) {
        queue.async {
            self.flushOnQueue()
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = AppLogDatabase()?.lines(
                    sessionId: sessionId,
                    cursor: cursor,
                    limit: limit,
                    newestFirst: newestFirst,
                    onlyErrors: onlyErrors,
                    contains: contains
                ) ?? []
                let items = rows.map { LogLineItem(id: $0.id, ts: $0.line.ts, isError: $0.line.isError, text: $0.line.text) }
                DispatchQueue.main.async { completion(items) }
            }
        }
    }

    /// Các dòng của khối đầu phiên như file xuất (bản app, máy, iOS, nhiệt / RAM / ổ trống, TTS, trạng thái cuối) — bỏ
    /// dòng "===== Phiên … =====" vì màn đã có tiêu đề.
    public func loadSessionHeader(sessionId: Int64, completion: @escaping ([String]) -> Void) {
        queue.async {
            self.flushOnQueue()
            DispatchQueue.global(qos: .userInitiated).async {
                let text = AppLogDatabase()?.session(id: sessionId).map { Self.header(for: $0) } ?? ""
                let lines = text.split(separator: "\n").dropFirst().map(String.init)
                DispatchQueue.main.async { completion(lines) }
            }
        }
    }
}
