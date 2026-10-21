import Foundation

/// Dựng chip cho **hàng gợi ý trên bàn phím** (`KeyboardSuggestionRowView`) của hai ô ở màn thêm/sửa rule — để chèn token
/// ngay lúc gõ mà không phải cuộn xuống bảng token / dải `{i}` đang bị bàn phím che.
///
/// - Ô **Mẫu**: đủ token (`<n>`, `<y>`… theo đúng thứ tự nhóm của `QuickTranslationRuleTokenPaletteView`) rồi tới cú pháp
///   nhóm `( | ) )?`; token đang tắt ở Cấu hình token rule hiện mờ, giống bảng token.
/// - Ô **Bản dịch**: `{0} {1}…` theo token của mẫu; đã dùng có ✓, chưa dùng hiện đỏ (`UNUSED_CAPTURE` là lỗi hard). Mẫu
///   chưa có token ⇒ `nil` ⇒ không có hàng.
///
/// **Lọc theo phần gõ dở** (mockup đã duyệt 2026-10-21): sát trước con trỏ là `<` + chữ cái (vd `<h`) thì chỉ còn token
/// bắt đầu bằng đoạn đó (không phân biệt hoa thường), và chip thay luôn đoạn gõ dở; với ô Bản dịch là `{` + chữ số. Không
/// khớp token nào thì hiện đủ. Đoạn gõ dở chỉ gồm ký tự ASCII nên số ký tự = số đơn vị UTF-16 mà
/// `KeyboardTextToolbarModel.applySuggestion` dùng để chọn lùi.
///
/// Chỉ số `selectionStart`/`selectionLength` đếm theo **ký tự** trên `Array(text)`, cùng đơn vị với màn thêm rule.
///
/// `@MainActor`: đọc danh sách/nhãn tĩnh của `QuickTranslationRuleTokenPaletteView` (một `View`, nên bị suy ra thuộc
/// MainActor ở SDK mới); nơi gọi duy nhất là ô nhập UIKit, vốn đã ở MainActor.
@MainActor
enum QuickTranslationRuleKeyboardSuggestions {
    enum Mode: Equatable {
        case pattern
        /// Mang theo **mẫu hiện tại** vì số `{i}` và trạng thái ✓ phụ thuộc vào nó.
        case replacement(pattern: String)
    }

    static func suggestions(
        mode: Mode,
        text: String,
        selectionStart: Int,
        selectionLength: Int
    ) -> [KeyboardSuggestion]? {
        // Đang bôi đen thì chip **thay** vùng đó như bảng token ⇒ không lọc theo phần gõ dở.
        let caret: Int? = selectionLength == 0 ? selectionStart : nil
        switch mode {
        case .pattern:
            let typed = caret.flatMap {
                partial(in: text, caret: $0, opener: "<", allowed: isTokenNameCharacter, tail: [">", ":", "|", "?"])
            }
            return patternSuggestions(typed: typed)
        case .replacement(let pattern):
            let typed = caret.flatMap {
                partial(in: text, caret: $0, opener: "{", allowed: isDigit, tail: ["}"])
            }
            return replacementSuggestions(pattern: pattern, replacement: text, typed: typed)
        }
    }

    private static func isTokenNameCharacter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    // MARK: - Ô Mẫu

    private static func patternSuggestions(typed: String?) -> [KeyboardSuggestion] {
        let kinds = QuickTranslationRuleTokenPaletteView.numeralKinds + QuickTranslationRuleTokenPaletteView.dictionaryKinds

        if let typed {
            let matches = kinds.filter { $0.syntax.lowercased().hasPrefix(typed.lowercased()) }
            if !matches.isEmpty {
                return matches.map { tokenSuggestion($0, replacing: typed) }
            }
        }

        let groups = QuickTranslationRuleTokenPaletteView.groupSyntax.map { syntax in
            KeyboardSuggestion(
                text: syntax,
                replacingPrefix: "",
                style: .normal,
                accessibilityLabel: "Chèn \(syntax) — \(QuickTranslationRuleTokenPaletteView.caption(forGroup: syntax))"
            )
        }
        return kinds.map { tokenSuggestion($0, replacing: "") } + groups
    }

