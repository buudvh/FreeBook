import SwiftUI

/// Sheet **"Thêm thay thế TTS"** mở từ menu bôi đen trong Reader.
///
/// Luật (user chốt 2026-09-30):
/// - `pattern` = text đang bôi đen; ô **Chuỗi thay thế LUÔN rỗng khi mở** — cố ý **không** điền sẵn từ rule
///   đã có (bản cũ điền sẵn ở `init`, và `onChange(of: pattern)` cũng điền lại; **cả hai đã bỏ**).
/// - Dưới ô nhập là **chip gợi ý**: mỗi rule đang có cho **đúng** `pattern` đó, lấy từ **cả 2 tầng**, badge
///   **R** (riêng truyện) / **C** (chung), tầng riêng xếp trước. Bấm chip ⇒ nhập `replacement` của rule đó
///   **và** đặt công tắc bật/tắt theo `isEnabled` của rule đó.
/// - Rule đang **tắt** ⇒ chip **mờ**, nhìn ra trạng thái mà không phải bấm thử.
/// - Bấm **Lưu** ⇒ chọn **Lưu riêng** hoặc **Lưu chung** (đúng 2 lựa chọn, không có "lưu cả hai").
struct AddTTSReplacementSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var isEnabled = true
    /// Chip đang bấm — chỉ để vẽ viền đậm, không ảnh hưởng dữ liệu lưu.
    @State private var selectedChipID: UUID?

    /// Một chip gợi ý. Là `struct` (không phải tuple) vì `ForEach` cần `id:` là key path, mà key path trên
    /// tuple không tồn tại trong Swift.
    private struct Chip: Identifiable {
        let id: UUID
        let layer: TTSReplacementScope
        let rule: TTSReplacementRule
    }

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
        _pattern = State(initialValue: initialPattern)
        _replacement = State(initialValue: "")
        _isEnabled = State(initialValue: true)
    }

    /// Chip cho **đúng** `pattern` đang có trong ô nhập: rule riêng trước, rồi rule chung. Tính lại theo
    /// `pattern` nên sửa ô chuỗi gốc là danh sách chip đổi theo.
    private var chips: [Chip] {
        let trimmed = pattern.trimmed
        var result: [Chip] = []
        if let bookId, !bookId.isEmpty {
            result += bookRules
                .filter { $0.pattern == trimmed }
                .map { Chip(id: $0.id, layer: .book(bookId), rule: $0) }
        }
        result += globalRules
            .filter { $0.pattern == trimmed }
            .map { Chip(id: $0.id, layer: .global, rule: $0) }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chuỗi thay thế TTS") {
                    TextField("Chuỗi gốc (pattern)", text: $pattern)
                        .textInputAutocapitalization(.never)

                    TextField("Chuỗi thay thế (replacement)", text: $replacement)
                        .textInputAutocapitalization(.never)

                    Toggle("Kích hoạt thay thế", isOn: $isEnabled)
                }

                if !chips.isEmpty {
                    Section {
                        FlowLayout(spacing: 8) {
                            ForEach(chips) { chip in
                                chipButton(chip)
                            }
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text("Gợi ý từ rule đã có")
                    } footer: {
                        Text("R = rule riêng của truyện · C = rule chung · chip **mờ** = rule đang tắt. Bấm chip để nhập lại chuỗi thay thế và đặt công tắc theo rule đó.")
                    }
                }

                if !pattern.trimmed.isEmpty {
                    Section {
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Thêm thay thế TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Lưu") {
                        Button("Lưu riêng — truyện này") { save(.book(bookId ?? "")) }
                            .disabled(!hasBookLayer)
                        Button("Lưu chung — mọi truyện") { save(.global) }
                    }
                    .disabled(pattern.trimmed.isEmpty)
                }
            }
        }
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

    @ViewBuilder
    private func chipButton(_ chip: Chip) -> some View {
        Button {
            selectedChipID = chip.id
            replacement = chip.rule.replacement
            isEnabled = chip.rule.isEnabled
        } label: {
            HStack(spacing: 6) {
                Text(badgeLabel(chip.layer))
                    .font(.caption2.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .background(badgeColor(chip.layer).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(badgeColor(chip.layer))
                // `(rỗng)` là quy ước **có sẵn** của app cho chuỗi thay thế rỗng — xem `ruleRow` ở
                // `TTSReplacementManagerView`. Không phải nhãn mới do lượt này nghĩ ra.
                Text(chip.rule.replacement.isEmpty ? "(rỗng)" : chip.rule.replacement)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                Capsule().stroke(
                    selectedChipID == chip.id ? Color.accentColor : Color.secondary.opacity(0.35),
                    lineWidth: selectedChipID == chip.id ? 1.5 : 0.5
                )
            )
            // Rule đang tắt ⇒ chip mờ.
            .opacity(chip.rule.isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    private func badgeLabel(_ layer: TTSReplacementScope) -> String {
        switch layer {
        case .book: return "R"
        case .global: return "C"
        }
    }

    private func badgeColor(_ layer: TTSReplacementScope) -> Color {
        switch layer {
        case .book: return .teal
        case .global: return .blue
        }
    }

    private func save(_ scope: TTSReplacementScope) {
        let trimmed = pattern.trimmed
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, replacement, isEnabled, scope)
        dismiss()
    }
}
