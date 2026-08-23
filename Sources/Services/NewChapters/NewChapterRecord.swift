import Foundation

/// Trạng thái theo dõi chương mới của **một** truyện online.
///
/// Hai bộ số nằm cạnh nhau và không được lẫn:
/// * `seen*` là **mốc người dùng đã thấy** — chỉ đổi khi người dùng mở truyện hoặc khi lần kiểm tra
///   xác nhận không có gì mới. Đây chính là "chapter identity đã thấy".
/// * `probed*` là kết quả **lần kiểm tra gần nhất**. Khi mục lục bị phân trang quá nhiều và chỉ trang
///   cuối được lấy thì `probedIsPartial == true`, nghĩa là `probedChapterCount` **không** phải tổng số
///   chương và không được dùng làm mốc.
///
/// Record cố ý **không** nằm trong SwiftData: schema `@Model` của app không có `VersionedSchema`, thêm
/// thuộc tính vào `Book` là rủi ro migration cho dữ liệu vốn có thể dựng lại được bằng một lần kiểm tra.
/// Chủ sở hữu là [`NewChapterStore`](NewChapterStore.swift).
struct NewChapterRecord: Codable, Sendable, Equatable {
    var bookId: String
    /// Lần kiểm tra mục lục gần nhất (thành công hay thất bại đều ghi) — dùng cho cooldown.
    var lastCheckedAt: Date?
    var seenChapterCount: Int
    var seenLastChapterUrl: String
    var probedChapterCount: Int
    var probedLastChapterUrl: String
    /// `true` ⇒ chỉ lấy được một phần mục lục (nguồn phân trang vượt `maxTOCPagesPerCheck`).
    var probedIsPartial: Bool
    var newChapterCount: Int
    /// `false` ⇒ con số chỉ là ước lượng, UI hiện dấu chấm thay vì số sai.
    var isCountExact: Bool
    var latestChapterTitle: String
    /// Lần **đầu tiên** phát hiện đợt chương mới hiện tại; `nil` khi không có gì mới.
    var firstFoundAt: Date?
    var lastFailure: String?

    var hasNew: Bool { newChapterCount > 0 }

    /// Nhãn badge: số chương khi đếm được chính xác, còn lại là dấu chấm.
    var badgeText: String {
        guard hasNew else { return "" }
        return isCountExact ? "\(newChapterCount)" : "•"
    }

    init(bookId: String) {
        self.bookId = bookId
        self.lastCheckedAt = nil
        self.seenChapterCount = 0
        self.seenLastChapterUrl = ""
        self.probedChapterCount = 0
        self.probedLastChapterUrl = ""
        self.probedIsPartial = false
        self.newChapterCount = 0
        self.isCountExact = true
        self.latestChapterTitle = ""
        self.firstFoundAt = nil
        self.lastFailure = nil
    }

    /// Decode chịu lỗi: mọi khoá đều `decodeIfPresent` để file của bản app cũ vẫn đọc được sau khi
    /// thêm field mới — cùng lý do `BackupManifest.Counts` phải viết `init(from:)` tay.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bookId = try container.decodeIfPresent(String.self, forKey: .bookId) ?? ""
        self.lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        self.seenChapterCount = try container.decodeIfPresent(Int.self, forKey: .seenChapterCount) ?? 0
        self.seenLastChapterUrl = try container.decodeIfPresent(String.self, forKey: .seenLastChapterUrl) ?? ""
        self.probedChapterCount = try container.decodeIfPresent(Int.self, forKey: .probedChapterCount) ?? 0
        self.probedLastChapterUrl = try container.decodeIfPresent(String.self, forKey: .probedLastChapterUrl) ?? ""
        self.probedIsPartial = try container.decodeIfPresent(Bool.self, forKey: .probedIsPartial) ?? false
        self.newChapterCount = try container.decodeIfPresent(Int.self, forKey: .newChapterCount) ?? 0
        self.isCountExact = try container.decodeIfPresent(Bool.self, forKey: .isCountExact) ?? true
        self.latestChapterTitle = try container.decodeIfPresent(String.self, forKey: .latestChapterTitle) ?? ""
        self.firstFoundAt = try container.decodeIfPresent(Date.self, forKey: .firstFoundAt)
        self.lastFailure = try container.decodeIfPresent(String.self, forKey: .lastFailure)
    }

    /// Người dùng đã mở truyện ⇒ mốc nhảy tới kết quả kiểm tra gần nhất và badge tắt.
    /// Số lượng **chỉ** được cập nhật khi lần kiểm tra đó lấy đủ mục lục.
    mutating func markSeen() {
        if !probedLastChapterUrl.isEmpty {
            seenLastChapterUrl = probedLastChapterUrl
        }
        if !probedIsPartial, probedChapterCount > 0 {
            seenChapterCount = probedChapterCount
        }
        newChapterCount = 0
        isCountExact = true
        firstFoundAt = nil
    }
}
