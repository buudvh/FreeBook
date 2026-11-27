import SwiftUI

/// Sheet thêm / sửa **một** đuôi của màn "Đuôi địa danh & tông môn" (mockup khung 5b), khuôn
/// `QuickTranslationSurnameEditorSheet` thêm hai ô **Loại** (Địa danh / Tông môn) và **Nghĩa đứng** (Trước tên / Sau tên —
/// mục mới mặc định Sau tên) + dòng "Ví dụ: 江海市 → …" đổi theo lựa chọn. Nút "Lưu" chữ ở header, không nút chỉ để
/// đóng (vuốt xuống; sửa dở thì `confirmDiscardOnSwipe` hỏi lại). Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
///
/// - Luật lấy từ `LocalNameFilterSuffixStore` (`keyError` / `meaningError` — cùng luật với file gốc), hiện ngay dưới ô;
///   ô còn trống thì không tô đỏ. Sửa chữ Hán = xoá khoá cũ + thêm khoá mới (store lo).
/// - Ghi do màn danh sách làm (`onSave` trả chuỗi lỗi nếu không lưu được — sheet giữ nguyên để sửa tiếp).
/// - Đuôi gốc: ô Nghĩa ghi "gốc: …" khi nghĩa khác bản gốc; đã sửa thì có thêm hàng "Về bản gốc".
struct LocalNameFilterSuffixEditorSheet: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Store = LocalNameFilterSuffixStore
    typealias Kind = LocalNameFilter.SuffixKind
    typealias Position = LocalNameFilter.MeaningPosition

    private enum Field: Hashable {
        case key
        case meaning
    }

    /// Phần tên riêng của dòng "Ví dụ" (江海 → Giang Hải).
    private static let sampleName = "江海"
    private static let sampleReading = "Giang Hải"

    /// `nil` = thêm đuôi mới.
    let original: Entry?
    let onSave: (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position) -> String?
    let onRestoreBundled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var key: String
    @State private var meaning: String
    @State private var kind: Kind
    @State private var position: Position
    /// Lỗi do màn danh sách trả về lúc ghi; xoá khi người dùng sửa tiếp.
    @State private var saveError: String?

    init(
        original: Entry?,
        initialKind: Kind = .place,
        onSave: @escaping (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position) -> String?,
        onRestoreBundled: @escaping () -> Void = {}
    ) {
        self.original = original
        self.onSave = onSave
        self.onRestoreBundled = onRestoreBundled
        _key = State(initialValue: original?.key ?? "")
        _meaning = State(initialValue: original?.meaning ?? "")
        _kind = State(initialValue: original?.kind ?? initialKind)
        _position = State(initialValue: original?.position ?? .after)
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedMeaning: String { meaning.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var keyError: String? {
        Store.shared.keyError(trimmedKey, replacing: original?.key)
    }

    private var meaningError: String? {
        Store.shared.meaningError(trimmedMeaning)
    }

    private var isDirty: Bool {
        guard let original else { return !trimmedKey.isEmpty || !trimmedMeaning.isEmpty }
        return trimmedKey != original.key || trimmedMeaning != original.meaning
            || kind != original.kind || position != original.position
    }

    private var canSave: Bool { isDirty && keyError == nil && meaningError == nil }

    /// Nghĩa gốc khi đuôi gốc đang mang nghĩa khác ("gốc: thị").
    private var bundledMeaningNote: String? {
        guard let bundled = original?.bundledValue, bundled.meaning != trimmedMeaning else { return nil }
        return "gốc: \(bundled.meaning)"
    }

    /// Đuôi gốc đã sửa ⇒ "Về bản gốc: thị · Địa danh · sau tên".
    private var restoreLabel: String? {
        guard let original, original.isEdited, let bundled = original.bundledValue else { return nil }
        let parts = [bundled.meaning, LocalNameFilterSuffixRow.kindLabel(bundled.kind),
                     LocalNameFilterSuffixRow.positionLabel(bundled.position)]
        return "Về bản gốc: " + parts.joined(separator: " · ")
    }

    /// "Ví dụ: 江海市 → thành phố Giang Hải" — chỉ hiện khi đã có đuôi và nghĩa.
    private var exampleText: String? {
        guard !trimmedKey.isEmpty, !trimmedMeaning.isEmpty else { return nil }
        let composed = position == .before
            ? "\(trimmedMeaning) \(Self.sampleReading)"
            : "\(Self.sampleReading) \(trimmedMeaning)"
        return "Ví dụ: \(Self.sampleName)\(trimmedKey) → \(composed)"
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("镇 hoặc 山脉", text: $key)
                        .font(.title3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .key)
                    if !trimmedKey.isEmpty, let keyError {
                        errorText(keyError)
                    }
                } header: {
                    Text("Chữ Hán")
                }

                Section {
                    HStack {
                        TextField("trấn hoặc thành phố", text: $meaning)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .meaning)
                        if let bundledMeaningNote {
                            Text(verbatim: bundledMeaningNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !trimmedMeaning.isEmpty, let meaningError {
                        errorText(meaningError)
                    }
                    if let saveError {
                        errorText(saveError)
                    }
                } header: {
                    Text("Nghĩa")
                }

                Section {
                    Picker("Loại", selection: $kind) {
                        ForEach(Kind.allCases, id: \.self) { option in
                            Text(LocalNameFilterSuffixRow.kindLabel(option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Loại")
                }

                Section {
                    Picker("Nghĩa đứng", selection: $position) {
                        Text("Trước tên").tag(Position.before)
                        Text("Sau tên").tag(Position.after)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if let exampleText {
                        Text(verbatim: exampleText)
                            .font(.subheadline)
                    }
                } header: {
                    Text("Nghĩa đứng")
                }

                if let restoreLabel {
                    Section {
                        Button {
                            onRestoreBundled()
                            dismiss()
                        } label: {
                            Text(verbatim: restoreLabel)
                        }
                    }
                }
            }.glassSheetRows() }
            .pageTitle(original == nil ? "Thêm đuôi" : "Sửa đuôi")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .headerTextButton()
                        .disabled(!canSave)
                }
            }
            .onChange(of: key) { _, _ in saveError = nil }
            .onChange(of: meaning) { _, _ in saveError = nil }
            .onAppear {
                focusedField = original == nil ? .key : .meaning
            }
        }
        .confirmDiscardOnSwipe(isDirty: isDirty)
        .presentationDragIndicator(.visible)
    }

    private func errorText(_ message: String) -> some View {
        Text(verbatim: message)
            .font(.footnote)
            .foregroundColor(.red)
    }

    private func save() {
        guard canSave else { return }
        if let error = onSave(trimmedKey, trimmedMeaning, kind, position) {
            saveError = error
            return
        }
        dismiss()
    }
}
