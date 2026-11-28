import Foundation

/// Phần **hậu tố / tiền tố** của màn duyệt luồng Lọc name local (plan 2026-11-27-nghia-ten-tay-huyen mục 7,
/// 2026-11-27-phan-loai-name L10 / L11): biết truyện + nghĩa máy ghép của từng name (`LocalNameFilterDraft.AutoMeaning`) để
/// - màn Sửa từ biết name nào có hàng "Tiền tố" / "Hậu tố" (`LocalNameFilterSuffixQuickRow`) và loại gợi ý cho mục mới
///   (`affixKind`) — mọi loại name trừ họ tộc;
/// - ghép lại nghĩa **ngay** sau khi thêm / sửa một hậu tố / tiền tố (`recompose`): name ghép lại được
///   (`LocalNameFilterMeaningComposer.canRecompose` — tên người, địa danh, tổ chức, thuật ngữ; không họ tộc) kết thúc bằng
///   hậu tố / mở đầu bằng tiền tố đó (còn ≥ 1 chữ phía bên kia), nghĩa vẫn do máy ghép — bằng đúng bộ ghép nghĩa của bộ lọc
///   với danh sách hậu tố + tiền tố hiện tại + công tắc "Ưu tiên tên Latin" của truyện.
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

    /// Loại gợi ý khi thêm hậu tố / tiền tố từ name này = nhóm của name (tên người ⇒ Nhân danh); `nil` = họ tộc (không có
    /// hàng "Tiền tố" / "Hậu tố"). Theo loại lúc lọc, gói cũ chưa có thì theo nhãn nhóm của hàng.
    func affixKind(for item: AIExtractedName) -> LocalNameFilter.SuffixKind? {
        if let kind = autoMeanings?[item.original]?.kind {
            switch kind {
            case .person: return .person
            case .place: return .place
            case .sect: return .sect
            case .term: return .term
            // Họ tộc (萧家) không bao giờ ghép lại (`canRecompose`) ⇒ không có hàng.
            case .family: return nil
            }
        }
        switch item.category {
        case LocalNameFilter.Category.person.label: return .person
        case LocalNameFilter.Category.place.label: return .place
        case LocalNameFilter.Category.organization.label: return .sect
        case LocalNameFilter.Category.term.label: return .term
        default: return nil
        }
    }

    /// Xếp hàng một lượt ghép lại sau khi lưu hậu tố / tiền tố: các lượt chạy **lần lượt** (lưu hai mục liền nhau, nhất là
    /// lúc mô hình Latin đang tải lần đầu, không còn chồng nhau); mỗi lượt chờ lượt trước áp xong lên màn rồi mới đọc danh
    /// sách (`currentNames`) ⇒ name vừa đổi ở lượt trước được ghép tiếp theo mục mới. `affixes` theo thứ tự: khoá vừa lưu
    /// rồi khoá cũ khi đổi chữ — khoá sau bỏ qua name khoá trước đã đổi. `apply` nhận thay đổi gộp của cả lượt.
    @MainActor
    func enqueueRecompose(
        affixes: [String],
        flavor: LocalNameFilterAffixListFlavor,
        currentNames: @escaping @MainActor () -> [AIExtractedName],
        apply: @escaping @MainActor ([UUID: Change]) -> Void
    ) {
        let previous = queue
        queue = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            let names = currentNames()
            var changes: [UUID: Change] = [:]
            for affix in affixes {
                let more = await self.recompose(names, affix: affix, flavor: flavor)
                changes.merge(more) { first, _ in first }
            }
            apply(changes)
        }
    }

    /// Ghép lại nghĩa các name kết thúc bằng hậu tố / mở đầu bằng tiền tố `affix` (xem doc của type). Trả thay đổi theo `id`
    /// của name — màn duyệt chỉ áp cho name mà nghĩa lúc đó vẫn là `old` (người dùng chưa sửa trong lúc chờ). Gói cũ chưa có
    /// nghĩa máy ghép, bật Latin mà thiếu mô hình, VietPhrase chưa nạp ⇒ không đổi gì.
    @MainActor
    func recompose(_ names: [AIExtractedName], affix: String, flavor: LocalNameFilterAffixListFlavor) async -> [UUID: Change] {
        guard var auto = autoMeanings, !affix.isEmpty else { return [:] }
        let candidates: [(id: UUID, term: String, kind: LocalNameFilter.Kind, old: String)] = names.compactMap { item in
            guard let entry = auto[item.original], LocalNameFilterMeaningComposer.canRecompose(entry.kind),
                  item.suggestedMeaning == entry.meaning,
                  flavor.remainder(of: item.original, removing: affix) != nil else { return nil }
            return (item.id, item.original, entry.kind, item.suggestedMeaning)
        }
        guard !candidates.isEmpty else { return [:] }

        let bookId = self.bookId
        let suffixes = LocalNameFilterSuffixStore.shared.allSuffixes(bookId: bookId)
        var latinModel: LocalNameFilterLatinModel?
        if LocalNameFilterLatinPreferenceStore.shared.prefersLatin(bookId: bookId) {
            do {
                latinModel = try await LocalNameFilterLatinModelGate.shared.model()
            } catch {
                if !(error is CancellationError) {
                    AppLogger.shared.log("❌ [LọcName] Không ghép lại nghĩa sau khi thêm \(flavor.lowercasedNoun): thiếu mô hình "
                        + "đoán tên Latin — " + error.localizedDescription)
                }
                return [:]
            }
        }
        let model = latinModel
        let prefixes = LocalNameFilterPrefixStore.shared.allPrefixes(bookId: bookId)
        // Nghĩa máy ghép lần trước đi kèm: tên người giữ danh xưng 1 chữ đã dùng ("Lâm ca") như gói tạm tự cập nhật.
        let terms = candidates.map { (term: $0.term, kind: $0.kind, previous: $0.old) }
        let rebuilt = await Task.detached(priority: .userInitiated) { () -> [String: (meaning: String, isGuessed: Bool)] in
            guard let composer = LocalNameFilterMeaningComposer(
                bookId: bookId, suffixes: suffixes, latinModel: model, prefixes: prefixes
            ) else {
                return [:]
            }
            var result: [String: (meaning: String, isGuessed: Bool)] = [:]
            for item in terms where result[item.term] == nil {
                if let built = composer.meaning(term: item.term, kind: item.kind, previousMeaning: item.previous) {
                    result[item.term] = built
                }
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
            AppLogger.shared.log("🔎 [LọcName] Thêm / sửa \(flavor.lowercasedNoun) \(affix) ⇒ ghép lại \(changes.count) name "
                + "ở màn duyệt")
        }
        return changes
    }
}
