import SwiftUI

/// Section **chip gợi ý** cho ô "chuỗi thay thế" / "cách đọc" — dùng chung cho bốn sheet (1.3.974, anh Bửu: "thêm
/// phiên âm anh và nhật (nếu có) vào chip gợi ý của thêm thay thế tts … thêm chip thay thế vào sửa từ trong từ điển
/// phiên âm của vieneu, nghitts, và danh sách từ thay thế tts"):
///
/// - `AddTTSReplacementSheet` (Reader › Thêm thay thế TTS) và sheet thêm / sửa quy tắc của `TTSReplacementManagerView`:
///   chip **luật đã có** cho đúng mẫu đang nhập (badge R / C, luật tắt ⇒ mờ) rồi tới chip phiên âm **JP / EN**;
/// - `EditWordSheet` (sửa một mục từ điển phiên âm NghiTTS / VieNeu): chip **NGI / VIE** (cách đọc đang lưu ở hai từ
///   điển) + JP / EN.
///
/// Bấm chip ⇒ `onSelect(chuỗi, bật)`: chuỗi **thay** nội dung ô (như mọi chip của app, không nối thêm); `bật` là
/// trạng thái công tắc kích hoạt — chip luật theo `isEnabled` của luật đó (luật chốt 2026-09-30), chip phiên âm luôn
/// `true`. Sheet từ điển không có công tắc thì bỏ qua tham số thứ hai.
///
/// Không có chip nào ⇒ không vẽ gì (kể cả tiêu đề). Chip phiên âm do `phoneticSuggestions(for:mode:into:)` nạp ngoài
/// main thread; view này chỉ vẽ.
struct TTSReplacementSuggestionSection: View {
    /// Một luật đã có cho đúng mẫu đang nhập, kèm tầng của nó.
    struct RuleChip: Identifiable {
        let scope: SuggestionChip.Scope
        let rule: TTSReplacementRule

        /// Kèm tầng: một luật chuyển / lấy sang tầng kia giữ nguyên `id`, hai chip không được trùng khoá.
        var id: String { (scope == .book ? "R|" : "C|") + rule.id.uuidString }
    }

    let mode: TTSPhoneticSuggestionLoadModifier.Mode
    let rules: [RuleChip]
    let phonetic: [TTSPhoneticSuggestion]
    let onSelect: (String, Bool) -> Void

    /// Chip vừa bấm — chỉ để vẽ viền đậm, không ảnh hưởng dữ liệu lưu.
    @State private var selectedID: String?

    init(
        mode: TTSPhoneticSuggestionLoadModifier.Mode,
        rules: [RuleChip] = [],
        phonetic: [TTSPhoneticSuggestion],
        onSelect: @escaping (String, Bool) -> Void
    ) {
        self.mode = mode
        self.rules = rules
        self.phonetic = phonetic
        self.onSelect = onSelect
    }

    /// Luật của **cả hai tầng** có mẫu trùng `pattern` — không phân biệt hoa thường, như lúc đọc (`matchKey`, 1.3.978):
    /// tầng riêng trước, rồi tầng chung. Sheet sửa luật tự bỏ
    /// luật đang sửa khỏi danh sách trước khi truyền vào (chip của chính nó chỉ lặp lại giá trị đang nằm trong ô).
    static func ruleChips(
        pattern: String,
        bookId: String?,
        bookRules: [TTSReplacementRule],
        globalRules: [TTSReplacementRule]
    ) -> [RuleChip] {
        let trimmed = pattern.trimmed
        guard !trimmed.isEmpty else { return [] }
        let key = TTSReplacementRule.matchKey(for: trimmed)
        var result: [RuleChip] = []
        if let bookId, !bookId.isEmpty {
            result += bookRules
                .filter { $0.matchKey == key }
                .map { RuleChip(scope: .book, rule: $0) }
        }
        result += globalRules
            .filter { $0.matchKey == key }
            .map { RuleChip(scope: .global, rule: $0) }
        return result
    }

    var body: some View {
        if !rules.isEmpty || !phonetic.isEmpty {
            Section {
                FlowLayout(spacing: 8) {
                    ForEach(rules) { chip in
                        ruleButton(chip)
                    }
                    ForEach(phonetic) { suggestion in
                        phoneticButton(suggestion)
                    }
                }
                // Chừa chỗ cho badge nhô ra góc trên phải chip.
                .padding(.top, 2 + ChipCornerBadge.inset)
                .padding(.bottom, 2)
                .padding(.trailing, ChipCornerBadge.inset)
            } header: {
                SectionHelpHeader("Gợi ý", paragraphs: helpParagraphs)
            }
        }
    }

    private var helpParagraphs: [LocalizedStringKey] {
        switch mode {
        case .replacementRule:
            return [
                "**R** = rule riêng của truyện · **C** = rule chung · chip **mờ** = rule đang tắt. Bấm chip để nhập lại chuỗi thay thế và đặt công tắc theo rule đó.",
                "**JP** = phiên âm theo âm tiết tiếng Nhật · **EN** = phiên âm tiếng Anh; chỉ hiện khi từ có phiên âm. Bấm chip để điền chuỗi thay thế và **bật** công tắc kích hoạt."
            ]
        case .phoneticDictionary:
            return [
                "**NGI** / **VIE** = cách đọc đang lưu ở từ điển phiên âm NghiTTS / VieNeu-TTS · **JP** = phiên âm theo âm tiết tiếng Nhật · **EN** = phiên âm tiếng Anh. Bấm chip để điền cách đọc."
            ]
        }
    }

    // MARK: - Chip

    private func ruleButton(_ chip: RuleChip) -> some View {
        Button {
            selectedID = chip.id
            onSelect(chip.rule.replacement, chip.rule.isEnabled)
        } label: {
            // `(rỗng)` là quy ước có sẵn của app cho chuỗi thay thế rỗng — xem `ruleRow` ở `TTSReplacementManagerView`.
            chipLabel(chip.rule.replacement.isEmpty ? "(rỗng)" : chip.rule.replacement, id: chip.id, isProminent: true)
                // Badge R/C ở góc trên phải, cùng màu chip nghĩa của panel Dịch (1.3.619).
                .overlay(alignment: .topTrailing) {
                    ChipCornerBadge(scope: chip.scope)
                }
                // Rule đang tắt ⇒ chip mờ.
                .opacity(chip.rule.isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(chip))
    }

    private func phoneticButton(_ suggestion: TTSPhoneticSuggestion) -> some View {
        Button {
            selectedID = suggestion.id
            onSelect(suggestion.text, true)
        } label: {
            // Chữ rõ = cách đọc bộ phiên âm sẽ chọn cho từ này; chữ nhạt = cách đọc còn lại.
            chipLabel(suggestion.text, id: suggestion.id, isProminent: suggestion.isPipelineChoice)
                .overlay(alignment: .topTrailing) {
                    ChipCornerBadge(text: suggestion.origin.badge, foreground: .black, background: suggestion.origin.tint)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(suggestion.text). \(suggestion.origin.explanation)")
    }

    private func chipLabel(_ text: String, id: String, isProminent: Bool) -> some View {
        let isSelected = selectedID == id
        return Text(text)
            .font(.footnote)
            .foregroundStyle(isProminent ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.35),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
    }

    private static func accessibilityLabel(_ chip: RuleChip) -> String {
        let text = chip.rule.replacement.isEmpty ? "rỗng" : chip.rule.replacement
        let layer = chip.scope == .book ? "rule riêng của truyện" : "rule chung"
        return chip.rule.isEnabled ? "\(text), \(layer)" : "\(text), \(layer), đang tắt"
    }
}
