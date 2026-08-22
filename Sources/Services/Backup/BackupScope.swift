import Foundation

/// Nhóm nội dung người dùng chọn khi sao lưu / khôi phục.
///
/// `books` là nền của mọi nhóm khác (mọi entry còn lại tra theo `slug` trong `library/slugs.json`)
/// nên luôn bật, không cho tắt. Ảnh bìa **không** có nhóm nào: bìa tải lại được từ `coverUrl`.
public enum BackupScope: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Danh sách truyện + tiến độ đọc + mục lục chương (metadata).
    case books
    /// Nội dung chương đã tải về (`books/<sha256>.bin`).
    case content
    /// Extension đã cài + danh sách kho.
    case extensions
    /// Từ điển VietPhrase/Names riêng của từng truyện.
    case dictBooks
    /// Custom VietPhrase/Names dùng chung (kể cả mục đã xoá — tombstone nằm trong chính file TXT).
    case dictCustom
    /// Từ điển chung dung lượng lớn (`.dat` + `ChinesePhienAmWords.txt`).
    case dictShared

    public var id: String { rawValue }

    /// Mặc định bật hết theo yêu cầu.
    public static var defaultSelection: Set<BackupScope> { Set(allCases) }

    public var isMandatory: Bool { self == .books }

    public var title: String {
        switch self {
        case .books: return "Danh sách truyện & mục lục"
        case .content: return "Nội dung chương đã tải"
        case .extensions: return "Extension & danh sách kho"
        case .dictBooks: return "Từ điển riêng từng truyện"
        case .dictCustom: return "Custom VietPhrase / Names"
        case .dictShared: return "Từ điển chung (dung lượng lớn)"
        }
    }

    public var subtitle: String {
        switch self {
        case .books: return "Bắt buộc — nền của mọi nhóm khác, kèm tiến độ đọc"
        case .content: return "Chương đã tải offline; có thể rất lớn"
        case .extensions: return "File extension trong máy + kho tải về"
        case .dictBooks: return "Gồm cả mục VietPhrase/Names đã xoá"
        case .dictCustom: return "Gồm cả mục đã xoá"
        case .dictShared: return "VietPhrase/Names/Pronouns/LuatNhan/PhienAm dùng chung"
        }
    }

    /// Thứ tự hiển thị ổn định cho UI.
    public static var displayOrder: [BackupScope] {
        [.books, .content, .extensions, .dictBooks, .dictCustom, .dictShared]
    }
}
