import Foundation

/// Phạm vi của một rule dịch — **ba bộ rule thật**:
///
/// - `.global` → `translate/QuickTranslateRules.txt`
/// - `.chapterTitle` → `translate/QuickTranslateChapterRules.txt` (1.3.683): dùng chung mọi truyện nhưng
///   **chỉ** áp khi dịch tên chương (`TranslateUtils.translateChapterTitle`), không bao giờ cho nội dung.
/// - `.book(bookId)` → `translate/books/<bookId>/QuickTranslateRules.txt`
///
/// Khi mọi tiêu chí ưu tiên khác bằng nhau: riêng thắng tên chương, tên chương thắng chung
/// (`QuickTranslationCompiledRule.scopeRank`, số nhỏ thắng).
public enum QuickTranslationRuleScope: Hashable, Sendable {
    case global
    case book(String)
    case chapterTitle

    /// Hạng của từng bộ trong `QuickTranslationCompiledRule.scopeRank`. Đổi số ở đây là đổi thứ tự ưu tiên.
    public static let bookRank = 0
    public static let chapterTitleRank = 1
    public static let globalRank = 2

    public var isGlobal: Bool {
        if case .global = self { return true }
        return false
    }

    public var isChapterTitle: Bool {
        if case .chapterTitle = self { return true }
        return false
    }

    /// `nil` với bộ chung và bộ tên chương — dùng làm tham số `bookId` cho các API đang có.
    public var bookId: String? {
        if case .book(let identifier) = self { return identifier }
        return nil
    }

    /// Riêng 0, tên chương 1, chung 2 — số nhỏ thắng khi trùng mọi tiêu chí ưu tiên khác.
    public var rank: Int {
        switch self {
        case .book: return Self.bookRank
        case .chapterTitle: return Self.chapterTitleRank
        case .global: return Self.globalRank
        }
    }

    public var label: String {
        switch self {
        case .book: return "Riêng"
        case .chapterTitle: return "Tên chương"
        case .global: return "Chung"
        }
    }

    /// Nhãn dài cho tiêu đề màn hình và thông báo.
    public var longLabel: String {
        switch self {
        case .book: return "Bộ rule riêng của truyện"
        case .chapterTitle: return "Bộ rule tên chương"
        case .global: return "Bộ rule chung"
        }
    }

    /// Khoá ổn định để dựng `id` (chip rule, bản nháp màn sửa): phân biệt đủ ba phạm vi và từng truyện.
    public var identityKey: String {
        switch self {
        case .book(let identifier): return "book:\(identifier)"
        case .chapterTitle: return "chapterTitle"
        case .global: return "global"
        }
    }
}
