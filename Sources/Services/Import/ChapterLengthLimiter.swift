import Foundation

/// Hậu xử lý **chung cho mọi parser** nhập truyện: chương dài bất thường — gần như luôn là dấu hiệu
/// parser không tìm được ranh giới chương thật — bị tách thành nhiều phần trước khi hiện sheet xác nhận.
///
/// Ba bất biến của phép tách:
/// 1. **Không mất text**: `parts.joined()` bằng đúng `content` gốc, vì mỗi unit giữ luôn ký tự `\n`
///    của nó và các phần chỉ là phép gộp unit liền kề.
/// 2. **Không sinh phần rỗng**: phần cuối quá ngắn được nhập lại vào phần trước.
/// 3. **Không tách lại phần đã tách**: chương có `partIndex != nil` được bỏ qua, nên "Phân tích lại"
///    trên sheet không bao giờ tạo ra `" (1) (1)"`.
///
/// Thứ tự ưu tiên điểm cắt: khối/dòng (ranh giới đoạn) → câu → cụm ký tự. Mọi phép cắt duyệt theo
/// `Character` (grapheme cluster) nên không bao giờ chẻ đôi một ký tự — đây là lý do **không** dùng
/// `NSRange` UTF-16 ở đây.
enum ChapterLengthLimiter {
    /// Ngưỡng kích hoạt: chương ngắn hơn mức này không bao giờ bị tách.
    static let triggerCharacters = 30_000
    /// Kích thước mong muốn của mỗi phần sau khi tách.
    static let targetCharacters = 15_000

    /// Áp limiter cho cả danh sách chương, giữ đúng thứ tự đọc.
    static func apply(to chapters: [ParserChapter]) -> [ParserChapter] {
        var output: [ParserChapter] = []
        for (index, chapter) in chapters.enumerated() {
            let length = chapter.content.count
            guard chapter.partIndex == nil, length > triggerCharacters else {
                output.append(chapter)
                continue
            }

            let parts = split(chapter.content)
            guard parts.count >= 2 else {
                output.append(chapter)
                continue
            }

            let reason = "chương gốc dài \(length) ký tự, vượt ngưỡng \(triggerCharacters)"
            for (offset, text) in parts.enumerated() {
                output.append(ParserChapter(
                    title: "\(chapter.title) (\(offset + 1))",
                    content: text,
                    originalTitle: chapter.title,
                    sourceOrdinal: index + 1,
                    partIndex: offset + 1,
                    partCount: parts.count,
                    splitReason: reason
                ))
            }
        }
        return output
    }

    /// Báo cáo cho sheet xác nhận; `nil` khi không có chương nào bị tách.
    static func report(for chapters: [ParserChapter]) -> String? {
        let parts = chapters.filter { $0.partCount != nil }
        guard !parts.isEmpty else { return nil }
        let sources = Set(parts.compactMap(\.sourceOrdinal))
        return "Đã tách \(sources.count) chương quá dài thành \(parts.count) phần"
    }

    // MARK: - Tách một chương

    private static func split(_ content: String) -> [String] {
        var units: [String] = []
        for unit in lineUnits(content) {
            if unit.count <= targetCharacters {
                units.append(unit)
            } else {
                units.append(contentsOf: sentenceOrCharacterUnits(unit))
            }
        }
        return group(units)
    }

    /// Mỗi dòng giữ luôn ký tự `\n` kết thúc của nó ⇒ ghép lại không thêm/mất ký tự nào.
    private static func lineUnits(_ content: String) -> [String] {
        var units: [String] = []
        var current = ""
        for character in content {
            current.append(character)
            if character == "\n" {
                units.append(current)
                current = ""
            }
        }
        if !current.isEmpty { units.append(current) }
        return units
    }

    private static func sentenceOrCharacterUnits(_ line: String) -> [String] {
        var result: [String] = []
        for sentence in sentenceUnits(line) {
            if sentence.count <= targetCharacters {
                result.append(sentence)
            } else {
                result.append(contentsOf: characterChunks(sentence))
            }
        }
        return result
    }

    private static let sentenceEnders: Set<Character> = [
        ".", "!", "?", ";", "。", "！", "？", "；", "…"
    ]

    /// Ký tự đi ngay sau dấu kết câu vẫn thuộc câu đó (dấu đóng ngoặc/nháy, khoảng trắng).
    private static let trailingMarks: Set<Character> = [
        "\"", "'", "”", "’", "»", ")", "]", "】", "」", "』", " "
    ]

    private static func sentenceUnits(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var pendingEnd = false

        for character in text {
            if pendingEnd {
                if trailingMarks.contains(character) || sentenceEnders.contains(character) {
                    current.append(character)
                    continue
                }
                result.append(current)
                current = ""
                pendingEnd = false
            }
            current.append(character)
            if sentenceEnders.contains(character) { pendingEnd = true }
        }

        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Lối cuối: một câu dài hơn cả một phần (văn bản không có dấu câu). Cắt theo số ký tự, vẫn ở
    /// ranh giới `Character` an toàn.
    private static func characterChunks(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var count = 0
        for character in text {
            current.append(character)
            count += 1
            if count >= targetCharacters {
                result.append(current)
                current = ""
                count = 0
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Gộp unit liền kề thành phần ~`targetCharacters`. Đếm bằng biến `Int` thay vì gọi `String.count`
    /// mỗi vòng — chương bị tách thường vài trăm nghìn ký tự.
    private static func group(_ units: [String]) -> [String] {
        var parts: [String] = []
        var current = ""
        var currentCount = 0

        for unit in units {
            let length = unit.count
            if currentCount > 0, currentCount + length > targetCharacters {
                parts.append(current)
                current = ""
                currentCount = 0
            }
            current += unit
            currentCount += length
        }
        if currentCount > 0 { parts.append(current) }

        // Phần cuối quá ngắn (hoặc chỉ có khoảng trắng) thì nhập vào phần trước.
        if parts.count >= 2,
           let last = parts.last,
           last.trimmingCharacters(in: .whitespacesAndNewlines).count < targetCharacters / 5 {
            let tail = parts.removeLast()
            parts[parts.count - 1] += tail
        }
        return parts
    }
}
