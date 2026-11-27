import Foundation

/// Nới / thu vùng chọn và chia ô hàng chữ gốc theo **trọn chữ** (composed character sequence), không theo từng đơn vị
/// UTF-16 — dùng chung cho panel Dịch / Xoá từ rác / Copy gốc của Reader, sheet Dịch truyện tranh và màn Sửa từ.
///
/// Vì sao (1.3.1080): chữ Hán ngoài BMP (𫄸 U+2B138 — một chữ, hai đơn vị UTF-16) bị nút ‹ › cắt đôi và hàng chữ gốc
/// vẽ thành hai ô vỡ. Vùng chọn **vẫn** là `NSRange` UTF-16 trên chuỗi gốc (bất biến của các màn trên); ở đây chỉ chọn mốc
/// rơi đúng ranh giới chữ. Với chữ dài 1 đơn vị kết quả y như cộng / trừ 1.
///
/// Bốn hàm nới / thu trả `nil` khi không đổi được (đã chạm mép chuỗi, hoặc vùng chọn chỉ còn một chữ) — caller giữ nguyên
/// vùng chọn.
enum ComposedTextSelection {
    /// Một ô của hàng chữ gốc: trọn một chữ và range UTF-16 của nó trên chuỗi gốc.
    struct Cell: Identifiable {
        let range: NSRange
        let text: String

        /// Offset đầu ô — duy nhất trong một chuỗi, nên cũng là khoá `scrollTo` (`"orig-\(offset)"`) như trước.
        var id: Int { range.location }

        /// Ô giao với `selection` (nằm trong vùng chọn hoặc vùng rule đang soi).
        func overlaps(_ selection: NSRange) -> Bool {
            selection.location < NSMaxRange(range) && NSMaxRange(selection) > range.location
        }
    }

    static func cells(in text: String) -> [Cell] {
        let ns = text as NSString
        var cells: [Cell] = []
        cells.reserveCapacity(ns.length)
        var location = 0
        while location < ns.length {
            let range = ns.rangeOfComposedCharacterSequence(at: location)
            cells.append(Cell(range: range, text: ns.substring(with: range)))
            location = max(NSMaxRange(range), location + 1)
        }
        return cells
    }

    static func expandLeft(_ selection: NSRange, in text: String) -> NSRange? {
        let ns = text as NSString
        guard selection.location > 0, NSMaxRange(selection) <= ns.length else { return nil }
        let previous = ns.rangeOfComposedCharacterSequence(at: selection.location - 1)
        return NSRange(location: previous.location, length: NSMaxRange(selection) - previous.location)
    }

    static func shrinkLeft(_ selection: NSRange, in text: String) -> NSRange? {
        let ns = text as NSString
        let end = NSMaxRange(selection)
        guard selection.location >= 0, selection.length > 0, end <= ns.length else { return nil }
        let start = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: selection.location))
        guard start < end else { return nil }
        return NSRange(location: start, length: end - start)
    }

    static func shrinkRight(_ selection: NSRange, in text: String) -> NSRange? {
        let ns = text as NSString
        let end = NSMaxRange(selection)
        guard selection.location >= 0, selection.length > 0, end <= ns.length else { return nil }
        let newEnd = ns.rangeOfComposedCharacterSequence(at: end - 1).location
        guard newEnd > selection.location else { return nil }
        return NSRange(location: selection.location, length: newEnd - selection.location)
    }

    static func expandRight(_ selection: NSRange, in text: String) -> NSRange? {
        let ns = text as NSString
        let end = NSMaxRange(selection)
        guard selection.location >= 0, end < ns.length else { return nil }
        let next = ns.rangeOfComposedCharacterSequence(at: end)
        return NSRange(location: selection.location, length: NSMaxRange(next) - selection.location)
    }
}
