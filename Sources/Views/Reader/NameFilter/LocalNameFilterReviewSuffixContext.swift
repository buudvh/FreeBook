import Foundation

/// Phần **đuôi** của màn duyệt luồng Lọc name local (plan 2026-11-27-nghia-ten-tay-huyen mục 7): biết truyện + nghĩa máy
/// ghép của từng name (`LocalNameFilterDraft.AutoMeaning`) để
/// - màn Sửa từ biết name nào có hàng "Đuôi" (`LocalNameFilterSuffixQuickRow`) và loại đuôi gợi ý (`suffixKind`);
/// - ghép lại nghĩa **ngay** sau khi thêm / sửa một đuôi (`recompose`): chỉ name không phải người / họ tộc, kết thúc bằng
///   đuôi đó (còn ≥ 1 chữ phía trước), nghĩa vẫn do máy ghép — bằng đúng bộ ghép nghĩa của bộ lọc
///   (`LocalNameFilterMeaningComposer`) với danh sách đuôi hiện tại + công tắc "Ưu tiên tên Latin" của truyện.
///
/// `LocalNameFilterSession` tạo khi vào màn duyệt (lọc xong / mở gói); nghĩa máy ghép đổi thì báo lại session (`onChange`)
/// để gói tạm mang bản mới. `public` chỉ vì `ReaderAINameReviewSheet` (kiểu `public`) nhận nó ở init.
///
/// Chỉ dùng trên main: `suffixKind` gọi lúc dựng màn Sửa từ, `recompose` cô lập `@MainActor` (ghi `autoMeanings`). Lớp
/// không gắn `@MainActor` cả lớp vì nội dung `.sheet` của SDK cũ không chắc chạy trong ngữ cảnh main-actor.
public final class LocalNameFilterReviewSuffixContext {
    /// Một name đổi nghĩa sau khi ghép lại.
    struct Change {
        let old: String
        let new: String
        let isGuessed: Bool
    }

    let bookId: String
    private(set) var autoMeanings: [String: LocalNameFilterDraft.AutoMeaning]?
    private let onChange: ([String: LocalNameFilterDraft.AutoMeaning]) -> Void

    init(
        bookId: String,
        autoMeanings: [String: LocalNameFilterDraft.AutoMeaning]?,
        onChange: @escaping ([String: LocalNameFilterDraft.AutoMeaning]) -> Void
    ) {
        self.bookId = bookId
        self.autoMeanings = autoMeanings
        self.onChange = onChange
    }

    /// Loại đuôi gợi ý khi thêm đuôi từ name này; `nil` = tên người (không có hàng "Đuôi"). Theo loại lúc lọc, gói cũ chưa
    /// có thì theo nhãn nhóm của hàng.
    func suffixKind(for item: AIExtractedName) -> LocalNameFilter.SuffixKind? {
        if let kind = autoMeanings?[item.original]?.kind {
            switch kind {
            case .place: return .place
            case .sect, .family: return .sect
            case .term: return .term
            case .person: return nil
            }
        }
        switch item.category {
        case LocalNameFilter.Category.place.label: return .place
        case LocalNameFilter.Category.organization.label: return .sect
        case LocalNameFilter.Category.term.label: return .term
        default: return nil
        }
    }

    /// Ghép lại nghĩa các name kết thúc bằng `suffix` (xem doc của type). Trả thay đổi theo `id` của name — màn duyệt chỉ
    /// áp cho name mà nghĩa lúc đó vẫn là `old` (người dùng chưa sửa trong lúc chờ). Gói cũ chưa có nghĩa máy ghép, bật Latin
    /// mà thiếu mô hình, VietPhrase chưa nạp ⇒ không đổi gì.
    @MainActor
    func recompose(_ names: [AIExtractedName], suffix: String) async -> [UUID: Change] {
        guard var auto = autoMeanings, !suffix.isEmpty else { return [:] }
        let suffixLength = suffix.unicodeScalars.count
        let candidates: [(id: UUID, term: String, kind: LocalNameFilter.Kind, old: String)] = names.compactMap { item in
            guard let entry = auto[item.original], LocalNameFilterMeaningComposer.canRecompose(entry.kind),
                  item.suggestedMeaning == entry.meaning, item.original.hasSuffix(suffix),
                  item.original.unicodeScalars.count > suffixLength else { return nil }
            return (item.id, item.original, entry.kind, item.suggestedMeaning)
        }
        guard !candidates.isEmpty else { return [:] }

        let bookId = self.bookId
        let suffixes = LocalNameFilterSuffixStore.shared.allSuffixes()
        var latinModel: LocalNameFilterLatinModel?
        if LocalNameFilterLatinPreferenceStore.shared.prefersLatin(bookId: bookId) {
            do {
                latinModel = try await LocalNameFilterLatinModelGate.shared.model()
            } catch {
                if !(error is CancellationError) {
                    AppLogger.shared.log("❌ [LọcName] Không ghép lại nghĩa sau khi thêm đuôi: thiếu mô hình đoán tên Latin — "
                        + error.localizedDescription)
                }
                return [:]
            }
        }
        let model = latinModel
        let terms = candidates.map { (term: $0.term, kind: $0.kind) }
        let rebuilt = await Task.detached(priority: .userInitiated) { () -> [String: (meaning: String, isGuessed: Bool)] in
            guard let composer = LocalNameFilterMeaningComposer(bookId: bookId, suffixes: suffixes, latinModel: model) else {
                return [:]
            }
            var result: [String: (meaning: String, isGuessed: Bool)] = [:]
            for item in terms where result[item.term] == nil {
                if let built = composer.meaning(term: item.term, kind: item.kind) { result[item.term] = built }
            }
            return result
        }.value

        var changes: [UUID: Change] = [:]
        for candidate in candidates {
            guard let built = rebuilt[candidate.term], built.meaning != candidate.old
                    || built.isGuessed != (names.first { $0.id == candidate.id }?.isGuessedMeaning ?? false) else { continue }
            changes[candidate.id] = Change(old: candidate.old, new: built.meaning, isGuessed: built.isGuessed)
            auto[candidate.term] = LocalNameFilterDraft.AutoMeaning(meaning: built.meaning, kind: candidate.kind)
        }
        if !changes.isEmpty {
            autoMeanings = auto
            onChange(auto)
            AppLogger.shared.log("🔎 [LọcName] Thêm / sửa đuôi \(suffix) ⇒ ghép lại \(changes.count) name ở màn duyệt")
        }
        return changes
    }
}
