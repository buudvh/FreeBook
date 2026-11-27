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
    /// Lượt ghép lại trước (`enqueueRecompose`): lượt sau chờ nó xong — cả bước áp lên màn — rồi mới đọc danh sách.
    private var queue: Task<Void, Never>?

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
            case .sect: return .sect
            case .term: return .term
            // Họ tộc (萧家) không bao giờ ghép lại theo đuôi (`canRecompose`) ⇒ không có hàng "Đuôi", như tên người.
            case .person, .family: return nil
            }
        }
        switch item.category {
        case LocalNameFilter.Category.place.label: return .place
        case LocalNameFilter.Category.organization.label: return .sect
        case LocalNameFilter.Category.term.label: return .term
        default: return nil
        }
    }

    /// Xếp hàng một lượt ghép lại sau khi lưu đuôi: các lượt chạy **lần lượt** (lưu hai đuôi liền nhau, nhất là lúc mô hình
    /// Latin đang tải lần đầu, không còn chồng nhau); mỗi lượt chờ lượt trước áp xong lên màn rồi mới đọc danh sách
    /// (`currentNames`) ⇒ name vừa đổi ở lượt trước được ghép tiếp theo đuôi mới. `suffixes` theo thứ tự: khoá vừa lưu
    /// rồi khoá cũ khi đổi chữ đuôi — khoá sau bỏ qua name khoá trước đã đổi. `apply` nhận thay đổi gộp của cả lượt.
    @MainActor
    func enqueueRecompose(
        suffixes: [String],
        currentNames: @escaping @MainActor () -> [AIExtractedName],
        apply: @escaping @MainActor ([UUID: Change]) -> Void
    ) {
        let previous = queue
        queue = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            let names = currentNames()
            var changes: [UUID: Change] = [:]
            for suffix in suffixes {
                let more = await self.recompose(names, suffix: suffix)
                changes.merge(more) { first, _ in first }
            }
            apply(changes)
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
            // Chỉ khi nghĩa đổi thật: nghĩa giữ nguyên thì không đụng cờ "đoán" (người dùng bấm Cập nhật để xác nhận đã bỏ
            // cờ — so cờ ở đây sẽ bật lại nhãn và đếm dư vào toast).
            guard let built = rebuilt[candidate.term], built.meaning != candidate.old else { continue }
            changes[candidate.id] = Change(old: candidate.old, new: built.meaning, isGuessed: built.isGuessed)
            auto[candidate.term] = LocalNameFilterDraft.AutoMeaning(meaning: built.meaning, kind: candidate.kind)
        }
        if !changes.isEmpty {
            // Chỉ gộp khoá vừa đổi vào bản hiện tại (bản chụp `auto` có từ trước các `await`).
            var current = autoMeanings ?? [:]
            for candidate in candidates where changes[candidate.id] != nil {
                current[candidate.term] = auto[candidate.term]
            }
            autoMeanings = current
            onChange(current)
            AppLogger.shared.log("🔎 [LọcName] Thêm / sửa đuôi \(suffix) ⇒ ghép lại \(changes.count) name ở màn duyệt")
        }
        return changes
    }
}
