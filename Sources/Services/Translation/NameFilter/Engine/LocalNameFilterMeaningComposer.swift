import Foundation

/// Ghép nghĩa cho **một name lẻ** ngoài lượt lọc — đúng `LocalNameFilterMeaningBuilder` của bộ lọc (đường hàng phía LAC:
/// cả từ trong từ điển ⇒ phủ trọn cả từ ⇒ phần riêng + nghĩa đuôi dài nhất của danh sách người dùng ⇒ phần tên riêng; tên
/// người ⇒ phần tên + danh xưng = hậu tố Nhân danh dài nhất; tiền tố của tên Latin). Dùng cho gói tạm tự cập nhật theo danh
/// sách hậu tố / tiền tố (`LocalNameFilterDraftRefresher`, plan 2026-11-27-nghia-ten-tay-huyen mục 6) và màn duyệt ghép lại
/// sau khi thêm hậu tố.
///
/// Ghép lại được (`canRecompose`): địa danh, tổ chức (không phải họ tộc), thuật ngữ và — từ plan 2026-11-27-phan-loai-name
/// L11 — **tên người** (sửa hậu tố Nhân danh / tiền tố ⇒ ghép lại). Họ tộc có cách ghép riêng — giữ nghĩa lúc lọc. Hàng bộ
/// luật địa danh / tổ chức lúc lọc lấy đúng đuôi đã dò; ghép lại ở đây lấy đuôi dài nhất của danh sách — khác nhau chỉ khi
/// danh sách có đuôi dài hơn khớp cuối name.
///
/// Danh xưng 1 chữ (哥 兄…) lúc lọc cần bằng chứng của cả lượt (≥ 3 tên khác nhau đứng trước) mà ở đây không có ⇒ chỉ giữ
/// khi nghĩa máy ghép trước đó đã dùng nó (`previousMeaning` kết thúc bằng nghĩa của danh xưng): "Lâm ca" không thành
/// "Lâm Ca" chỉ vì người dùng sửa một hậu tố khác.
///
/// Chụp từ điển của truyện một lần lúc tạo (`LocalNameFilterDictionaries.capture`), nhớ kết quả như bộ lọc. **Không khoá**:
/// dùng trên một task.
final class LocalNameFilterMeaningComposer {
    private let builder: LocalNameFilterMeaningBuilder
    private let suffixes: [LocalNameFilter.Suffix]

    /// `nil` ⇒ VietPhrase chưa nạp (không ghép được). `latinModel` khác `nil` ⇒ như bật "Ưu tiên tên Latin" có mô hình.
    /// `prefixes` mặc định = danh sách "Tiền tố" hiện tại.
    init?(
        bookId: String,
        suffixes: [LocalNameFilter.Suffix],
        latinModel: LocalNameFilterLatinModel?,
        prefixes: [LocalNameFilter.Suffix] = LocalNameFilterPrefixStore.shared.allPrefixes()
    ) {
        guard let dictionaries = LocalNameFilterDictionaries.capture(bookId: bookId) else { return nil }
        let configuration = LocalNameFilter.Configuration(
            minCount: 1,
            suffixes: suffixes,
            blockedTerms: [],
            prefersLatinNames: latinModel != nil,
            prefixes: prefixes
        )
        let setup = LocalNameFilterSetup(configuration: configuration, dictionaries: dictionaries, rulesV3: true)
        builder = LocalNameFilterMeaningBuilder(
            setup: setup,
            dictionaries: dictionaries,
            properNames: LocalNameFilterProperNames(dictionaries: dictionaries, latinModel: latinModel, prefixes: prefixes)
        )
        self.suffixes = suffixes
    }

    /// **Dấu** của những gì quyết định nghĩa máy ghép ngoài từ điển: danh sách hậu tố + danh sách tiền tố (chữ, nghĩa, loại,
    /// vị trí) + công tắc "Ưu tiên tên Latin". Gói tạm nhớ dấu lần ghép gần nhất (`LocalNameFilterDraft.meaningSignature`);
    /// trùng dấu hiện tại ⇒ không ghép lại — nếu không, mỗi lần trang đầu hiện ra hàng bộ luật địa danh / tổ chức (lúc lọc
    /// lấy đúng đuôi đã dò) có thể đổi nghĩa theo đường ghép ở đây dù người dùng không đổi gì. `prefixes` mặc định = danh
    /// sách "Tiền tố" hiện tại. Danh sách tiền tố rỗng cho đúng dấu của bản trước (không thêm dòng nào).
    static func signature(
        suffixes: [LocalNameFilter.Suffix],
        prefersLatinNames: Bool,
        prefixes: [LocalNameFilter.Suffix] = LocalNameFilterPrefixStore.shared.allPrefixes()
    ) -> String {
        func line(_ item: LocalNameFilter.Suffix) -> String {
            "\(item.key)=\(item.meaning)|\(item.kind.rawValue)|\(item.position.rawValue)"
        }
        let suffixLines = suffixes.map(line).sorted()
        let prefixLines = prefixes.map { "prefix:" + line($0) }.sorted()
        return (suffixLines + prefixLines + ["latin=\(prefersLatinNames ? 1 : 0)"]).joined(separator: "\n").sha256()
    }

    /// Loại ghép lại được: tên người, địa danh, tổ chức (không phải họ tộc), thuật ngữ.
    static func canRecompose(_ kind: LocalNameFilter.Kind) -> Bool {
        switch kind {
        case .person, .place, .sect, .term: return true
        case .family: return false
        }
    }

    /// Nghĩa máy ghép của `term` (chữ Hán) loại `kind`; loại không ghép lại được hoặc chữ rỗng ⇒ `nil`. `previousMeaning` =
    /// nghĩa máy ghép lần trước (chỉ dùng cho danh xưng 1 chữ của tên người — xem doc của type).
    func meaning(term: String, kind: LocalNameFilter.Kind, previousMeaning: String? = nil) -> (meaning: String, isGuessed: Bool)? {
        let word = LocalNameFilterWord(term.trimmingCharacters(in: .whitespacesAndNewlines))
        guard Self.canRecompose(kind), !word.isEmpty else { return nil }
        let titles = kind == .person ? singleCharacterTitle(of: word, previousMeaning: previousMeaning) : []
        let built = builder.meaning(word: word, kind: kind, titles: titles)
        return (built.meaning, built.isGuessed)
    }

    /// Danh xưng 1 chữ đã dùng ở nghĩa trước: chữ cuối là chữ thân tộc, là hậu tố Nhân danh của danh sách, và nghĩa trước
    /// kết thúc bằng " " + nghĩa của nó.
    private func singleCharacterTitle(of word: LocalNameFilterWord, previousMeaning: String?) -> Set<LocalNameFilterTermKey> {
        guard let previousMeaning, word.count >= 2, let key = word.suffix(1).termKey,
              LocalNameFilterRules.has(key[0], .kinship),
              let suffix = suffixes.first(where: { $0.kind == .person && $0.key == key.string }) else { return [] }
        let meaning = LocalNameFilterRules.firstReading(suffix.meaning) ?? suffix.key
        return previousMeaning.hasSuffix(" " + meaning) ? [key] : []
    }
}
