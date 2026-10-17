import Foundation

/// Phân loại tiện ích có nội dung người lớn (NSFW) — hàm **thuần**, không I/O.
///
/// Người dùng tự đánh dấu / bỏ đánh dấu (`Extension.nsfwOverride`) thắng tất cả. Không có thì: cờ tiện ích tự khai
/// (`Extension.isNsfw == true`, từ `metadata.nsfw`/thẻ `nsfw`) **hoặc** heuristic:
/// - từ khoá trên tên + mô tả + tác giả (bỏ dấu, chữ thường, `đ` ⇒ `d`);
/// - tên miền trên `sourceUrl`.
///
/// `isNsfw == false` không tắt heuristic: registry gộp hầu như không khai cờ, nên `false` chỉ là "không khai".
///
/// Danh sách theo khảo sát danh mục tiện ích cộng đồng (85/736 khớp). Cố ý **không** có từ đơn `dam`, `cu`
/// (quá nhiều khớp nhầm tiếng Việt: "đam mỹ", "cũ"…).
/// - Từ khoá một chữ: so **chuỗi con** (bắt được cả tên ghép như `truyensex`, `hentaivn`), trừ `sex` so theo
///   ranh giới từ (tránh "sussex", "sexy"…).
/// - Cụm nhiều chữ tiếng Việt (`hiep dam`, `khoa than`…): so theo **ranh giới từ** — chuỗi con sẽ khớp nhầm
///   "khoa thanh", "sau dam"…
enum ExtensionNsfwClassifier {
    nonisolated static func isNsfw(_ ext: Extension) -> Bool {
        if let override = ext.nsfwOverride { return override }
        if ext.isNsfw == true { return true }
        let text = normalized([ext.name, ext.desc ?? "", ext.author].joined(separator: " "))
        if matchesKeyword(in: text) { return true }
        let source = ext.sourceUrl.lowercased()
        return !source.isEmpty && domainKeywords.contains { source.contains($0) }
    }

    // MARK: - Danh sách

    /// So chuỗi con trên văn bản đã chuẩn hoá.
    static let substringKeywords: [String] = [
        "nsfw", "18+", "18plus", "adult", "porn", "hentai", "ecchi", "erotica", "jav", "uncensored",
        "doujinshi", "yuri", "yaoi", "po18", "book18", "cartoon18", "manga18", "mh18", "18mh", "tranh18",
        "cool18", "men18", "hen18", "truyensex", "truyenxxx", "xxx", "truyenheo", "nudes"
    ]

    /// So theo ranh giới từ (sau khi mọi ký tự không phải chữ/số thành khoảng trắng).
    static let wordKeywords: [String] = [
        "sex", "khoa than", "loan luan", "hiep dam", "thu dam", "phim heo", "phim nguoi lon", "bao dam",
        "kheu goi", "tinh duc", "au dam", "dam duc", "dit nhau", "cuong buc"
    ]

    /// Chuỗi con trên `sourceUrl` (chữ thường).
    static let domainKeywords: [String] = [
        "hentai", "vlxx", "porn", "xvideos", "xnxx", "lxhentai", "hentaivn", "blogtruyen18", "biquge18",
        "sayhentai", "truyensextv", "khomanhwa", "loppytoon", "mimimoe", "thienthaitruyen", "hongtrateam"
    ]

    // MARK: - Chuẩn hoá

    /// Bỏ dấu, chữ thường, `đ` ⇒ `d` (folding không đổi `đ`).
    nonisolated static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "đ", with: "d")
    }

    nonisolated private static func matchesKeyword(in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if substringKeywords.contains(where: { text.contains($0) }) { return true }
        let words = " " + text.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .joined(separator: " ") + " "
        return wordKeywords.contains { words.contains(" " + $0 + " ") }
    }
}