    private static func tokenSuggestion(
        _ kind: QuickTranslationRuleTokenSettings.Kind,
        replacing typed: String
    ) -> KeyboardSuggestion {
        KeyboardSuggestion(
            text: kind.syntax,
            replacingPrefix: typed,
            style: QuickTranslationRuleTokenSettings.isEnabled(kind) ? .normal : .dimmed,
            accessibilityLabel: "Chèn token \(kind.syntax) — \(QuickTranslationRuleTokenPaletteView.caption(for: kind))"
        )
    }

    // MARK: - Ô Bản dịch

    private static func replacementSuggestions(
        pattern: String,
        replacement: String,
        typed: String?
    ) -> [KeyboardSuggestion]? {
        let analysis = QuickTranslationRuleDraftAnalyzer.analyze(pattern: pattern, replacement: replacement)
        guard analysis.captureCount > 0 else { return nil }

        // Token gốc của từng `{i}` — chỉ để đọc cho VoiceOver, chip chỉ hiện `{i}` cho gọn một dòng.
        var tokenTexts: [Int: String] = [:]
        for segment in QuickTranslationRuleDraftAnalyzer.segments(of: pattern) {
            if let ordinal = segment.tokenOrdinal {
                tokenTexts[ordinal] = segment.text
            }
        }

        let all = (0..<analysis.captureCount).map { index -> KeyboardSuggestion in
            let reference = "{\(index)}"
            let isUsed = analysis.referenced.contains(index)
            let source = tokenTexts[index].map { " (token \($0))" } ?? ""
            return KeyboardSuggestion(
                text: reference,
                replacingPrefix: "",
                style: isUsed ? .used : .missing,
                accessibilityLabel: isUsed
                    ? "Chèn thêm \(reference)\(source)"
                    : "\(reference)\(source) chưa được dùng, bấm để chèn"
            )
        }

        if let typed {
            let matches = all.filter { $0.text.hasPrefix(typed) }
            if !matches.isEmpty {
                return matches.map {
                    KeyboardSuggestion(
                        text: $0.text,
                        replacingPrefix: typed,
                        style: $0.style,
                        accessibilityLabel: $0.accessibilityLabel
                    )
                }
            }
        }
        return all
    }

    // MARK: - Phần gõ dở

    /// Đoạn `opener` + các ký tự thoả `allowed` nằm **sát trước** con trỏ (vd `<h`, `{1`, hoặc chỉ `<`). `nil` nếu:
    /// - không có;
    /// - `opener` bị escape bằng số lẻ dấu `\` (`\<` là ký tự `<` thường của mẫu, không phải mở token);
    /// - con trỏ nằm **giữa** một token đã viết xong (ký tự ngay sau con trỏ là chữ của token hoặc thuộc `tail`, vd chạm
    ///   vào giữa `<n|:1-6>`) — thay `<n` lúc đó sẽ để lại `<n>:1-6>`.
    private static func partial(
        in text: String,
        caret: Int,
        opener: Character,
        allowed: (Character) -> Bool,
        tail: Set<Character>
    ) -> String? {
        let chars = Array(text)
        let end = min(max(0, caret), chars.count)
        if end < chars.count, allowed(chars[end]) || tail.contains(chars[end]) {
            return nil
        }
        var start = end
        while start > 0, allowed(chars[start - 1]) {
            start -= 1
        }
        guard start > 0, chars[start - 1] == opener else { return nil }

        var backslashes = 0
        var index = start - 2
        while index >= 0, chars[index] == "\\" {
            backslashes += 1
            index -= 1
        }
        guard backslashes % 2 == 0 else { return nil }
        return String(chars[(start - 1)..<end])
    }
}
