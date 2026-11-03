import Foundation

/// Điều kiện của neo dòng `<^>` / `<$>` (1.3.686) và ranh giới dòng của `<any>`, trên mảng UTF-16 mà
/// `QuickTranslationRuleMatcher` đang khớp.
///
/// "Dòng" là chuỗi đưa vào dịch: Reader/TTS dịch từng đoạn (đã cắt khoảng trắng), tên chương dịch cả
/// tên, xuất TXT dịch cả chương nên đầu dòng là sau mỗi `\n`/`\r`.
///
/// **Bỏ qua khoảng trắng**: `<^>` vẫn đúng khi giữa đầu dòng và vị trí hiện tại chỉ có khoảng trắng
/// (thụt đầu dòng `　　第一章`), `<$>` tương tự ở cuối. Khoảng trắng đó nằm **ngoài** vùng khớp nên giữ
/// nguyên trong bản dịch. Mỗi lần kiểm dừng ngay ở ký tự đầu tiên không phải khoảng trắng nên chi phí
/// chỉ bằng độ dài dải khoảng trắng, kể cả khi dịch cả chương.
///
/// Tách thành type riêng (không phải `private` trong matcher) để matcher không vượt trần 400 dòng.
enum QuickTranslationRuleLineAnchor {
    /// Unicode Zs (kể cả `　` U+3000, NBSP) + tab — **không** gồm xuống dòng. Dựng một lần, không dựng
    /// trong vòng lặp.
    private static let spaceScalars = CharacterSet.whitespaces

    /// Chỉ `\n` và `\r` là ranh giới dòng.
    static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D
    }

    /// Đơn vị surrogate (`Unicode.Scalar(UInt16)` trả `nil`) không phải khoảng trắng.
    private static func isSpace(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return spaceScalars.contains(scalar)
    }

    /// `<^>`: từ đầu chuỗi (hoặc ngay sau `\n`/`\r` gần nhất) tới `position` chỉ có khoảng trắng.
    static func isAtLineStart(_ units: [UInt16], _ position: Int) -> Bool {
        var index = min(position, units.count)
        while index > 0 {
            let unit = units[index - 1]
            if isLineBreak(unit) { return true }
            guard isSpace(unit) else { return false }
            index -= 1
        }
        return true
    }

    /// `<$>`: từ `position` tới cuối chuỗi (hoặc tới `\n`/`\r` kế tiếp) chỉ có khoảng trắng.
    static func isAtLineEnd(_ units: [UInt16], _ position: Int) -> Bool {
        var index = max(position, 0)
        while index < units.count {
            let unit = units[index]
            if isLineBreak(unit) { return true }
            guard isSpace(unit) else { return false }
            index += 1
        }
        return true
    }
}
