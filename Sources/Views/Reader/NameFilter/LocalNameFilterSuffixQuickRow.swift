import SwiftUI

/// Hàng **"Hậu tố"** hoặc **"Tiền tố"** (`LocalNameFilterAffixListFlavor`) ở màn Sửa từ khi mở từ màn duyệt Lọc name local
/// (plan 2026-11-27-phan-loai-name mục 7 / 10 / L10 / L11, mockup khung 2–3 — anh Bửu: "Ngoài lựa chọn nhanh hãy hiển thị
/// đủ các hậu tố và tiền tố nằm trong cụm", "sắp xếp theo thứ tự số từ tăng dần"). Mọi loại name trừ họ tộc
/// (`LocalNameFilterReviewSuffixContext.affixKind`).
///
/// Đọc danh sách **hiệu lực của truyện** (2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2):
/// mục Riêng truyện rồi mục Chung không trùng chữ — cùng chữ thì bản Riêng thắng (`LocalNameFilterAffixScopedEntry.effective`).
///
/// Cuộn ngang, **mọi chip xếp theo số chữ tăng dần** (cùng số chữ ⇒ đứng trước trong name trước):
/// - chip ✓ cho **mọi** mục hiệu lực nằm **trong** cụm, dài 1–6 chữ (`Flavor.usablePosition`): hậu tố ở cuối **hoặc giữa**
///   cụm (còn ≥ 1 chữ phía trước), tiền tố ở đầu hoặc giữa cụm (còn ≥ 1 chữ phía sau) — "✓ 长老 · trưởng lão · Nhân danh",
///   chạm ⇒ sửa mục đó ở **đúng phạm vi** của nó (cụm R | C chọn sẵn). Mục đang dùng để ghép nghĩa (hậu tố dài nhất ở
///   **cuối**, tiền tố dài nhất ở **đầu**, cùng nhóm với name như bộ ghép nghĩa: loại Nhân danh ⇄ tên người, loại khác ⇄
///   name không phải người — tính trên danh sách hiệu lực) có dấu ●. Màn sửa mở với **cả name**, chữ của mục chọn sẵn
///   (mockup M5b) — nới / thu bằng ‹ › là đổi chữ của mục;
/// - chip "+ X" cho đoạn cuối (hậu tố) / đầu (tiền tố) 1–3 chữ toàn chữ Hán chưa có trong danh sách hiệu lực, chừa ≥ 1 chữ
///   phía bên kia — chạm ⇒ màn thêm với đúng đoạn đó đã chọn (vẫn nới / thu được bằng ‹ ›);
/// - cuối hàng: "+ Thêm hậu tố / tiền tố" ⇒ màn thêm với **nguyên cụm** name, người dùng thu hẹp bằng ‹ ›.
/// Thêm mới mặc định vào **R** (Riêng truyện), đổi được ở cụm R | C. Không có thao tác nhấn giữ — xoá ở màn Quản lý
/// (nút ⚙ cuối dòng nhãn "Tiền tố", `onManage`).
/// Màn thêm / sửa là `LocalNameFilterSuffixEditorSheet` (chế độ thêm từ name hoặc sửa mục có sẵn), ghi theo luật phạm vi của
/// lõi. Lưu được ⇒ `onSaved` (màn duyệt ghép lại nghĩa + toast).
struct LocalNameFilterSuffixQuickRow: View {
    typealias Scoped = LocalNameFilterAffixScopedEntry
    typealias Flavor = LocalNameFilterAffixListFlavor
    typealias Editor = LocalNameFilterSuffixEditorSheet

    let flavor: Flavor
    let name: String
    /// Truyện đang duyệt — danh sách hiệu lực + phạm vi R.
    let bookId: String
    /// Loại gợi ý cho mục mới = nhóm của name (`.person` cho tên người).
    let kind: LocalNameFilter.SuffixKind
    /// Tăng khi danh sách bị sửa ở chỗ khác (hàng còn lại, màn Quản lý) ⇒ đọc lại.
    let revision: Int
    /// Nút tròn ⚙ cuối dòng nhãn ⇒ màn Quản lý tiền tố, hậu tố (chỉ hàng "Tiền tố", mockup M2); `nil` = không có.
    let onManage: (() -> Void)?
    /// Mục vừa lưu; `replaced` = khoá cũ khi sửa mục có sẵn mà đổi chữ (街 ⇒ 兰街) — màn duyệt ghép lại cả name mang khoá
    /// cũ; `isNew` = thêm mới (không phải sửa mục có sẵn).
    let onSaved: (_ key: String, _ replaced: String?, _ isNew: Bool) -> Void

