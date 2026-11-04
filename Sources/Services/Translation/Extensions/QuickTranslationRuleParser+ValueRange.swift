import Foundation

/// Khoảng giá trị `#min-max` của token số (1.3.701) — phần parser. Cú pháp, kiểm giá trị và tập token được nhận
/// nằm ở `QuickTranslationRuleValueRange`; file này chỉ gói lỗi thành `INVALID_VALUE_RANGE`.
///
/// `#…` được tách khỏi spec **trước** khi tách `:` độ dài: `<n:1-4#1-200>` mà tách `:` trước thì phần độ dài thành
/// `1-4#1-200` và parser cũ lặng lẽ đọc ra `1-200` ký tự. Tách ở file riêng để `QuickTranslationRuleParser.swift`
/// không vượt trần 400 dòng.
extension QuickTranslationRuleParser {
    /// `spec` (phần giữa `<` và `>`) → phần tên + độ dài (không còn `#…`) và khoảng giá trị; `#` viết sai ⇒ ném lỗi.
    static func splitValueRange(_ spec: String) throws -> (lengthSpec: String, valueRange: QuickTranslationRuleValueRange?) {
        let split = QuickTranslationRuleValueRange.split(spec: spec)
        guard let valueText = split.valueText else { return (spec, nil) }
        do {
            let valueRange = try QuickTranslationRuleValueRange.parse(valueText)
            return (split.head, valueRange)
        } catch {
            let message = (error as? QuickTranslationRuleValueRange.ParseFailure)?.message
                ?? "Khoảng giá trị #\(valueText) không hợp lệ"
            throw ParseError(code: .invalidValueRange, message: message)
        }
    }

    /// `#min-max` chỉ dành cho token đọc ra một con số; `<a#1-3>`, `<m#10>`, `<any#1-5>`, `<ne#1>`… ⇒ lỗi nặng
    /// thay vì lặng lẽ bỏ phần `#`.
    static func requireValueRangeSupport(_ valueRange: QuickTranslationRuleValueRange?, names: [String]) throws {
        guard valueRange != nil, !QuickTranslationRuleValueRange.supports(names: names) else { return }
        let token = "<" + names.joined(separator: "|") + ">"
        throw ParseError(
            code: .invalidValueRange,
            message: "Token \(token) không nhận khoảng giá trị #min-max; chỉ <n> <y> <h> <d> <hn> nhận"
        )
    }

    /// Neo dòng và ngoặc không chiếm con số nào ⇒ `<START#1>`, `<[#2>` báo lỗi cùng mã với token khác.
    static func rejectValueRangeOnUncapturedToken(_ spec: String) throws {
        guard isUncapturedTokenSpec(spec), QuickTranslationRuleValueRange.split(spec: spec).valueText != nil else {
            return
        }
        throw ParseError(code: .invalidValueRange, message: "Neo dòng và token ngoặc không nhận khoảng giá trị #min-max")
    }
}
