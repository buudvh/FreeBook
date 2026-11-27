import SwiftUI

/// Màn **Không phải name** của Lọc name local (mockup khung 6) — đẩy vào `NavigationStack` của sheet "Lọc name local" từ
/// mục "Danh sách". Kiểu màn danh sách: header nút quay lại + `…` (`.sideDrawerMenu`: Xoá hết), ô tìm luôn hiện (chữ Hán /
/// âm Hán-Việt), tiêu đề section "N cụm", hàng `LocalNameFilterBlocklistRow` (chạm thân hàng mở màn Sửa từ, 🗑), nút `+`
/// nổi mở cùng màn ở chế độ thêm — `LocalNameFilterBlocklistEditorSheet`.
///
/// Store (`LocalNameFilterBlocklistStore`) không phát thay đổi ⇒ màn giữ bản chụp ở `@State`, đọc lại sau mọi lần ghi và
/// ở `onAppear` (cụm thêm từ màn duyệt hiện ra khi quay lại). Âm Hán-Việt tính một lần mỗi lần đọc lại, không trong `body`.
struct LocalNameFilterBlocklistView: View {
    typealias Store = LocalNameFilterBlocklistStore

    private struct Item: Identifiable {
        let term: String
        /// Âm Hán-Việt viết thường ("đường tam tố") — dùng cả cho tìm kiếm.
        let reading: String
        /// "đường tam tố · thêm 26/11".
        let subtitle: String

        var id: String { term }
    }

    /// Đích của màn Sửa từ; `term == nil` = thêm cụm mới.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let term: String?
    }

    private static let title = "Không phải name"

    /// "dd/MM" cố định, không theo vùng máy.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    @State private var items: [Item] = []
    @State private var searchText = ""
    @State private var editorTarget: EditorTarget?
    @State private var showingMenu = false
    @State private var confirmingClear = false

    init() {}

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchedItems: [Item] {
        let query = trimmedQuery
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.term.contains(query) || $0.reading.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var sectionTitle: String {
        trimmedQuery.isEmpty ? "\(items.count) cụm" : "\(matchedItems.count) kết quả cho \"\(trimmedQuery)\""
    }

    var body: some View {
        List { Group {
            Section {
                let matched = matchedItems
                if matched.isEmpty {
                    Text(verbatim: items.isEmpty
                         ? "Chưa có cụm nào. Thêm từ màn duyệt (✕ › Không phải name) hoặc bấm +."
                         : "Không có cụm nào khớp.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(matched) { item in
                    LocalNameFilterBlocklistRow(
                        term: item.term,
                        subtitle: item.subtitle,
                        onEdit: { editorTarget = EditorTarget(term: item.term) },
                        onDelete: { remove(item.term) }
                    )
                }
            } header: {
                SectionHelpHeader(sectionTitle, paragraphs: [
                    "Cụm chữ Hán không phải name, dùng chung mọi truyện. Lọc name local bỏ đúng các cụm này khỏi kết quả, không đổi cách xét các cụm khác.",
                    "Khớp **nguyên cụm**: chặn 唐三做 không làm 唐三 biến mất."
                ])
            }
        }.glassSheetRows() }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm chữ Hán hoặc âm Hán-Việt")
        .backPageTitle(Self.title)
        .floatingAddButton("Thêm cụm") {
            editorTarget = EditorTarget(term: nil)
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
                .accessibilityLabel("Tuỳ chọn danh sách Không phải name")
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: Self.title) {
            SideDrawerActionRow("Xoá hết", systemImage: "trash", role: .destructive) {
                confirmingClear = true
            }
            .disabled(items.isEmpty)
        }
        .sheet(item: $editorTarget) { target in
            Group {
                LocalNameFilterBlocklistEditorSheet(original: target.term) { term, replacing in
                    save(term, replacing: replacing)
                }
            }
            .appGlassSheet()
        }
        .confirmationDialog("Xoá hết danh sách “Không phải name”?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Xoá hết \(items.count) cụm", role: .destructive) { removeAll() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Lần lọc sau các cụm này có thể hiện lại.")
        }
        .onAppear { reload() }
    }

    // MARK: - Thao tác

    private func reload() {
        let phienAm = TranslationManager.shared.phienAmMap
        items = Store.shared.entries().map { entry in
            let reading = Self.reading(of: entry.term, phienAm: phienAm)
            let day = Self.dayFormatter.string(from: entry.addedAt)
            return Item(term: entry.term, reading: reading, subtitle: "\(reading) · thêm \(day)")
        }
    }

    /// Âm Hán-Việt viết thường, mỗi chữ lấy âm đầu (`TranslateUtils.getFirstMeaning`); chữ không có âm giữ nguyên.
    private static func reading(of term: String, phienAm: [String: String]) -> String {
        term.map { character -> String in
            let key = String(character)
            guard let raw = phienAm[key] else { return key }
            let first = TranslateUtils.getFirstMeaning(of: raw)
            return first.isEmpty ? key : first
        }
        .joined(separator: " ")
        .lowercased()
    }

    /// Lưu từ màn Sửa từ: `replacing == nil` ⇒ thêm cụm; khác ⇒ đổi cụm đó thành `term` (giữ nguyên ⇒ không làm gì,
    /// không toast). `nil` = đã lưu; chuỗi = lỗi để sheet hiện.
    private func save(_ term: String, replacing originalTerm: String?) -> String? {
        if let originalTerm, originalTerm == term { return nil }
        let error: String?
        if let originalTerm {
            error = Store.shared.replace(originalTerm, with: term)
        } else {
            error = Store.shared.add(term)
        }
        reload()
        if let error { return error }
        let message = originalTerm.map { "Đã đổi \($0) thành \(term)" } ?? "Đã thêm \(term) vào “Không phải name”"
        ToastManager.shared.show(message: message, type: .success)
        return nil
    }

    private func remove(_ term: String) {
        let error = Store.shared.remove(term)
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: "Đã xoá \(term)", type: .success)
        }
    }

    private func removeAll() {
        Store.shared.removeAll()
        reload()
        ToastManager.shared.show(message: "Đã xoá hết danh sách “Không phải name”", type: .success)
    }
}
