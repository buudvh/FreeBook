import Foundation

/// Bước làm sạch **cuối** của một chuỗi đã dịch: trim từng dòng, dọn khoảng trắng quanh dấu câu, viết
/// hoa sau dấu kết câu, gộp khoảng trắng lặp.
///
/// Vị trí trong pipeline (xem `TranslationPunctuationMapper`):
/// `rule dịch → tokenize → tra từ điển → joined → TranslationPunctuationMapper → **ở đây**`.
///
/// Tách khỏi `TranslateUtils` ở 1.3.339 vì **bốn regex là hằng nhưng đang được biên dịch lại mỗi lần
/// gọi**, và hàm này được gọi cho **từng token** khi dựng span (`translatedCandidate(for:)`). Một
/// chương ~6.000 token ⇒ ~24.000 lượt biên dịch pattern ICU cho **một** lần dựng lại chương; mà mỗi
/// lần sửa một mục VP hoặc một rule trong Reader đều kéo theo đúng một lần dựng lại như vậy. Đó là
/// nguồn nóng máy chính khi tinh chỉnh từ điển/rule ngay trong lúc đọc, và nó **không** liên quan tới
/// số rule đang có — bộ 50 rule cũng nóng như bộ 17k.
///
/// Giữ nguyên hành vi từng bước, kể cả thứ tự: đổi thứ tự là đổi kết quả dịch của mọi chương.
public enum TranslationTextPostProcessor {
    private static let trimSpacesBefore = try! NSRegularExpression(
        pattern: #" +([,.?!\}\]>”’\):】])"#,
        options: []
    )
    private static let trimSpacesAfter = try! NSRegularExpression(
        pattern: #"([\{\[\(“‘\(【]) +"#,
        options: []
    )
    /// Viết hoa đầu dòng hoặc sau dấu kết câu / dấu hai chấm (`.`, `!`, `?`, `:`, `：`), kể cả khi có
    /// dấu đóng/mở ngoặc hoặc gạch đầu dòng bọc ngoài.
    private static let capitalize = try! NSRegularExpression(
        pattern: #"(^\s*[“‘"'\(\[\{【\-—–]?\s*|[.!?:：]+[”’"'\)\]\}】]*\s*[“‘"'\(\[\{【\-—–]?\s*)(\p{Ll})"#,
        options: [.anchorsMatchLines]
    )
    private static let multiSpaces = try! NSRegularExpression(pattern: #" +"#, options: [])

    public static func apply(to input: String) -> String {
        let lines = input.components(separatedBy: .newlines)
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = trimmedLines.joined(separator: "\n")

        result = replacingAll(trimSpacesBefore, in: result, with: "$1")
        result = replacingAll(trimSpacesAfter, in: result, with: "$1")

        var nsString = result as NSString
        let matches = capitalize.matches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        for match in matches where match.numberOfRanges == 3 {
            let target = match.range(at: 2)
            let char = nsString.substring(with: target)
            nsString = nsString.replacingCharacters(in: target, with: char.uppercased()) as NSString
        }
        result = nsString as String

        // Giữ nguyên các dấu ngoặc kép cong (curly quotes) theo yêu cầu người dùng — cố ý **không**
        // đổi `“ ” ‘ ’` thành `"`.

        result = replacingAll(multiSpaces, in: result, with: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingAll(
        _ regex: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template
        )
    }
}
