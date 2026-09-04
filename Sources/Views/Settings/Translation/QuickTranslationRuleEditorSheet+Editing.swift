import SwiftUI

/// Khối biên tập **mẫu** và **bản dịch** của màn thêm/sửa rule: định vị token đang chọn, chèn/thay
/// token, xoá lùi, và chèn `{i}` tại con trỏ ô Bản dịch.
///
/// Tách khỏi `QuickTranslationRuleEditorSheet.swift` vì file đó đã tới 300+ dòng và trần của
/// `check_architecture.py` cho file mới là 400. Vì `private` trong Swift là phạm vi **file**, các
/// `@State` mà khối này sửa (`pattern`, `selectionStart`, `selectionLength`, `replacement`,
/// `replacementSelection*`) phải là `internal` — cùng lý do và cùng khuôn với `ReaderView` +
/// `ReaderView+Selection`.
///
/// Bất biến của cả khối: mọi chỉ số vùng chọn đếm theo **ký tự** trên `Array(...)` của chuỗi tương ứng.
/// Quy đổi sang `NSRange` UTF-16 chỉ xảy ra ở `QuickTranslationRulePatternField`, tức đúng biên UIKit.
extension QuickTranslationRuleEditorSheet {

    /// Token mà thanh min–max đang nói về.
    ///
    /// Có vùng chọn ⇒ phải trùng **khít** một chip token (chọn hai ký tự literal không mở thanh ra vô
    /// nghĩa). Chỉ có con trỏ ⇒ token nào **chứa** con trỏ hoặc kết thúc ngay tại đó: nhờ vậy vừa chèn
    /// `<n>` xong (con trỏ nằm sau token) là thanh mở ngay, và chạm vào giữa `<n:1-6>` trong ô nhập
    /// cũng mở đúng token đó.
    func selectedTokenSegment(
        in segments: [QuickTranslationRuleDraftAnalyzer.Segment]
    ) -> QuickTranslationRuleDraftAnalyzer.Segment? {
        if selectionLength > 0 {
            return segments.first {
                $0.kind == .token && $0.start == selectionStart && $0.length == selectionLength
            }
        }
        return segments.first {
            $0.kind == .token && $0.start < selectionStart && selectionStart <= $0.end
        }
    }

    /// Đặt mẫu mới kèm con trỏ. Luôn để con trỏ (không phải vùng chọn) để lượt gõ tiếp theo không
    /// vô tình thay mất phần vừa chèn.
    func setPattern(_ newPattern: String, caret: Int) {
        pattern = newPattern
        selectionStart = max(0, min(caret, Array(newPattern).count))
        selectionLength = 0
    }

    /// Kẹp vùng chọn về biên hợp lệ sau khi mẫu đổi từ đường khác (khôi phục bản nháp, xoá bằng nút).
    /// Con trỏ do ô nhập cấp nên ở đây **không** còn heuristic "đưa về cuối" nào.
    func reconcileSelection(after newPattern: String) {
        let count = Array(newPattern).count
        selectionStart = min(max(0, selectionStart), count)
        if selectionStart + selectionLength > count {
            selectionLength = 0
        }
    }

    /// Chèn tại con trỏ, hoặc **thay** vùng đang chọn. Đây là đường duy nhất mà bảng token dùng, nên
    /// hai ngữ nghĩa đó không thể lệch nhau.
    func insertIntoPattern(_ text: String) {
        let count = Array(pattern).count
        let start = min(max(0, selectionStart), count)
        let end = min(max(start, start + selectionLength), count)
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(
            range: start..<end,
            in: pattern,
            with: text
        )
        setPattern(updated, caret: start + Array(text).count)
    }

    func applyTokenSpec(
        _ spec: QuickTranslationRuleDraftAnalyzer.TokenSpec,
        to segment: QuickTranslationRuleDraftAnalyzer.Segment
    ) {
        let syntax = spec.syntax
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(
            range: segment.range,
            in: pattern,
            with: syntax
        )
        setPattern(updated, caret: segment.start + Array(syntax).count)
    }

    /// Xoá vùng đang chọn; chỉ có con trỏ thì xoá **cả chip** liền trước (một token là một chip, không
    /// phải 7 ký tự lẻ).
    func deleteBackwardInPattern() {
        let count = Array(pattern).count
        let start = min(max(0, selectionStart), count)

        if selectionLength > 0 {
            let end = min(start + selectionLength, count)
            let updated = QuickTranslationRuleDraftAnalyzer.replacing(range: start..<end, in: pattern, with: "")
            setPattern(updated, caret: start)
            return
        }

        guard let previous = QuickTranslationRuleDraftAnalyzer.segments(of: pattern)
            .last(where: { $0.end <= start }) else { return }
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(range: previous.range, in: pattern, with: "")
        setPattern(updated, caret: previous.start)
    }

    // MARK: - Ô Bản dịch (vế phải)

    /// Chèn `{i}` tại con trỏ của ô Bản dịch, hoặc **thay** vùng đang chọn — đúng ngữ nghĩa của bảng
    /// token ở vế trái. `QuickTranslationRuleDraftAnalyzer.replacing` chỉ cắt/dán theo chỉ số ký tự nên
    /// dùng được cho cả hai vế; nó **không** phân tích cú pháp mẫu.
    func insertIntoReplacement(_ text: String) {
        let count = Array(replacement).count
        let start = min(max(0, replacementSelectionStart), count)
        let end = min(max(start, start + replacementSelectionLength), count)
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(
            range: start..<end,
            in: replacement,
            with: text
        )
        replacement = updated
        replacementSelectionStart = min(start + Array(text).count, Array(updated).count)
        replacementSelectionLength = 0
    }

    /// Kẹp con trỏ ô Bản dịch về biên hợp lệ sau khi chuỗi đổi từ đường khác (khôi phục bản nháp).
    func reconcileReplacementSelection(after newReplacement: String) {
        let count = Array(newReplacement).count
        replacementSelectionStart = min(max(0, replacementSelectionStart), count)
        if replacementSelectionStart + replacementSelectionLength > count {
            replacementSelectionLength = 0
        }
    }
}
