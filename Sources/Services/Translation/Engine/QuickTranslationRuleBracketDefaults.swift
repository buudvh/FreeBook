import Foundation

/// Bộ ngoặc **mặc định** của token `<[>` / `<]>` (1.3.692): 50 cặp tròn, mai rùa, vuông, ngoặc móc và
/// ngoặc góc, ghép theo tên LEFT/RIGHT của Unicode.
///
/// Mỗi ký tự viết bằng escape Unicode (glyph ở comment cuối dòng) để không công cụ nào chuẩn hoá hay đổi
/// mã hoá làm lệch code point. Cả 100 ký tự đều là **một** đơn vị UTF-16 và không ký tự nào lặp lại.
///
/// Cố ý **không** có:
/// - `「」` `『』` `﹁﹂` `﹃﹄`: ngoặc kép CJK bọc lời thoại — rule nội dung có `<[>` sẽ khớp cả câu thoại.
/// - `⦍⦎⦏⦐`: Unicode ghép chéo (LEFT của cặp này đi với RIGHT của cặp kia), dễ ghép sai.
/// - `〈〉` U+2329/U+232A: bản cũ, chuẩn hoá Unicode coi là trùng `〈〉` U+3008/U+3009 đã có.
///
/// `<>` ASCII có trong danh sách nhưng **tắt sẵn**: trong chữ hai dấu này hay là dấu so sánh, mũi tên
/// `->` hoặc thẻ HTML sót lại. `《》` bật sẵn dù hay bọc tên sách — cần thì người dùng tắt.
///
/// Bộ chung vắng khoá `UserDefaults` ⇒ dùng đúng danh sách này, nên thêm cặp mặc định mới ở bản sau vẫn
/// tới người chưa từng sửa bộ ngoặc.
public enum QuickTranslationRuleBracketDefaults {
    public static let pairs: [QuickTranslationRuleBracketPair] = [
        // Ngoặc tròn (11)
        pair("\u{0028}", "\u{0029}", "Ngoặc tròn"), // ( )
        pair("\u{FF08}", "\u{FF09}", "Ngoặc tròn toàn khổ"), // （ ）
        pair("\u{FE59}", "\u{FE5A}", "Ngoặc tròn nhỏ"), // ﹙ ﹚
        pair("\u{FE35}", "\u{FE36}", "Ngoặc tròn dọc"), // ︵ ︶
        pair("\u{207D}", "\u{207E}", "Ngoặc tròn chỉ số trên"), // ⁽ ⁾
        pair("\u{208D}", "\u{208E}", "Ngoặc tròn chỉ số dưới"), // ₍ ₎
        pair("\u{2768}", "\u{2769}", "Ngoặc tròn trang trí"), // ❨ ❩
        pair("\u{276A}", "\u{276B}", "Ngoặc tròn dẹt trang trí"), // ❪ ❫
        pair("\u{2985}", "\u{2986}", "Ngoặc tròn rỗng"), // ⦅ ⦆
        pair("\u{FF5F}", "\u{FF60}", "Ngoặc tròn rỗng toàn khổ"), // ｟ ｠
        pair("\u{2E28}", "\u{2E29}", "Ngoặc tròn đôi"), // ⸨ ⸩
        // Ngoặc mai rùa (6)
        pair("\u{3014}", "\u{3015}", "Ngoặc mai rùa"), // 〔 〕
        pair("\u{FE5D}", "\u{FE5E}", "Ngoặc mai rùa nhỏ"), // ﹝ ﹞
        pair("\u{FE39}", "\u{FE3A}", "Ngoặc mai rùa dọc"), // ︹ ︺
        pair("\u{3018}", "\u{3019}", "Ngoặc mai rùa rỗng"), // 〘 〙
        pair("\u{2997}", "\u{2998}", "Ngoặc mai rùa đặc"), // ⦗ ⦘
        pair("\u{2772}", "\u{2773}", "Ngoặc mai rùa trang trí"), // ❲ ❳
        // Ngoặc vuông (11)
        pair("\u{005B}", "\u{005D}", "Ngoặc vuông"), // [ ]
        pair("\u{FF3B}", "\u{FF3D}", "Ngoặc vuông toàn khổ"), // ［ ］
        pair("\u{3010}", "\u{3011}", "Ngoặc vuông đặc"), // 【 】
        pair("\u{FE3B}", "\u{FE3C}", "Ngoặc vuông đặc dọc"), // ︻ ︼
        pair("\u{3016}", "\u{3017}", "Ngoặc vuông rỗng"), // 〖 〗
        pair("\u{FE17}", "\u{FE18}", "Ngoặc vuông rỗng dọc"), // ︗ ︘
        pair("\u{301A}", "\u{301B}", "Ngoặc vuông kép"), // 〚 〛
        pair("\u{27E6}", "\u{27E7}", "Ngoặc vuông kép toán học"), // ⟦ ⟧
        pair("\u{2045}", "\u{2046}", "Ngoặc vuông có ngạnh"), // ⁅ ⁆
        pair("\u{298B}", "\u{298C}", "Ngoặc vuông gạch dưới"), // ⦋ ⦌
        pair("\u{FE47}", "\u{FE48}", "Ngoặc vuông dọc"), // ﹇ ﹈
        // Ngoặc nhọn — ngoặc móc (6)
        pair("\u{007B}", "\u{007D}", "Ngoặc móc"), // { }
        pair("\u{FF5B}", "\u{FF5D}", "Ngoặc móc toàn khổ"), // ｛ ｝
        pair("\u{FE5B}", "\u{FE5C}", "Ngoặc móc nhỏ"), // ﹛ ﹜
        pair("\u{FE37}", "\u{FE38}", "Ngoặc móc dọc"), // ︷ ︸
        pair("\u{2983}", "\u{2984}", "Ngoặc móc rỗng"), // ⦃ ⦄
        pair("\u{2774}", "\u{2775}", "Ngoặc móc trang trí"), // ❴ ❵
        // Ngoặc nhọn — ngoặc góc (16)
        pair("\u{003C}", "\u{003E}", "Ngoặc nhọn", isEnabled: false), // < >
        pair("\u{FF1C}", "\u{FF1E}", "Ngoặc nhọn toàn khổ"), // ＜ ＞
        pair("\u{FE64}", "\u{FE65}", "Ngoặc nhọn nhỏ"), // ﹤ ﹥
        pair("\u{3008}", "\u{3009}", "Ngoặc góc"), // 〈 〉
        pair("\u{27E8}", "\u{27E9}", "Ngoặc góc toán học"), // ⟨ ⟩
        pair("\u{300A}", "\u{300B}", "Ngoặc góc kép"), // 《 》
        pair("\u{27EA}", "\u{27EB}", "Ngoặc góc kép toán học"), // ⟪ ⟫
        pair("\u{FE3F}", "\u{FE40}", "Ngoặc góc dọc"), // ︿ ﹀
        pair("\u{FE3D}", "\u{FE3E}", "Ngoặc góc kép dọc"), // ︽ ︾
        pair("\u{2039}", "\u{203A}", "Nháy góc đơn"), // ‹ ›
        pair("\u{00AB}", "\u{00BB}", "Nháy góc kép"), // « »
        pair("\u{276C}", "\u{276D}", "Ngoặc góc trang trí"), // ❬ ❭
        pair("\u{276E}", "\u{276F}", "Nháy góc trang trí"), // ❮ ❯
        pair("\u{2770}", "\u{2771}", "Ngoặc góc trang trí đậm"), // ❰ ❱
        pair("\u{2991}", "\u{2992}", "Ngoặc góc có chấm"), // ⦑ ⦒
        pair("\u{29FC}", "\u{29FD}", "Ngoặc góc cong"), // ⧼ ⧽
    ]

    private static func pair(
        _ open: String,
        _ close: String,
        _ name: String,
        isEnabled: Bool = true
    ) -> QuickTranslationRuleBracketPair {
        QuickTranslationRuleBracketPair(open: open, close: close, name: name, isEnabled: isEnabled)
    }
}
