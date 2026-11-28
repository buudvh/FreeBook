import SwiftUI

/// Màn **Quản lý tiền tố, hậu tố** của một name (2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung
/// M3 / M4 / M5 / M5b, plan mục C9) — mở từ nút tròn ⚙ cuối dòng "Tiền tố" ở màn Sửa từ của màn duyệt Lọc name local.
///
/// Kiểu thẻ chip như màn Quản lý nghĩa từ (`ManageDefinitionsView`): đầu màn là name + âm Hán-Việt, một thẻ bốn nhóm
/// Tiền tố · Riêng truyện / Tiền tố · Chung / Hậu tố · Riêng truyện / Hậu tố · Chung (`LocalNameFilterAffixManagerGroupView`).
/// **Chỉ mục nằm trong name** — cùng luật chip ✓ (`LocalNameFilterAffixListFlavor.usablePosition`: tiền tố ở đầu / giữa,
/// hậu tố ở cuối / giữa, 1–6 chữ), xếp theo số chữ tăng dần rồi vị trí; nhóm Chung giữ cả mục đang bị bản Riêng cùng chữ che
/// (chip mờ, ghi "bị che").
///
/// Mỗi thao tác **lưu ngay** rồi báo màn duyệt (`onChanged` ⇒ ghép lại nghĩa các name + toast "Đã … hậu tố X · ghép lại N
/// name"), không chờ đóng màn như Quản lý nghĩa từ:
/// - chạm chip ⇒ màn **Sửa từ** của mục đó (`LocalNameFilterSuffixEditorSheet`, R | C đúng phạm vi — M5b);
/// - ⓧ ⇒ hộp hỏi lại (M4: "Xoá hậu tố 语?", dòng phụ nói phạm vi) rồi xoá;
/// - "+ Thêm" ⇒ màn **Thêm từ** với cả cụm name để thu hẹp bằng ‹ ›, R | C chọn sẵn theo nhóm, loại mặc định = nhóm của name
///   (M5).
/// Lưu xong màn Sửa từ tự đóng ⇒ về đây, danh sách đọc lại.
struct LocalNameFilterAffixManagerView: View {
    typealias Flavor = LocalNameFilterAffixListFlavor
    typealias Scope = LocalNameFilterAffixListStore.Scope
    typealias Scoped = LocalNameFilterAffixScopedEntry
    typealias Editor = LocalNameFilterSuffixEditorSheet

