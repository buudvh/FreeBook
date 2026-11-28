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
/// - **đổi Phân loại** của một name trong lượt duyệt (`changeKind`, 2026-11-28 — mockup
///   https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2, hợp đồng lõi mục 7): nghĩa máy ghép + loại của gói tạm theo
///   nhóm mới, ghép lại nghĩa khi người dùng chưa sửa tay; nhóm lúc lọc nhớ trong bộ nhớ (`originalCategory`), không lưu.
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
    /// Lượt ghép lại trước (`enqueueRecompose`, `changeKind`): lượt sau chờ nó xong — cả bước áp lên màn — rồi mới đọc danh
    /// sách.
    private var queue: Task<Void, Never>?
    /// Nhóm lúc lọc của name đã đổi Phân loại trong lượt duyệt này (khoá = chữ Hán) — chỉ bộ nhớ, đóng màn duyệt là mất.
    private var originalCategories: [String: LocalNameFilter.Category] = [:]

    init(
        bookId: String,
        autoMeanings: [String: LocalNameFilterDraft.AutoMeaning]?,
        onChange: @escaping ([String: LocalNameFilterDraft.AutoMeaning]) -> Void
    ) {
        self.bookId = bookId
        self.autoMeanings = autoMeanings
        self.onChange = onChange
    }

    /// Loại gợi ý khi thêm hậu tố / tiền tố từ name này = nhóm **đang hiện** của name (nhãn badge — đổi ngay khi người dùng
    /// đổi Phân loại, trước khi `changeKind` kịp ghi gói tạm; tên người ⇒ Nhân danh); `nil` = họ tộc hoặc nhãn ngoài bốn nhóm
    /// (không có hàng "Phân loại" / "Tiền tố" / "Hậu tố").
    func affixKind(for item: AIExtractedName) -> LocalNameFilter.SuffixKind? {
        // Họ tộc (萧家) không bao giờ ghép lại (`canRecompose`) ⇒ không có hàng; nhãn của nó trùng "Tổ chức" nên phải hỏi
        // loại lúc lọc.
        if autoMeanings?[item.original]?.kind == .family { return nil }
        switch item.category {
        case LocalNameFilter.Category.person.label: return .person
        case LocalNameFilter.Category.place.label: return .place
        case LocalNameFilter.Category.organization.label: return .sect
        case LocalNameFilter.Category.term.label: return .term
        default: return nil
        }
    }

    /// Nhóm lúc lọc của name nếu lượt duyệt này đã đổi Phân loại của nó (hàng "Phân loại" ghi "Lúc lọc: …").
    func originalCategory(of term: String) -> LocalNameFilter.Category? {
        originalCategories[term]
    }

    /// Ghi nhớ nhóm lúc lọc **trước** lần đổi đầu tiên (lần sau giữ giá trị cũ). Gọi đồng bộ từ màn duyệt để hàng "Phân loại"
    /// vẽ lại ngay đã có nhãn.
    func rememberOriginalCategory(_ category: LocalNameFilter.Category?, of term: String) {
        guard let category, originalCategories[term] == nil else { return }
        originalCategories[term] = category
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

        // Nghĩa máy ghép lần trước đi kèm: tên người giữ danh xưng 1 chữ đã dùng ("Lâm ca") như gói tạm tự cập nhật.
        let terms = candidates.map { (term: $0.term, kind: $0.kind, previous: $0.old) }
        guard let rebuilt = await composeMeanings(terms, reason: "thêm \(flavor.lowercasedNoun)") else { return [:] }

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

    /// Đổi **Phân loại** của một name (hàng "Phân loại" ở màn Sửa từ; hợp đồng lõi mục 7): xếp vào **cùng hàng đợi** với
    /// `enqueueRecompose` (vừa đổi loại vừa thêm hậu tố không chồng lượt). Màn duyệt đã đổi nhãn badge trước khi gọi.
    /// - Ghi `autoMeanings[term]` = nghĩa máy ghép theo **loại mới** (ghép không được ⇒ giữ nghĩa cũ) + loại mới, báo session
    ///   (`onChange`) ⇒ gói tạm nhớ loại mới, gói tạm tự cập nhật ghép theo loại mới.
    /// - Chỉ khi nghĩa đang hiện **vẫn là nghĩa máy** (chưa sửa tay) và nghĩa mới khác thật ⇒ `apply` một `Change` để màn duyệt
    ///   đổi nghĩa + cờ "đoán".
    /// Gói cũ không có nghĩa máy ghép (`autoMeanings == nil`) hoặc name không có trong đó ⇒ không làm gì (chỉ đổi nhãn).
    @MainActor
    func changeKind(
        of term: String,
        itemId: UUID,
        to kind: LocalNameFilter.Kind,
        currentNames: @escaping @MainActor () -> [AIExtractedName],
        apply: @escaping @MainActor (Change) -> Void
    ) {
        let previous = queue
        queue = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, let entry = self.autoMeanings?[term], entry.kind != kind else { return }
            var machineMeaning = entry.meaning
            var change: Change?
            if LocalNameFilterMeaningComposer.canRecompose(kind),
               let built = await self.composeMeanings([(term: term, kind: kind, previous: entry.meaning)],
                                                      reason: "đổi phân loại")?[term] {
                machineMeaning = built.meaning
                if let item = currentNames().first(where: { $0.id == itemId }),
                   item.suggestedMeaning == entry.meaning, built.meaning != item.suggestedMeaning {
                    change = Change(old: item.suggestedMeaning, new: built.meaning, isGuessed: built.isGuessed)
                }
            }
            // Gộp vào bản hiện tại (các `await` ở trên có thể đã để lượt khác ghi `autoMeanings`).
            var current = self.autoMeanings ?? [:]
            current[term] = LocalNameFilterDraft.AutoMeaning(meaning: machineMeaning, kind: kind)
            self.autoMeanings = current
            self.onChange(current)
            AppLogger.shared.log("🔎 [LọcName] Đổi phân loại \(term) ⇒ \(kind.label)"
                + (change == nil ? "" : ", ghép lại nghĩa ở màn duyệt"))
            if let change { apply(change) }
        }
    }

    /// Ghép nghĩa máy cho `terms` bằng đúng bộ ghép của bộ lọc với danh sách hậu tố + tiền tố **hiệu lực của truyện**
    /// (`allSuffixes(bookId:)` / `allPrefixes(bookId:)`, khớp dấu gói tạm) + mô hình Latin khi truyện bật "Ưu tiên tên Latin";
    /// chạy ngoài main. Trả nghĩa theo chữ Hán (thiếu ⇒ không ghép được); `nil` = bật Latin mà thiếu mô hình (đã log) — nơi
    /// gọi không đổi gì. `reason` vào dòng log lỗi.
    @MainActor
    private func composeMeanings(
        _ terms: [(term: String, kind: LocalNameFilter.Kind, previous: String)],
        reason: String
    ) async -> [String: (meaning: String, isGuessed: Bool)]? {
        let bookId = self.bookId
        let suffixes = LocalNameFilterSuffixStore.shared.allSuffixes(bookId: bookId)
        var latinModel: LocalNameFilterLatinModel?
        if LocalNameFilterLatinPreferenceStore.shared.prefersLatin(bookId: bookId) {
            do {
                latinModel = try await LocalNameFilterLatinModelGate.shared.model()
            } catch {
                if !(error is CancellationError) {
                    AppLogger.shared.log("❌ [LọcName] Không ghép lại nghĩa sau khi \(reason): thiếu mô hình "
                        + "đoán tên Latin — " + error.localizedDescription)
                }
                return nil
            }
        }
        let model = latinModel
        let prefixes = LocalNameFilterPrefixStore.shared.allPrefixes(bookId: bookId)
        return await Task.detached(priority: .userInitiated) { () -> [String: (meaning: String, isGuessed: Bool)] in
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
    }
}
