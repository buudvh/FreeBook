import Foundation

/// Phân tích **bản nháp** của một rule đang được gõ ở màn thêm/sửa rule: đếm token, biết `{i}` nào
/// còn thiếu, và cắt mẫu thành từng chip để UI chọn/sửa từng token.
///
/// Không cài lại bất kỳ luật cú pháp nào. Verdict lấy bằng cách dựng **đúng dòng mà store sẽ ghi**
/// (`QuickTranslationRuleRecordStore.serialize`) rồi chạy lại `parse` → `compile`, nên cảnh báo hiện
/// lúc gõ trùng khít cảnh báo lúc lưu — kể cả trường hợp mẫu có dấu `=`: định dạng file cắt ở dấu `=`
/// đầu tiên nên mẫu như vậy vốn không biểu diễn được, và phải hiện lỗi ngay chứ không đợi tới lúc lưu.
///
/// Ranh giới tầng: đây là Service nên **không** `import SwiftUI`.
public enum QuickTranslationRuleDraftAnalyzer {

    // MARK: - Verdict của một bản nháp

    public struct Analysis: Sendable {
        /// Số token trong mẫu, đánh số theo thứ tự xuất hiện (kể cả token nằm trong nhóm).
        public var captureCount: Int = 0
        /// Các `{i}` mà bản dịch đang tham chiếu.
        public var referenced: Set<Int> = []
        /// Token có trong mẫu nhưng bản dịch chưa dùng — `UNUSED_CAPTURE`, lỗi **hard**.
        public var missing: [Int] = []
        /// `{i}` vượt quá số token — `INVALID_REF_INDEX`, lỗi **hard**.
        public var outOfRange: [Int] = []
        public var issues: [QuickTranslationRuleIssue] = []

        public var hardIssues: [QuickTranslationRuleIssue] {
            issues.filter { $0.severity == .hard }
        }

        public var warnings: [QuickTranslationRuleIssue] {
            issues.filter { $0.severity != .hard }
        }

        /// Rule sẽ được nhận khi lưu hay không. Chỉ lỗi `hard` mới chặn.
        public var isAcceptable: Bool { hardIssues.isEmpty }
    }

    public static func analyze(pattern: String, replacement: String) -> Analysis {
        var analysis = Analysis()
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return analysis }

        let text = QuickTranslationRuleRecordStore.serialize([
            QuickTranslationRuleRecordStore.Record(pattern: pattern, replacement: replacement)
        ])
        let parsed = QuickTranslationRuleParser.parse(text)
        let compiled = QuickTranslationRuleCompiler.compile(parsed)

