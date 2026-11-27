import Foundation

/// Token lớp ký tự (`<n>` `<y>` `<h>` `<d>` `<m>` `<a>` `<hn>`) của matcher — tách khỏi `QuickTranslationRuleMatcher.swift`
/// (sát trần 400 dòng) ở 1.3.1093 khi thêm các luật đọc số lớn (anh Bửu: "các token số như vạn ức, ngàn vạn chưa chính
/// xác", "vạn vạn thật ra không phải số vẫn bị nhận là số"). Bản tham chiếu Python: `Docs/Plans/token-so-lon/engine2.py`.
///
/// Ba luật mới, đều chỉ **loại bớt** độ dài thử (không đổi thứ tự thử dài → ngắn):
/// 1. **Cụm ghép phải là một số thật** (`QuickTranslationNumeralShape.isNumber`) — phần token bắt ghép với chữ số liền kề
///    trong chữ cố định (`numeralUnitsBefore` / `numeralUnitsAfter`). Kèm hai luật của `<n>`: chữ cố định trước kết thúc
///    bằng bậc ⇒ giá trị token phải **nhỏ hơn** bậc đó (`<n>万<n>年` không tách `一万亿`); bậc trần đứng ngay sau `几` / `数`
///    trong câu ⇒ không khớp (`两千几百人`).
/// 2. **Token đầu mẫu không bắt đầu giữa một số Ả Rập** (`3千年`, `1.5万`): để rule `<d>…` hoặc VietPhrase lo cả cụm.
/// 3. **Danh sách `<n>、<n>`**: số trước là một chữ số trần thì mượn đuôi bậc của số sau (`applyNumeralListUnits`).
extension QuickTranslationRuleMatcher {
    func walkNumeral(
        _ element: QuickTranslationRuleElement,
        kind: QuickTranslationRuleElement.NumeralKind,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        guard position < units.count else {
            return skipOptional(element, advanced, position)
        }
        let baseAllowed = QuickTranslationNumberFormatter.units(for: kind)
        guard baseAllowed.contains(units[position]) else {
            return skipOptional(element, advanced, position)
        }

        // `<hn>` render bằng bảng phiên âm; bảng chưa nạp thì token không có gì để trả ⇒ coi như không
        // khớp, đúng chính sách của `<hv>` (`QuickTranslationDictionaryToken.isUsable`).
        if kind == .hanNumeral, !dictionaries.isUsable(.hanViet) {
            return skipOptional(element, advanced, position)
        }

        let allowed: Set<UInt16>
        if kind == .chinese || kind == .digitwise {
            if QuickTranslationNumberFormatter.asciiDigitsUnits.contains(units[position]) {
                allowed = baseAllowed.intersection(QuickTranslationNumberFormatter.asciiDigitsUnits)
            } else {
                allowed = baseAllowed.subtracting(QuickTranslationNumberFormatter.asciiDigitsUnits)
            }
        } else {
            allowed = baseAllowed
        }

        // Guard bên trái: ký tự ngay trước match thuộc cùng lớp số ⇒ token đang nuốt phần giữa của
        // một chuỗi số dài hơn. Ngoại lệ: nếu ký tự bên trái thuộc Name riêng thì nó là ranh giới tên chứ
        // không phải phần tiếp nối của số.
        if element.guardsLeft, position > 0,
           !bookNameOccupiedIndices.contains(position - 1),
           allowed.contains(units[position - 1]) {
            return skipOptional(element, advanced, position)
        }

        if element.isPatternHead, kind != .latinLetters, startsInsideArabicNumber(at: position) {
            return skipOptional(element, advanced, position)
        }

        var run = 0
        while position + run < units.count, allowed.contains(units[position + run]) {
            run += 1
        }

        // Guard bên phải: nếu buộc phải nuốt hết chuỗi số thì chỉ có duy nhất độ dài `run` hợp lệ —
        // mọi độ dài ngắn hơn đều để lại ký tự cùng lớp ở ngay sau match.
        let upper = element.guardsRight ? run : min(run, element.maxLength)
        let lower = element.guardsRight ? run : element.minLength
        guard upper <= element.maxLength, upper >= element.minLength, lower <= upper else {
            return skipOptional(element, advanced, position)
        }

        let saved = captures
        var candidate = upper
        while candidate >= lower {
            let value = text.substring(with: NSRange(location: position, length: candidate))
            guard acceptsNumeralCandidate(value, kind: kind, element: element, position: position) else {
                candidate -= 1
                continue
            }
            let rendered: String
            switch kind {
            case .chinese:
                rendered = QuickTranslationNumberFormatter.renderNumeral(value)
            case .digitwise:
                rendered = QuickTranslationNumberFormatter.renderDigitwise(value)
            case .hanDigits:
                rendered = QuickTranslationNumberFormatter.renderHanDigits(value)
            case .asciiDigits:
                rendered = QuickTranslationNumberFormatter.renderAsciiDigits(value)
            case .hanNumeral:
                rendered = dictionaries.hanVietReading(for: value)
            case .magnitude:
                rendered = QuickTranslationNumberFormatter.renderMagnitude(value, leadsPattern: element.leadsPattern)
            case .latinLetters:
                rendered = QuickTranslationNumberFormatter.renderLatinLetters(value)
            }
            store(
                rendered,
                sourceRange: NSRange(location: position, length: candidate),
                for: element
            )
            if let end = walk(advanced, position + candidate) { return end }
            captures = saved
            candidate -= 1
        }

        return skipOptional(element, advanced, position)
    }

