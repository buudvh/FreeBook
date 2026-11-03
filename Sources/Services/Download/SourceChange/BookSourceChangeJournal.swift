import Foundation

/// Nhật ký của **một** lượt đổi nguồn đang dở (1.3.689), ghi xuống đĩa **trước** tác dụng phụ đầu tiên. App chết giữa
/// chừng thì lần mở sau đọc lại để đi tiếp hoặc lùi lại (`BookSourceChangeCoordinator.recoverIfNeeded`).
///
/// Trước 1.3.689 không có nhật ký: chết sau khi chép chương mà trước khi xoá truyện cũ ⇒ hai truyện, thiết lập riêng
/// (từ điển, phiên AI…) đã rời truyện cũ, không ai dọn.
///
/// Mốc chốt là `.committed`: trước mốc, truyện cũ còn **nguyên vẹn** (mọi thứ chỉ được chép sang) ⇒ lùi = xoá truyện mới;
/// sau mốc, truyện mới đã đủ ⇒ tiến = dọn truyện cũ. Mỗi lần chỉ có một lượt (một file).
struct BookSourceChangeJournal: Codable, Sendable, Equatable {
    enum Phase: String, Codable, Sendable {
        /// Đang tạo/làm mới truyện đích, chép chương và thiết lập.
        case copying
        /// Truyện đích đã đủ; còn lại là dọn truyện cũ.
        case committed
    }

    let oldBookId: String
    let newBookId: String
    /// Tên truyện cũ, chỉ để hiện trong thông báo khôi phục.
    let bookTitle: String
    /// `true` = lượt này tạo ra truyện đích ⇒ lùi lại thì xoá nó. `false` = dùng lại truyện đã có trên máy ⇒ giữ nguyên.
    let createdNewBook: Bool
    /// Giữ truyện cũ sau khi xong (đang nghe TTS truyện đó, hoặc có chương chép lỗi).
    var keepsOldBook: Bool
    var phase: Phase
    let startedAt: Date

    private static var fileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("source_change", isDirectory: true)
            .appendingPathComponent("journal.json")
    }

    static func load() -> BookSourceChangeJournal? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(BookSourceChangeJournal.self, from: data)
        } catch {
            AppLogger.shared.log("❌ [SourceChangeJournal] Nhật ký đổi nguồn hỏng, bỏ qua: \(error.localizedDescription)")
            clear()
            return nil
        }
    }

    /// Ghi nguyên tử (`.atomic`): đọc lại luôn thấy bản cũ hoặc bản mới, không bao giờ nửa file.
    func save() throws {
        guard let url = Self.fileURL else {
            throw NSError(domain: "BookSourceChangeJournal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy thư mục dữ liệu app"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLogger.shared.log("❌ [SourceChangeJournal] Không xoá được nhật ký đổi nguồn: \(error.localizedDescription)")
        }
    }
}
