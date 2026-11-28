import SwiftUI

/// Sheet thêm / sửa **một** mục của danh sách "Hậu tố" hoặc "Tiền tố" (`LocalNameFilterAffixListFlavor`) = màn **Sửa từ**
/// của từ điển (`DictEntryEditSheet` chế độ danh sách — anh Bửu: danh sách vế trái chữ Hán làm kiểu Sửa từ; "Thêm tiền tố
/// phải đầy đủ như hậu tố"): header "Sửa từ" / "Thêm từ" + badge "Hậu tố · chung" / "Tiền tố · chung" + bút chì đổi chữ
/// gốc, hàng chữ gốc chọn được, hàng token, ô nghĩa, chip nghĩa gợi ý, aa…AA; phần riêng của danh sách là khối **Loại**
/// (Địa danh / Tổ chức / Thuật ngữ / Nhân danh) + **Nghĩa đứng** (Trước tên / Sau tên — hậu tố mới mặc định Sau tên, tiền
/// tố mới Trước tên) và dòng "Ví dụ" đổi theo lựa chọn (江海市 → …, 陈长老 → Trần trưởng lão, 老尼尔 → lão Neil). Chỗ
/// trình bày bọc `Group { … }.appGlassSheet()`.
///
/// - Luật lấy từ store của danh sách (`keyError` / `meaningError` — cùng luật với file gốc), hiện đỏ ở dòng thông báo; ô
///   còn trống thì không tô đỏ. Đổi chữ gốc = xoá khoá cũ + thêm khoá mới (store lo); chọn một phần chữ gốc ⇒ thêm mục mới
///   = cụm đang chọn, mục đang sửa giữ nguyên.
/// - Ghi do nơi mở làm (`onSave` trả chuỗi lỗi nếu không lưu được — sheet giữ nguyên để sửa tiếp).
/// - Mục gốc: nghĩa khác bản gốc ⇒ dòng "Nghĩa gốc: …"; đã sửa ⇒ nút "Về bản gốc: …".
/// - **Thêm từ một name** (`source` — hàng "Hậu tố" / "Tiền tố" ở màn Sửa từ của màn duyệt Lọc name local): mở với nguyên
///   cụm name (佐特兰街, 老尼尔) hoặc đoạn cuối / đầu đã chọn sẵn; người dùng thu / nới bằng ‹ › của hàng chữ gốc, khoá lưu =
///   phần đang chọn (luôn thêm mới). Ô nghĩa = phiên âm viết thường của phần đang chọn (đã gõ thì giữ); "Thêm" mờ + dòng
///   nhắc khi chọn cả cụm, phần chọn không nằm **cuối** (hậu tố) / **đầu** (tiền tố) name, hoặc dài quá 6 chữ. Dòng "Ví dụ"
///   của hậu tố dùng chính name (phần riêng đọc Hán-Việt); của tiền tố dùng mẫu tên Latin (tiền tố chỉ ghép trước tên Latin,
///   phần sau của name không tra được nghĩa Latin ở đây).
struct LocalNameFilterSuffixEditorSheet: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Flavor = LocalNameFilterAffixListFlavor
    typealias Kind = LocalNameFilter.SuffixKind
    typealias Position = LocalNameFilter.MeaningPosition

    /// Name nguồn khi thêm từ màn Sửa từ của màn duyệt + vùng chọn ban đầu (UTF-16 trên name đã bỏ khoảng trắng).
    struct Source {
        let name: String
        let selection: NSRange
    }

    /// Bề ngang nhãn "Loại" / "Nghĩa đứng" của khối phụ (mockup khung 4).
    private static let optionLabelWidth: CGFloat = 86

    let flavor: Flavor
    /// `nil` = thêm mục mới.
    let original: Entry?
    /// Thêm từ một name (xem doc của type); `nil` = màn danh sách như cũ.
    let source: Source?
    /// `replacing` = khoá bị thay (`nil` = thêm mới, kể cả thêm cụm chọn một phần khi đang sửa).
    let onSave: (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position, _ replacing: String?) -> String?
    let onRestoreBundled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind
    @State private var position: Position

    /// `initialKind == nil` ⇒ loại mặc định của danh sách (`Flavor.defaultKind`).
    init(
        flavor: Flavor = .suffix,
        original: Entry?,
        initialKind: Kind? = nil,
        source: Source? = nil,
        onSave: @escaping (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position, _ replacing: String?) -> String?,
        onRestoreBundled: @escaping () -> Void = {}
    ) {
        self.flavor = flavor
        self.original = original
        self.source = original == nil ? source : nil
        self.onSave = onSave
        self.onRestoreBundled = onRestoreBundled
        _kind = State(initialValue: original?.kind ?? initialKind ?? flavor.defaultKind)
        _position = State(initialValue: original?.position ?? flavor.defaultPosition)
    }

    var body: some View {
        let store = flavor.store
        return DictEntryEditSheet(
            originalKey: original?.key ?? source?.name ?? "",
            originalValue: original?.meaning ?? "",
            dictType: .vietPhrase, // chỉ nuôi badge mặc định — `badgeText` thay
            scopeBookId: nil,
            chipBookId: nil,
            existingValue: { key in store.entries().first { $0.key == key }?.meaning },
            onUpdate: { _, _ in },
            onAddEntry: { _, _ in },
            onDefinitionsChanged: {},
            badgeText: flavor.badgeText,
            listMode: listMode,
            initialSelection: source?.selection
        )
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
                source.flatMap { flavor.sourceKeyError(key, name: $0.name) } ?? store.keyError(key, replacing: replacing)
            },
            meaningError: { meaning in store.meaningError(meaning) },
            save: { key, meaning, replacing in onSave(key, meaning, kind, position, replacing) },
            isExtraDirty: original.map { kind != $0.kind || position != $0.position } ?? false,
            extraRows: { key, meaning in AnyView(extraRows(key: key, meaning: meaning)) },
            addsFromSource: source != nil,
            suggestedMeaning: suggest
        )
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

    /// Mục gốc đang mang nghĩa khác bản gốc (chưa lưu) ⇒ "Nghĩa gốc: thị". Đã sửa thì nút "Về bản gốc" nói thay.
    private func bundledMeaningNote(key: String, meaning: String) -> String? {
        guard restoreLabel == nil, let original, key == original.key, let bundled = original.bundledValue,
              !meaning.isEmpty, bundled.meaning != meaning else { return nil }
        return "Nghĩa gốc: \(bundled.meaning)"
    }

    /// Mục gốc đã sửa ⇒ "Về bản gốc: thị · Địa danh · sau tên".
    private var restoreLabel: String? {
        guard let original, original.isEdited, let bundled = original.bundledValue else { return nil }
        let parts = [bundled.meaning, LocalNameFilterSuffixRow.kindLabel(bundled.kind),
                     LocalNameFilterSuffixRow.positionLabel(bundled.position)]
        return "Về bản gốc: " + parts.joined(separator: " · ")
    }
}
