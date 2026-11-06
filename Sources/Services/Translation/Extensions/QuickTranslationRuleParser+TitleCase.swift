import Foundation

/// Token chữ viết **HOA tên** = ép viết hoa phần nghĩa (1.3.761): `<vp>` dịch như thường, `<VP>` cho nghĩa kiểu
/// AA của `TextCaseFormatter` (hoa chữ đầu mọi từ, còn lại thường) — `天剑宗` qua `<VP>宗 = {0} Tông` ra
/// `Thiên Kiếm Tông`.
///
/// Chỉ token có chữ trong nghĩa mới nhận: từ điển `<NE> <PN> <VP> <W> <HV>`, `<HN>` (Hán-Việt), `<M>` (mươi, trăm…)
/// và `<A>` (chữ Latin). Token số `<n> <y> <h> <d>` ra chữ số, `<any>` trả nguyên văn chữ Hán (dịch sau ở bước tra
/// từ điển của cả dòng) nên bản viết hoa của chúng vẫn là lỗi `UNKNOWN_TOKEN_NAME`; `<L>` vốn viết hoa tên và luôn
/// ra nhãn viết hoa sẵn.
///
/// Parser hạ tên về chữ thường **ngay khi tách** rồi gắn cờ `capitalizesMeaning` lên phần tử: mọi chỗ phía sau
/// (công tắc token, cấu hình riêng truyện, độ hẹp token số, nhận diện `<m>` đầu mẫu) thấy đúng token thường, nên
/// `<VP>` theo công tắc VietPhrase như `<vp>`. Chữ hoa chỉ áp ở `QuickTranslationRuleElement.renderedMeaning`.
extension QuickTranslationRuleParser {
    /// Tên (chữ thường) của các token chữ được viết HOA để ép viết hoa nghĩa.
    static let titleCaseTokenNames: Set<String> = ["ne", "pn", "vp", "w", "hv", "hn", "m", "a"]

    /// `true` khi `name` là bản viết HOA toàn bộ của một token chữ (`VP`, `HN`, `M`…). `Vp` hay `vP` không tính —
    /// chúng rơi xuống lỗi "không được hỗ trợ" như mọi tên sai.
    static func isTitleCaseTokenName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered != name && name == name.uppercased() && titleCaseTokenNames.contains(lowered)
    }

    /// Tách phần tên của token (trước `:`) theo `|`. Mọi tên đều viết HOA ⇒ trả tên thường + `true`; không tên nào
    /// viết HOA ⇒ trả nguyên văn + `false`; trộn (`<NE|pn>`) ⇒ lỗi nặng, vì cờ viết hoa là của cả token.
    ///
    /// Tên rỗng (`<NE|>`) trả nguyên văn để `parseToken` báo đúng lỗi "không có tên" thay vì lỗi trộn.
    static func normalizedTokenNames(
        _ rawNames: String,
        spec: String
    ) throws -> (names: [String], capitalizesMeaning: Bool) {
        let names = rawNames.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.contains(where: \.isEmpty) else { return (names, false) }

        let titleCaseCount = names.filter(isTitleCaseTokenName).count
        guard titleCaseCount > 0 else { return (names, false) }
        guard titleCaseCount == names.count else {
            throw ParseError(
                code: .unknownTokenName,
                message: "Token <\(spec)> trộn tên viết hoa với tên thường; viết hoa cả token (ép viết hoa nghĩa) hoặc viết thường cả token"
            )
        }
        return (names.map { $0.lowercased() }, true)
    }
}
