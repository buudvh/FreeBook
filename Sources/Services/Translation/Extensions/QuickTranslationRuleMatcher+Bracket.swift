import Foundation

/// Token ngoặc `<[>` / `<]>` của matcher (1.3.692) và bộ lọc "phần tử kế tiếp" của `<any>`.
///
/// - `<[>` khớp **một** ký tự thuộc `brackets.openUnits`, lưu ký tự đó (kèm vị trí) vào ô **ẩn**
///   `bracketSlot` — sau mọi ô `{i}`, nên không bao giờ ra bản dịch (`Match.captures` cắt bỏ).
/// - `<]>` khớp **một** ký tự thuộc `brackets.closeUnits`. Nếu ô của `<[>` đi cặp (`bracketPartnerSlot`)
///   có giá trị thì ký tự phải là **đúng** ngoặc đóng của ký tự mở đó, và đoạn giữa hai ngoặc phải
///   **cân bằng** với cùng kiểu ngoặc — nên `<[><any><]>` trên `(a)Y(b)` ra `(a)` chứ không nuốt cả
///   `(a)Y(b)`. Ô trống (không có `<[>` đi cặp, hoặc `<[>` nằm ở nhánh không khớp) ⇒ nhận mọi ngoặc đóng.
///
/// Ô ẩn dùng chung cơ chế `let saved = captures` … `captures = saved` với các token khác, nên thử lùi qua
/// nhóm hay qua độ dài của `<any>` tự trả ô về trạng thái cũ.
///
/// Tách khỏi `QuickTranslationRuleMatcher.swift` để file gốc không vượt trần 400 dòng.
extension QuickTranslationRuleMatcher {
    // MARK: - <[> / <]>

    func walkOpenBracket(
        _ element: QuickTranslationRuleElement,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        guard position < units.count, brackets.isOpen(units[position]) else {
            return skipOptional(element, advanced, position)
        }
        let saved = captures
        if let slot = element.bracketSlot, slot < captures.count {
            let range = NSRange(location: position, length: 1)
            captures[slot] = Capture(text: text.substring(with: range), sourceRange: range)
        }
        if let end = walk(advanced, position + 1) { return end }
        captures = saved
        return skipOptional(element, advanced, position)
    }

    func walkCloseBracket(
        _ element: QuickTranslationRuleElement,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        guard position < units.count, brackets.isClose(units[position]) else {
            return skipOptional(element, advanced, position)
        }
        if let open = partnerOpen(of: element) {
            guard let expected = brackets.close(forOpen: open.unit), units[position] == expected,
                  isBalanced(open: open.unit, close: expected, from: open.location + 1, to: position) else {
                return skipOptional(element, advanced, position)
            }
        }
        if let end = walk(advanced, position + 1) { return end }
        return skipOptional(element, advanced, position)
    }

    /// Ký tự mở mà `<[>` đi cặp đã bắt **trong lượt khớp hiện tại**; `nil` khi `<]>` không có cặp hoặc ô
    /// còn trống (`sourceRange == nil` — `<[>` vắng mặt hay nằm ở nhánh không khớp).
    private func partnerOpen(of element: QuickTranslationRuleElement) -> (unit: UInt16, location: Int)? {
        guard let slot = element.bracketPartnerSlot, slot < captures.count,
              let range = captures[slot].sourceRange, range.location < units.count else { return nil }
        return (units[range.location], range.location)
    }

    /// Đoạn `units[start..<end]` cân bằng với **đúng** cặp `open`/`close`: đếm mở +1, đóng −1, không lúc nào
    /// âm và kết thúc ở 0. Ngoặc kiểu khác không được đếm.
    private func isBalanced(open: UInt16, close: UInt16, from start: Int, to end: Int) -> Bool {
        guard start <= end, end <= units.count else { return false }
        var depth = 0
        for index in start..<end {
            let unit = units[index]
            if unit == open {
                depth += 1
            } else if unit == close {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0
    }

    // MARK: - Phần tử ngay sau <any>

    /// Chữ cố định (không optional) đứng **ngay sau** phần tử đang xét trong cùng dãy; `nil` nếu không có.
    func followingLiteral(in advanced: [Frame]) -> [UInt16]? {
        guard let frame = advanced.last, frame.index < frame.elements.count else { return nil }
        let next = frame.elements[frame.index]
        guard !next.isOptional, case .literal(let literal) = next.kind, !literal.isEmpty else { return nil }
        return literal
    }

    func hasLiteral(_ literal: [UInt16], at index: Int) -> Bool {
        guard index + literal.count <= units.count else { return false }
        for offset in literal.indices where units[index + offset] != literal[offset] {
            return false
        }
        return true
    }

    /// Tập ký tự được phép đứng **ngay sau** `<any>` khi phần tử kế tiếp trong cùng dãy là token ngoặc không
    /// optional; `nil` = không ràng buộc. `<]>` có cặp đã bắt ⇒ chỉ đúng ngoặc đóng mong đợi. Tính **một lần**
    /// trước vòng thử độ dài: ô của `<[>` đi cặp đã cố định lúc đó vì `<[>` luôn đứng trước `<any>`.
    func followingBracketUnits(in advanced: [Frame]) -> Set<UInt16>? {
        guard let frame = advanced.last, frame.index < frame.elements.count else { return nil }
        let next = frame.elements[frame.index]
        guard !next.isOptional else { return nil }
        if case .openBracket = next.kind { return brackets.openUnits }
        guard case .closeBracket = next.kind else { return nil }
        guard let open = partnerOpen(of: next) else { return brackets.closeUnits }
        guard let expected = brackets.close(forOpen: open.unit) else { return Set<UInt16>() }
        return Set([expected])
    }
}
