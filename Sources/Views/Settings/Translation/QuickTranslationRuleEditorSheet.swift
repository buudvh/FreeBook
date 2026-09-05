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
///
/// **Chữ đang gõ không còn chỉ sống trong `@State` của sheet**: nó được mirror sang
/// `QuickTranslationRuleDraftStore` và `init` khôi phục lại từ đó. Lý do đầy đủ ở doc của store — tóm
/// lại là Reader tự chuyển chương lúc đang nghe làm SwiftUI dựng lại content của sheet (sheet vẫn mở),
/// `init` chạy lại và mọi ô về giá trị seed.
///
/// Bốn công cụ nhập nhanh của vế trái đều tác động lên **cùng** một vùng chọn
/// (`selectionStart`/`selectionLength`, tính theo chỉ số ký tự của `Array(pattern)`): ô nhập
/// `QuickTranslationRulePatternField` cấp con trỏ **thật**, dải chip cho chọn token và đặt con trỏ giữa
/// hai chip, bảng token chèn hoặc thay token tại con trỏ, thanh min–max sửa token đang chọn.
///
/// Từ 1.3.336 vế phải có **đúng cơ chế đó**: ô Bản dịch cũng là `QuickTranslationRulePatternField`
/// (khác font) với cặp `replacementSelectionStart`/`replacementSelectionLength` riêng, nên chip `{i}`
/// chèn tại con trỏ thay vì nối vào cuối chuỗi.
struct QuickTranslationRuleEditorSheet: View {
    /// `Identifiable` để màn danh sách mở sheet bằng `.sheet(item:)` — mở theo *dữ liệu* thì không có
    /// khoảng thời gian sheet đã hiện mà state còn rỗng như cách `isPresented` + biến phụ.
    enum Mode: Identifiable {
        /// `prefilledPattern` khác rỗng khi mở từ panel Dịch: mẫu điền sẵn bằng cụm đang chọn.
        ///
        /// `prefilledReplacement` là **nghĩa đang có trong ô nhập nghĩa của panel Dịch** (`customMeaning`),
        /// kể cả nghĩa người dùng vừa sửa tay — mở nút `+` từ đó thì hai ô đã có sẵn cặp mẫu/nghĩa,
        /// không phải gõ lại. Rỗng khi mở từ màn danh sách rule.
        ///
        /// Không dùng giá trị mặc định cho tham số vì Swift không cho phép default argument trong
        /// khai báo case của enum — mọi call site truyền tường minh.
        case add(prefilledPattern: String, prefilledReplacement: String)
        /// Sửa rule đang có. `pattern` là **key** dùng để định vị dòng trong file.
        case edit(pattern: String, replacement: String, sourceLine: Int, scope: QuickTranslationRuleScope)

