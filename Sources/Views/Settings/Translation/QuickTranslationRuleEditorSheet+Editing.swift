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

    /// Thay token thứ `tokenOrdinal` bằng cú pháp mới.
    ///
    /// Nhận **thứ tự token** chứ không nhận `Segment`: `Segment` mang `range` tính trên mẫu **lúc dựng
    /// body**, mà `applyTokenSpec` có thể được gọi sau khi mẫu đã đổi. Range cũ + `replacing(range:)`
    /// (chỉ kẹp về biên chuỗi) = cắt sai chỗ **im lặng**, để lại rác ở đuôi (`<n:1-8>1-9>`).
    /// `replacing(tokenOrdinal:)` tự định vị lại token trên mẫu hiện tại.
    func applyTokenSpec(
        _ spec: QuickTranslationRuleDraftAnalyzer.TokenSpec,
        tokenOrdinal: Int
    ) {
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(
            tokenOrdinal: tokenOrdinal,
            in: pattern,
            with: spec
        )
        // Không còn token thứ đó (mẫu đã bị sửa từ đường khác) ⇒ không đổi gì, không di con trỏ.
        guard let segment = QuickTranslationRuleDraftAnalyzer.segments(of: updated)
            .first(where: { $0.tokenOrdinal == tokenOrdinal }) else { return }
        setPattern(updated, caret: segment.end)
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

    // MARK: - Sao chép & Dán Clipboard

    func copyPatternToClipboard() {
        guard !pattern.isEmpty else { return }
        UIPasteboard.general.string = pattern
        ToastManager.shared.show(message: "Đã sao chép mẫu vào clipboard", type: .success)
    }

    func pastePatternFromClipboard() {
        guard let pasted = UIPasteboard.general.string,
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastManager.shared.show(message: "Không có nội dung trong clipboard", type: .info)
            return
        }
        let clean = pasted.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        insertIntoPattern(clean)
    }

    func copyReplacementToClipboard() {
        guard !replacement.isEmpty else { return }
        UIPasteboard.general.string = replacement
        ToastManager.shared.show(message: "Đã sao chép bản dịch vào clipboard", type: .success)
    }

    func pasteReplacementFromClipboard() {
        guard let pasted = UIPasteboard.general.string,
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastManager.shared.show(message: "Không có nội dung trong clipboard", type: .info)
            return
        }
        let clean = pasted.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        insertIntoReplacement(clean)
    }

    // MARK: - Các Section ViewBuilder

    @ViewBuilder
    func patternSection(segments: [QuickTranslationRuleDraftAnalyzer.Segment]) -> some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if pattern.isEmpty {
                        Text("第<n:1-6>章")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(Color(uiColor: .placeholderText))
                            .allowsHitTesting(false)
                    }

                    QuickTranslationRulePatternField(
                        text: $pattern,
                        selectionStart: $selectionStart,
                        selectionLength: $selectionLength,
                        autoFocus: restoredFocus == .pattern
                    ) { focused in
                        if focused {
                            focusedField = .pattern
                        } else if focusedField == .pattern {
                            focusedField = nil
                        }
                    }
                }

                HStack(spacing: 4) {
                    if !pattern.isEmpty {
                        Button(action: { setPattern("", caret: 0) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Xoá mẫu")
                    }

                    Button(action: copyPatternToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.borderless)
                    .disabled(pattern.isEmpty)
                    .opacity(pattern.isEmpty ? 0.4 : 1.0)
                    .accessibilityLabel("Sao chép mẫu")

                    Button(action: pastePatternFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dán vào mẫu")
                }
            }

            QuickTranslationRulePatternStripView(
                segments: segments,
                selectionStart: $selectionStart,
                selectionLength: $selectionLength,
                onDeleteBackward: deleteBackwardInPattern
            )

            QuickTranslationRuleTokenPaletteView { insertIntoPattern($0) }

            if let segment = selectedTokenSegment(in: segments),
               let ordinal = segment.tokenOrdinal,
               let spec = QuickTranslationRuleDraftAnalyzer.tokenSpec(of: segment.text) {
                QuickTranslationRuleTokenLengthBar(spec: spec) { updated in
                    applyTokenSpec(updated, tokenOrdinal: ordinal)
                }
            }
        } header: {
            Text("Mẫu (vế trái dấu =)")
        } footer: {
            Text("Nút token chèn **tại con trỏ** của ô nhập, hoặc thay đoạn đang bôi đen. Chạm một chip token (ở dải trên hoặc trong ô nhập) để mở thanh chỉnh độ dài. Token: `<n>` số, `<y>` đọc từng chữ số, `<h>` chữ số Hán, `<d>` chữ số 0-9, `<m>` đơn vị bậc (十 → mươi, 百 → trăm), `<a>` chữ cái A-Z giữ nguyên văn, `<L>` nhãn chương, `<hv>` một chữ Hán-Việt, `<ne>/<pn>/<vp>/<w>` cụm trong từ điển. `<L>`, `<hv>` và `<m>` luôn đúng một ký tự nên không có thanh độ dài. Nhóm `(a|b)` và `(a|b)?` không được đánh số. Mỗi token chịu sự chi phối của Cấu hình token rule; tắt token không sửa file nhưng rule chứa token đó sẽ không chạy.")
        }
    }

    @ViewBuilder
    func replacementSection(analysis: QuickTranslationRuleDraftAnalyzer.Analysis) -> some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if replacement.isEmpty {
                        Text("Chương {0}")
                            .foregroundColor(Color(uiColor: .placeholderText))
                            .allowsHitTesting(false)
                    }

                    QuickTranslationRulePatternField(
                        text: $replacement,
                        selectionStart: $replacementSelectionStart,
                        selectionLength: $replacementSelectionLength,
                        autoFocus: restoredFocus == .replacement,
                        usesMonospacedFont: false
                    ) { focused in
                        if focused {
                            focusedField = .replacement
                        } else if focusedField == .replacement {
                            focusedField = nil
                        }
                    }
                }

                HStack(spacing: 4) {
                    if !replacement.isEmpty {
                        Button(action: {
                            replacement = ""
                            replacementSelectionStart = 0
                            replacementSelectionLength = 0
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Xoá bản dịch")
                    }

                    Button(action: copyReplacementToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.borderless)
                    .disabled(replacement.isEmpty)
                    .opacity(replacement.isEmpty ? 0.4 : 1.0)
                    .accessibilityLabel("Sao chép bản dịch")

                    Button(action: pasteReplacementFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dán vào bản dịch")
                }
            }

            QuickTranslationRuleCaptureChipsView(analysis: analysis) { index in
                insertIntoReplacement("{\(index)}")
            }
        } header: {
            Text("Bản dịch (vế phải dấu =)")
        } footer: {
            Text("`{0}`, `{1}`… đánh số **token** theo thứ tự xuất hiện, không đánh số nhóm hay literal. Chip chèn **tại con trỏ** của ô nhập, hoặc thay đoạn đang bôi đen. Mọi token phải được dùng, và mẫu phải có ít nhất một ký tự thường làm neo.")
        }
    }

    @ViewBuilder
    var editInfoSection: some View {
        if case .edit(_, _, let sourceLine, let scope) = mode {
            Section {
                LabeledContent("Phạm vi", value: scope.longLabel)
                LabeledContent("Dòng trong file", value: "\(sourceLine)")
                Text("Đổi mẫu sẽ **thêm rule mới** và giữ nguyên rule cũ — giống sửa key ở từ điển. Muốn bỏ rule cũ thì xoá nó ở danh sách.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
