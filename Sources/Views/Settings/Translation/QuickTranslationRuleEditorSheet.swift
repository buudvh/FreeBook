import SwiftUI

/// Sheet thêm / sửa **một** rule dịch.
///
/// Sheet **không** tự đóng khi lưu thất bại: `importRules` validate toàn bộ file, nên một mẫu viết
/// sai (lệch ngoặc, `{2}` vượt số token, không có literal làm neo…) sẽ bị từ chối kèm lý do — đóng
/// sheet lúc đó là bắt người dùng gõ lại từ đầu. Đóng chỉ khi ghi file thành công.
struct QuickTranslationRuleEditorSheet: View {
    /// `Identifiable` để màn danh sách mở sheet bằng `.sheet(item:)` — mở theo *dữ liệu* thì không có
    /// khoảng thời gian sheet đã hiện mà state còn rỗng như cách `isPresented` + biến phụ.
    enum Mode: Identifiable {
        case add
        /// Sửa rule đang có. `pattern` là **key** dùng để định vị dòng trong file.
        case edit(pattern: String, replacement: String, sourceLine: Int)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let pattern, _, let sourceLine): return "edit:\(sourceLine):\(pattern)"
            }
        }
    }

    let mode: Mode
    /// Trả về kết quả để sheet biết đóng hay giữ; phía gọi chịu trách nhiệm phát toast.
    let onSubmit: (_ pattern: String, _ replacement: String) -> QuickTranslationRuleStore.LoadOutcome

    @Environment(\.dismiss) private var dismiss

    @State private var pattern: String
    @State private var replacement: String
    @State private var errorText: String? = nil

    init(
        mode: Mode,
        onSubmit: @escaping (_ pattern: String, _ replacement: String) -> QuickTranslationRuleStore.LoadOutcome
    ) {
        self.mode = mode
        self.onSubmit = onSubmit
        switch mode {
        case .add:
            _pattern = State(initialValue: "")
            _replacement = State(initialValue: "")
        case .edit(let pattern, let replacement, _):
            _pattern = State(initialValue: pattern)
            _replacement = State(initialValue: replacement)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("第<n:1-6>章", text: $pattern, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Mẫu (vế trái dấu =)")
                } footer: {
                    Text("Token: `<n>` số, `<y>` đọc từng chữ số, `<L>` nhãn chương, `<hv>` một chữ Hán-Việt, `<ne>/<pn>/<vp>/<w>` cụm trong từ điển. Giới hạn độ dài viết liền: `<n:1-6>`. Nhóm `(a|b)` và `(a|b)?` không được đánh số. Mỗi token chịu sự chi phối của Cấu hình token rule; tắt token không sửa file nhưng rule chứa token đó sẽ không chạy.")
                }

                Section {
                    TextField("Chương {0}", text: $replacement, axis: .vertical)
                        .autocorrectionDisabled()
                } header: {
                    Text("Bản dịch (vế phải dấu =)")
                } footer: {
                    Text("`{0}`, `{1}`… đánh số **token** theo thứ tự xuất hiện, không đánh số nhóm hay literal. Mọi token phải được dùng, và mẫu phải có ít nhất một ký tự thường làm neo.")
                }

                if case .edit(_, _, let sourceLine) = mode {
                    Section {
                        LabeledContent("Dòng trong file", value: "\(sourceLine)")
                        Text("Đổi mẫu sẽ **thêm rule mới** và giữ nguyên rule cũ — giống sửa key ở từ điển. Muốn bỏ rule cũ thì xoá nó ở danh sách.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let errorText = errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Sửa rule" : "Thêm rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { submit() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func submit() {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        switch onSubmit(key, replacement) {
        case .success:
            errorText = nil
            dismiss()
        case .rejected(let issues):
            // Chỉ nêu dòng lỗi đầu tiên: sửa một rule thì lỗi gần như luôn nằm ở chính rule đó.
            if let first = issues.first {
                errorText = "Dòng \(first.sourceLine) — \(first.code.rawValue): \(first.message)"
            } else {
                errorText = "Rule không hợp lệ"
            }
        case .failure(let message):
            errorText = message
        }
    }
}
