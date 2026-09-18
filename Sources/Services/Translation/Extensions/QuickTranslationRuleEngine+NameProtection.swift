import Foundation

/// Mở rộng `QuickTranslationRuleEngine` xử lý bảo vệ Name riêng của truyện trước các Rule dịch.
extension QuickTranslationRuleEngine {

    /// Quét các vị trí của Name riêng trên text nguồn để bảo vệ không bị Rule dịch cắt xén.
    public static func scanBookNameOccupiedIndices(
        text: String,
        bookId: String?
    ) -> (ranges: [NSRange], indices: Set<Int>) {
        guard let bookId, !bookId.isEmpty else { return ([], []) }
        let bookNames = TranslationReadContext.current?.bookDictionaries.names
            ?? TranslationManager.shared.getBookDictionaries(for: bookId).names
        guard let bookNames else { return ([], []) }
        let units = Array(text.utf16)
        var ranges: [NSRange] = []
        var indices = Set<Int>()
        var cursor = 0
        while cursor < units.count {
            if let match = bookNames.findLongestMatch(text: text, startIndex: cursor) {
                ranges.append(NSRange(location: cursor, length: match.length))
                for idx in cursor..<(cursor + match.length) {
                    indices.insert(idx)
                }
                cursor += max(1, match.length)
            } else {
                cursor += 1
            }
        }
        return (ranges, indices)
    }

    /// Kiểm tra xem một lượt khớp rule có cắt ngang / xâm phạm bất hợp pháp vào Name riêng hay không.
    public static func ruleMatchConflictsWithBookNames(
        matchStart: Int,
        matchLength: Int,
        captures: [QuickTranslationRuleMatcher.Capture],
        bookNameRanges: [NSRange]
    ) -> Bool {
        guard !bookNameRanges.isEmpty else { return false }
        let ruleRange = NSRange(location: matchStart, length: matchLength)
        for nameRange in bookNameRanges {
            let intersection = NSIntersectionRange(ruleRange, nameRange)
            guard intersection.length > 0 else { continue }
            // Nếu capture bao trọn vẹn Name riêng thì coi là hợp lệ (ví dụ token <ne> nuốt trọn Name)
            let cleanlyCapturesName = captures.contains { capture in
                guard let src = capture.sourceRange else { return false }
                return src.location == nameRange.location && src.length == nameRange.length
            }
            if !cleanlyCapturesName {
                return true
            }
        }
        return false
    }
}
