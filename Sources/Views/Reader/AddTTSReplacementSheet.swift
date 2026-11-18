import SwiftUI

/// Sheet **"Thêm thay thế TTS"** mở từ menu bôi đen trong Reader.
///
/// Luật (user chốt 2026-09-30):
/// - `pattern` = text đang bôi đen; ô **Chuỗi thay thế LUÔN rỗng khi mở** — cố ý **không** điền sẵn từ rule
///   đã có (bản cũ điền sẵn ở `init`, và `onChange(of: pattern)` cũng điền lại; **cả hai đã bỏ**).
/// - Dưới ô nhập là **chip gợi ý** (`TTSReplacementSuggestionSection`, dùng chung với sheet sửa quy tắc và sheet sửa
///   từ điển phiên âm): mỗi rule đang có cho `pattern` đó (không phân biệt hoa thường, 1.3.978), lấy từ **cả 2 tầng**, badge **R** (riêng truyện)
///   / **C** (chung), tầng riêng xếp trước. Bấm chip ⇒ nhập `replacement` của rule đó **và** đặt công tắc bật/tắt
///   theo `isEnabled` của rule đó.
/// - Rule đang **tắt** ⇒ chip **mờ**, nhìn ra trạng thái mà không phải bấm thử.
/// - Sau chip rule là chip **phiên âm JP / EN** của `pattern` (1.3.974, chỉ hiện khi từ có phiên âm): bấm ⇒ điền
///   chuỗi thay thế **và bật** công tắc kích hoạt.
/// - Bấm **Lưu** ⇒ chọn **Lưu riêng** hoặc **Lưu chung** (đúng 2 lựa chọn, không có "lưu cả hai").
/// - Mục **Kiểm tra** (1.3.920, `TTSReplacementRuleValidator`): mẫu phải là đúng một token (một từ hoặc một dãy ký
///   hiệu), sai thì Lưu bị tắt. Không xét trùng mẫu ở đây — chip R/C đã cho thấy luật trùng của cả hai tầng.
struct AddTTSReplacementSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var isEnabled = true
    /// Chip phiên âm JP / EN của `pattern` — nạp ngoài main thread bởi `phoneticSuggestions(for:mode:into:)`.
    @State private var phoneticSuggestions: [TTSPhoneticSuggestion] = []

    private let bookId: String?
    private let bookRules: [TTSReplacementRule]
    private let globalRules: [TTSReplacementRule]
    private let onSave: (String, String, Bool, TTSReplacementScope) -> Void

    init(
        initialPattern: String,
        existingRules: [TTSReplacementRule],
        bookRules: [TTSReplacementRule],
        bookId: String?,
        onSave: @escaping (String, String, Bool, TTSReplacementScope) -> Void
    ) {
        self.bookId = bookId
        self.bookRules = bookRules
        self.globalRules = existingRules
        self.onSave = onSave
        // Vùng bôi đen hay dính dấu cách ở mép; mẫu có dấu cách là luật sai nên cắt sẵn.
        _pattern = State(initialValue: initialPattern.trimmingCharacters(in: .whitespacesAndNewlines))
        _replacement = State(initialValue: "")
        _isEnabled = State(initialValue: true)
    }

    /// Chip rule cho **đúng** `pattern` đang có trong ô nhập: rule riêng trước, rồi rule chung. Tính lại theo
    /// `pattern` nên sửa ô chuỗi gốc là danh sách chip đổi theo.
    private var ruleChips: [TTSReplacementSuggestionSection.RuleChip] {
        TTSReplacementSuggestionSection.ruleChips(
            pattern: pattern,
            bookId: bookId,
            bookRules: bookRules,
            globalRules: globalRules
        )
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section("Chuỗi thay thế TTS") {
                    TextField("Chuỗi gốc (pattern)", text: $pattern)
                        .textInputAutocapitalization(.never)

                    TextField("Chuỗi thay thế (replacement)", text: $replacement)
                        .textInputAutocapitalization(.never)

                    Toggle("Kích hoạt thay thế", isOn: $isEnabled)
                }

                TTSReplacementSuggestionSection(
                    mode: .replacementRule,
                    rules: ruleChips,
                    phonetic: phoneticSuggestions
                ) { text, enabled in
                    replacement = text
                    isEnabled = enabled
                }

                if !pattern.trimmed.isEmpty {
                    Section {
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Kiểm tra") {
                    TTSReplacementRuleIssuesView(pattern: pattern, issues: issues)
                }
            }.glassSheetRows() }
            .phoneticSuggestions(for: pattern, mode: .replacementRule, into: $phoneticSuggestions)
            .pageTitle("Thêm thay thế TTS")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Lưu") {
                        Button("Lưu riêng — truyện này") { save(.book(bookId ?? "")) }
                            .disabled(!hasBookLayer)
                        Button("Lưu chung — mọi truyện") { save(.global) }
                    }
                    .headerTextButton()
                    .disabled(issues.contains { $0.severity == .error })
                }
            }
        }
        // Mở nửa màn, vuốt lên được toàn màn (1.3.610) — `Form` tự cuộn khi bàn phím hiện.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Lỗi / cảnh báo của mẫu đang gõ — chính mẫu sẽ lưu (không cắt dấu cách: dấu cách ở mép là lỗi phải thấy).
    private var issues: [TTSReplacementRuleValidator.Issue] {
        TTSReplacementRuleValidator.issues(pattern: pattern, replacement: replacement)
    }

    private var hasBookLayer: Bool {
        !(bookId ?? "").isEmpty
    }

    private var summaryText: String {
        let effect = replacement.trimmed.isEmpty
            ? "sẽ bị bỏ trống khi đọc"
            : "sẽ được đọc thành '\(replacement.trimmed)'"
        return "Pattern '\(pattern.trimmed)' \(effect)\(isEnabled ? "" : " (Đang tắt)")"
    }

    private func save(_ scope: TTSReplacementScope) {
        let trimmed = pattern.trimmed
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, replacement, isEnabled, scope)
        dismiss()
    }
}
