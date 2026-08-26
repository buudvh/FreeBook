import Foundation

/// Phạm vi của một rule dịch — **hai bộ rule thật**, đúng mô hình "VP riêng / VP chung" của từ điển:
///
/// - `.global` → `translate/QuickTranslateRules.txt`
/// - `.book(bookId)` → `translate/books/<bookId>/QuickTranslateRules.txt`
///
/// Rule của bộ riêng **thắng** rule của bộ chung khi mọi tiêu chí ưu tiên khác bằng nhau
/// (`QuickTranslationCompiledRule.scopeRank`).
public enum QuickTranslationRuleScope: Hashable, Sendable {
    case global
    case book(String)

    public var isGlobal: Bool {
        if case .global = self { return true }
        return false
    }

    /// `nil` với phạm vi chung — dùng làm tham số `bookId` cho các API đang có.
    public var bookId: String? {
        if case .book(let identifier) = self { return identifier }
        return nil
    }

    /// Rule của bộ riêng xếp trước bộ chung khi trùng mọi tiêu chí ưu tiên khác.
    public var rank: Int {
        isGlobal ? 1 : 0
    }

    public var label: String {
        isGlobal ? "Chung" : "Riêng"
    }

    /// Nhãn dài cho tiêu đề màn hình và thông báo.
    public var longLabel: String {
        isGlobal ? "Bộ rule chung" : "Bộ rule riêng của truyện"
    }
}
