import SwiftUI

struct AddTTSReplacementSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var pattern = ""
    @State private var replacement = ""

    let existingRules: [TTSReplacementRule]
    let onAdd: (String, String) -> Void

    init(
        initialPattern: String,
        existingRules: [TTSReplacementRule],
        onAdd: @escaping (String, String) -> Void
    ) {
        self.existingRules = existingRules
        self.onAdd = onAdd
        _pattern = State(initialValue: initialPattern)

        let trimmed = initialPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingRule = existingRules.first(where: { $0.pattern == trimmed }) {
            _replacement = State(initialValue: existingRule.replacement)
        } else {
            _replacement = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chuỗi thay thế TTS") {
                    TextField("Chuỗi gốc (pattern)", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Chuỗi thay thế (replacement)", text: $replacement)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if !pattern.trimmed.isEmpty {
                    Section {
                        Text("Pattern '\(pattern.trimmed)' \(replacement.trimmed.isEmpty ? "sẽ bị bỏ trống khi đọc" : "sẽ được đọc thành '\(replacement.trimmed)'")")
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
                        onAdd(pattern.trimmed, replacement)
                        dismiss()
                    }
                    .disabled(pattern.trimmed.isEmpty)
                }
            }
        }
    }
}