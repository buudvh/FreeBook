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

    // MARK: - Thông báo đã phát (tách khỏi badge)

    /// Bộ ba `announced*` là **thông báo đã phát** cho người dùng, cố ý **không** dùng chung với
    /// `newChapterCount`: con số kia là trạng thái badge và bị **mỗi** lượt probe ghi lại (`applyDiff`
    /// luôn gán, `markSeen` đưa về 0), nên trước 1.3.329 dòng thông báo biến mất ngay khi đánh dấu đã
    /// đọc. Thông báo chỉ mất khi người dùng tự xoá.
    var announcedChapterCount: Int
    var announcedIsCountExact: Bool
    var announcedAt: Date?
    /// `nil` ⇒ chưa đọc.
    var announcementReadAt: Date?

    var hasNew: Bool { newChapterCount > 0 }

    var hasAnnouncement: Bool { announcedAt != nil && announcedChapterCount > 0 }
    var isAnnouncementRead: Bool { announcementReadAt != nil }

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
        self.announcedChapterCount = 0
        self.announcedIsCountExact = true
        self.announcedAt = nil
        self.announcementReadAt = nil
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
        self.announcedChapterCount = try container.decodeIfPresent(Int.self, forKey: .announcedChapterCount) ?? 0
        self.announcedIsCountExact = try container.decodeIfPresent(Bool.self, forKey: .announcedIsCountExact) ?? true
        self.announcedAt = try container.decodeIfPresent(Date.self, forKey: .announcedAt)
        self.announcementReadAt = try container.decodeIfPresent(Date.self, forKey: .announcementReadAt)
    }

    /// Người dùng đã mở truyện ⇒ mốc nhảy tới kết quả kiểm tra gần nhất và badge tắt.
    /// Số lượng **chỉ** được cập nhật khi lần kiểm tra đó lấy đủ mục lục.
    ///
    /// Cố ý **không** đụng nhóm `announced*`: đó là dòng trong Trung tâm thông báo, đánh dấu đã đọc
    /// không được làm nó biến mất.
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

    mutating func markAnnouncementRead(at date: Date = Date()) {
        guard hasAnnouncement, announcementReadAt == nil else { return }
        announcementReadAt = date
    }

    /// Người dùng xoá dòng khỏi Trung tâm thông báo. Chỉ bỏ **thông báo**, giữ nguyên mốc đã thấy —
    /// xoá cả record sẽ làm lượt kiểm tra sau mất mốc và báo lại từ đầu.
    mutating func clearAnnouncement() {
        announcedChapterCount = 0
        announcedIsCountExact = true
        announcedAt = nil
        announcementReadAt = nil
    }

    /// Ghi nhận một đợt chương mới vừa dò ra thành **thông báo**. Đợt mới (chưa có thông báo, hoặc
    /// thông báo trước đã đọc) bắt đầu một dòng chưa đọc; đợt đang chờ đọc thì chỉ cập nhật con số và
    /// giữ nguyên mốc thời gian phát hiện đầu tiên.
    mutating func announceCurrentFinding(at date: Date = Date()) {
        guard hasNew else { return }
        if announcedAt == nil || isAnnouncementRead {
            announcedAt = firstFoundAt ?? date
            announcementReadAt = nil
        }
        announcedChapterCount = newChapterCount
        announcedIsCountExact = isCountExact
    }
}
