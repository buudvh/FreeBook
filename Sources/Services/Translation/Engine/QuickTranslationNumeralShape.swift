import Foundation

/// Luật "cụm chữ số Hán này có phải **một số thật** không" của token `<n>` / `<m>` (1.3.1093, anh Bửu: "vạn vạn thật ra
/// không phải số vẫn bị nhận là số").
///
/// Matcher gọi với **cụm ghép** = chữ số / bậc cuối của chữ cố định đứng trước token + phần token bắt + chữ số / bậc đầu
/// của chữ cố định đứng sau (`QuickTranslationRuleElement.numeralUnitsBefore` / `numeralUnitsAfter`). Xét riêng phần token
/// bắt là sót: `<n:1-5>万年` trên `万万年` chỉ bắt `万` (một số hợp lệ), cụm thành ngữ `万万` do chữ cố định ghép thêm.
///
/// Bản tham chiếu Python: `Docs/Plans/token-so-lon/fix.py` (`well_formed`) — đổi luật thì sửa Python trước, chạy lại
/// `compare1.py` trên 6 truyện.
enum QuickTranslationNumeralShape {
    /// Giá trị của từng chữ bậc.
    static let unitValues: [Character: Int] = [
        "十": 10, "百": 100, "千": 1_000, "万": 10_000, "萬": 10_000,
        "亿": 100_000_000, "億": 100_000_000, "兆": 1_000_000_000_000
    ]
    /// Chữ số Hán khác 0.
    static let nonZeroDigits: Set<Character> = Set("一二两兩三四五六七八九")
    /// Chữ ước lượng "mấy": bậc trần đứng ngay sau nó (`几百`, `数万`) là số ước lượng, không phải số đứng riêng. Chỉ
    /// hai chữ này — thêm `多` / `余` thì hỏng `众多十万年`, `其余十万年` (đo trên 6 truyện).
    static let approximationMarkers: Set<UInt16> = Set("几数".utf16)

    /// `false` khi cụm **không** phải một số:
    /// - bắt đầu bằng `兆` (`征兆`, `前兆`, tên `沈兆`);
    /// - đúng `万一` ("lỡ mà") hoặc hai chữ số trùng nhau `一一`, `三三`;
    /// - bậc lớn đứng ngay trước bậc nhỏ: `亿万`, `万千`, `千百` (số thật luôn có chữ số chen giữa: `一万一千`);
    /// - một bậc lặp liền nhau: `万万`, `千千`, `亿亿` — trừ `万万` có chữ số đứng trước (`两万万`, `四万万` = cách nói cũ
    ///   của 2 ức, 4 ức).
    static func isNumber(_ run: String) -> Bool {
        let chars = Array(run)
        guard let first = chars.first, first != "兆" else { return false }
        if run == "万一" || run == "萬一" { return false }
        if chars.count == 2, chars[0] == chars[1], nonZeroDigits.contains(chars[0]) { return false }

        for index in 0..<(chars.count - 1) {
            guard let left = unitValues[chars[index]], let right = unitValues[chars[index + 1]] else { continue }
            if left > right { return false }
            if left == right {
                let isWan = left == 10_000
                let hasDigitBefore = chars[..<index].contains { nonZeroDigits.contains($0) }
                guard isWan, hasDigitBefore else { return false }
            }
        }
        return true
    }
}
