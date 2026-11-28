import SwiftUI

/// Màn **Hậu tố** / **Tiền tố** của Lọc name local (plan 2026-11-27-phan-loai-name mockup khung 6 / 7) — một màn cho cả hai
/// danh sách, khác nhau ở `LocalNameFilterAffixListFlavor` (store, chữ, mặc định). Đẩy vào `NavigationStack` của sheet "Lọc
/// name local" từ mục "Danh sách". Khuôn màn Danh sách họ (`QuickTranslationSurnameListView`): header nút quay lại + `…`
/// (`.sideDrawerMenu`: Khôi phục mặc định), ô tìm luôn hiện (chữ Hán / nghĩa), hàng chip lọc theo loại kèm số
/// (`LocalNameFilterAffixKindFilterBar`: Tất cả / Địa danh / Tổ chức / Thuật ngữ / Nhân danh), nút `+` nổi, hàng
/// `LocalNameFilterSuffixRow` (chạm thân hàng mở màn Sửa từ `LocalNameFilterSuffixEditorSheet`, `[Xoá]`). Danh sách chỉ để
/// ghép nghĩa — việc dò dùng bộ hậu tố cố định của app.
///
/// Bản gốc đóng trong app; mọi thao tác chỉ ghi lớp riêng của store. Store không phát thay đổi ⇒ màn giữ bản chụp ở
/// `@State`, đọc lại sau **mọi** lần ghi và ở `onAppear`. Danh sách chung mọi truyện. Toast ở đây (Service không gọi
/// `ToastManager`).
struct LocalNameFilterSuffixListView: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Flavor = LocalNameFilterAffixListFlavor
    typealias Kind = LocalNameFilter.SuffixKind

    /// Đích của sheet sửa; `entry == nil` = thêm mục mới.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let entry: Entry?
    }

    let flavor: Flavor

    @State private var entries: [Entry]
    @State private var isCustomized: Bool
    @State private var searchText = ""
    /// Chip loại đang chọn; `nil` = Tất cả.
    @State private var kindFilter: Kind? = nil
    @State private var editorTarget: EditorTarget? = nil
    @State private var showingMenu = false
    @State private var confirmingReset = false

    init(flavor: Flavor = .suffix) {
        self.flavor = flavor
        _entries = State(initialValue: flavor.store.entries())
        _isCustomized = State(initialValue: flavor.store.isCustomized)
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Loại đang lọc có hiệu lực: loại đã chọn mà hết mục (vừa xoá mục cuối) ⇒ như Tất cả.
    private var activeKind: Kind? {
        guard let kindFilter, entries.contains(where: { $0.kind == kindFilter }) else { return nil }
        return kindFilter
    }

    private var kindEntries: [Entry] {
        guard let kind = activeKind else { return entries }
        return entries.filter { $0.kind == kind }
    }

    private var matchedEntries: [Entry] {
        let query = trimmedQuery
        guard !query.isEmpty else { return kindEntries }
        return kindEntries.filter {
            $0.key.contains(query) || $0.meaning.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// "1.190 hậu tố" theo chip đang chọn; đang tìm ⇒ số kết quả.
    private var sectionTitle: String {
        if !trimmedQuery.isEmpty {
            return "\(matchedEntries.count) kết quả cho \"\(trimmedQuery)\""
        }
        return "\(LocalNameFilterAffixKindFilterBar.formattedCount(kindEntries.count)) \(flavor.lowercasedNoun)"
    }

    private var emptyText: String {
        if !trimmedQuery.isEmpty { return "Không có \(flavor.lowercasedNoun) nào khớp." }
        if entries.isEmpty { return flavor.emptyListText }
        return "Chưa có \(flavor.lowercasedNoun) loại này. Bấm + để thêm."
    }

    var body: some View {
        VStack(spacing: 0) {
            LocalNameFilterAffixKindFilterBar(entries: entries, selection: $kindFilter)

            List { Group {
                Section {
                    let matched = matchedEntries
                    if matched.isEmpty {
                        Text(verbatim: emptyText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(matched) { entry in
                        LocalNameFilterSuffixRow(
                            entry: entry,
                            noun: flavor.lowercasedNoun,
                            onEdit: { editorTarget = EditorTarget(entry: entry) },
                            onDelete: { delete(entry) }
                        )
                    }
                } header: {
                    SectionHelpHeader(sectionTitle, paragraphs: flavor.listHelpParagraphs.map { LocalizedStringKey($0) })
                }
            }.glassSheetRows() }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm chữ Hán hoặc nghĩa")
        .backPageTitle(flavor.noun)
        .floatingAddButton("Thêm \(flavor.lowercasedNoun)") {
            editorTarget = EditorTarget(entry: nil)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                        .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tuỳ chọn danh sách \(flavor.lowercasedNoun)")
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: flavor.noun) {
            SideDrawerActionRow("Khôi phục mặc định", systemImage: "arrow.counterclockwise", role: .destructive) {
                confirmingReset = true
            }
            .disabled(!isCustomized)
        }
        .sheet(item: $editorTarget) { target in
            Group {
                LocalNameFilterSuffixEditorSheet(
                    flavor: flavor,
                    original: target.entry,
                    initialKind: activeKind,
                    onSave: { key, meaning, kind, position, replacing in
                        save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing)
                    },
                    onRestoreBundled: { restoreBundled(target.entry) }
                )
            }
            .appGlassSheet()
        }
        .confirmationDialog(
            "Khôi phục danh sách \(flavor.lowercasedNoun) mặc định?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Khôi phục mặc định", role: .destructive) { resetToDefaults() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Mọi \(flavor.lowercasedNoun) đã thêm, sửa hoặc xoá sẽ mất.")
        }
        .onAppear { reload() }
    }

    // MARK: - Thao tác

    private func reload() {
        entries = flavor.store.entries()
        isCustomized = flavor.store.isCustomized
    }

    /// Lưu từ sheet: store kiểm lại luật + trùng khoá trên dữ liệu mới nhất. `nil` = đã lưu; chuỗi = lỗi để sheet hiện.
    private func save(key: String, meaning: String, kind: Kind,
                      position: LocalNameFilter.MeaningPosition, replacing originalKey: String?) -> String? {
        let error = flavor.store.save(key: key, meaning: meaning, kind: kind, position: position, replacing: originalKey)
        reload()
        if let error { return error }
        let verb = originalKey == nil ? "Đã thêm" : "Đã lưu"
        ToastManager.shared.show(message: "\(verb) \(flavor.lowercasedNoun) \(key)", type: .success)
        return nil
    }

    /// Xoá một chạm như danh sách họ; mục gốc đã xoá thêm lại được, hoặc "Khôi phục mặc định".
    private func delete(_ entry: Entry) {
        report(flavor.store.delete(key: entry.key), success: "Đã xoá \(flavor.lowercasedNoun) \(entry.key)")
    }

    private func restoreBundled(_ entry: Entry?) {
        guard let entry, entry.bundledValue != nil else { return }
        report(flavor.store.restoreBundledValue(key: entry.key),
               success: "Đã đưa \(flavor.lowercasedNoun) \(entry.key) về bản gốc")
    }

    private func resetToDefaults() {
        flavor.store.resetToDefaults()
        reload()
        ToastManager.shared.show(message: "Đã khôi phục danh sách \(flavor.lowercasedNoun) mặc định", type: .success)
    }

    private func report(_ error: String?, success: String) {
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: success, type: .success)
        }
    }
}
