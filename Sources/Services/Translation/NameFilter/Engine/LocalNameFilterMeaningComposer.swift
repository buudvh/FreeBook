import Foundation

/// Ghép nghĩa cho **một name lẻ** ngoài lượt lọc — đúng `LocalNameFilterMeaningBuilder` của bộ lọc (đường hàng phía LAC:
/// cả từ trong từ điển ⇒ phủ trọn cả từ ⇒ phần riêng + nghĩa đuôi dài nhất của danh sách người dùng ⇒ phần tên riêng; tên
/// người ⇒ phần tên + danh xưng = hậu tố Nhân danh dài nhất; tiền tố của tên Latin). Dùng cho gói tạm tự cập nhật theo danh
/// sách hậu tố / tiền tố (`LocalNameFilterDraftRefresher`, plan 2026-11-27-nghia-ten-tay-huyen mục 6) và màn duyệt ghép lại
/// sau khi thêm hậu tố.
///
/// Ghép lại được (`canRecompose`): địa danh, tổ chức (không phải họ tộc), thuật ngữ và — từ plan 2026-11-27-phan-loai-name
/// L11 — **tên người** (sửa hậu tố Nhân danh / tiền tố ⇒ ghép lại). Họ tộc có cách ghép riêng — giữ nghĩa lúc lọc. Hàng bộ
/// luật địa danh / tổ chức lúc lọc cũng lấy hậu tố dài nhất của danh sách (2026-11-28); ghép lại ở đây chỉ khác khi danh
/// sách không còn đuôi đã dò (lúc lọc ⇒ âm Hán-Việt viết thường đặt sau, ở đây ⇒ phần tên riêng như name không đuôi).
///
/// Danh xưng 1 chữ (哥 兄…) lúc lọc cần bằng chứng của cả lượt (≥ 3 tên khác nhau đứng trước) mà ở đây không có ⇒ chỉ giữ
/// khi nghĩa máy ghép trước đó đã dùng nó (`previousMeaning` kết thúc bằng nghĩa của danh xưng): "Lâm ca" không thành
/// "Lâm Ca" chỉ vì người dùng sửa một hậu tố khác.
///
/// Chụp từ điển của truyện một lần lúc tạo (`LocalNameFilterDictionaries.capture`), nhớ kết quả như bộ lọc. **Không khoá**:
/// dùng trên một task.
final class LocalNameFilterMeaningComposer {
    private let setup: LocalNameFilterSetup
    private let dictionaries: LocalNameFilterDictionaries
    private let latinModel: LocalNameFilterLatinModel?
    private let suffixes: [LocalNameFilter.Suffix]
    private let prefixes: [LocalNameFilter.Suffix]
    /// "Nới đoán tên Latin" hiệu lực của truyện — mặc định cho mọi name không có ghi đè riêng.
    private let loosensLatin: Bool
    /// Bộ ghép theo từng giá trị công tắc nới (dựng khi cần): name ghi đè công tắc ở màn Sửa từ (2026-11-28, mockup N6)
    /// dùng bộ còn lại. Hai bộ chung bản chụp từ điển + danh sách, chỉ khác `LocalNameFilterProperNames.loosensLatinCore`.
    private var builders: [Bool: LocalNameFilterMeaningBuilder] = [:]

    /// `nil` ⇒ VietPhrase chưa nạp (không ghép được). `latinModel` khác `nil` ⇒ như bật "Ưu tiên tên Latin" có mô hình.
    /// `suffixes` / `prefixes` = danh sách hiệu lực **của truyện** (`LocalNameFilterSuffixStore.allSuffixes(bookId:)` /
    /// `LocalNameFilterPrefixStore.allPrefixes(bookId:)` — Chung + Riêng truyện); `loosensLatin` = công tắc "Nới đoán tên
    /// Latin" hiệu lực của truyện (`LocalNameFilterLatinPreferenceStore.loosensLatin(bookId:)`). Không có mặc định để chỗ
    /// gọi nào cũng phải truyền đúng bản của truyện.
    init?(
        bookId: String,
        suffixes: [LocalNameFilter.Suffix],
        latinModel: LocalNameFilterLatinModel?,
        prefixes: [LocalNameFilter.Suffix],
        loosensLatin: Bool
    ) {
        guard let dictionaries = LocalNameFilterDictionaries.capture(bookId: bookId) else { return nil }
        let configuration = LocalNameFilter.Configuration(
            minCount: 1,
            suffixes: suffixes,
            blockedTerms: [],
            prefersLatinNames: latinModel != nil,
            prefixes: prefixes,
            loosensLatinGuess: loosensLatin
        )
        setup = LocalNameFilterSetup(configuration: configuration, dictionaries: dictionaries, rulesV3: true)
        self.dictionaries = dictionaries
        self.latinModel = latinModel
        self.suffixes = suffixes
        self.prefixes = prefixes
        self.loosensLatin = loosensLatin
    }

