import Foundation

/// Ô thử rule (trang "Thử nhanh một câu" và sheet "Thử rule" của danh sách rule): luôn bỏ qua công tắc tổng và không
/// dùng memo, nhưng **vẫn tôn trọng file tắt** — nếu không nó nói khác kết quả thật của Reader.
///
/// Bộ rule áp theo **phạm vi** của chỗ mở ô thử, như khi dịch thật:
/// - `.global`: chỉ bộ chung (không truyện nào) — như trang "Thử nhanh một câu" từ trước tới nay.
/// - `.chapterTitle`: bộ tên chương + bộ chung — như khi dịch **tên chương** (tên chương thắng chung khi hoà). Trước
///   đây ô thử bỏ hẳn bộ tên chương nên rule tên chương không bao giờ khớp ở đây.
/// - `.book(bookId)`: bộ riêng của truyện + bộ chung, với `bookId` của truyện (file tắt riêng, token, thứ tự ưu tiên,
///   bộ ngoặc, Name riêng). Bộ tên chương không áp: ô thử dịch một câu nội dung.
///
/// Mỗi đoạn do rule sinh mang `scopeRank` (`QuickTranslationRewriteResult.Segment`) để bên hiển thị tra đúng mẫu theo
/// cặp (bộ, dòng) — số dòng trùng nhau giữa các bộ.
extension QuickTranslationRuleEngine {
    public static func preview(
        _ text: String,
        scope: QuickTranslationRuleScope = .global,
        mode: PreviewMode = .respectTokenConfiguration
    ) -> QuickTranslationRewriteResult? {
        guard !text.isEmpty else { return nil }
        let bookId = scope.bookId
        let globalSnapshot = nonEmpty(QuickTranslationRuleStore.shared.currentSnapshot)
        let bookSnapshot = bookId.flatMap { nonEmpty(QuickTranslationRuleBookStore.shared.snapshot(for: $0)) }
        let chapterSnapshot = scope.isChapterTitle ? nonEmpty(QuickTranslationRuleChapterStore.shared.currentSnapshot) : nil
        guard globalSnapshot != nil || bookSnapshot != nil || chapterSnapshot != nil else { return nil }

        let tokenConfiguration: QuickTranslationRuleTokenSettings.Configuration
        switch mode {
        case .respectTokenConfiguration:
            tokenConfiguration = QuickTranslationBookEngineConfigStore.shared
                .tokenConfiguration(bookId: bookId)
        case .ignoreTokenConfiguration:
            tokenConfiguration = .allEnabled
        }
        return execute(
            text,
            ruleSets: [
                (bookSnapshot, QuickTranslationRuleScope.bookRank),
                (chapterSnapshot, QuickTranslationRuleScope.chapterTitleRank),
                (globalSnapshot, QuickTranslationRuleScope.globalRank)
            ],
            bookId: bookId,
            tokenConfiguration: tokenConfiguration,
            priority: QuickTranslationBookEngineConfigStore.shared.priorityConfiguration(bookId: bookId)
        )
    }
}
