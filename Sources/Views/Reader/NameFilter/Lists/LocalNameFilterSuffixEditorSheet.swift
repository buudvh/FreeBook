import SwiftUI

/// Sheet thêm / sửa **một** đuôi của màn "Đuôi địa danh, tổ chức, thuật ngữ" = màn **Sửa từ** của từ điển
/// (`DictEntryEditSheet` chế độ danh sách, plan 2026-11-27 mockup khung 4 — anh Bửu: danh sách vế trái chữ Hán làm kiểu
/// Sửa từ): header "Sửa từ" / "Thêm từ" + badge "Đuôi · Chung" + bút chì đổi chữ gốc, hàng chữ gốc chọn được, hàng token,
/// ô nghĩa, chip nghĩa gợi ý, aa…AA; phần riêng của đuôi là khối **Loại** (Địa danh / Tổ chức / Thuật ngữ) + **Nghĩa
/// đứng** (Trước tên / Sau tên — mục mới mặc định Sau tên) và dòng "Ví dụ" đổi theo lựa chọn (江海市 → …; thuật ngữ
/// 五气丹 → Ngũ Khí đan). Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
///
/// - Luật lấy từ `LocalNameFilterSuffixStore` (`keyError` / `meaningError` — cùng luật với file gốc), hiện đỏ ở dòng thông
///   báo; ô còn trống thì không tô đỏ. Đổi chữ gốc = xoá khoá cũ + thêm khoá mới (store lo); chọn một phần chữ gốc ⇒ thêm
///   đuôi mới = cụm đang chọn, đuôi đang sửa giữ nguyên.
/// - Ghi do màn danh sách làm (`onSave` trả chuỗi lỗi nếu không lưu được — sheet giữ nguyên để sửa tiếp).
/// - Đuôi gốc: nghĩa khác bản gốc ⇒ dòng "Nghĩa gốc: …"; đã sửa ⇒ nút "Về bản gốc: …".
/// - **Thêm từ một name** (`source`, plan 2026-11-27-nghia-ten-tay-huyen mục 7 — hàng "Đuôi" ở màn Sửa từ của màn duyệt
///   Lọc name local): mở với nguyên cụm name (佐特兰街) hoặc đoạn cuối đã chọn sẵn; người dùng thu / nới bằng ‹ › của hàng
///   chữ gốc, khoá lưu = phần đang chọn (luôn thêm mới). Ô nghĩa = phiên âm viết thường của phần đang chọn (đã gõ thì giữ);
///   "Thêm" mờ + dòng nhắc khi chọn cả cụm, phần chọn không nằm cuối name, hoặc dài quá 6 chữ. Dòng "Ví dụ" dùng chính name.
struct LocalNameFilterSuffixEditorSheet: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Store = LocalNameFilterSuffixStore
    typealias Kind = LocalNameFilter.SuffixKind
    typealias Position = LocalNameFilter.MeaningPosition

    /// Name nguồn khi thêm đuôi từ màn Sửa từ của màn duyệt + vùng chọn ban đầu (UTF-16 trên name đã bỏ khoảng trắng).
    struct Source {
        let name: String
        let selection: NSRange
    }

    /// Phần tên riêng của dòng "Ví dụ": địa danh / tổ chức 江海 → Giang Hải, thuật ngữ 五气 → Ngũ Khí (五气丹 → Ngũ Khí đan).
    private static func sample(for kind: Kind) -> (name: String, reading: String) {
        switch kind {
        case .place, .sect: return ("江海", "Giang Hải")
        case .term: return ("五气", "Ngũ Khí")
        }
    }
    /// Bề ngang nhãn "Loại" / "Nghĩa đứng" của khối phụ (mockup khung 4).
    private static let optionLabelWidth: CGFloat = 86

    /// `nil` = thêm đuôi mới.
    let original: Entry?
    /// Thêm đuôi từ một name (xem doc của type); `nil` = màn danh sách đuôi như cũ.
    let source: Source?
    /// `replacing` = khoá bị thay (`nil` = thêm mới, kể cả thêm cụm chọn một phần khi đang sửa).
    let onSave: (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position, _ replacing: String?) -> String?
    let onRestoreBundled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind
    @State private var position: Position

    init(
        original: Entry?,
        initialKind: Kind = .place,
        source: Source? = nil,
        onSave: @escaping (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position, _ replacing: String?) -> String?,
        onRestoreBundled: @escaping () -> Void = {}
    ) {
        self.original = original
        self.source = original == nil ? source : nil
        self.onSave = onSave
        self.onRestoreBundled = onRestoreBundled
        _kind = State(initialValue: original?.kind ?? initialKind)
        _position = State(initialValue: original?.position ?? .after)
    }

    var body: some View {
        DictEntryEditSheet(
            originalKey: original?.key ?? source?.name ?? "",
            originalValue: original?.meaning ?? "",
            dictType: .vietPhrase, // chỉ nuôi badge mặc định — `badgeText` thay
            scopeBookId: nil,
            chipBookId: nil,
            existingValue: { key in Store.shared.entries().first { $0.key == key }?.meaning },
            onUpdate: { _, _ in },
            onAddEntry: { _, _ in },
            onDefinitionsChanged: {},
            badgeText: "Đuôi · Chung",
            listMode: listMode,
            initialSelection: source?.selection
        )
    }

    private var listMode: DictEntryEditListMode {
        let source = self.source
        let suggest: ((String) -> String)? = source == nil ? nil : { key in Store.suggestedMeaning(for: key) }
        return DictEntryEditListMode(
            meaningPlaceholder: "Nghĩa của đuôi (trấn, thành phố…)",
            keyError: { key, replacing in
                Self.sourceKeyError(key, source: source) ?? Store.shared.keyError(key, replacing: replacing)
            },
            meaningError: { meaning in Store.shared.meaningError(meaning) },
            save: { key, meaning, replacing in onSave(key, meaning, kind, position, replacing) },
            isExtraDirty: original.map { kind != $0.kind || position != $0.position } ?? false,
            extraRows: { key, meaning in AnyView(extraRows(key: key, meaning: meaning)) },
            addsFromSource: source != nil,
            suggestedMeaning: suggest
        )
    }

    /// Thêm từ một name: đuôi phải là phần **cuối** name và chừa ≥ 1 chữ phía trước. `nil` = hợp lệ (luật chung còn lại do
    /// store kiểm, gồm cả dài quá 6 chữ).
    private static func sourceKeyError(_ key: String, source: Source?) -> String? {
        guard let source else { return nil }
        let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if key == name { return "Chừa ít nhất 1 chữ trước đuôi." }
        if !name.hasSuffix(key) { return "Đuôi phải là phần cuối của \(name)." }
        return nil
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
                Text("Ví dụ: \(exampleSample(key: key).name)\(key) → \(Text(verbatim: example).bold().foregroundColor(.primary))")
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

    /// "thành phố Giang Hải" / "Giang Hải thành phố" / "Ngũ Khí đan" — chỉ khi đã có đuôi và nghĩa.
    private func exampleText(key: String, meaning: String) -> String? {
        guard !key.isEmpty, !meaning.isEmpty else { return nil }
        let reading = exampleSample(key: key).reading
        return position == .before ? "\(meaning) \(reading)" : "\(reading) \(meaning)"
    }

    /// Phần tên riêng của dòng "Ví dụ": thêm từ một name ⇒ chính name đó (佐特兰 + 街, phần riêng đọc Hán-Việt); không thì
    /// mẫu theo loại.
    private func exampleSample(key: String) -> (name: String, reading: String) {
        if let source {
            let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasSuffix(key), name.count > key.count {
                let proper = String(name.dropLast(key.count))
                return (proper, LocalNameFilterRules.capitalizeWords(Store.suggestedMeaning(for: proper)))
            }
        }
        return Self.sample(for: kind)
    }

    /// Đuôi gốc đang mang nghĩa khác bản gốc (chưa lưu) ⇒ "Nghĩa gốc: thị". Đã sửa thì nút "Về bản gốc" nói thay.
    private func bundledMeaningNote(key: String, meaning: String) -> String? {
        guard restoreLabel == nil, let original, key == original.key, let bundled = original.bundledValue,
              !meaning.isEmpty, bundled.meaning != meaning else { return nil }
        return "Nghĩa gốc: \(bundled.meaning)"
    }

    /// Đuôi gốc đã sửa ⇒ "Về bản gốc: thị · Địa danh · sau tên".
    private var restoreLabel: String? {
        guard let original, original.isEdited, let bundled = original.bundledValue else { return nil }
        let parts = [bundled.meaning, LocalNameFilterSuffixRow.kindLabel(bundled.kind),
                     LocalNameFilterSuffixRow.positionLabel(bundled.position)]
        return "Về bản gốc: " + parts.joined(separator: " · ")
    }
}