    /// `true` khi `position` nằm giữa một số Ả Rập: chữ Hán ngay sau chữ số 0-9 (`3千`), hoặc phần lẻ sau dấu thập phân
    /// (`1.5` — trái là `.`/`．` và trước nữa là 0-9).
    private func startsInsideArabicNumber(at position: Int) -> Bool {
        guard position > 0 else { return false }
        let digits = QuickTranslationNumberFormatter.asciiDigitsUnits
        let left = units[position - 1]
        if !digits.contains(units[position]), digits.contains(left) { return true }
        return (left == 0x2E || left == 0xFF0E) && position >= 2 && digits.contains(units[position - 2])
    }

    /// Luật cụm ghép cho **một** độ dài thử của `<n>` / `<m>`; token khác luôn nhận.
    private func acceptsNumeralCandidate(
        _ value: String,
        kind: QuickTranslationRuleElement.NumeralKind,
        element: QuickTranslationRuleElement,
        position: Int
    ) -> Bool {
        let before = String(decoding: element.numeralUnitsBefore, as: UTF16.self)
        let after = String(decoding: element.numeralUnitsAfter, as: UTF16.self)
        switch kind {
        case .magnitude:
            guard QuickTranslationMagnitudeFormatter.isMagnitudeCandidate(value) else { return false }
            return QuickTranslationNumeralShape.isNumber(before + value + after)
        case .chinese:
            // Nhánh 0-9: lớp ký tự đã tách hẳn khỏi chữ Hán, không có gì để ghép.
            guard let firstUnit = value.utf16.first,
                  !QuickTranslationNumberFormatter.asciiDigitsUnits.contains(firstUnit) else { return true }
            guard QuickTranslationNumeralShape.isNumber(before + value + after) else { return false }
            if let lastBefore = before.last, let scale = QuickTranslationNumeralShape.unitValues[lastBefore] {
                guard let parsed = QuickTranslationNumberFormatter.parseChineseNumeral(value), parsed < scale else {
                    return false
                }
            }
            if before.isEmpty, position > 0,
               QuickTranslationNumeralShape.approximationMarkers.contains(units[position - 1]),
               let first = value.first, QuickTranslationNumeralShape.unitValues[first] != nil {
                return false
            }
            return true
        case .digitwise, .hanDigits, .asciiDigits, .hanNumeral, .latinLetters:
            return true
        }
    }

    /// Danh sách `<n>、<n>` (cặp do compiler tính, `QuickTranslationCompiledRule.numeralListPairs`): số trước là **một** chữ
    /// số trần, số sau = chữ số + toàn bậc ⇒ đọc lại số trước với đuôi bậc đó. `八,九万` ⇒ 80000, 90000; `三、四千` ⇒ 3000,
    /// 4000. Gọi sau khi khớp xong cả mẫu nên không ảnh hưởng việc chọn độ dài.
    func applyNumeralListUnits(_ pairs: [QuickTranslationCompiledRule.NumeralListPair]) {
        let digits = QuickTranslationNumeralShape.nonZeroDigits
        let unitValues = QuickTranslationNumeralShape.unitValues
        for pair in pairs where pair.first < captures.count && pair.second < captures.count {
            guard let firstRange = captures[pair.first].sourceRange,
                  let secondRange = captures[pair.second].sourceRange else { continue }
            let first = Array(text.substring(with: firstRange))
            let second = Array(text.substring(with: secondRange))
            guard first.count == 1, digits.contains(first[0]),
                  second.count >= 2, digits.contains(second[0]),
                  second.dropFirst().allSatisfy({ unitValues[$0] != nil }) else { continue }
            let value = String(first[0]) + String(second.dropFirst())
            captures[pair.first] = Capture(text: QuickTranslationNumberFormatter.renderNumeral(value), sourceRange: firstRange)
        }
    }
}
