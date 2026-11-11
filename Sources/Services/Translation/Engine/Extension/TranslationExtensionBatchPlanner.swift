import Foundation

/// Chia các dòng cần dịch thành lô theo `max_line` / `max_length` của tiện ích, và tách bản dịch của một lô về lại
/// từng dòng. Hàm thuần.
///
/// Một lô = các dòng nối bằng `\n`. Một dòng dài hơn `max_length` vẫn đi riêng một lô (không cắt giữa dòng: cắt là mất
/// khớp dòng ↔ bản dịch).
enum TranslationExtensionBatchPlanner {
    struct Line: Sendable {
        /// `ChapterTextLine.id` — chỉ số dòng thô, thưa; không phải vị trí mảng.
        let id: Int
        let text: String
    }

    static func batches(_ lines: [Line], maxLines: Int?, maxLength: Int?, disablesSplitting: Bool) -> [[Line]] {
        guard !lines.isEmpty else { return [] }
        guard !disablesSplitting else { return [lines] }
        var result: [[Line]] = []
        var current: [Line] = []
        var currentLength = 0
        for line in lines {
            let length = line.text.count
            let addedLength = current.isEmpty ? length : currentLength + 1 + length
            let exceedsLines = maxLines.map { current.count >= $0 } ?? false
            let exceedsLength = maxLength.map { !current.isEmpty && addedLength > $0 } ?? false
            if exceedsLines || exceedsLength {
                result.append(current)
                current = []
                currentLength = 0
            }
            current.append(line)
            currentLength = current.count == 1 ? length : currentLength + 1 + length
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Nội dung gửi đi của một lô.
    static func joined(_ batch: [Line]) -> String {
        batch.map(\.text).joined(separator: "\n")
    }

    /// Tách bản dịch của một lô theo dòng: bỏ dòng trống ở hai đầu, `\r\n` ⇒ `\n`, bỏ khoảng trắng hai đầu mỗi dòng.
    /// Trả `nil` khi số dòng lệch lô (caller chia nhỏ lô). Lô một dòng luôn khớp: xuống dòng bên trong gộp thành dấu
    /// cách để không đẻ thêm dòng (TTS dựng lại nội dung theo dòng).
    static func split(_ output: String, for batch: [Line]) -> [String]? {
        let normalized = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
        if batch.count == 1 {
            let collapsed = normalized
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return [collapsed]
        }
        let parts = normalized.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == batch.count { return parts }
        // Một số máy dịch chèn dòng trống giữa các dòng: bỏ dòng trống rồi thử khớp lại.
        let nonEmpty = parts.filter { !$0.isEmpty }
        return nonEmpty.count == batch.count ? nonEmpty : nil
    }

    /// Dòng có chữ mới gửi đi dịch; dòng chỉ có số / dấu câu giữ nguyên.
    static func needsTranslation(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .letters) != nil
    }
}
