import SwiftUI

/// Màn **Đuôi địa danh, tổ chức, thuật ngữ** của Lọc name local (mockup khung 5, bản LAC khung 4) — đẩy vào
/// `NavigationStack` của sheet "Lọc name local" từ mục "Danh sách". Khuôn màn Danh sách họ
/// (`QuickTranslationSurnameListView`): header nút quay lại + `…` (`.sideDrawerMenu`: Khôi phục mặc định), ô tìm luôn hiện
/// (chữ Hán / nghĩa), tab Tất cả / Địa danh / Tổ chức / Thuật ngữ, nút `+`
/// nổi, hàng `LocalNameFilterSuffixRow` (chạm thân hàng mở màn Sửa từ `LocalNameFilterSuffixEditorSheet`, `[Tắt/Bật] [Xoá]`).
///
/// Bản gốc đóng trong app; mọi thao tác chỉ ghi lớp riêng (`LocalNameFilterSuffixStore`). Store không phát thay đổi ⇒ màn
/// giữ bản chụp ở `@State`, đọc lại sau **mọi** lần ghi và ở `onAppear`. Danh sách chung mọi truyện. Toast ở đây (Service
/// không gọi `ToastManager`).
struct LocalNameFilterSuffixListView: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Store = LocalNameFilterSuffixStore

    private enum Tab: Hashable, CaseIterable {
        case all
        case place
        case sect
        case term

        var title: String {
            kind.map(LocalNameFilterSuffixRow.kindLabel) ?? "Tất cả"
        }

        var kind: LocalNameFilter.SuffixKind? {
            switch self {
            case .all: return nil
            case .place: return .place
            case .sect: return .sect
            case .term: return .term
            }
        }
    }

    /// Đích của sheet sửa; `entry == nil` = thêm đuôi mới.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let entry: Entry?
    }

    private static let title = "Đuôi địa danh, tổ chức, thuật ngữ"

    @State private var entries: [Entry] = Store.shared.entries()
    @State private var isCustomized = Store.shared.isCustomized
    @State private var searchText = ""
    @State private var tab: Tab = .all
    @State private var editorTarget: EditorTarget?
    @State private var showingMenu = false
    @State private var confirmingReset = false

    init() {}

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tabEntries: [Entry] {
        guard let kind = tab.kind else { return entries }
        return entries.filter { $0.kind == kind }
    }

    private var matchedEntries: [Entry] {
        let query = trimmedQuery
        guard !query.isEmpty else { return tabEntries }
        return tabEntries.filter {
            $0.key.contains(query) || $0.meaning.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// "63 đuôi · 4 đang tắt" theo tab đang chọn; đang tìm ⇒ số kết quả.
    private var sectionTitle: String {
        if !trimmedQuery.isEmpty {
            return "\(matchedEntries.count) kết quả cho \"\(trimmedQuery)\""
        }
        let shown = tabEntries
        let disabled = shown.filter { !$0.isEnabled }.count
        return disabled > 0 ? "\(shown.count) đuôi · \(disabled) đang tắt" : "\(shown.count) đuôi"
    }

    private var emptyText: String {
        if !trimmedQuery.isEmpty { return "Không có đuôi nào khớp." }
        if entries.isEmpty {
            return "Danh sách đuôi đang trống: bộ lọc sẽ khó nhận ra địa danh / tổ chức / thuật ngữ. Bấm + để thêm."
        }
        return "Chưa có đuôi loại này. Bấm + để thêm."
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Loại đuôi", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, HeaderMetrics.horizontalMargin)
            .padding(.vertical, 8)

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
                            onEdit: { editorTarget = EditorTarget(entry: entry) },
                            onToggle: { toggle(entry) },
                            onDelete: { delete(entry) }
                        )
                    }
                } header: {
                    SectionHelpHeader(sectionTitle, paragraphs: [
                        "Cụm chữ Hán kết thúc bằng một đuôi **đang bật** (落霞**镇**, 天斗**帝国**, 史莱克**学院**, 五气**丹**) được xét là địa danh, tổ chức hoặc thuật ngữ theo loại của đuôi. Đuôi tắt vẫn nằm trong danh sách nhưng bộ lọc bỏ qua.",
                        "Nghĩa đề xuất = phần tên riêng viết hoa + nghĩa của đuôi giữ nguyên chữ, đặt **sau tên** (落霞镇 → Lạc Hà trấn, 五气丹 → Ngũ Khí đan) hoặc **trước tên** (市 = \"thành phố\" · trước tên ⇒ 江海市 → thành phố Giang Hải).",
                        "Danh sách dùng chung mọi truyện. \"Khôi phục mặc định\" ở menu … bỏ mọi đuôi đã thêm, sửa, xoá hoặc bật / tắt."
                    ])
                }
            }.glassSheetRows() }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm chữ Hán hoặc nghĩa")
        .backPageTitle(Self.title)
        .floatingAddButton("Thêm đuôi") {
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
                .accessibilityLabel("Tuỳ chọn danh sách đuôi")
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: Self.title) {
            SideDrawerActionRow("Khôi phục mặc định", systemImage: "arrow.counterclockwise", role: .destructive) {
                confirmingReset = true
            }
            .disabled(!isCustomized)
        }
        .sheet(item: $editorTarget) { target in
            Group {
                LocalNameFilterSuffixEditorSheet(
                    original: target.entry,
                    initialKind: tab.kind ?? .place,
                    onSave: { key, meaning, kind, position, replacing in
                        save(key: key, meaning: meaning, kind: kind, position: position, replacing: replacing)
                    },
                    onRestoreBundled: { restoreBundled(target.entry) }
                )
            }
            .appGlassSheet()
        }
        .confirmationDialog("Khôi phục danh sách đuôi mặc định?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Khôi phục mặc định", role: .destructive) { resetToDefaults() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Mọi đuôi đã thêm, sửa, xoá hoặc bật / tắt sẽ mất.")
        }
        .onAppear { reload() }
    }

    // MARK: - Thao tác

    private func reload() {
        entries = Store.shared.entries()
        isCustomized = Store.shared.isCustomized
    }

    /// Lưu từ sheet: store kiểm lại luật + trùng khoá trên dữ liệu mới nhất. `nil` = đã lưu; chuỗi = lỗi để sheet hiện.
    private func save(key: String, meaning: String, kind: LocalNameFilter.SuffixKind,
                      position: LocalNameFilter.MeaningPosition, replacing originalKey: String?) -> String? {
        let error = Store.shared.save(key: key, meaning: meaning, kind: kind, position: position, replacing: originalKey)
        reload()
        if let error { return error }
        ToastManager.shared.show(message: originalKey == nil ? "Đã thêm đuôi \(key)" : "Đã lưu đuôi \(key)", type: .success)
        return nil
    }

    private func toggle(_ entry: Entry) {
        report(Store.shared.setEnabled(!entry.isEnabled, key: entry.key),
               success: entry.isEnabled ? "Đã tắt đuôi \(entry.key)" : "Đã bật đuôi \(entry.key)")
    }

    /// Xoá một chạm như danh sách họ; đuôi gốc đã xoá thêm lại được, hoặc "Khôi phục mặc định".
    private func delete(_ entry: Entry) {
        report(Store.shared.delete(key: entry.key), success: "Đã xoá đuôi \(entry.key)")
    }

    private func restoreBundled(_ entry: Entry?) {
        guard let entry, entry.bundledValue != nil else { return }
        report(Store.shared.restoreBundledValue(key: entry.key), success: "Đã đưa đuôi \(entry.key) về bản gốc")
    }

    private func resetToDefaults() {
        Store.shared.resetToDefaults()
        reload()
        ToastManager.shared.show(message: "Đã khôi phục danh sách đuôi mặc định", type: .success)
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
