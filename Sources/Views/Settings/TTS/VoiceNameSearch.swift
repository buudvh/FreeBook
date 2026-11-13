import Foundation

/// So khớp **tên giọng** cho ô tìm của màn chọn giọng (VieNeu và các trình đọc khác): bỏ dấu, không phân biệt hoa thường,
/// "đ" coi như "d" (bỏ dấu của Foundation không đổi "đ"), khoảng trắng thừa bỏ đi. Gõ "ngoc huyen" ra "Ngọc Huyền (mới)".
enum VoiceNameSearch {
    /// Chuỗi đã chuẩn hoá để so; rỗng ⇒ không lọc.
    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "vi_VN"))
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `query` đã qua `normalize`. Rỗng ⇒ mọi tên đều khớp.
    static func matches(_ name: String, normalizedQuery query: String) -> Bool {
        query.isEmpty || normalize(name).contains(query)
    }
}