        /// Bản nháp lưu theo `id` này, nên `id` phải mang **cả** hai giá trị điền sẵn: đổi nghĩa ở panel
        /// Dịch rồi bấm `+` là một điểm khởi đầu khác, không được khôi phục nháp của lần trước.
        var id: String {
            switch self {
            case .add(let prefilled, let replacement): return "add:\(prefilled)|\(replacement)"
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

    /// `internal` (không `private`): `QuickTranslationRuleEditorSheet+Editing` nằm ở file khác, mà
    /// `private` trong Swift là phạm vi **file** nên extension ngoài file sẽ không thấy được.
    @State var pattern: String
    @State var replacement: String
    @State private var saveToBook: Bool
    /// Con trỏ / vùng chọn trong mẫu, đếm theo **ký tự** trên `Array(pattern)`. Nguồn cấp là ô nhập
    /// (`QuickTranslationRulePatternField` báo lên con trỏ thật); dải chip ghi vào đây thì ô nhập nhận
    /// lại — hai chiều cùng một biến, không có bản sao thứ hai.
    @State var selectionStart: Int
    @State var selectionLength: Int
    /// Con trỏ / vùng chọn trong ô **Bản dịch**, cùng đơn vị và cùng lý do `internal` như trên. Có từ
    /// 1.3.336: trước đó chip `{i}` nối thẳng vào **cuối** `replacement` vì ô này là `TextField` và
    /// SwiftUI iOS 17 không cấp vùng chọn của nó.
    @State var replacementSelectionStart: Int
    @State var replacementSelectionLength: Int
    /// Lỗi do store trả về lúc lưu (khác với lỗi cú pháp mà bản nháp tự chấm được).
    @State private var errorText: String? = nil
    /// Bật khi bấm Lưu ở chế độ **thêm** và có truyện đang mở: phạm vi được chọn ngay lúc lưu thay vì
    /// bằng một ô chọn nằm sẵn trong form.
    @State private var showingScopeDialog = false
    /// Ô đang gõ, chỉ để ghi vào bản nháp. Cả hai ô nhập đều là `UIViewRepresentable` nên không dùng
    /// được `@FocusState`; mỗi ô tự báo lên qua `onFocusChange`.
    @State private var focusedField: QuickTranslationRuleDraftStore.Field?

    /// Ô đang gõ lúc bản nháp được lưu. Khôi phục ở `onAppear` để một lượt dựng lại không làm tụt
    /// bàn phím giữa lúc gõ.
    private let restoredFocus: QuickTranslationRuleDraftStore.Field?
    /// Đúng khi `init` này chạy trên một identity mới mà store đã có bản nháp — tức SwiftUI vừa dựng
    /// lại content của sheet. Log ở `onAppear` (không log trong `init`: `init` chạy lại theo **mỗi**
    /// lượt body của view chủ, còn `onAppear` chỉ nổ một lần cho mỗi identity).
    private let didRestoreDraft: Bool

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

        let seedPattern: String
        let seedReplacement: String
        switch mode {
        case .add(let prefilled, let prefilledReplacement):
            seedPattern = prefilled
            seedReplacement = prefilledReplacement
        case .edit(let pattern, let replacement, _, _):
            seedPattern = pattern
            seedReplacement = replacement
        }

        let restored = QuickTranslationRuleDraftStore.shared.draft(for: mode.id)
        _pattern = State(initialValue: restored?.pattern ?? seedPattern)
        _replacement = State(initialValue: restored?.replacement ?? seedReplacement)
        _saveToBook = State(initialValue: restored?.saveToBook ?? !defaultScope.isGlobal)
        _selectionStart = State(initialValue: restored?.selectionStart ?? Array(seedPattern).count)
        _selectionLength = State(initialValue: restored?.selectionLength ?? 0)
        _replacementSelectionStart = State(
            initialValue: restored?.replacementSelectionStart ?? Array(seedReplacement).count
        )
        _replacementSelectionLength = State(initialValue: restored?.replacementSelectionLength ?? 0)
        restoredFocus = restored?.focus
        didRestoreDraft = restored != nil
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Phạm vi sẽ ghi khi **không** hỏi: chế độ sửa dùng scope từ `mode`, chế độ thêm mà không có
    /// truyện nào đang mở thì chỉ còn bộ chung. Chế độ thêm có truyện mở đi qua popup, không qua đây.
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

    private var currentDraft: QuickTranslationRuleDraftStore.Draft {
        QuickTranslationRuleDraftStore.Draft(
            pattern: pattern,
            replacement: replacement,
            saveToBook: saveToBook,
            selectionStart: selectionStart,
            selectionLength: selectionLength,
            replacementSelectionStart: replacementSelectionStart,
            replacementSelectionLength: replacementSelectionLength,
            focus: focusedField
        )
    }

    var body: some View {
        let segments = QuickTranslationRuleDraftAnalyzer.segments(of: pattern)
        let analysis = QuickTranslationRuleDraftAnalyzer.analyze(pattern: pattern, replacement: replacement)

        return NavigationStack {
            Form {
                patternSection(segments: segments)
                replacementSection(analysis: analysis)
                editInfoSection

                if !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        QuickTranslationRuleDraftIssuesView(analysis: analysis, storeError: errorText)
                    } header: {
                        Text("Kiểm tra")
                    }
                }
            }
            .navigationTitle(isEditing ? "Sửa rule" : "Thêm rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        QuickTranslationRuleDraftStore.shared.clear(id: mode.id)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { submit() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Lưu rule vào bộ nào?",
                isPresented: $showingScopeDialog,
                titleVisibility: .visible
            ) {
                if let contextBookId, !contextBookId.isEmpty {
                    Button("Bộ riêng truyện") {
                        saveToBook = true
                        performSubmit(scope: .book(contextBookId))
                    }
                }
                Button("Bộ chung") {
                    saveToBook = false
                    performSubmit(scope: .global)
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Bộ riêng chỉ áp cho truyện đang đọc và thắng bộ chung khi trùng mọi tiêu chí ưu tiên khác.")
            }
            .onAppear {
                if didRestoreDraft {
                    // Không log nội dung mẫu: đây là dữ liệu của người dùng, chỉ cần biết *đã* có một
                    // lượt dựng lại để lần sau chẩn đoán được nguyên nhân gốc.
                    AppLogger.shared.log("📝 [RuleEditor] Sheet dựng lại giữa lúc gõ — đã khôi phục bản nháp (\(isEditing ? "sửa" : "thêm"))")
                }
            }
            .onChange(of: currentDraft) { _, newValue in
                QuickTranslationRuleDraftStore.shared.store(newValue, for: mode.id)
            }
            .onChange(of: pattern) { _, newValue in
                reconcileSelection(after: newValue)
            }
            .onChange(of: replacement) { _, newValue in
                reconcileReplacementSelection(after: newValue)
            }
        }
    }

    // MARK: - Các section

    @ViewBuilder
    private func patternSection(segments: [QuickTranslationRuleDraftAnalyzer.Segment]) -> some View {
        Section {
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

            QuickTranslationRulePatternStripView(
                segments: segments,
                selectionStart: $selectionStart,
                selectionLength: $selectionLength,
                onDeleteBackward: deleteBackwardInPattern
            )

            QuickTranslationRuleTokenPaletteView { insertIntoPattern($0) }

            if let segment = selectedTokenSegment(in: segments),
               let spec = QuickTranslationRuleDraftAnalyzer.tokenSpec(of: segment.text) {
                QuickTranslationRuleTokenLengthBar(spec: spec) { updated in
                    applyTokenSpec(updated, to: segment)
                }
            }
        } header: {
            Text("Mẫu (vế trái dấu =)")
        } footer: {
            Text("Nút token chèn **tại con trỏ** của ô nhập, hoặc thay đoạn đang bôi đen. Chạm một chip token (ở dải trên hoặc trong ô nhập) để mở thanh chỉnh độ dài. Token: `<n>` số, `<y>` đọc từng chữ số, `<h>` chữ số Hán, `<d>` chữ số 0-9, `<m>` đơn vị bậc (十 → mươi, 百 → trăm), `<a>` chữ cái A-Z giữ nguyên văn, `<L>` nhãn chương, `<hv>` một chữ Hán-Việt, `<ne>/<pn>/<vp>/<w>` cụm trong từ điển. `<L>`, `<hv>` và `<m>` luôn đúng một ký tự nên không có thanh độ dài. Nhóm `(a|b)` và `(a|b)?` không được đánh số. Mỗi token chịu sự chi phối của Cấu hình token rule; tắt token không sửa file nhưng rule chứa token đó sẽ không chạy.")
        }
    }

    @ViewBuilder
    private func replacementSection(analysis: QuickTranslationRuleDraftAnalyzer.Analysis) -> some View {
        Section {
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
    private var editInfoSection: some View {
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

    // MARK: - Lưu

    /// Bấm Lưu. Ở chế độ **thêm** và đang có truyện mở, phạm vi được hỏi ngay tại đây thay vì bằng một
    /// ô chọn nằm sẵn trong form — người dùng quyết định lúc đã viết xong rule, không phải trước đó.
    private func submit() {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        if !isEditing, let contextBookId, !contextBookId.isEmpty {
            showingScopeDialog = true
            return
        }
        performSubmit(scope: effectiveScope)
    }

    /// Lưu thật vào một phạm vi cụ thể.
    ///
    /// Mẫu đã có trong phạm vi đó thì **đè vế phải** và giữ nguyên vị trí dòng; chưa có thì thêm mới —
    /// cùng một lời gọi `QuickTranslationRuleRecordStore.upsert` cho cả hai bộ, nên không có nhánh
    /// "trùng mẫu thì báo lỗi" nào.
    private func performSubmit(scope: QuickTranslationRuleScope) {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        switch onSubmit(key, replacement, scope) {
        case .success:
            errorText = nil
            QuickTranslationRuleDraftStore.shared.clear(id: mode.id)
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
