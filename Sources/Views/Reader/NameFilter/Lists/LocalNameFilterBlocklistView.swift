import SwiftUI

/// Màn **Không phải name** của Lọc name local (mockup khung 6) — đẩy vào `NavigationStack` của sheet "Lọc name local" từ
/// mục "Danh sách". Kiểu màn danh sách: header nút quay lại + `…` (`.sideDrawerMenu`: Xoá hết), ô tìm luôn hiện (chữ Hán /
/// âm Hán-Việt), tiêu đề section "N cụm", hàng `LocalNameFilterBlocklistRow` (chạm thân hàng mở màn Sửa từ, 🗑), nút `+`
/// nổi mở cùng màn ở chế độ thêm — `LocalNameFilterBlocklistEditorSheet`.
///
/// **Mở từ một truyện** (`bookId`, 2026-11-28 — mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N4): hàng chip
/// phạm vi **"Chung N · Riêng truyện N"** như màn Hậu tố (M6); thêm / sửa / xoá / Xoá hết theo chip đang chọn — Riêng truyện
/// ghi `LocalNameFilterBookBlocklistStore`. Bộ lọc của truyện chặn theo cả hai danh sách.
///
/// Store (`LocalNameFilterBlocklistStore` / `LocalNameFilterBookBlocklistStore`) không phát thay đổi ⇒ màn giữ bản chụp ở
/// `@State`, đọc lại sau mọi lần ghi và ở `onAppear` (cụm thêm từ màn duyệt hiện ra khi quay lại). Âm Hán-Việt tính một lần
/// mỗi lần đọc lại, không trong `body`.
struct LocalNameFilterBlocklistView: View {
    typealias Store = LocalNameFilterBlocklistStore
    typealias BookStore = LocalNameFilterBookBlocklistStore
    typealias Scope = LocalNameFilter.BlockScope

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

    /// Truyện đang mở; `nil` / rỗng ⇒ chỉ danh sách Chung, không có chip phạm vi.
    let bookId: String?

    /// Cụm Chung và Riêng truyện giữ riêng để số trên chip luôn đúng; `items` = của chip đang chọn.
    @State private var commonItems: [Item] = []
    @State private var bookItems: [Item] = []
    @State private var searchText = ""
    /// Chip phạm vi đang chọn (chỉ khi có truyện).
    @State private var scope: Scope = .common
    @State private var editorTarget: EditorTarget?
    @State private var showingMenu = false
    @State private var confirmingClear = false

    init(bookId: String? = nil) {
        self.bookId = bookId.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Phạm vi đang xem có hiệu lực (không có truyện ⇒ luôn Chung).
    private var activeScope: Scope { bookId == nil ? .common : scope }

    private var items: [Item] { activeScope == .book ? bookItems : commonItems }

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
        if !trimmedQuery.isEmpty { return "\(matchedItems.count) kết quả cho \"\(trimmedQuery)\"" }
        let count = LocalNameFilterAffixKindFilterBar.formattedCount(items.count)
        return activeScope == .book ? "\(count) cụm riêng" : "\(count) cụm"
    }

    private var emptyText: String {
        if !items.isEmpty { return "Không có cụm nào khớp." }
        return activeScope == .book
            ? "Truyện này chưa có cụm riêng. Thêm từ màn duyệt (🗑 › Không phải name · riêng truyện) hoặc bấm +."
            : "Chưa có cụm nào. Thêm từ màn duyệt (🗑 › Không phải name · mọi truyện) hoặc bấm +."
    }