        analysis.captureCount = parsed.rules.first?.captureCount ?? 0
        analysis.issues = compiled.issues
        analysis.referenced = Set(
            QuickTranslationRuleCompiler.parseTemplate(replacement).compactMap { segment -> Int? in
                if case .capture(let index) = segment { return index }
                return nil
            }
        )
        analysis.missing = (0..<analysis.captureCount).filter { !analysis.referenced.contains($0) }
        analysis.outOfRange = analysis.referenced.filter { $0 >= analysis.captureCount }.sorted()
        return analysis
    }

    // MARK: - Cắt mẫu thành chip

    /// Một mảnh của mẫu, cắt theo **văn bản nguồn** (không phải AST): token là một chip nguyên khối,
    /// cú pháp nhóm là chip riêng, còn lại là từng ký tự.
    ///
    /// Cắt phẳng chứ không đi theo cây: nhờ vậy token nằm trong `(a|<n>)` vẫn chọn và sửa được như
    /// token ở ngoài, và `tokenOrdinal` khớp đúng `captureIndex` của parser vì cả hai đều đánh số
    /// theo thứ tự xuất hiện từ trái sang phải.
    public struct Segment: Identifiable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Ký tự thường. `\x` giữ nguyên hai ký tự trong một chip để không mất dấu escape.
            case literal
            /// `<n>`, `<n:1-6>`, `<ne|pn>?`…
            case token
            /// `(`, `|`, `)`, `)?` — không sinh capture.
            case groupPunct
        }

        public let id: Int
        public let kind: Kind
        public let text: String
        /// Vị trí trong `Array(pattern)`: mọi chỉ số UI cầm đều là **chỉ số ký tự**, không phải UTF-16.
        public let start: Int
        public let length: Int
        /// Thứ tự token, chỉ đếm chip `.token`; `nil` với literal và cú pháp nhóm.
        public let tokenOrdinal: Int?

        public var end: Int { start + length }
        public var range: Range<Int> { start..<end }
    }

    public static func segments(of pattern: String) -> [Segment] {
        let chars = Array(pattern)
        var result: [Segment] = []
        var cursor = 0
        var tokenCount = 0

        func append(_ kind: Segment.Kind, length: Int, ordinal: Int? = nil) {
            result.append(Segment(
                id: result.count,
                kind: kind,
                text: String(chars[cursor..<(cursor + length)]),
                start: cursor,
                length: length,
                tokenOrdinal: ordinal
            ))
            cursor += length
        }

        while cursor < chars.count {
            let char = chars[cursor]

            if char == "\\", cursor + 1 < chars.count {
                append(.literal, length: 2)
                continue
            }

            if char == "<", let close = chars[cursor...].firstIndex(of: ">") {
                var length = close - cursor + 1
                if close + 1 < chars.count, chars[close + 1] == "?" { length += 1 }
                append(.token, length: length, ordinal: tokenCount)
                tokenCount += 1
                continue
            }

            if char == "(" || char == "|" || char == ")" {
                let optionalSuffix = char == ")" && cursor + 1 < chars.count && chars[cursor + 1] == "?"
                append(.groupPunct, length: optionalSuffix ? 2 : 1)
                continue
            }

            append(.literal, length: 1)
        }

        return result
    }

    // MARK: - Một token và khoảng độ dài của nó

    /// Cú pháp một token đã tách sẵn, để thanh điều chỉnh min–max không phải tự parse chuỗi.
    ///
    /// Mọi hằng số ở đây lấy **từ parser**, không đặt lại: token không khai `:min-max` nghĩa là
    /// `1...12` (`QuickTranslationRuleParser.parseToken`), nên khi hai đầu đúng bằng mặc định thì
    /// `syntax` xuất lại token trần thay vì viết thừa `:1-12` vào mẫu của người dùng.
    public struct TokenSpec: Sendable, Equatable {
        public static let defaultMinLength = 1
        public static let defaultMaxLength = 12
        /// Trần của thanh điều chỉnh. Parser không cấm số lớn hơn, nhưng `wildcardCapacity` càng rộng
        /// thì rule càng thua ở tiêu chí ưu tiên thứ 3 và càng nặng backtracking.
        public static let adjustableUpperBound = 20

        public var names: [String]
        public var minLength: Int
        public var maxLength: Int
        public var isOptional: Bool

        /// `<L>` và `<hv>` bị parser ép về đúng 1 ký tự bất kể `:min-max`, nên không cho điều chỉnh:
        /// hiện thanh cho chúng là hứa một việc không có hiệu lực.
        public var supportsLengthRange: Bool {
            if names.allSatisfy({ $0 == "L" }) { return false }
            if names == ["hv"] { return false }
            return true
        }

        public var isDefaultRange: Bool {
            minLength == Self.defaultMinLength && maxLength == Self.defaultMaxLength
        }

        public var syntax: String {
            var spec = names.joined(separator: "|")
            if supportsLengthRange, !isDefaultRange {
                spec += minLength == maxLength ? ":\(minLength)" : ":\(minLength)-\(maxLength)"
            }
            return "<\(spec)>" + (isOptional ? "?" : "")
        }

        /// Kẹp về vùng hợp lệ của parser: `min ≥ 1` là điều kiện cứng (sai thì `UNKNOWN_TOKEN_NAME`,
        /// lỗi hard) và `max = max(min, max)`.
        public mutating func clamp() {
            minLength = min(max(1, minLength), Self.adjustableUpperBound)
            maxLength = min(max(minLength, maxLength), Self.adjustableUpperBound)
        }
    }

    public static func tokenSpec(of segmentText: String) -> TokenSpec? {
        var text = segmentText
        var isOptional = false
        if text.hasSuffix("?") {
            isOptional = true
            text.removeLast()
        }
        guard text.hasPrefix("<"), text.hasSuffix(">") else { return nil }

        let parts = String(text.dropFirst().dropLast()).components(separatedBy: ":")
        let names = parts[0].components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty, !names.contains(where: { $0.isEmpty }) else { return nil }

        var spec = TokenSpec(
            names: names,
            minLength: TokenSpec.defaultMinLength,
            maxLength: TokenSpec.defaultMaxLength,
            isOptional: isOptional
        )
        if parts.count > 1, !parts[1].isEmpty {
            let bounds = parts[1].components(separatedBy: "-").compactMap { Int($0) }
            if let first = bounds.first, first >= 1 {
                spec.minLength = first
                spec.maxLength = bounds.count > 1 ? max(first, bounds[1]) : first
            }
        }
        if !spec.supportsLengthRange {
            spec.minLength = 1
            spec.maxLength = 1
        }
        spec.clamp()
        return spec
    }

    // MARK: - Ghi lại mẫu

    /// Splice theo **chỉ số ký tự** của `Array(pattern)`, kẹp về biên hợp lệ để một vùng chọn cũ
    /// (mẫu vừa bị gõ ngắn lại) không bao giờ làm crash.
    public static func replacing(range: Range<Int>, in pattern: String, with text: String) -> String {
        var chars = Array(pattern)
        let lower = min(max(0, range.lowerBound), chars.count)
        let upper = min(max(lower, range.upperBound), chars.count)
        chars.replaceSubrange(lower..<upper, with: Array(text))
        return String(chars)
    }

    public static func replacing(tokenOrdinal: Int, in pattern: String, with spec: TokenSpec) -> String {
        guard let segment = segments(of: pattern).first(where: { $0.tokenOrdinal == tokenOrdinal }) else {
            return pattern
        }
        return replacing(range: segment.range, in: pattern, with: spec.syntax)
    }
}
