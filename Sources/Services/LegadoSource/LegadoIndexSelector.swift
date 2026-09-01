import Foundation

/// Bộ chỉ số của một bước rule jsoup — port `AnalyzeByJSoup.ElementsSingle.findIndexSet`
/// (`:406-500`).
///
/// Hai dạng cú pháp, cùng được quét **từ phải sang trái**:
/// * Dạng `[…]` (kết thúc bằng `]`): `div[1, 3:-2:-10, 2]`, `div[!0,1]`. Bên trong là danh sách chỉ số
///   và **khoảng** `start:end:step` (hai đầu bao gồm, cho phép số âm và đảo chiều).
/// * Dạng cũ của app 阅读: `tag.div.-1:10:2` hoặc `tag.div!0:3`. Ở dạng này `:` **không** phải khoảng
///   mà chỉ là dấu ngăn danh sách chỉ số.
///
/// Dấu ngăn quyết định phép chọn: `.` là chọn, `!` là loại trừ.
public struct LegadoIndexSelector {
    public enum Filter {
        case none
        case select
        case exclude
    }

    public enum Entry {
        case single(Int)
        /// `start`/`end` `nil` nghĩa là bỏ trống (0 và `len - 1`).
        case range(start: Int?, end: Int?, step: Int)
    }

    public let beforeRule: String
    public let filter: Filter
    public let entries: [Entry]

    public init(beforeRule: String, filter: Filter, entries: [Entry]) {
        self.beforeRule = beforeRule
        self.filter = filter
        self.entries = entries
    }

    /// Không có chỉ số ⇒ bước rule là selector thuần.
    public static func plain(_ rule: String) -> LegadoIndexSelector {
        LegadoIndexSelector(beforeRule: rule, filter: .none, entries: [])
    }

    public static func parse(_ rule: String) -> LegadoIndexSelector {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return plain(trimmed) }
        if trimmed.hasSuffix("]") {
            return parseBracketForm(trimmed)
        }
        return parseLegacyForm(trimmed)
    }

    // MARK: - Dạng `[…]`

    private static func parseBracketForm(_ rule: String) -> LegadoIndexSelector {
        let chars = Array(rule)
        var index = chars.count - 2 // bỏ `]` cuối
        var digits = ""
        var negative = false
        var rangeParts: [Int?] = []
        var entries: [Entry] = []
        var filter: Filter = .select

        while index >= 0 {
            let char = chars[index]
            if char == " " {
                index -= 1
                continue
            }
            if char.isNumber {
                digits = String(char) + digits
                index -= 1
                continue
            }
            if char == "-" {
                negative = true
                index -= 1
                continue
            }

            let current: Int? = digits.isEmpty ? nil : (negative ? -(Int(digits) ?? 0) : Int(digits))

            if char == ":" {
                rangeParts.append(current)
                digits = ""
                negative = false
                index -= 1
                continue
            }

            if rangeParts.isEmpty {
                // Không có chỉ số nào ⇒ đây là selector jsoup (`div[style]`), không phải danh sách.
                guard let current else { return plain(rule) }
                entries.append(.single(current))
            } else {
                // `rangeParts` được nạp từ phải sang: phần tử cuối là `end`, phần tử đầu là `step`.
                let end = rangeParts.last ?? nil
                let step = rangeParts.count == 2 ? (rangeParts.first ?? nil) : 1
                entries.append(.range(start: current, end: end, step: step ?? 1))
                rangeParts.removeAll()
            }

            var boundary = char
            if boundary == "!" {
                filter = .exclude
                index -= 1
                while index >= 0, chars[index] == " " { index -= 1 }
                boundary = index >= 0 ? chars[index] : " "
            }

            if boundary == "[" {
                let head = String(chars[0..<index])
                return LegadoIndexSelector(
                    beforeRule: head,
                    filter: filter,
                    entries: entries.reversed()
                )
            }

            if boundary != "," {
                return plain(rule)
            }

            digits = ""
            negative = false
            index -= 1
        }

        return plain(rule)
    }

    // MARK: - Dạng cũ `tag.div.-1:10:2`

    private static func parseLegacyForm(_ rule: String) -> LegadoIndexSelector {
        let chars = Array(rule)
        var index = chars.count - 1
        var digits = ""
        var negative = false
        var collected: [Int] = []

        while index >= 0 {
            let char = chars[index]
            if char == " " {
                index -= 1
                continue
            }
            if char.isNumber {
                digits = String(char) + digits
                index -= 1
                continue
            }
            if char == "-" {
                negative = true
                index -= 1
                continue
            }

            guard char == "!" || char == "." || char == ":" else { return plain(rule) }
            guard let value = Int(digits) else { return plain(rule) }
            collected.append(negative ? -value : value)

            if char != ":" {
                let head = String(chars[0..<index])
                return LegadoIndexSelector(
                    beforeRule: head,
                    filter: char == "!" ? .exclude : .select,
                    entries: collected.reversed().map { Entry.single($0) }
                )
            }

            digits = ""
            negative = false
            index -= 1
        }

        return plain(rule)
    }

    // MARK: - Áp chỉ số

    /// Danh sách chỉ số hợp lệ, **giữ thứ tự xuất hiện trong rule** và không trùng lặp — giống
    /// `LinkedHashSet` của Legado.
    public func resolvedIndexes(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var seen = Set<Int>()
        var ordered: [Int] = []

        func push(_ value: Int) {
            guard value >= 0, value < count, !seen.contains(value) else { return }
            seen.insert(value)
            ordered.append(value)
        }

        for entry in entries {
            switch entry {
            case .single(let raw):
                if raw >= 0 {
                    push(raw)
                } else if count >= -raw {
                    push(raw + count)
                }

            case .range(let rawStart, let rawEnd, let rawStep):
                var start = rawStart ?? 0
                if start < 0 { start += count }
                var end = rawEnd ?? (count - 1)
                if end < 0 { end += count }

                if (start < 0 && end < 0) || (start >= count && end >= count) { continue }
                if start >= count { start = count - 1 } else if start < 0 { start = 0 }
                if end >= count { end = count - 1 } else if end < 0 { end = 0 }

                if start == end || rawStep >= count {
                    push(start)
                    continue
                }
                let step = rawStep > 0 ? rawStep : (-rawStep < count ? rawStep + count : 1)
                guard step > 0 else { push(start); continue }

                if end > start {
                    var cursor = start
                    while cursor <= end {
                        push(cursor)
                        cursor += step
                    }
                } else {
                    var cursor = start
                    while cursor >= end {
                        push(cursor)
                        cursor -= step
                    }
                }
            }
        }
        return ordered
    }
}
