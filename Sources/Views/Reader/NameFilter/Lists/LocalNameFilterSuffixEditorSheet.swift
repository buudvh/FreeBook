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
struct LocalNameFilterSuffixEditorSheet: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Store = LocalNameFilterSuffixStore
    typealias Kind = LocalNameFilter.SuffixKind
    typealias Position = LocalNameFilter.MeaningPosition

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
    /// `replacing` = khoá bị thay (`nil` = thêm mới, kể cả thêm cụm chọn một phần khi đang sửa).
    let onSave: (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position, _ replacing: String?) -> String?
    let onRestoreBundled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind
    @State private var position: Position

    init(
        original: Entry?,
        initialKind: Kind = .place,
        onSave: @escaping (_ key: String, _ meaning: String, _ kind: Kind, _ position: Position, _ replacing: String?) -> String?,
        onRestoreBundled: @escaping () -> Void = {}
    ) {
        self.original = original
        self.onSave = onSave
        self.onRestoreBundled = onRestoreBundled
        _kind = State(initialValue: original?.kind ?? initialKind)
        _position = State(initialValue: original?.position ?? .after)
    }

    var body: some View {
        DictEntryEditSheet(
            originalKey: original?.key ?? "",
            originalValue: original?.meaning ?? "",
            dictType: .vietPhrase, // chỉ nuôi badge mặc định — `badgeText` thay
            scopeBookId: nil,
            chipBookId: nil,
            existingValue: { key in Store.shared.entries().first { $0.key == key }?.meaning },
            onUpdate: { _, _ in },
            onAddEntry: { _, _ in },
            onDefinitionsChanged: {},
            badgeText: "Đuôi · Chung",
            listMode: listMode
        )
    }

    private var listMode: DictEntryEditListMode {
        DictEntryEditListMode(
            meaningPlaceholder: "Nghĩa của đuôi (trấn, thành phố…)",
            keyError: { key, replacing in Store.shared.keyError(key, replacing: replacing) },
            meaningError: { meaning in Store.shared.meaningError(meaning) },
            save: { key, meaning, replacing in onSave(key, meaning, kind, position, replacing) },
            isExtraDirty: original.map { kind != $0.kind || position != $0.position } ?? false,
            extraRows: { key, meaning in AnyView(extraRows(key: key, meaning: meaning)) }
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
                Text("Ví dụ: \(Self.sample(for: kind).name)\(key) → \(Text(verbatim: example).bold().foregroundColor(.primary))")
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
        let reading = Self.sample(for: kind).reading
        return position == .before ? "\(meaning) \(reading)" : "\(reading) \(meaning)"
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