    var body: some View {
        VStack(spacing: 0) {
            if bookId != nil { scopeBar }
            list
        }
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
            SideDrawerActionRow(
                activeScope == .book ? "Xoá hết cụm riêng" : "Xoá hết", systemImage: "trash", role: .destructive
            ) {
                confirmingClear = true
            }
            .disabled(items.isEmpty)
        }
        .sheet(item: $editorTarget) { target in
            Group {
                LocalNameFilterBlocklistEditorSheet(original: target.term, scope: activeScope, bookId: bookId) { term, replacing in
                    save(term, replacing: replacing)
                }
            }
            .appGlassSheet()
        }
        .confirmationDialog(clearTitle, isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Xoá hết \(items.count) cụm", role: .destructive) { removeAll() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Lần lọc sau các cụm này có thể hiện lại.")
        }
        .onAppear { reload() }
    }

    private var clearTitle: String {
        activeScope == .book
            ? "Xoá hết “Không phải name” riêng của truyện?"
            : "Xoá hết danh sách “Không phải name”?"
    }

    /// "Chung 214 · Riêng truyện 3" (mockup N4) — cùng kiểu chip với màn Hậu tố (`LocalNameFilterAffixKindFilterBar.chip`).
    private var scopeBar: some View {
        HStack(spacing: 8) {
            LocalNameFilterAffixKindFilterBar.chip(
                title: "Chung \(LocalNameFilterAffixKindFilterBar.formattedCount(commonItems.count))",
                isSelected: activeScope == .common
            ) {
                scope = .common
            }
            LocalNameFilterAffixKindFilterBar.chip(
                title: "Riêng truyện \(LocalNameFilterAffixKindFilterBar.formattedCount(bookItems.count))",
                isSelected: activeScope == .book
            ) {
                scope = .book
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HeaderMetrics.horizontalMargin)
        .padding(.vertical, 6)
    }

    private var list: some View {
        List { Group {
            Section {
                let matched = matchedItems
                if matched.isEmpty {
                    Text(verbatim: emptyText)
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
                    "Cụm chữ Hán không phải name. Lọc name local bỏ đúng các cụm này khỏi kết quả, không đổi cách xét các cụm khác.",
                    "**Chung**: chặn ở mọi truyện. **Riêng truyện**: chỉ chặn ở truyện đang mở (cụm là rác ở truyện này nhưng có thể là tên ở truyện khác). Bộ lọc của truyện chặn theo cả hai.",
                    "Khớp **nguyên cụm**: chặn 唐三做 không làm 唐三 biến mất."
                ])
            }
        }.glassSheetRows() }
        .listStyle(.plain)
    }

    // MARK: - Thao tác

    private func reload() {
        let phienAm = TranslationManager.shared.phienAmMap
        func makeItems(_ entries: [Store.Entry]) -> [Item] {
            entries.map { entry in
                let reading = Self.reading(of: entry.term, phienAm: phienAm)
                let day = Self.dayFormatter.string(from: entry.addedAt)
                return Item(term: entry.term, reading: reading, subtitle: "\(reading) · thêm \(day)")
            }
        }
        commonItems = makeItems(Store.shared.entries())
        bookItems = bookId.map { makeItems(BookStore.shared.entries(bookId: $0)) } ?? []
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

    /// Lưu từ màn Sửa từ vào danh sách của chip đang chọn: `replacing == nil` ⇒ thêm cụm; khác ⇒ đổi cụm đó thành `term`
    /// (giữ nguyên ⇒ không làm gì, không toast). `nil` = đã lưu; chuỗi = lỗi để sheet hiện.
    private func save(_ term: String, replacing originalTerm: String?) -> String? {
        if let originalTerm, originalTerm == term { return nil }
        let error: String?
        if let bookId, activeScope == .book {
            error = originalTerm.map { BookStore.shared.replace($0, with: term, bookId: bookId) }
                ?? BookStore.shared.add(term, bookId: bookId)
        } else if let originalTerm {
            error = Store.shared.replace(originalTerm, with: term)
        } else {
            error = Store.shared.add(term)
        }
        reload()
        if let error { return error }
        let target = activeScope == .book ? "“Không phải name” riêng truyện" : "“Không phải name”"
        let message = originalTerm.map { "Đã đổi \($0) thành \(term)" } ?? "Đã thêm \(term) vào \(target)"
        ToastManager.shared.show(message: message, type: .success)
        return nil
    }

    private func remove(_ term: String) {
        let error: String?
        if let bookId, activeScope == .book {
            error = BookStore.shared.remove(term, bookId: bookId)
        } else {
            error = Store.shared.remove(term)
        }
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: "Đã xoá \(term)", type: .success)
        }
    }

    private func removeAll() {
        if let bookId, activeScope == .book {
            BookStore.shared.remove(bookId: bookId)
            reload()
            ToastManager.shared.show(message: "Đã xoá hết “Không phải name” riêng của truyện", type: .success)
            return
        }
        Store.shared.removeAll()
        reload()
        ToastManager.shared.show(message: "Đã xoá hết danh sách “Không phải name”", type: .success)
    }
}
