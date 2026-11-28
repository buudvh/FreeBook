import SwiftUI

/// Sheet thêm / sửa **một** mục của danh sách "Hậu tố" hoặc "Tiền tố" (`LocalNameFilterAffixListFlavor`) = màn **Sửa từ**
/// của từ điển (`DictEntryEditSheet` chế độ danh sách — anh Bửu: danh sách vế trái chữ Hán làm kiểu Sửa từ; "Thêm tiền tố
/// phải đầy đủ như hậu tố"): header "Sửa từ" / "Thêm từ" + badge + bút chì đổi chữ gốc, hàng chữ gốc chọn được, hàng token,
/// ô nghĩa, chip nghĩa gợi ý, aa…AA; phần riêng của danh sách là khối **Loại** (Địa danh / Tổ chức / Thuật ngữ / Nhân danh)
/// + **Nghĩa đứng** (Trước tên / Sau tên — hậu tố mới mặc định Sau tên, tiền tố mới Trước tên) và dòng "Ví dụ" đổi theo lựa
/// chọn (江海市 → …, 陈长老 → Trần trưởng lão, 老尼尔 → lão Neil). Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
///
/// - Luật lấy từ store của danh sách (`keyError` / `meaningError` — cùng luật với file gốc), hiện đỏ ở dòng thông báo; ô
///   còn trống thì không tô đỏ. Đổi chữ gốc = xoá khoá cũ + thêm khoá mới (store lo); chọn một phần chữ gốc ⇒ thêm mục mới
///   = cụm đang chọn, mục đang sửa giữ nguyên.
/// - Ghi do nơi mở làm (`onSave` nhận `SaveRequest`, thường gọi `SaveRequest.save(in:bookId:)`; trả chuỗi lỗi nếu không lưu
///   được — sheet giữ nguyên để sửa tiếp).
/// - Mục gốc (Chung): nghĩa khác bản gốc ⇒ dòng "Nghĩa gốc: …"; đã sửa ⇒ nút "Về bản gốc: …".
/// - **Mở từ một truyện** (`bookId`, 2026-11-28 — mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M5 / M5b):
///   cụm **R | C** cuối hàng aa…AA (`DictEntryEditScopeToggle`), badge chỉ còn "Hậu tố" / "Tiền tố"; thêm mới mặc định R
///   (`initialScope` chọn sẵn theo nhóm khi mở từ màn quản lý), sửa thì đúng phạm vi của mục. Đổi phạm vi khi sửa theo luật
///   chuyển của lõi (`LocalNameFilterAffixListStore.save(...scope:bookId:original:)`): C → R tạo bản riêng (Chung giữ cho
///   truyện khác), R → C ghi lên Chung rồi xoá bản riêng — Chung đã có chữ đó ⇒ **hỏi lại** trước khi ghi đè
///   (`DictEntryEditListMode.interceptSave`). Không có truyện ⇒ chỉ Chung như trước.
/// - **Thêm từ một name** (`source` — hàng "Hậu tố" / "Tiền tố" ở màn Sửa từ của màn duyệt Lọc name local, màn Quản lý tiền
///   tố, hậu tố): mở với nguyên cụm name (佐特兰街, 老尼尔) hoặc đoạn cuối / đầu đã chọn sẵn; người dùng thu / nới bằng ‹ ›
///   của hàng chữ gốc, khoá lưu = phần đang chọn (luôn thêm mới). Ô nghĩa = phiên âm viết thường của phần đang chọn (đã gõ thì
///   giữ); "Thêm" mờ + dòng nhắc khi chọn cả cụm, phần chọn không nằm **cuối** (hậu tố) / **đầu** (tiền tố) name, hoặc dài
///   quá 6 chữ. Dòng "Ví dụ" của hậu tố dùng chính name (phần riêng đọc Hán-Việt); của tiền tố dùng mẫu tên Latin (tiền tố
///   chỉ ghép trước tên Latin, phần sau của name không tra được nghĩa Latin ở đây).
struct LocalNameFilterSuffixEditorSheet: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Flavor = LocalNameFilterAffixListFlavor
    typealias Kind = LocalNameFilter.SuffixKind
    typealias Position = LocalNameFilter.MeaningPosition
    typealias Scope = LocalNameFilterAffixListStore.Scope
    typealias ScopedKey = LocalNameFilterAffixListStore.ScopedKey

    /// Name nguồn khi thêm từ màn Sửa từ của màn duyệt + vùng chọn ban đầu (UTF-16 trên name đã bỏ khoảng trắng).
    struct Source {
        let name: String
        let selection: NSRange
    }

    /// Một lần lưu: mục sẽ ghi + phạm vi đích + mục bị thay.
    struct SaveRequest {
        let key: String
        let meaning: String
        let kind: Kind
        let position: Position
        /// Phạm vi đích (không có truyện ⇒ luôn `.common`).
        let scope: Scope
        /// Mục đang sửa (chữ + phạm vi hiện tại); `nil` = thêm mới, kể cả chọn một phần khi đang sửa.
        let original: ScopedKey?

        /// Khoá cũ khi sửa mà đổi chữ (街 ⇒ 兰街) — nơi mở ghép lại cả name mang khoá cũ.
        var replacedKey: String? {
            guard let original, original.key != key else { return nil }
            return original.key
        }

        /// Ghi theo luật phạm vi của lõi. `bookId` rỗng ⇒ chỉ Chung (đúng `save(...replacing:)` cũ).
        func save(in store: LocalNameFilterAffixListStore, bookId: String) -> String? {
            store.save(key: key, meaning: meaning, kind: kind, position: position, scope: scope, bookId: bookId,
                       original: original)
        }
    }

    /// Bề ngang nhãn "Loại" / "Nghĩa đứng" của khối phụ (mockup khung 4).
    private static let optionLabelWidth: CGFloat = 86

    let flavor: Flavor
    /// `nil` = thêm mục mới.
    let original: Entry?
    /// Phạm vi của `original` (mục Riêng ⇒ `.book`).
    let originalScope: Scope
    /// Thêm từ một name (xem doc của type); `nil` = màn danh sách như cũ.
    let source: Source?
    /// Truyện đang mở; `nil` / rỗng ⇒ chỉ danh sách Chung, không có cụm R | C.
    let bookId: String?
    let onSave: (SaveRequest) -> String?
    let onRestoreBundled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind
    @State private var position: Position
    @State private var scope: Scope
    /// R → C mà Chung đã có chữ đó: chờ người dùng đồng ý ghi đè.
    @State private var pendingOverwrite: SaveRequest? = nil

    /// `initialKind == nil` ⇒ loại mặc định của danh sách (`Flavor.defaultKind`). `initialScope == nil` ⇒ thêm mới vào R khi
    /// có truyện.
    init(
        flavor: Flavor = .suffix,
        original: Entry?,
        originalScope: Scope = .common,
        initialKind: Kind? = nil,
        source: Source? = nil,
        bookId: String? = nil,
        initialScope: Scope? = nil,
        onSave: @escaping (SaveRequest) -> String?,
        onRestoreBundled: @escaping () -> Void = {}
    ) {
        self.flavor = flavor
        self.original = original
        self.originalScope = original == nil ? .common : originalScope
        self.source = original == nil ? source : nil
        let book = bookId.flatMap { $0.isEmpty ? nil : $0 }
        self.bookId = book
        self.onSave = onSave
        self.onRestoreBundled = onRestoreBundled
        _kind = State(initialValue: original?.kind ?? initialKind ?? flavor.defaultKind)
        _position = State(initialValue: original?.position ?? flavor.defaultPosition)
        let startScope: Scope
        if book == nil {
            startScope = .common
        } else if original != nil {
            startScope = originalScope
        } else {
            startScope = initialScope ?? .book
        }
        _scope = State(initialValue: startScope)
    }

    var body: some View {
        DictEntryEditSheet(
            originalKey: original?.key ?? source?.name ?? "",
            originalValue: original?.meaning ?? "",
            dictType: .vietPhrase, // chỉ nuôi badge mặc định — `badgeText` thay
            scopeBookId: nil,
            chipBookId: nil,
            existingValue: { key in entry(for: key, in: scope)?.meaning },
            onUpdate: { _, _ in },
            onAddEntry: { _, _ in },
            onDefinitionsChanged: {},
            // Có cụm R | C thì phạm vi đọc ở đó — badge chỉ còn danh từ (mockup M5 / M5b).
            badgeText: bookId == nil ? flavor.badgeText : flavor.noun,
            listMode: listMode,
            initialSelection: source?.selection
        )
        .alert(
            overwriteTitle,
            isPresented: Binding(get: { pendingOverwrite != nil }, set: { if !$0 { pendingOverwrite = nil } }),
            presenting: pendingOverwrite
        ) { request in
            Button("Huỷ", role: .cancel) { pendingOverwrite = nil }
            Button("Ghi đè", role: .destructive) { confirmOverwrite(request) }
        } message: { request in
            Text(verbatim: overwriteMessage(for: request))
        }
    }

    private var listMode: DictEntryEditListMode {
        let source = self.source
        let flavor = self.flavor
        let store = flavor.store
        let suggest: ((String) -> String)? = source == nil ? nil : { key in
            LocalNameFilterAffixListStore.suggestedMeaning(for: key)
        }
        return DictEntryEditListMode(
            meaningPlaceholder: flavor.meaningPlaceholder,
            keyError: { key, replacing in
                if let error = source.flatMap({ flavor.sourceKeyError(key, name: $0.name) }) { return error }
                guard let bookId else { return store.keyError(key, replacing: replacing) }
                return store.keyError(key, scope: scope, bookId: bookId, original: scopedOriginal(replacing))
            },
            meaningError: { meaning in store.meaningError(meaning) },
            save: { key, meaning, replacing in onSave(request(key: key, meaning: meaning, replacing: replacing)) },
            isExtraDirty: original.map { kind != $0.kind || position != $0.position || scope != originalScope } ?? false,
            extraRows: { key, meaning in AnyView(extraRows(key: key, meaning: meaning)) },
            addsFromSource: source != nil,
            suggestedMeaning: suggest,
            caseRowTrailing: bookId == nil ? nil : AnyView(DictEntryEditScopeToggle(isBookScope: Binding(
                get: { scope == .book },
                set: { scope = $0 ? .book : .common }
            ))),
            interceptSave: { key, meaning, replacing in
                let pending = self.request(key: key, meaning: meaning, replacing: replacing)
                guard needsOverwriteConfirmation(pending) else { return false }
                pendingOverwrite = pending
                return true
            }
        )
    }

    // MARK: - Phạm vi

    /// `replacing` của màn Sửa từ (khoá đang sửa; `nil` = thêm mới) ⇒ mục đang sửa kèm phạm vi hiện tại của nó.
    private func scopedOriginal(_ replacing: String?) -> ScopedKey? {
        replacing.map { ScopedKey(key: $0, scope: originalScope) }
    }

    private func request(key: String, meaning: String, replacing: String?) -> SaveRequest {
        SaveRequest(key: key, meaning: meaning, kind: kind, position: position,
                    scope: bookId == nil ? .common : scope, original: scopedOriginal(replacing))
    }

    /// Mục đang có của chữ `key` ở phạm vi `scope` (Riêng ⇒ danh sách riêng của truyện).
    private func entry(for key: String, in scope: Scope) -> Entry? {
        let store = flavor.store
        switch scope {
        case .book:
            guard let bookId else { return nil }
            return store.bookStore.entries(bookId: bookId).first { $0.key == key }
        case .common:
            return store.entries().first { $0.key == key }
        }
    }

    /// R → C (sửa mục riêng, đưa lên Chung) mà Chung đã có chữ đó ⇒ lõi sẽ ghi đè mục Chung cho mọi truyện: hỏi trước.
    private func needsOverwriteConfirmation(_ request: SaveRequest) -> Bool {
        guard bookId != nil, request.scope == .common, request.original?.scope == .book else { return false }
        return entry(for: request.key, in: .common) != nil
    }

    private var overwriteTitle: String {
        "Ghi đè \(flavor.lowercasedNoun) chung \(pendingOverwrite?.key ?? "")?"
    }

    private func overwriteMessage(for request: SaveRequest) -> String {
        let current = entry(for: request.key, in: .common).map {
            " (\($0.meaning) · \(LocalNameFilterSuffixRow.kindLabel($0.kind)))"
        } ?? ""
        return "Danh sách chung đã có \(request.key)\(current). Đưa lên Chung sẽ thay mục đó cho mọi truyện, "
            + "rồi xoá bản riêng của truyện này."
    }

    private func confirmOverwrite(_ request: SaveRequest) {
        pendingOverwrite = nil
        if let error = onSave(request) {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            dismiss()
        }
    }

    // MARK: - Khối Loại / Nghĩa đứng

    private func extraRows(key: String, meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                optionRow("Loại") {
                    Picker("Loại", selection: $kind) {
                        ForEach(Kind.allCases, id: \.self) { option in
                            Text(LocalNameFilterSuffixRow.kindLabel(option)).tag(option)
                        }
                    }
                }
                Divider()
                optionRow("Nghĩa đứng") {
                    Picker("Nghĩa đứng", selection: $position) {
                        Text("Trước tên").tag(Position.before)
                        Text("Sau tên").tag(Position.after)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            if let example = exampleText(key: key, meaning: meaning) {
                Text("Ví dụ: \(flavor.word(key: key, proper: exampleSample(key: key).name)) → \(Text(verbatim: example).bold().foregroundColor(.primary))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let note = bundledMeaningNote(key: key, meaning: meaning) {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let restoreLabel {
                Button {
                    onRestoreBundled()
                    dismiss()
                } label: {
                    Label(restoreLabel, systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .frame(width: Self.optionLabelWidth, alignment: .leading)
            control()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
        .frame(minHeight: 40)
    }

    /// "thành phố Giang Hải" / "Giang Hải thành phố" / "Trần trưởng lão" / "lão Neil" — chỉ khi đã có mục và nghĩa.
    private func exampleText(key: String, meaning: String) -> String? {
        guard !key.isEmpty, !meaning.isEmpty else { return nil }
        let reading = exampleSample(key: key).reading
        return position == .before ? "\(meaning) \(reading)" : "\(reading) \(meaning)"
    }

    /// Phần tên riêng của dòng "Ví dụ": thêm hậu tố từ một name ⇒ chính name đó (佐特兰 + 街, phần riêng đọc Hán-Việt);
    /// tiền tố và màn danh sách ⇒ mẫu theo loại (`Flavor.sample(for:)`).
    private func exampleSample(key: String) -> (name: String, reading: String) {
        if flavor == .suffix, let source, let proper = flavor.remainder(of: source.name, removing: key) {
            let suggested = LocalNameFilterAffixListStore.suggestedMeaning(for: proper)
            return (proper, LocalNameFilterRules.capitalizeWords(suggested))
        }
        return flavor.sample(for: kind)
    }

    /// Mục gốc (Chung) đang mang nghĩa khác bản gốc (chưa lưu) ⇒ "Nghĩa gốc: thị". Đã sửa thì nút "Về bản gốc" nói thay.
    /// Đang chuyển sang R ⇒ không nói (bản riêng không có bản gốc).
    private func bundledMeaningNote(key: String, meaning: String) -> String? {
        guard scope == .common, restoreLabel == nil, let original, key == original.key,
              let bundled = original.bundledValue, !meaning.isEmpty, bundled.meaning != meaning else { return nil }
        return "Nghĩa gốc: \(bundled.meaning)"
    }

    /// Mục gốc (Chung) đã sửa ⇒ "Về bản gốc: thị · Địa danh · sau tên". Đang chuyển sang R ⇒ ẩn (nút đó ghi lên Chung).
    private var restoreLabel: String? {
        guard scope == .common, let original, original.isEdited, let bundled = original.bundledValue else { return nil }
        let parts = [bundled.meaning, LocalNameFilterSuffixRow.kindLabel(bundled.kind),
                     LocalNameFilterSuffixRow.positionLabel(bundled.position)]
        return "Về bản gốc: " + parts.joined(separator: " · ")
    }
}
