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
/// Ba công cụ nhập nhanh đều tác động lên **cùng** một vùng chọn (`selectionStart`/`selectionLength`,
/// tính theo chỉ số ký tự của `Array(pattern)`): dải chip mẫu cấp con trỏ, bảng token chèn hoặc thay
/// token tại con trỏ, thanh min–max sửa token đang chọn.
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
    /// Vùng chọn trong mẫu: `length == 0` là con trỏ chèn. Chỉ số **ký tự**, không phải UTF-16 —
    /// mẫu rule ngắn và mọi thao tác ở đây là chèn/thay chuỗi, không trao range cho UIKit.
    @State private var selectionStart: Int
    @State private var selectionLength: Int
    /// Lỗi do store trả về lúc lưu (khác với lỗi cú pháp mà bản nháp tự chấm được).
    @State private var errorText: String? = nil
    /// Phân biệt "người dùng gõ tay vào TextField" với "nút vừa chèn/sửa token". Gõ tay thì con trỏ
    /// nhảy về cuối (đúng thứ tay người dùng đang làm), còn nút thì phải giữ nguyên vùng nó vừa đặt —
    /// nếu không, thanh min–max sẽ đóng ngay sau khi chèn token.
    @State private var isProgrammaticPatternEdit = false
    @FocusState private var focusedField: QuickTranslationRuleDraftStore.Field?

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
        case .add(let prefilled):
            seedPattern = prefilled
            seedReplacement = ""
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
        restoredFocus = restored?.focus
        didRestoreDraft = restored != nil
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

    private var currentDraft: QuickTranslationRuleDraftStore.Draft {
        QuickTranslationRuleDraftStore.Draft(
            pattern: pattern,
            replacement: replacement,
            saveToBook: saveToBook,
            selectionStart: selectionStart,
            selectionLength: selectionLength,
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
                scopeSection
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
            .onAppear {
                if didRestoreDraft {
                    // Không log nội dung mẫu: đây là dữ liệu của người dùng, chỉ cần biết *đã* có một
                    // lượt dựng lại để lần sau chẩn đoán được nguyên nhân gốc.
                    AppLogger.shared.log("📝 [RuleEditor] Sheet dựng lại giữa lúc gõ — đã khôi phục bản nháp (\(isEditing ? "sửa" : "thêm"))")
                }
                if let restoredFocus, focusedField == nil {
                    focusedField = restoredFocus
                }
            }
            .onChange(of: currentDraft) { _, newValue in
                QuickTranslationRuleDraftStore.shared.store(newValue, for: mode.id)
            }
            .onChange(of: pattern) { _, newValue in
                reconcileSelection(after: newValue)
            }
        }
    }

    // MARK: - Các section

    @ViewBuilder
    private func patternSection(segments: [QuickTranslationRuleDraftAnalyzer.Segment]) -> some View {
        Section {
            TextField("第<n:1-6>章", text: $pattern, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .pattern)

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
            Text("Bấm một chip ở dải trên để chọn token rồi chỉnh độ dài, hoặc bấm vạch giữa hai chip để đặt chỗ chèn. Token: `<n>` số, `<y>` đọc từng chữ số, `<h>` chữ số Hán, `<d>` chữ số 0-9, `<L>` nhãn chương, `<hv>` một chữ Hán-Việt, `<ne>/<pn>/<vp>/<w>` cụm trong từ điển. Nhóm `(a|b)` và `(a|b)?` không được đánh số. Mỗi token chịu sự chi phối của Cấu hình token rule; tắt token không sửa file nhưng rule chứa token đó sẽ không chạy.")
        }
    }

    @ViewBuilder
    private func replacementSection(analysis: QuickTranslationRuleDraftAnalyzer.Analysis) -> some View {
        Section {
            TextField("Chương {0}", text: $replacement, axis: .vertical)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .replacement)

            QuickTranslationRuleCaptureChipsView(analysis: analysis) { index in
                replacement += "{\(index)}"
            }
        } header: {
            Text("Bản dịch (vế phải dấu =)")
        } footer: {
            Text("`{0}`, `{1}`… đánh số **token** theo thứ tự xuất hiện, không đánh số nhóm hay literal. Mọi token phải được dùng, và mẫu phải có ít nhất một ký tự thường làm neo.")
        }
    }

    @ViewBuilder
    private var scopeSection: some View {
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

    // MARK: - Vùng chọn trong mẫu

    /// Token đang chọn là token mà vùng chọn trùng **khít** — nhờ vậy chọn hai ký tự literal hay một
    /// phần của token không mở thanh min–max ra một cách vô nghĩa.
    private func selectedTokenSegment(
        in segments: [QuickTranslationRuleDraftAnalyzer.Segment]
    ) -> QuickTranslationRuleDraftAnalyzer.Segment? {
        guard selectionLength > 0 else { return nil }
        return segments.first {
            $0.kind == .token && $0.start == selectionStart && $0.length == selectionLength
        }
    }

    private func setPattern(_ newPattern: String, selection: Range<Int>) {
        isProgrammaticPatternEdit = true
        pattern = newPattern
        selectionStart = selection.lowerBound
        selectionLength = selection.count
    }

    /// Gõ tay ⇒ con trỏ về cuối; nút chèn/sửa ⇒ giữ vùng nó vừa đặt. Cả hai đường đều kẹp lại vùng
    /// chọn để một mẫu vừa bị gõ ngắn đi không để lại range trỏ ra ngoài chuỗi.
    private func reconcileSelection(after newPattern: String) {
        let count = Array(newPattern).count
        if isProgrammaticPatternEdit {
            isProgrammaticPatternEdit = false
        } else if focusedField == .pattern {
            selectionStart = count
            selectionLength = 0
        }
        selectionStart = min(max(0, selectionStart), count)
        if selectionStart + selectionLength > count {
            selectionLength = 0
        }
    }

    /// Chèn tại con trỏ, hoặc **thay** vùng đang chọn — đúng cái cần cho luồng nút `+` của Check rule,
    /// nơi mẫu điền sẵn là cả cụm chữ Trung và việc phải làm là đổi một đoạn thành token.
    private func insertIntoPattern(_ text: String) {
        let count = Array(pattern).count
        let start = min(max(0, selectionStart), count)
        let end = min(max(start, start + selectionLength), count)
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(
            range: start..<end,
            in: pattern,
            with: text
        )
        setPattern(updated, selection: start..<(start + Array(text).count))
    }

    private func applyTokenSpec(
        _ spec: QuickTranslationRuleDraftAnalyzer.TokenSpec,
        to segment: QuickTranslationRuleDraftAnalyzer.Segment
    ) {
        let syntax = spec.syntax
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(
            range: segment.range,
            in: pattern,
            with: syntax
        )
        setPattern(updated, selection: segment.start..<(segment.start + Array(syntax).count))
    }

    private func deleteBackwardInPattern() {
        let count = Array(pattern).count
        let start = min(max(0, selectionStart), count)

        if selectionLength > 0 {
            let end = min(start + selectionLength, count)
            let updated = QuickTranslationRuleDraftAnalyzer.replacing(range: start..<end, in: pattern, with: "")
            setPattern(updated, selection: start..<start)
            return
        }

        guard let previous = QuickTranslationRuleDraftAnalyzer.segments(of: pattern)
            .last(where: { $0.end <= start }) else { return }
        let updated = QuickTranslationRuleDraftAnalyzer.replacing(range: previous.range, in: pattern, with: "")
        setPattern(updated, selection: previous.start..<previous.start)
    }

    // MARK: - Lưu

    private func submit() {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        switch onSubmit(key, replacement, effectiveScope) {
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
