import SwiftUI

struct AddTTSReplacementSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var isEnabled = true

    let existingRules: [TTSReplacementRule]
    let onAdd: (String, String, Bool) -> Void

    init(
        initialPattern: String,
        existingRules: [TTSReplacementRule],
        onAdd: @escaping (String, String, Bool) -> Void
    ) {
        self.existingRules = existingRules
        self.onAdd = onAdd
        _pattern = State(initialValue: initialPattern)

        let trimmed = initialPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingRule = existingRules.first(where: { $0.pattern == trimmed }) {
            _replacement = State(initialValue: existingRule.replacement)
            _isEnabled = State(initialValue: existingRule.isEnabled)
        } else {
            _replacement = State(initialValue: "")
            _isEnabled = State(initialValue: true)
        }
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

                if !pattern.trimmed.isEmpty {
                    Section {
                        Text("Pattern '\(pattern.trimmed)' \(replacement.trimmed.isEmpty ? "sẽ bị bỏ trống khi đọc" : "sẽ được đọc thành '\(replacement.trimmed)'")\(isEnabled ? "" : " (Đang tắt)")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Thêm thay thế TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onAdd(pattern.trimmed, replacement, isEnabled)
                        dismiss()
                    }
                    .disabled(pattern.trimmed.isEmpty)
                }
            }
            .onChange(of: pattern) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let existing = existingRules.first(where: { $0.pattern == trimmed }) {
                    isEnabled = existing.isEnabled
                    if replacement.isEmpty {
                        replacement = existing.replacement
                    }
                }
            }
        }
    }
}