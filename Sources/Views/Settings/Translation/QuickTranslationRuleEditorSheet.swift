import SwiftUI

/// Sheet thêm / sửa **một** rule dịch, cho **cả hai** phạm vi (bộ chung và bộ riêng của truyện).
///
/// Sheet **không** tự đóng khi lưu thất bại: `importRules` validate toàn bộ file, nên một mẫu viết
/// sai (lệch ngoặc, `{2}` vượt số token, không có literal làm neo…) sẽ bị từ chối kèm lý do — đóng
/// sheet lúc đó là bắt người dùng gõ lại từ đầu. Đóng chỉ khi ghi file thành công.
///
/// Segment **Riêng / Chung** chỉ hiện ở chế độ **thêm** và chỉ khi biết truyện đang mở. Ở chế độ sửa,
/// phạm vi cố định theo rule đang sửa: đổi phạm vi lúc sửa là *copy sang bộ khác*, không phải sửa —
/// việc đó đã có nút Chuyển ở danh sách.
struct QuickTranslationRuleEditorSheet: View {
    /// `Identifiable` để màn danh sách mở sheet bằng `.sheet(item:)` — mở theo *dữ liệu* thì không có
    /// khoảng thời gian sheet đã hiện mà state còn rỗng như cách `isPresented` + biến phụ.
    enum Mode: Identifiable {
        /// `prefilledPattern` khác rỗng khi mở từ màn Check rule: mẫu điền sẵn bằng cụm đang chọn.
        /// Không dùng giá trị mặc định cho tham số vì Swift không cho phép default argument trong
        /// khai báo case của enum — mọi call site truyền tường minh.
        case add(prefilledPattern: String)
        /// Sửa rule đang có. `pattern` là **key** dùng để định vị dòng trong file.
        case edit(pattern: String, replacement: String, sourceLine: Int, scope: QuickTranslationRuleScope)

        var id: String {
            switch self {
            case .add(let prefilled): return "add:\(prefilled)"
            case .edit(let pattern, _, let sourceLine, let scope): return "edit:\(scope.label)#\(sourceLine):\(pattern)"
            }
        }
    }

    let mode: Mode
    /// Phạm vi mặc định khi mở sheet (chỉ dùng ở chế độ thêm). Ở chế độ sửa, phạm vi lấy từ `mode`.
    let defaultScope: QuickTranslationRuleScope
    /// `nil` = không biết truyện nào đang mở ⇒ ẩn segment, chỉ lưu được vào bộ chung.
    let contextBookId: String?
    /// Trả về kết quả để sheet biết đóng hay giữ; phía gọi chịu trách nhiệm phát toast.
    let onSubmit: (
        _ pattern: String,
        _ replacement: String,
        _ scope: QuickTranslationRuleScope
    ) -> QuickTranslationRuleStore.LoadOutcome

    @Environment(\.dismiss) private var dismiss

    @State private var pattern: String
    @State private var replacement: String
    @State private var saveToBook: Bool
    @State private var errorText: String? = nil

    init(
        mode: Mode,
        defaultScope: QuickTranslationRuleScope = .global,
        contextBookId: String? = nil,
        onSubmit: @escaping (
            _ pattern: String,
            _ replacement: String,
            _ scope: QuickTranslationRuleScope
        ) -> QuickTranslationRuleStore.LoadOutcome
    ) {
        self.mode = mode
        self.defaultScope = defaultScope
        self.contextBookId = contextBookId
        self.onSubmit = onSubmit
        switch mode {
        case .add(let prefilled):
            _pattern = State(initialValue: prefilled)
            _replacement = State(initialValue: "")
        case .edit(let pattern, let replacement, _, _):
            _pattern = State(initialValue: pattern)
            _replacement = State(initialValue: replacement)
        }
        _saveToBook = State(initialValue: !defaultScope.isGlobal)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Phạm vi sẽ ghi. Chế độ sửa luôn dùng scope từ `mode`; chế độ thêm theo segment.
    private var effectiveScope: QuickTranslationRuleScope {
        if isEditing {
            if case .edit(_, _, _, let scope) = mode { return scope }
            return defaultScope
        }
        guard saveToBook, let contextBookId, !contextBookId.isEmpty else { return .global }
        return .book(contextBookId)
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

                if !isEditing, let contextBookId, !contextBookId.isEmpty {
                    Section {
                        Picker("Lưu vào", selection: $saveToBook) {
                            Text("Bộ riêng truyện").tag(true)
                            Text("Bộ chung").tag(false)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text("Bộ riêng chỉ áp cho truyện đang đọc và **thắng** bộ chung khi trùng mọi tiêu chí ưu tiên khác.")
                    }
                }

                if case .edit(_, _, let sourceLine, let scope) = mode {
                    Section {
                        LabeledContent("Phạm vi", value: scope.longLabel)
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

        switch onSubmit(key, replacement, effectiveScope) {
        case .success:
            errorText = nil
            dismiss()
        case .rejected(let issues):
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
