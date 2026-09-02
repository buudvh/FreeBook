import Foundation

/// Số thứ tự tiếng Việt cho TTS: `thứ 1` phải đọc là **thứ nhất**, không phải "thứ một".
///
/// Chạy **trước** `processDigits` — bước đó đọc mọi chữ số theo số đếm (`1` → "một"), nên nếu để nó
/// chạy trước thì không còn chữ số nào để nhận ra đây là số thứ tự.
///
/// Chỉ hai giá trị là bất quy tắc trong tiếng Việt: `1` → "nhất" và `4` → "tư". Từ `2` trở đi (trừ 4)
/// dùng đúng số đếm (`thứ hai`, `thứ ba`, `thứ năm`), và số nhiều chữ số cũng vậy (`thứ 21` → "thứ hai
/// mươi mốt") nên **không** đụng tới — để `processDigits` lo, tránh sinh ra "thứ hai mươi nhất".
enum VietnameseOrdinalSpeller {

    /// Các từ mở đầu một số thứ tự. `hạng`/`đứng thứ` dùng cùng luật với `thứ`.
    private static let irregularOrdinals: [String: String] = ["1": "nhất", "4": "tư"]

    /// `thứ 1`, `Thứ 4`, `hạng 1` — chỉ khớp khi **đúng một** chữ số và không dính chữ số khác.
    private static let pattern = try! NSRegularExpression(
        pattern: #"\b(thứ|hạng)(\s+)([14])(?![\d,.])\b"#,
        options: [.caseInsensitive]
    )

    static func apply(_ text: String) -> String {
        guard text.range(of: "thứ", options: .caseInsensitive) != nil
                || text.range(of: "hạng", options: .caseInsensitive) != nil else {
            return text
        }

        let ns = text as NSString
        let matches = pattern.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = text
        // Thay từ cuối về đầu để offset của các match trước không bị lệch.
        for match in matches.reversed() {
            guard match.numberOfRanges > 3 else { continue }
            let label = ns.substring(with: match.range(at: 1))
            let spacing = ns.substring(with: match.range(at: 2))
            let digit = ns.substring(with: match.range(at: 3))
            guard let word = irregularOrdinals[digit] else { continue }
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: label + spacing + word)
        }
        return result
    }
}
