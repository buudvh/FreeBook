import Foundation

/// Thông tin quanh token số mà matcher cần để xét "cả cụm có phải một số thật" (1.3.1093, anh Bửu: "vạn vạn thật ra không
/// phải số vẫn bị nhận là số"). Bản tham chiếu Python: `Docs/Plans/token-so-lon/engine2.py`.
///
/// - `numeralUnitsBefore` / `numeralUnitsAfter` (chỉ `<n>` / `<m>`): chữ số / bậc Hán **cuối** của chữ cố định ngay trước
///   token và **đầu** của chữ cố định ngay sau. Chỉ xét mức ngoài cùng của mẫu, như `applyBoundaryGuards`.
/// - `isPatternHead`: token lớp ký tự đứng đầu mẫu (bỏ neo dòng, mẫu mở đầu bằng nhóm thì đầu mỗi nhánh — cùng cách duyệt
///   với `markLeadingMagnitude`). Token đầu mẫu không được bắt đầu giữa một số Ả Rập (`3千年`, `1.5万`).
/// - `numeralListPairs`: dạng danh sách `<n>、<n>` để số trước mượn đuôi bậc của số sau.
///
/// Tách file riêng để `QuickTranslationRuleCompiler.swift` không vượt trần 400 dòng.
extension QuickTranslationRuleCompiler {
    /// Dấu ngăn của dạng danh sách số.
    private static let numeralListSeparators: Set<UInt16> = Set(",，、".utf16)

    static func markNumeralNeighbours(_ elements: inout [QuickTranslationRuleElement]) {
        markPatternHead(&elements)
        let hanNumeral = QuickTranslationNumberFormatter.hanNumeralUnits
        for index in elements.indices {
            guard case .numeral(let kind) = elements[index].kind, kind == .chinese || kind == .magnitude else { continue }
            if index > 0, case .literal(let units) = elements[index - 1].kind {
                elements[index].numeralUnitsBefore = Array(units.reversed().prefix(while: { hanNumeral.contains($0) }).reversed())
            }
            if index + 1 < elements.count, case .literal(let units) = elements[index + 1].kind {
                elements[index].numeralUnitsAfter = Array(units.prefix(while: { hanNumeral.contains($0) }))
            }
        }
    }

    private static func markPatternHead(_ elements: inout [QuickTranslationRuleElement]) {
        guard let index = elements.firstIndex(where: { !$0.isLineAnchor }) else { return }
        switch elements[index].kind {
        case .numeral:
            elements[index].isPatternHead = true
        case .group(var alternatives):
            for branch in alternatives.indices {
                markPatternHead(&alternatives[branch])
            }
            elements[index].kind = .group(alternatives)
        case .literal, .chapterLabel, .dictionary, .anyRun, .lineStart, .lineEnd, .openBracket, .closeBracket:
            return
        }
    }

    /// `<n>` + đúng một dấu `,` `，` `、` + `<n>`, cả hai không optional, ở mức ngoài cùng của mẫu.
    static func numeralListPairs(_ elements: [QuickTranslationRuleElement]) -> [QuickTranslationCompiledRule.NumeralListPair] {
        guard elements.count >= 3 else { return [] }
        var pairs: [QuickTranslationCompiledRule.NumeralListPair] = []
        for index in 0..<(elements.count - 2) {
            let first = elements[index]
            let separator = elements[index + 1]
            let second = elements[index + 2]
            guard case .numeral(.chinese) = first.kind, case .numeral(.chinese) = second.kind,
                  case .literal(let units) = separator.kind, units.count == 1, numeralListSeparators.contains(units[0]),
                  !first.isOptional, !second.isOptional,
                  let firstIndex = first.captureIndex, let secondIndex = second.captureIndex else { continue }
            pairs.append(QuickTranslationCompiledRule.NumeralListPair(first: firstIndex, second: secondIndex))
        }
        return pairs
    }
}