    /// Một nhóm của thẻ: danh sách + phạm vi.
    private struct GroupKey: Hashable {
        let flavor: Flavor
        let scope: Scope
    }

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let flavor: Flavor
        /// Mục để sửa; `nil` = thêm vào nhóm `scope`.
        let item: Scoped?
        let scope: Scope
    }

    /// Thứ tự nhóm như mockup: tiền tố trên, hậu tố dưới; Riêng trước Chung.
    private static let groupOrder: [GroupKey] = [
        GroupKey(flavor: .prefix, scope: .book), GroupKey(flavor: .prefix, scope: .common),
        GroupKey(flavor: .suffix, scope: .book), GroupKey(flavor: .suffix, scope: .common)
    ]

    let name: String
    let bookId: String
    /// Loại gợi ý cho mục mới = nhóm của name.
    let kind: LocalNameFilter.SuffixKind
    /// Một thao tác đã ghi: danh sách, khoá, khoá cũ khi đổi chữ, động từ của toast ("Đã thêm" / "Đã lưu" / "Đã xoá").
    let onChanged: (_ flavor: Flavor, _ key: String, _ replaced: String?, _ verb: String) -> Void

    @State private var groups: [GroupKey: [Scoped]]
    @State private var editorTarget: EditorTarget? = nil
    @State private var deleteTarget: Scoped? = nil
    /// Danh sách của mục đang chờ hỏi xoá.
    @State private var deleteFlavor: Flavor = .suffix

    /// Tính một lần lúc mở: `body` chạy lại mỗi lần đọc lại danh sách, không tra `phienAmMap` ở đó.
    private let hanViet: String

    init(
        name: String,
        bookId: String,
        kind: LocalNameFilter.SuffixKind,
        onChanged: @escaping (_ flavor: Flavor, _ key: String, _ replaced: String?, _ verb: String) -> Void
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed
        self.bookId = bookId
        self.kind = kind
        self.onChanged = onChanged
        self.hanViet = LocalNameFilterAffixListStore.suggestedMeaning(for: trimmed)
        _groups = State(initialValue: Self.loadGroups(name: trimmed, bookId: bookId))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    wordHeader
                    groupsCard
                    statusLine
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .pageTitle("Tiền tố · Hậu tố")
            .presentationDragIndicator(.visible)
        }
        .onAppear { reload() }
        .sheet(item: $editorTarget) { target in
            Group {
                editor(for: target)
            }
            .appGlassSheet()
        }
        .alert(
            deleteTitle,
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { item in
            Button("Huỷ", role: .cancel) { deleteTarget = nil }
            Button("Xoá", role: .destructive) { delete(item, flavor: deleteFlavor) }
        } message: { item in
            Text(verbatim: deleteMessage(for: item, flavor: deleteFlavor))
        }
    }

    // MARK: - Bố cục

    private var wordHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: name)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(2)
            Text(verbatim: hanViet)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), phiên âm \(hanViet)")
    }

    private var groupsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.groupOrder.enumerated()), id: \.element) { index, key in
                if index > 0 {
                    Divider()
                        .padding(.leading, 14)
                }
                LocalNameFilterAffixManagerGroupView(
                    flavor: key.flavor,
                    scope: key.scope,
                    items: groups[key] ?? [],
                    shadowedKeys: shadowedKeys(for: key.flavor),
                    onTap: { item in
                        editorTarget = EditorTarget(flavor: key.flavor, item: item, scope: item.scope)
                    },
                    onDelete: { item in
                        deleteFlavor = key.flavor
                        deleteTarget = item
                    },
                    onAdd: {
                        editorTarget = EditorTarget(flavor: key.flavor, item: nil, scope: key.scope)
                    }
                )
            }
        }
        .background(AppGlassSheetModifier.rowFill, in: RoundedRectangle(cornerRadius: 14))
    }

    /// "Bản Riêng truyện thắng bản Chung cùng chữ (ở đây: 语)." + lời nhắc lưu ngay (mockup M3).
    private var statusLine: some View {
        var shadowed: [String] = []
        for flavor in [Flavor.prefix, .suffix] {
            let hidden = shadowedKeys(for: flavor)
            let commonKeys = (groups[GroupKey(flavor: flavor, scope: .common)] ?? []).map(\.key)
            shadowed.append(contentsOf: commonKeys.filter { hidden.contains($0) })
        }
        let example = shadowed.isEmpty ? "" : " (ở đây: \(shadowed.joined(separator: ", ")))"
        return Text(verbatim: "Bản Riêng truyện thắng bản Chung cùng chữ\(example).\n"
            + "Mỗi thao tác lưu ngay, rồi ghép lại nghĩa các name trong màn duyệt.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Đọc danh sách

    private static func loadGroups(name: String, bookId: String) -> [GroupKey: [Scoped]] {
        let scalars = Array(name.unicodeScalars)
        var result: [GroupKey: [Scoped]] = [:]
        for flavor in [Flavor.prefix, .suffix] {
            result[GroupKey(flavor: flavor, scope: .book)] =
                inName(Scoped.book(flavor: flavor, bookId: bookId), scalars: scalars, flavor: flavor)
            result[GroupKey(flavor: flavor, scope: .common)] =
                inName(Scoped.common(flavor: flavor), scalars: scalars, flavor: flavor)
        }
        return result
    }

    /// Mục nằm trong name (luật chip ✓), xếp theo số chữ tăng dần rồi vị trí trong name.
    private static func inName(_ items: [Scoped], scalars: [Unicode.Scalar], flavor: Flavor) -> [Scoped] {
        guard scalars.count >= 2 else { return [] }
        let placed: [(item: Scoped, length: Int, position: Int)] = items.compactMap { item in
            let key = Array(item.key.unicodeScalars)
            guard let position = flavor.usablePosition(of: key, in: scalars) else { return nil }
            return (item, key.count, position)
        }
        return placed.sorted { ($0.length, $0.position) < ($1.length, $1.position) }.map(\.item)
    }

    private func reload() {
        groups = Self.loadGroups(name: name, bookId: bookId)
    }

    /// Chữ có bản Riêng trong name ⇒ bản Chung cùng chữ đang bị che.
    private func shadowedKeys(for flavor: Flavor) -> Set<String> {
        Set((groups[GroupKey(flavor: flavor, scope: .book)] ?? []).map(\.key))
    }

    // MARK: - Sửa / thêm

    @ViewBuilder
    private func editor(for target: EditorTarget) -> some View {
        let flavor = target.flavor
        if let item = target.item {
            Editor(
                flavor: flavor,
                original: item.entry,
                originalScope: item.scope,
                bookId: bookId,
                // Chọn một phần của mục (兰街 ⇒ 街) = thêm mục mới (`original == nil`).
                onSave: { request in save(request, flavor: flavor, isNew: request.original == nil) },
                onRestoreBundled: { restoreBundled(item.entry, flavor: flavor) }
            )
        } else {
            // Cả cụm name để thu hẹp bằng ‹ › (mockup M5) — "Thêm" mờ cho tới khi phần chọn nằm cuối / đầu name.
            Editor(
                flavor: flavor,
                original: nil,
                initialKind: kind,
                source: Editor.Source(name: name, selection: NSRange(location: 0, length: (name as NSString).length)),
                bookId: bookId,
                initialScope: target.scope,
                onSave: { request in save(request, flavor: flavor, isNew: true) }
            )
        }
    }

    /// Ghi theo luật phạm vi của lõi; `nil` = đã lưu (màn Sửa từ tự đóng), chuỗi = lỗi để màn Sửa từ hiện.
    private func save(_ request: Editor.SaveRequest, flavor: Flavor, isNew: Bool) -> String? {
        let error = request.save(in: flavor.store, bookId: bookId)
        reload()
        if error == nil { onChanged(flavor, request.key, request.replacedKey, isNew ? "Đã thêm" : "Đã lưu") }
        return error
    }

    private func restoreBundled(_ entry: LocalNameFilterSuffixEntry, flavor: Flavor) {
        let error = flavor.store.restoreBundledValue(key: entry.key)
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            onChanged(flavor, entry.key, nil, "Đã lưu")
        }
    }

    // MARK: - Xoá (M4)

    private var deleteTitle: String {
        "Xoá \(deleteFlavor.lowercasedNoun) \(deleteTarget?.key ?? "")?"
    }

    /// Dòng phụ nói rõ phạm vi: Chung ⇒ mọi truyện; Riêng ⇒ chỉ truyện này (còn bản chung cùng chữ thì nói sẽ dùng lại).
    private func deleteMessage(for item: Scoped, flavor: Flavor) -> String {
        let regroup = "Name đang ghép bằng \(item.key) sẽ ghép lại nghĩa."
        switch item.scope {
        case .common:
            return "\(flavor.noun) chung — xoá khỏi danh sách của mọi truyện. \(regroup)"
        case .book:
            let hasCommon = flavor.store.entries().contains { $0.key == item.key }
            let fallback = hasCommon ? " Truyện này dùng lại bản chung \(item.key)." : ""
            return "\(flavor.noun) riêng — chỉ xoá khỏi truyện này.\(fallback) \(regroup)"
        }
    }

    private func delete(_ item: Scoped, flavor: Flavor) {
        deleteTarget = nil
        let error = flavor.store.delete(key: item.key, scope: item.scope, bookId: bookId)
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            onChanged(flavor, item.key, nil, "Đã xoá")
        }
    }
}
