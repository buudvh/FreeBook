import Foundation

/// Thứ hạng cố định giữa các token **lớp ký tự** của rule dịch Quick Translate.
///
/// Đây là tiêu chí phá hoà **cuối cùng** của `QuickTranslationRuleEngine.select`, đứng ngay trước
/// `sourceLine`. Nó chỉ nổ khi hai rule giống nhau mọi thứ khác — cùng vị trí, cùng số chữ ghim, cùng
/// hạn mức token, cùng độ dài khớp, cùng bộ rule — và chỉ khác phần token, ví dụ `<d>天` gặp `<n>天`
/// trên đoạn `3天`. Trước 1.3.416 ca này rơi xuống `sourceLine`, tức dòng nào viết sớm hơn trong file
/// thì thắng: một kết quả phụ thuộc thứ tự dòng chứ không phụ thuộc ngữ nghĩa.
///
/// **Nguyên tắc**: token nào càng **rộng** thì càng **ít** ưu tiên. "Rộng" đo bằng số ký tự của lớp
/// ký tự mà token nuốt được (`QuickTranslationNumberFormatter.units(for:)`), nên thứ hạng dưới đây
/// không bao giờ mâu thuẫn với quan hệ bao hàm: lớp nào là **con** của lớp kia thì luôn ít ký tự hơn
/// và luôn thắng (`<h>` ⊂ `<hn>` ⊂ `<n>`, `<d>` ⊂ `<y>` ⊂ `<n>`).
///
/// | Hạng | Token | Số ký tự | Lớp |
/// | ---: | --- | ---: | --- |
/// | 0 | `<h>` | 13 | chữ số Hán trần |
/// | 1 | `<d>` | 20 | `0-9` + full-width |
/// | 2 | `<hn>` | 21 | số Hán đầy đủ (kể cả bậc) |
/// | 3 | `<m>` | 22 | cơ số 10 |
/// | 4 | `<y>` | 33 | đọc từng chữ số |
/// | 5 | `<n>` | 41 | số tổng quát |
/// | 6 | `<a>` | 104 | chữ cái Latin |
///
/// **Bảng viết tay chứ không suy ra từ `units(for:).count`** — cố ý. Suy ra thì hôm nay cho kết quả y
/// hệt, nhưng mai kia ai đó nới lớp ký tự của một token (đúng việc đã xảy ra với `<m>` ở 1.3.415) là
/// thứ hạng **đảo ngầm** và bản dịch đổi mà không có gì báo. Khai tay thì `switch` exhaustive bắt lỗi
/// compile ngay khi thêm token mới mà quên khai hạng.
///
/// Vài cặp token có lớp **rời nhau** (`<d>` với `<h>`, `<d>` với `<hn>`) không bao giờ cùng khớp một
/// chỗ, nên thứ tự giữa chúng vô hại; chúng vẫn được xếp hạng để thứ tự là **tổng**, không còn cặp hoà
/// nào phải đoán.
public enum QuickTranslationRuleNumeralNarrowness {
    /// Hạng của một token lớp ký tự. Hạng **nhỏ hơn** = lớp hẹp hơn = thắng.
    public static func rank(of kind: QuickTranslationRuleElement.NumeralKind) -> Int {
        switch kind {
        case .hanDigits: return 0
        case .asciiDigits: return 1
        case .hanNumeral: return 2
        case .magnitude: return 3
        case .digitwise: return 4
        case .chinese: return 5
        case .latinLetters: return 6
        }
    }

    /// So hai vector hạng **theo thứ tự token xuất hiện trong mẫu**, như so từ trong từ điển: cặp
    /// token đầu tiên khác nhau là quyết định, các token sau không được xét.
    ///
    /// - Returns: `.orderedAscending` khi `lhs` thắng, `.orderedDescending` khi `rhs` thắng, `nil` khi
    ///   **hoà** — hoặc vì hai vector giống nhau, hoặc vì vector này là tiền tố của vector kia (một
    ///   rule có thêm token mà không đổi token nào phía trước). Hoà thì bên gọi rơi tiếp xuống
    ///   `sourceLine`, đúng hành vi cũ.
    public static func verdict(lhs: [Int], rhs: [Int]) -> ComparisonResult? {
        for (left, right) in zip(lhs, rhs) where left != right {
            return left < right ? .orderedAscending : .orderedDescending
        }
        return nil
    }
}