    /// Bộ ghép cho một giá trị công tắc nới (nhớ lại để dùng cho các name sau).
    private func builder(loosensLatin loose: Bool) -> LocalNameFilterMeaningBuilder {
        if let cached = builders[loose] { return cached }
        let built = LocalNameFilterMeaningBuilder(
            setup: setup,
            dictionaries: dictionaries,
            properNames: LocalNameFilterProperNames(
                dictionaries: dictionaries, latinModel: latinModel, prefixes: prefixes, affixes: suffixes,
                loosensLatinCore: loose
            )
        )
        builders[loose] = built
        return built
    }

    /// **Dấu** của những gì quyết định nghĩa máy ghép ngoài từ điển: danh sách hậu tố + danh sách tiền tố (chữ, nghĩa, loại,
    /// vị trí) + công tắc "Ưu tiên tên Latin" + công tắc "Nới đoán tên Latin" **của truyện** (giá trị hiệu lực; ghi đè theo
    /// name ở màn Sửa từ không vào dấu — nó đi theo từng name trong `autoMeanings` và được áp lúc ghép lại). Gói tạm nhớ
    /// dấu lần ghép gần nhất (`LocalNameFilterDraft.meaningSignature`); trùng dấu hiện tại ⇒ không ghép lại — nếu không, mỗi lần trang đầu hiện ra hàng bộ luật địa danh / tổ chức mà danh
    /// sách đã xoá đuôi đã dò có thể đổi nghĩa theo đường ghép ở đây dù người dùng không đổi gì. Hai danh sách là bản hiệu
    /// lực **của truyện** (Chung + Riêng, `allSuffixes(bookId:)` / `allPrefixes(bookId:)`) ⇒ sửa danh sách Riêng cũng đổi
    /// dấu; không có mặc định — mọi chỗ tính dấu phải cùng một cách, lệch một chỗ là gói tạm ghép lại mỗi lần hoặc không
    /// bao giờ. Có thêm số phiên bản luật ghép (`rulesVersion`): đổi luật ghép ⇒ tăng số ⇒ mọi gói tạm ghép lại một lần
    /// (nghĩa người dùng đã sửa vẫn giữ).
    static func signature(
        suffixes: [LocalNameFilter.Suffix],
        prefersLatinNames: Bool,
        prefixes: [LocalNameFilter.Suffix],
        loosensLatin: Bool
    ) -> String {
        func line(_ item: LocalNameFilter.Suffix) -> String {
            "\(item.key)=\(item.meaning)|\(item.kind.rawValue)|\(item.position.rawValue)"
        }
        let suffixLines = suffixes.map(line).sorted()
        let prefixLines = prefixes.map { "prefix:" + line($0) }.sorted()
        let tail = ["latin=\(prefersLatinNames ? 1 : 0)", "loose=\(loosensLatin ? 1 : 0)", "rules=\(rulesVersion)"]
        return (suffixLines + prefixLines + tail).joined(separator: "\n").sha256()
    }

    /// Phiên bản luật ghép nghĩa trong dấu gói tạm. 2 = 2026-11-28: hậu tố dài nhất cho cả hàng bộ luật, phủ trọn chỉ cho
    /// tên Latin. 3 = 2026-11-28: tên kiểu Latin bỏ tiền tố / hậu tố rồi xét phần lõi (`latinAffixed`: 古赫密斯语 ⇒ "cổ
    /// Hermes ngữ"). 4 = 2026-11-28: lõi tên kiểu Latin tin Name / VP riêng (图铎家族 ⇒ "Tudor gia tộc") + công tắc "Nới
    /// đoán tên Latin".
    static let rulesVersion = 4

    /// Loại ghép lại được: tên người, địa danh, tổ chức (không phải họ tộc), thuật ngữ.
    static func canRecompose(_ kind: LocalNameFilter.Kind) -> Bool {
        switch kind {
        case .person, .place, .sect, .term: return true
        case .family: return false
        }
    }

    /// Nghĩa máy ghép của `term` (chữ Hán) loại `kind`; loại không ghép lại được hoặc chữ rỗng ⇒ `nil`. `previousMeaning` =
    /// nghĩa máy ghép lần trước (chỉ dùng cho danh xưng 1 chữ của tên người — xem doc của type). `loosensLatin` = ghi đè
    /// công tắc "Nới đoán tên Latin" của riêng name này (`LocalNameFilterDraft.AutoMeaning.loosensLatin`); `nil` = theo
    /// truyện.
    func meaning(
        term: String,
        kind: LocalNameFilter.Kind,
        previousMeaning: String? = nil,
        loosensLatin override: Bool? = nil
    ) -> (meaning: String, isGuessed: Bool)? {
        let word = LocalNameFilterWord(term.trimmingCharacters(in: .whitespacesAndNewlines))
        guard Self.canRecompose(kind), !word.isEmpty else { return nil }
        let titles = kind == .person ? singleCharacterTitle(of: word, previousMeaning: previousMeaning) : []
        let built = builder(loosensLatin: override ?? loosensLatin).meaning(word: word, kind: kind, titles: titles)
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
