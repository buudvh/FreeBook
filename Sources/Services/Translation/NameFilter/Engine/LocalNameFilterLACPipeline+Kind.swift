import Foundation

/// Bước 4 của phía LAC — loại của một hàng (`classify` của `lacpipe.py`, plan `Docs/Plans/2026-11-27-phan-loai-name.md`,
/// anh Bửu duyệt). Thứ tự:
///
/// 1. Hậu tố dò dài nhất (`setup.lacSuffix`, bộ cố định — cách A):
///    - Nhân danh (L11, hậu tố 2–6 chữ của bản gốc) ⇒ người (天元圣女 — LAC xếp Thuật ngữ);
///    - địa danh / tổ chức mà LAC bảo người + chữ cuối là đuôi yếu phía LAC (山 峰 河… + 卫 泽): L2 — nhãn thường nhiều hơn
///      nhãn thực thể, không mở đầu bằng họ, không có danh xưng ⇒ theo hậu tố (魔渊, 血河); L1 — ≥ 3 chữ không mở đầu bằng
///      họ ⇒ theo hậu tố (玄剑峰, 执事堂); L16 (2026-11-28) — phần trước hậu tố (hoặc nó bỏ một tiền tố của danh sách) có
///      nghĩa từ điển là tên Latin thật (`LocalNameFilterProperNames.hasLatinCore`: 霍伊 = Khoy) ⇒ theo hậu tố (霍伊河);
///      còn lại vẫn là người (刘云峰, 楚渊, 王精卫);
///    - còn lại ⇒ loại của hậu tố.
/// 2. Không hậu tố ⇒ nhãn LAC nhiều nhất. LAC bảo người, không mở đầu bằng họ, không có danh xưng: L3 — chữ cuối là loài
///    vật / yêu ma, không mở đầu bằng 阿 / 小 ⇒ Thuật ngữ (蜃龙, 啸月银狼); L4 — nhãn thường ≥ 2 lần nhãn thực thể, không mở
///    đầu bằng 小 / 阿 / 老, không kết thúc bằng 儿 / 子 ⇒ Thuật ngữ (天君, 虚空乱流).
///
/// Nhãn thường / thực thể đếm **thô** trên đúng từ (trước khi gộp), như luật (e). "Mở đầu bằng họ" =
/// `LocalNameFilterDictionaries.surnameLength(of:) > 0`; "có danh xưng" = `LocalNameFilterSetup.personTitle` (hậu tố Nhân
/// danh của danh sách người dùng, hoặc danh xưng 1 chữ đã qua chốt của bộ luật).
extension LocalNameFilterLACPipeline {
    func kind(
        of word: Word,
        suffix: SuffixMatch?,
        tag: LocalNameFilter.Category,
        entities: [Word: LocalNameFilterLACCounts.Entry],
        statsOf statsWord: Word? = nil
    ) -> LocalNameFilter.Kind {
        // `stat` của `classify` (đợt 4): cụm đã nối lấy nhãn thường / thực thể của cụm gốc LAC gắn nhãn.
        let counted = statsWord ?? word
        let entity = entities[counted]?.tally.total ?? 0
        let other = counts.others[counted] ?? 0
        if let suffix {
            let kind = Self.kind(for: suffix.suffix.kind)
            if kind == .person { return .person }
            guard tag == .person, Rules.lacWeakSuffixScalars.contains(word.last), kind == .place || kind == .sect else {
                return kind
            }
            let startsWithSurname = dictionaries.surnameLength(of: word) > 0
            if other > entity, !startsWithSurname, !hasTitle(word) { return kind }
            if word.count >= 3, !startsWithSurname { return kind }
            // L16: phần trước hậu tố (hoặc nó bỏ một tiền tố của danh sách) có nghĩa Latin trong từ điển (霍伊 = Khoy) ⇒ chữ
            // đầu không phải họ ⇒ theo hậu tố (霍伊河, 苏尼亚海). Không theo công tắc "Ưu tiên tên Latin".
            if properNames.hasLatinCore(word.dropLast(suffix.length)) { return kind }
            return .person
        }
        let kind = Self.kind(for: tag)
        guard tag == .person, dictionaries.surnameLength(of: word) == 0, !hasTitle(word) else { return kind }
        if Rules.creatureScalars.contains(word.last), !Rules.creatureKeepStartScalars.contains(word[0]) { return .term }
        if other >= Rules.commonTagFactor * entity, !Rules.commonKeepStartScalars.contains(word[0]),
           !Rules.commonKeepEndScalars.contains(word.last) {
            return .term
        }
        return kind
    }

    static func kind(for category: LocalNameFilter.Category) -> LocalNameFilter.Kind {
        switch category {
        case .person: return .person
        case .place: return .place
        case .organization: return .sect
        case .term: return .term
        }
    }

    static func kind(for suffixKind: LocalNameFilter.SuffixKind) -> LocalNameFilter.Kind {
        switch suffixKind {
        case .place: return .place
        case .sect: return .sect
        case .term: return .term
        case .person: return .person
        }
    }

    /// `title_of(w, 0) is not None`.
    private func hasTitle(_ word: Word) -> Bool {
        setup.personTitle(of: word, surnameLength: 0, titles: titles) != nil
    }
}
