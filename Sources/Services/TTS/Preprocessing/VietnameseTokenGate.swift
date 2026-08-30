import Foundation

/// Quyết định một token có được phiên âm hay không, **theo ngữ cảnh**.
///
/// Vấn đề của bản cũ: điều kiện duy nhất là `!VietnameseWordChecker.isVietnameseWord(token)`, mà bảng
/// âm tiết không dấu của nó có ~700 mục nên "man", "can", "ban", "men", "hen", "cam", "song", "tin",
/// "pin", "phim" **không bao giờ** được phiên âm — TTS đọc chúng theo tiếng Việt ngay giữa một câu
/// tiếng Anh.
///
/// Không thể chỉ xoá các mục đó khỏi bảng: giữa văn bản tiếng Việt thì "cam", "song", "tin" đúng là
/// tiếng Việt và phải đọc như tiếng Việt. Thứ phân biệt hai trường hợp là **láng giềng**: một âm tiết
/// mơ hồ nằm trong một dãy từ Latin lạ thì thuộc dãy đó.
///
/// Tiếng Việt viết có dấu dày đặc nên phép thử này an toàn một chiều: token có dấu luôn được giữ, và
/// một câu tiếng Việt thuần hầu như luôn có láng giềng mang dấu.
enum VietnameseTokenGate {

    /// Bao nhiêu token mỗi bên được xét.
    private static let windowRadius = 2

    /// Ký tự chặn cửa sổ: qua dấu kết câu hoặc xuống dòng thì không còn là cùng một dãy.
    private static let boundaryCharacters = CharacterSet(charactersIn: ".!?…\n\r;:")

    /// `true` = đưa token qua bộ phiên âm.
    static func shouldTransliterate(
        _ token: String,
        at index: Int,
        in matches: [NSTextCheckingResult],
        source: NSString
    ) -> Bool {
        // Có dấu tiếng Việt ⇒ chắc chắn là tiếng Việt, không bàn thêm.
        if hasVietnameseDiacritic(token) { return false }

        // Không phải âm tiết tiếng Việt ⇒ phiên âm như trước.
        if !VietnameseWordChecker.isVietnameseWord(token) { return true }

        // Âm tiết mơ hồ: chỉ phiên âm khi nằm trong một dãy từ lạ.
        return foreignNeighbourCount(around: index, in: matches, source: source) > 0
    }

    /// Dùng cho màn Thử phiên âm: nói rõ vì sao token được giữ hay bị phiên âm.
    static func explain(
        _ token: String,
        at index: Int,
        in matches: [NSTextCheckingResult],
        source: NSString
    ) -> String {
        if hasVietnameseDiacritic(token) { return "giữ nguyên: có dấu tiếng Việt" }
        if !VietnameseWordChecker.isVietnameseWord(token) { return "phiên âm: không phải âm tiết tiếng Việt" }
        let neighbours = foreignNeighbourCount(around: index, in: matches, source: source)
        return neighbours > 0
            ? "phiên âm: âm tiết mơ hồ nhưng có \(neighbours) láng giềng lạ"
            : "giữ nguyên: âm tiết tiếng Việt, không có láng giềng lạ"
    }

    // MARK: - Phụ trợ

    private static func hasVietnameseDiacritic(_ token: String) -> Bool {
        let marked = "àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ"
        return token.lowercased().contains { marked.contains($0) }
    }

    /// Đếm token "lạ" trong cửa sổ hai bên: dài hơn 1 ký tự, chỉ gồm chữ ASCII, và **không** phải âm
    /// tiết tiếng Việt. Gặp ranh giới câu thì dừng về phía đó.
    private static func foreignNeighbourCount(
        around index: Int,
        in matches: [NSTextCheckingResult],
        source: NSString
    ) -> Int {
        var count = 0

        for offset in 1...windowRadius {
            let previous = index - offset
            guard previous >= 0 else { break }
            if crossesBoundary(from: matches[previous], to: matches[previous + 1], source: source) { break }
            if isForeign(source.substring(with: matches[previous].range)) { count += 1 }
        }

        for offset in 1...windowRadius {
            let next = index + offset
            guard next < matches.count else { break }
            if crossesBoundary(from: matches[next - 1], to: matches[next], source: source) { break }
            if isForeign(source.substring(with: matches[next].range)) { count += 1 }
        }

        return count
    }

    private static func isForeign(_ token: String) -> Bool {
        guard token.count > 1 else { return false }
        guard token.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        return !VietnameseWordChecker.isVietnameseWord(token)
    }

    private static func crossesBoundary(
        from first: NSTextCheckingResult,
        to second: NSTextCheckingResult,
        source: NSString
    ) -> Bool {
        let start = first.range.location + first.range.length
        let end = second.range.location
        guard end > start, end <= source.length else { return false }
        let gap = source.substring(with: NSRange(location: start, length: end - start))
        return gap.rangeOfCharacter(from: boundaryCharacters) != nil
    }
}
