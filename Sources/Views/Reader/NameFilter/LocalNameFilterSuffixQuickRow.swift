import SwiftUI

/// Hàng **"Đuôi"** ở màn Sửa từ khi mở từ màn duyệt Lọc name local (plan 2026-11-27-nghia-ten-tay-huyen mục 7, mockup v4
/// khung 2 — anh Bửu: "cho 1 nút thêm đuôi…", "thêm vào option nhanh trước nút thêm đuôi"). Chỉ name không phải tên người
/// (`LocalNameFilterReviewSuffixContext.suffixKind`).
///
/// Cuộn ngang:
/// - đầu hàng: chip chọn nhanh = đoạn cuối 1, 2, 3 chữ của name (chừa ≥ 1 chữ phía trước, bỏ đoạn có chữ không phải Hán) —
///   `+ 街` `+ 兰街` `+ 特兰街`, chạm ⇒ màn thêm đuôi với đúng đoạn đó đã chọn (vẫn nới / thu được bằng ‹ ›);
/// - đoạn đã là đuôi trong danh sách ⇒ chip "✓ 街 · phố · trước", chạm ⇒ sửa đuôi đó (không có chip "+" trùng);
/// - cuối hàng: nút "+ Thêm đuôi" ⇒ màn thêm đuôi với **nguyên cụm** name, người dùng thu hẹp bằng ‹ ›.
/// Màn thêm / sửa là `LocalNameFilterSuffixEditorSheet` (chế độ thêm từ name hoặc sửa đuôi có sẵn), ghi qua
/// `LocalNameFilterSuffixStore` như màn danh sách đuôi. Lưu được ⇒ `onSaved` (màn duyệt ghép lại nghĩa + toast).
struct LocalNameFilterSuffixQuickRow: View {
    typealias Store = LocalNameFilterSuffixStore

    let name: String
    let kind: LocalNameFilter.SuffixKind
    /// Đuôi vừa lưu; `isNew` = thêm mới (không phải sửa đuôi có sẵn).
    let onSaved: (_ key: String, _ isNew: Bool) -> Void

    private struct EditorTarget: Identifiable {
        let id = UUID()
        /// Đuôi có sẵn để sửa; `nil` = thêm từ name với vùng chọn `selection`.
        let entry: LocalNameFilterSuffixEntry?
        let selection: NSRange
    }

    private static let quickLengths = 1...3

    @State private var entries: [LocalNameFilterSuffixEntry] = Store.shared.entries()
    @State private var target: EditorTarget?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Đoạn cuối 1…3 chữ (code point) còn ≥ 1 chữ phía trước, toàn chữ Hán; ngắn trước.
    private var tails: [String] {
        let scalars = Array(trimmedName.unicodeScalars)
        return Self.quickLengths.compactMap { length in
            guard scalars.count > length else { return nil }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars.suffix(length))
            let tail = String(view)
            return LocalNameFilterSuffixListParser.isHanText(tail) ? tail : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text("Đuôi")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                SectionHelpButton(accessibilityLabel: "Giải thích Đuôi", paragraphs: [
                    "Thêm đuôi vào danh sách **Đuôi địa danh, tổ chức, thuật ngữ** ngay từ name này: chạm một đoạn cuối gợi ý (+ 街, + 兰街…) hoặc **+ Thêm đuôi** (mở với cả cụm, thu hẹp bằng ‹ ›). Đuôi dài 1–6 chữ, chừa ít nhất 1 chữ phía trước.",
                    "Lưu xong, các name không phải tên người kết thúc bằng đuôi đó mà nghĩa vẫn do máy ghép được ghép lại nghĩa ngay; nghĩa đã tự sửa giữ nguyên. Đoạn đã là đuôi hiện ✓ — chạm để sửa."
                ])
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tails, id: \.self) { tail in
                        tailChip(tail)
                    }
                    Button {
                        open(entry: nil, tail: nil)
                    } label: {
                        chipLabel("+ Thêm đuôi", highlighted: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { entries = Store.shared.entries() }
        .sheet(item: $target) { target in
            Group {
                editor(for: target)
            }
            .appGlassSheet()
        }
    }

    // MARK: - Chip

    @ViewBuilder
    private func tailChip(_ tail: String) -> some View {
        if let entry = entries.first(where: { $0.key == tail }) {
            Button {
                open(entry: entry, tail: tail)
            } label: {
                chipLabel("✓ \(tail) · \(entry.meaning) · \(entry.position == .before ? "trước" : "sau")", highlighted: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sửa đuôi \(tail)")
        } else {
            Button {
                open(entry: nil, tail: tail)
            } label: {
                chipLabel("+ \(tail)", highlighted: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thêm đuôi \(tail)")
        }
    }

    /// Chip kiểu chip lọc của app: đuôi đã có ⇒ chữ màu nhấn, nền nhấn mờ, viền nhấn; còn lại nền xám mờ.
    private func chipLabel(_ text: String, highlighted: Bool) -> some View {
        Text(verbatim: text)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(highlighted ? .accentColor : .primary)
            .background(Capsule().fill(highlighted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
            .overlay(Capsule().stroke(highlighted ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
    }

    // MARK: - Màn thêm / sửa

    /// `tail == nil` ⇒ nguyên cụm name; vùng chọn tính theo UTF-16 như màn Sửa từ.
    private func open(entry: LocalNameFilterSuffixEntry?, tail: String?) {
        let total = (trimmedName as NSString).length
        let length = tail.map { ($0 as NSString).length } ?? total
        target = EditorTarget(entry: entry, selection: NSRange(location: total - length, length: length))
    }

    @ViewBuilder
    private func editor(for target: EditorTarget) -> some View {
        if let entry = target.entry {
            LocalNameFilterSuffixEditorSheet(
                original: entry,
                onSave: { key, meaning, kind, position, replacing in
                    save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing, isNew: false)
                },
                onRestoreBundled: { restoreBundled(entry) }
            )
        } else {
            LocalNameFilterSuffixEditorSheet(
                original: nil,
                initialKind: kind,
                source: LocalNameFilterSuffixEditorSheet.Source(name: trimmedName, selection: target.selection),
                onSave: { key, meaning, kind, position, replacing in
                    save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing, isNew: true)
                }
            )
        }
    }

    /// Ghi qua store (kiểm lại luật + trùng khoá trên dữ liệu mới nhất). `nil` = đã lưu; chuỗi = lỗi để màn sửa hiện.
    private func save(key: String, meaning: String, kind: LocalNameFilter.SuffixKind,
                      position: LocalNameFilter.MeaningPosition, replacing: String?, isNew: Bool) -> String? {
        let error = Store.shared.save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing)
        entries = Store.shared.entries()
        if error == nil { onSaved(key, isNew) }
        return error
    }

    private func restoreBundled(_ entry: LocalNameFilterSuffixEntry) {
        let error = Store.shared.restoreBundledValue(key: entry.key)
        entries = Store.shared.entries()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            onSaved(entry.key, false)
        }
    }
}