    /// Một chip: mục có sẵn (`item != nil`, ✓) hoặc đoạn đầu / cuối gợi ý thêm (`item == nil`, +).
    private struct Chip: Identifiable {
        let key: String
        /// Số chữ (code point).
        let length: Int
        /// Vị trí (code point) của lần xuất hiện dùng được đầu tiên trong name — xếp chip cùng số chữ.
        let position: Int
        let item: Scoped?
        var id: String { key }
    }

    private struct EditorTarget: Identifiable {
        let id = UUID()
        /// Mục có sẵn để sửa; `nil` = thêm từ name với vùng chọn `selection`.
        let item: Scoped?
        let selection: NSRange
    }

    private static let quickLengths = 1...3

    @State private var entries: [Scoped]
    @State private var target: EditorTarget? = nil

    init(
        flavor: Flavor,
        name: String,
        bookId: String,
        kind: LocalNameFilter.SuffixKind,
        revision: Int = 0,
        onManage: (() -> Void)? = nil,
        onSaved: @escaping (_ key: String, _ replaced: String?, _ isNew: Bool) -> Void
    ) {
        self.flavor = flavor
        self.name = name
        self.bookId = bookId
        self.kind = kind
        self.revision = revision
        self.onManage = onManage
        self.onSaved = onSaved
        _entries = State(initialValue: Scoped.effective(flavor: flavor, bookId: bookId))
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
                if let onManage { manageButton(action: onManage) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        chipButton(chip, isActive: chip.key == activeKey)
                    }
                    Button {
                        open(item: nil, piece: nil)
                    } label: {
                        chipLabel("+ Thêm \(flavor.lowercasedNoun)", highlighted: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { reload() }
        .onChange(of: revision) { _, _ in reload() }
        .sheet(item: $target) { target in
            Group {
                editor(for: target)
            }
            .appGlassSheet()
        }
    }

    private func reload() {
        entries = Scoped.effective(flavor: flavor, bookId: bookId)
    }

    /// Nút tròn ⚙ — cùng dáng nút Quản lý nghĩa từ của màn Sửa từ (`slider.horizontal.3`), viền + icon màu nhấn như mockup.
    private func manageButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .padding(8)
                .background(Color.primary.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quản lý tiền tố, hậu tố")
    }

    // MARK: - Tính chip (theo code point, không theo UTF-16)

    /// Chip ✓ + chip "+" (xem doc của type), xếp theo số chữ tăng dần rồi theo vị trí trong name.
    private static func chips(in scalars: [Unicode.Scalar], entries: [Scoped], flavor: Flavor) -> [Chip] {
        guard scalars.count >= 2 else { return [] }
        var result: [Chip] = []
        var seen = Set<String>()
        for item in entries where !seen.contains(item.key) {
            let key = Array(item.key.unicodeScalars)
            guard let position = flavor.usablePosition(of: key, in: scalars) else { continue }
            seen.insert(item.key)
            result.append(Chip(key: item.key, length: key.count, position: position, item: item))
        }
        for length in quickLengths where length < scalars.count {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: flavor == .suffix ? scalars.suffix(length) : scalars.prefix(length))
            let piece = String(view)
            guard LocalNameFilterSuffixListParser.isHanText(piece), !seen.contains(piece) else { continue }
            seen.insert(piece)
            let position = flavor == .suffix ? scalars.count - length : 0
            result.append(Chip(key: piece, length: length, position: position, item: nil))
        }
        return result.sorted { ($0.length, $0.position) < ($1.length, $1.position) }
    }

    /// Khoá đang dùng để ghép nghĩa (dấu ●) trên danh sách hiệu lực: mục dài nhất ở **cuối** (hậu tố, còn ≥ 1 chữ phía
    /// trước) / **đầu** (tiền tố, còn ≥ 2 chữ phía sau như bộ ghép) cùng nhóm với name — loại Nhân danh cho tên người, loại
    /// khác cho name không phải người (`LocalNameFilterSetup.meaningSuffix` / `personTitle`,
    /// `LocalNameFilterProperNames.prefixed`). Không xét các điều kiện còn lại của bộ ghép (tên Latin sau tiền tố, danh xưng
    /// 1 chữ cần ≥ 3 tên, tách tiền tố / hậu tố mọi loại của tên Latin).
    private static func activeKey(
        in scalars: [Unicode.Scalar],
        entries: [Scoped],
        flavor: Flavor,
        isPerson: Bool
    ) -> String? {
        let minimumRest = flavor == .suffix ? 1 : 2
        var best: (key: String, length: Int)?
        for item in entries where (item.entry.kind == .person) == isPerson {
            let key = Array(item.key.unicodeScalars)
            guard !key.isEmpty, scalars.count - key.count >= minimumRest else { continue }
            let matches = flavor == .suffix ? scalars.suffix(key.count).elementsEqual(key)
                : scalars.prefix(key.count).elementsEqual(key)
            if matches, key.count > (best?.length ?? 0) { best = (item.key, key.count) }
        }
        return best?.key
    }

    // MARK: - Chip

    @ViewBuilder
    private func chipButton(_ chip: Chip, isActive: Bool) -> some View {
        if let item = chip.item {
            let text = "✓ \(chip.key) · \(item.entry.meaning) · \(LocalNameFilterSuffixRow.kindLabel(item.entry.kind))"
            let scopeText = item.scope == .book ? "riêng truyện" : "chung"
            Button {
                open(item: item, piece: nil)
            } label: {
                chipLabel(isActive ? "● " + text : text, highlighted: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Sửa \(flavor.lowercasedNoun) \(chip.key), \(scopeText)\(isActive ? ", đang dùng để ghép nghĩa" : "")"
            )
        } else {
            Button {
                open(item: nil, piece: chip.key)
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
    private func open(item: Scoped?, piece: String?) {
        let total = (trimmedName as NSString).length
        let length = piece.map { ($0 as NSString).length } ?? total
        let location = flavor == .suffix ? total - length : 0
        target = EditorTarget(item: item, selection: NSRange(location: location, length: length))
    }

    @ViewBuilder
    private func editor(for target: EditorTarget) -> some View {
        if let item = target.item {
            // Cả name, chữ của mục chọn sẵn (M5b): chọn chữ khác = đổi chữ của mục (`original` vẫn là mục này).
            Editor(
                flavor: flavor,
                original: item.entry,
                originalScope: item.scope,
                source: flavor.selection(of: item.key, in: trimmedName).map {
                    Editor.Source(name: trimmedName, selection: $0)
                },
                bookId: bookId,
                onSave: { request in save(request, isNew: request.original == nil) },
                onRestoreBundled: { restoreBundled(item.entry) }
            )
        } else {
            Editor(
                flavor: flavor,
                original: nil,
                initialKind: kind,
                source: Editor.Source(name: trimmedName, selection: target.selection),
                bookId: bookId,
                initialScope: .book,
                onSave: { request in save(request, isNew: true) }
            )
        }
    }

    /// Ghi theo luật phạm vi của lõi (kiểm lại luật + trùng khoá trên dữ liệu mới nhất). `nil` = đã lưu; chuỗi = lỗi để màn
    /// sửa hiện.
    private func save(_ request: Editor.SaveRequest, isNew: Bool) -> String? {
        let error = request.save(in: flavor.store, bookId: bookId)
        reload()
        if error == nil { onSaved(request.key, request.replacedKey, isNew) }
        return error
    }

    private func restoreBundled(_ entry: LocalNameFilterSuffixEntry) {
        let error = flavor.store.restoreBundledValue(key: entry.key)
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            onSaved(entry.key, nil, false)
        }
    }
}
