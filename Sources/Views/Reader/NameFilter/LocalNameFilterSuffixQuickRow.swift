import SwiftUI

/// Hàng **"Hậu tố"** hoặc **"Tiền tố"** (`LocalNameFilterAffixListFlavor`) ở màn Sửa từ khi mở từ màn duyệt Lọc name local
/// (plan 2026-11-27-phan-loai-name mục 7 / 10 / L10 / L11, mockup khung 2–3 — anh Bửu: "Ngoài lựa chọn nhanh hãy hiển thị
/// đủ các hậu tố và tiền tố nằm trong cụm", "sắp xếp theo thứ tự số từ tăng dần"). Mọi loại name trừ họ tộc
/// (`LocalNameFilterReviewSuffixContext.affixKind`).
///
/// Cuộn ngang, **mọi chip xếp theo số chữ tăng dần** (cùng số chữ ⇒ đứng trước trong name trước):
/// - chip ✓ cho **mọi** mục có sẵn của danh sách nằm **trong** cụm, dài 1–6 chữ: hậu tố ở cuối **hoặc giữa** cụm (còn ≥ 1
///   chữ phía trước), tiền tố ở đầu hoặc giữa cụm (còn ≥ 1 chữ phía sau) — "✓ 长老 · trưởng lão · Nhân danh", chạm ⇒ sửa
///   mục đó. Mục đang dùng để ghép nghĩa (hậu tố dài nhất ở **cuối**, tiền tố dài nhất ở **đầu**, cùng nhóm với name như bộ
///   ghép nghĩa: loại Nhân danh ⇄ tên người, loại khác ⇄ name không phải người) có dấu ●;
/// - chip "+ X" cho đoạn cuối (hậu tố) / đầu (tiền tố) 1–3 chữ toàn chữ Hán chưa có trong danh sách, chừa ≥ 1 chữ phía bên
///   kia — chạm ⇒ màn thêm với đúng đoạn đó đã chọn (vẫn nới / thu được bằng ‹ ›);
/// - cuối hàng: "+ Thêm hậu tố / tiền tố" ⇒ màn thêm với **nguyên cụm** name, người dùng thu hẹp bằng ‹ ›.
/// Màn thêm / sửa là `LocalNameFilterSuffixEditorSheet` (chế độ thêm từ name hoặc sửa mục có sẵn), ghi qua store của danh
/// sách như màn danh sách. Lưu được ⇒ `onSaved` (màn duyệt ghép lại nghĩa + toast).
struct LocalNameFilterSuffixQuickRow: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Flavor = LocalNameFilterAffixListFlavor

    let flavor: Flavor
    let name: String
    /// Loại gợi ý cho mục mới = nhóm của name (`.person` cho tên người).
    let kind: LocalNameFilter.SuffixKind
    /// Mục vừa lưu; `replaced` = khoá cũ khi sửa mục có sẵn mà đổi chữ (街 ⇒ 兰街) — màn duyệt ghép lại cả name mang khoá
    /// cũ; `isNew` = thêm mới (không phải sửa mục có sẵn).
    let onSaved: (_ key: String, _ replaced: String?, _ isNew: Bool) -> Void

    /// Một chip: mục có sẵn (`entry != nil`, ✓) hoặc đoạn đầu / cuối gợi ý thêm (`entry == nil`, +).
    private struct Chip: Identifiable {
        let key: String
        /// Số chữ (code point).
        let length: Int
        /// Vị trí (code point) của lần xuất hiện dùng được đầu tiên trong name — xếp chip cùng số chữ.
        let position: Int
        let entry: Entry?
        var id: String { key }
    }

    private struct EditorTarget: Identifiable {
        let id = UUID()
        /// Mục có sẵn để sửa; `nil` = thêm từ name với vùng chọn `selection`.
        let entry: Entry?
        let selection: NSRange
    }

    private static let quickLengths = 1...3

    @State private var entries: [Entry]
    @State private var target: EditorTarget? = nil

    init(
        flavor: Flavor,
        name: String,
        kind: LocalNameFilter.SuffixKind,
        onSaved: @escaping (_ key: String, _ replaced: String?, _ isNew: Bool) -> Void
    ) {
        self.flavor = flavor
        self.name = name
        self.kind = kind
        self.onSaved = onSaved
        _entries = State(initialValue: flavor.store.entries())
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let scalars = Array(trimmedName.unicodeScalars)
        let chips = Self.chips(in: scalars, entries: entries, flavor: flavor)
        let activeKey = Self.activeKey(in: scalars, entries: entries, flavor: flavor, isPerson: kind == .person)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(verbatim: flavor.noun)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                SectionHelpButton(
                    accessibilityLabel: "Giải thích \(flavor.noun)",
                    paragraphs: flavor.quickRowHelpParagraphs.map { LocalizedStringKey($0) }
                )
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        chipButton(chip, isActive: chip.key == activeKey)
                    }
                    Button {
                        open(entry: nil, piece: nil)
                    } label: {
                        chipLabel("+ Thêm \(flavor.lowercasedNoun)", highlighted: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { entries = flavor.store.entries() }
        .sheet(item: $target) { target in
            Group {
                editor(for: target)
            }
            .appGlassSheet()
        }
    }

    // MARK: - Tính chip (theo code point, không theo UTF-16)

    /// Chip ✓ + chip "+" (xem doc của type), xếp theo số chữ tăng dần rồi theo vị trí trong name.
    private static func chips(in scalars: [Unicode.Scalar], entries: [Entry], flavor: Flavor) -> [Chip] {
        guard scalars.count >= 2 else { return [] }
        var result: [Chip] = []
        var seen = Set<String>()
        for entry in entries where !seen.contains(entry.key) {
            let key = Array(entry.key.unicodeScalars)
            guard let position = usablePosition(of: key, in: scalars, flavor: flavor) else { continue }
            seen.insert(entry.key)
            result.append(Chip(key: entry.key, length: key.count, position: position, entry: entry))
        }
        for length in quickLengths where length < scalars.count {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: flavor == .suffix ? scalars.suffix(length) : scalars.prefix(length))
            let piece = String(view)
            guard LocalNameFilterSuffixListParser.isHanText(piece), !seen.contains(piece) else { continue }
            seen.insert(piece)
            let position = flavor == .suffix ? scalars.count - length : 0
            result.append(Chip(key: piece, length: length, position: position, entry: nil))
        }
        return result.sorted { ($0.length, $0.position) < ($1.length, $1.position) }
    }

    /// Lần xuất hiện đầu tiên của `key` mà còn ≥ 1 chữ phía trước (hậu tố) / phía sau (tiền tố); `nil` = không có (cả cụm,
    /// hậu tố chỉ nằm đầu cụm, tiền tố chỉ nằm cuối cụm, dài quá 6 chữ).
    private static func usablePosition(of key: [Unicode.Scalar], in scalars: [Unicode.Scalar], flavor: Flavor) -> Int? {
        let length = key.count
        guard length >= 1, length <= LocalNameFilterSuffixListParser.maxKeyLength, length < scalars.count else {
            return nil
        }
        for start in 0...(scalars.count - length) where scalars[start..<(start + length)].elementsEqual(key) {
            switch flavor {
            case .suffix where start >= 1: return start
            case .prefix where start + length <= scalars.count - 1: return start
            default: continue
            }
        }
        return nil
    }

    /// Khoá đang dùng để ghép nghĩa (dấu ●): mục dài nhất ở **cuối** (hậu tố, còn ≥ 1 chữ phía trước) / **đầu** (tiền tố,
    /// còn ≥ 2 chữ phía sau như bộ ghép) cùng nhóm với name — loại Nhân danh cho tên người, loại khác cho name không phải
    /// người (`LocalNameFilterSetup.meaningSuffix` / `personTitle`, `LocalNameFilterProperNames.prefixed`). Không xét các
    /// điều kiện còn lại của bộ ghép (tên Latin sau tiền tố, danh xưng 1 chữ cần ≥ 3 tên).
    private static func activeKey(
        in scalars: [Unicode.Scalar],
        entries: [Entry],
        flavor: Flavor,
        isPerson: Bool
    ) -> String? {
        let minimumRest = flavor == .suffix ? 1 : 2
        var best: (key: String, length: Int)?
        for entry in entries where (entry.kind == .person) == isPerson {
            let key = Array(entry.key.unicodeScalars)
            guard !key.isEmpty, scalars.count - key.count >= minimumRest else { continue }
            let matches = flavor == .suffix ? scalars.suffix(key.count).elementsEqual(key)
                : scalars.prefix(key.count).elementsEqual(key)
            if matches, key.count > (best?.length ?? 0) { best = (entry.key, key.count) }
        }
        return best?.key
    }

    // MARK: - Chip

    @ViewBuilder
    private func chipButton(_ chip: Chip, isActive: Bool) -> some View {
        if let entry = chip.entry {
            let text = "✓ \(chip.key) · \(entry.meaning) · \(LocalNameFilterSuffixRow.kindLabel(entry.kind))"
            Button {
                open(entry: entry, piece: nil)
            } label: {
                chipLabel(isActive ? "● " + text : text, highlighted: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sửa \(flavor.lowercasedNoun) \(chip.key)\(isActive ? ", đang dùng để ghép nghĩa" : "")")
        } else {
            Button {
                open(entry: nil, piece: chip.key)
            } label: {
                chipLabel("+ \(chip.key)", highlighted: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thêm \(flavor.lowercasedNoun) \(chip.key)")
        }
    }

    /// Chip kiểu chip lọc của app: mục đã có ⇒ chữ màu nhấn, nền nhấn mờ, viền nhấn; còn lại nền xám mờ.
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

    /// `piece == nil` ⇒ nguyên cụm name; đoạn gợi ý nằm cuối (hậu tố) / đầu (tiền tố) name. Vùng chọn tính theo UTF-16 như
    /// màn Sửa từ.
    private func open(entry: Entry?, piece: String?) {
        let total = (trimmedName as NSString).length
        let length = piece.map { ($0 as NSString).length } ?? total
        let location = flavor == .suffix ? total - length : 0
        target = EditorTarget(entry: entry, selection: NSRange(location: location, length: length))
    }

    @ViewBuilder
    private func editor(for target: EditorTarget) -> some View {
        if let entry = target.entry {
            LocalNameFilterSuffixEditorSheet(
                flavor: flavor,
                original: entry,
                onSave: { key, meaning, kind, position, replacing in
                    // Chọn một phần của mục đang có (兰街 ⇒ 街) = thêm mục mới (`replacing == nil`).
                    save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing,
                         isNew: replacing == nil)
                },
                onRestoreBundled: { restoreBundled(entry) }
            )
        } else {
            LocalNameFilterSuffixEditorSheet(
                flavor: flavor,
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
        let error = flavor.store.save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing)
        entries = flavor.store.entries()
        if error == nil { onSaved(key, replacing == key ? nil : replacing, isNew) }
        return error
    }

    private func restoreBundled(_ entry: Entry) {
        let error = flavor.store.restoreBundledValue(key: entry.key)
        entries = flavor.store.entries()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            onSaved(entry.key, nil, false)
        }
    }
}
