import Foundation

/// Nhận và đọc cụm bậc tròn của token `<m>` — **ghép theo luật** thay cho bảng tay (1.3.1094, anh Bửu: "các token số
/// như vạn ức, ngàn vạn chưa chính xác"; bảng cũ thiếu 万亿, 两亿, 三百亿, 十万亿…).
///
/// Một cụm hợp lệ = [một chữ số] + một hay nhiều bậc **tăng dần** (十 < 百 < 千 < 万 < 亿 < 兆), tối đa 4 chữ (parser cố
/// định `<m>` 1–4); `廿` `卅` `卌` đứng riêng tính như có chữ số. Không nhận bậc lặp hay bậc lớn trước bậc nhỏ (`万万`,
/// `亿万`) — đó là thành ngữ, để VietPhrase đọc.
///
/// Chữ số đầu chỉ được nhận khi `{i}` của token **đứng đầu bản dịch** (`QuickTranslationRuleElement.leadsReplacement`,
/// anh chốt 2026-11-27): `<m>几 = {0} mấy` cần `二十几` = hai mươi mấy; còn `几<m>年 = mấy {0} năm` thì sau 几 / 数 tiếng
/// Trung không bao giờ có chữ số, nên chỉ nhận bậc trần (`之数五万年` không còn ra "mấy năm vạn năm").
///
/// Đọc: chữ số (`一` bỏ, `二/两/兩` hai…) rồi từng bậc — `十` mươi, `百` trăm, `千` **ngàn**, `万` vạn, `亿` ức, `兆` triệu.
/// `十` không có chữ số đứng trước đọc **chục** khi ngay sau nó là 万 / 亿 / 兆 (trong cụm hoặc chữ cố định ngay sau
/// token: `数<m>万年` trên `数十万年` = mấy chục vạn năm), đọc **mười** khi cả cụm là `十` / `一十` và token đứng đầu bản
/// dịch (`十几` = mười mấy), còn lại **mươi** (`几十年` = mấy mươi năm). Bản tham chiếu Python: `m_valid` / `m_render` ở
/// `Docs/Plans/token-so-lon/fix.py`.
public enum QuickTranslationMagnitudeFormatter {
    /// Tập hợp ký tự UTF-16 cấu thành token `<m>`.
    public static let magnitudeUnits: Set<UInt16> = Set(
        "十百千万萬亿億兆廿卅卌一二两兩三四五六七八九".utf16
    )

    private static let digitWords: [Character: String] = [
        "一": "", "二": "hai", "两": "hai", "兩": "hai", "三": "ba", "四": "bốn",
        "五": "năm", "六": "sáu", "七": "bảy", "八": "tám", "九": "chín"
    ]
    private static let unitWords: [Character: String] = [
        "十": "mươi", "百": "trăm", "千": "ngàn", "万": "vạn", "萬": "vạn", "亿": "ức", "億": "ức", "兆": "triệu"
    ]
    /// Số mũ của bậc — để kiểm "tăng dần" và nhận ra bậc từ vạn trở lên.
    private static let unitExponents: [Character: Int] = [
        "十": 1, "百": 2, "千": 3, "万": 4, "萬": 4, "亿": 8, "億": 8, "兆": 12
    ]
    private static let oldTens: [Character: String] = ["廿": "hai mươi", "卅": "ba mươi", "卌": "bốn mươi"]

    /// `allowsDigits` = `{i}` của token đứng đầu bản dịch.
    public static func isMagnitudeCandidate(_ value: String, allowsDigits: Bool) -> Bool {
        let chars = Array(value)
        guard !chars.isEmpty, chars.count <= 4 else { return false }
        if chars.count == 1, oldTens[chars[0]] != nil { return allowsDigits }

        var body = chars[...]
        if let first = body.first, digitWords[first] != nil {
            guard allowsDigits else { return false }
            body = body.dropFirst()
        }
        guard !body.isEmpty else { return false }

        var previous = 0
        for char in body {
            guard let exponent = unitExponents[char], exponent > previous else { return false }
            previous = exponent
        }
        return true
    }

    /// Đọc cụm đã qua `isMagnitudeCandidate`. `followingUnit` = chữ đầu của chữ cố định ngay sau token (nếu là chữ số / bậc
    /// Hán), để `十` trước một 万 / 亿 nằm trong chữ cố định vẫn đọc "chục".
    public static func renderMagnitude(_ value: String, leadsReplacement: Bool, followingUnit: Character? = nil) -> String {
        let chars = Array(value)
        if chars.count == 1, let word = oldTens[chars[0]] { return word }

        var words: [String] = []
        var body = chars[...]
        var hasCountingDigit = false
        if let first = body.first, let word = digitWords[first] {
            body = body.dropFirst()
            if !word.isEmpty {
                words.append(word)
                hasCountingDigit = true
            }
        }

        for (offset, char) in body.enumerated() {
            if char == "十", offset == 0, !hasCountingDigit {
                let next = offset + 1 < body.count ? body[body.startIndex + offset + 1] : followingUnit
                if let next, let exponent = unitExponents[next], exponent >= 4 {
                    words.append("chục")
                    continue
                }
                if leadsReplacement, body.count == 1 {
                    words.append("mười")
                    continue
                }
            }
            words.append(unitWords[char] ?? String(char))
        }
        return words.joined(separator: " ")
    }
}
