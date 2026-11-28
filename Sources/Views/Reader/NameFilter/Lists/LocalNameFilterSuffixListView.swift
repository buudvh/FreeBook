import SwiftUI
import UniformTypeIdentifiers

/// Màn **Hậu tố** / **Tiền tố** của Lọc name local (plan 2026-11-27-phan-loai-name mockup khung 6 / 7) — một màn cho cả hai
/// danh sách, khác nhau ở `LocalNameFilterAffixListFlavor` (store, chữ, mặc định). Đẩy vào `NavigationStack` của sheet "Lọc
/// name local" từ mục "Danh sách". Khuôn màn Danh sách họ (`QuickTranslationSurnameListView`): header nút quay lại + `…`
/// (`.sideDrawerMenu`: Nhập file, Xuất file, Khôi phục mặc định), ô tìm luôn hiện (chữ Hán / nghĩa), hàng chip lọc theo
/// loại kèm số (`LocalNameFilterAffixKindFilterBar`: Tất cả / Địa danh / Tổ chức / Thuật ngữ / Nhân danh), nút `+` nổi, hàng
/// `LocalNameFilterSuffixRow` (chạm thân hàng mở màn Sửa từ `LocalNameFilterSuffixEditorSheet`, `[Xoá]`). Danh sách chỉ để
/// ghép nghĩa — việc dò dùng bộ hậu tố cố định của app.
///
/// **Mở từ một truyện** (`bookId`, 2026-11-28 — mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M6, plan mục
/// B7): hàng chip phạm vi **"Chung N · Riêng truyện N"** trên hàng chip loại. "Riêng truyện" là chỗ xem hết mục riêng của
/// truyện — thêm / sửa / xoá ở đó ghi kho riêng (`LocalNameFilterBookAffixStore`); màn Sửa từ có cụm R | C chọn sẵn theo chip
/// đang chọn (đổi được: C → R tạo bản riêng, R → C đưa lên chung). "Khôi phục mặc định" chỉ áp cho Chung.
///
/// Bản gốc đóng trong app; mọi thao tác chỉ ghi lớp riêng của store. Store không phát thay đổi ⇒ màn giữ bản chụp ở
/// `@State`, đọc lại sau **mọi** lần ghi và ở `onAppear`. Toast ở đây (Service không gọi `ToastManager`).
struct LocalNameFilterSuffixListView: View {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Flavor = LocalNameFilterAffixListFlavor
    typealias Kind = LocalNameFilter.SuffixKind
    typealias Scope = LocalNameFilterAffixListStore.Scope

    /// Đích của sheet sửa; `entry == nil` = thêm mục mới.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let entry: Entry?
    }

    let flavor: Flavor
    /// Truyện đang mở; `nil` / rỗng ⇒ chỉ danh sách Chung, không có chip phạm vi.
    let bookId: String?

    @State private var entries: [Entry]
    @State private var bookEntries: [Entry]
    @State private var isCustomized: Bool
    @State private var searchText = ""
    /// Chip phạm vi đang chọn (chỉ khi có truyện).
    @State private var scope: Scope = .common
    /// Chip loại đang chọn; `nil` = Tất cả.
    @State private var kindFilter: Kind? = nil
    @State private var editorTarget: EditorTarget? = nil
    @State private var showingMenu = false
    @State private var confirmingReset = false
    @State private var exportedFile: LocalNameFilterListExport.File? = nil
    @State private var showingFilePicker = false

    init(flavor: Flavor = .suffix, bookId: String? = nil) {
        self.flavor = flavor
        let book = bookId.flatMap { $0.isEmpty ? nil : $0 }
        self.bookId = book
        _entries = State(initialValue: flavor.store.entries())
        _bookEntries = State(initialValue: book.map { flavor.store.bookStore.entries(bookId: $0) } ?? [])
        _isCustomized = State(initialValue: flavor.store.isCustomized)
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Phạm vi đang xem có hiệu lực (không có truyện ⇒ luôn Chung).
    private var activeScope: Scope { bookId == nil ? .common : scope }

    /// Danh sách của chip phạm vi đang chọn.
    private var scopeEntries: [Entry] { activeScope == .book ? bookEntries : entries }

    /// Loại đang lọc có hiệu lực: loại đã chọn mà hết mục (vừa xoá mục cuối) ⇒ như Tất cả.
    private var activeKind: Kind? {
        guard let kindFilter, scopeEntries.contains(where: { $0.kind == kindFilter }) else { return nil }
        return kindFilter
    }

    private var kindEntries: [Entry] {
        guard let kind = activeKind else { return scopeEntries }
        return scopeEntries.filter { $0.kind == kind }
    }

    private var matchedEntries: [Entry] {
        let query = trimmedQuery
        guard !query.isEmpty else { return kindEntries }
        return kindEntries.filter {
            $0.key.contains(query) || $0.meaning.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// "1.190 hậu tố" / "3 hậu tố riêng" theo chip đang chọn; đang tìm ⇒ số kết quả.
    private var sectionTitle: String {
        if !trimmedQuery.isEmpty {
            return "\(matchedEntries.count) kết quả cho \"\(trimmedQuery)\""
        }
        let count = LocalNameFilterAffixKindFilterBar.formattedCount(kindEntries.count)
        return activeScope == .book ? "\(count) \(flavor.lowercasedNoun) riêng" : "\(count) \(flavor.lowercasedNoun)"
    }

    private var emptyText: String {
        if !trimmedQuery.isEmpty { return "Không có \(flavor.lowercasedNoun) nào khớp." }
        if activeScope == .book, bookEntries.isEmpty {
            return "Truyện này chưa có \(flavor.lowercasedNoun) riêng. Bấm + để thêm, hoặc thêm từ màn Sửa từ của màn duyệt name."
        }
        if scopeEntries.isEmpty { return flavor.emptyListText }
        return "Chưa có \(flavor.lowercasedNoun) loại này. Bấm + để thêm."
    }

    var body: some View {
        VStack(spacing: 0) {
            if bookId != nil { scopeBar }
            LocalNameFilterAffixKindFilterBar(entries: scopeEntries, selection: $kindFilter)

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
                            showsUserAddedNote: activeScope == .common,
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
            // Nhập vào đúng danh sách của chip phạm vi đang chọn: chọn file trước, rồi popup ba cách nhập.
            SideDrawerActionRow("Nhập file", systemImage: "square.and.arrow.down") {
                showingFilePicker = true
            }
            // Xuất đúng danh sách của chip phạm vi đang chọn (`LocalNameFilterListExport`).
            SideDrawerActionRow("Xuất file", systemImage: "square.and.arrow.up") {
                exportList()
            }
            .disabled(scopeEntries.isEmpty)
            // Chỉ danh sách Chung có bản gốc để khôi phục.
            SideDrawerActionRow("Khôi phục mặc định", systemImage: "arrow.counterclockwise", role: .destructive) {
                confirmingReset = true
            }
            .disabled(!isCustomized || activeScope == .book)
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .sheet(item: $editorTarget) { target in
            Group {
                LocalNameFilterSuffixEditorSheet(
                    flavor: flavor,
                    original: target.entry,
                    originalScope: activeScope,
                    initialKind: activeKind,
                    bookId: bookId,
                    initialScope: activeScope,
                    onSave: { request in save(request) },
                    onRestoreBundled: { restoreBundled(target.entry) }
                )
            }
            .appGlassSheet()
        }
        .dataImportFilePicker(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text],
            title: importTitle
        ) { url, mode in
            importFile(url, mode: mode)
        }
        .confirmationDialog(
            "Khôi phục danh sách \(flavor.lowercasedNoun) mặc định?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Khôi phục mặc định", role: .destructive) { resetToDefaults() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text(verbatim: bookId == nil
                 ? "Mọi \(flavor.lowercasedNoun) đã thêm, sửa hoặc xoá sẽ mất."
                 : "Mọi \(flavor.lowercasedNoun) chung đã thêm, sửa hoặc xoá sẽ mất. Danh sách riêng của truyện giữ nguyên.")
        }
        .onAppear { reload() }
    }

    /// "Chung 1.299 · Riêng truyện 3" (mockup M6) — cùng kiểu chip với hàng chip loại ngay dưới.
    private var scopeBar: some View {
        HStack(spacing: 8) {
            LocalNameFilterAffixKindFilterBar.chip(
                title: "Chung \(LocalNameFilterAffixKindFilterBar.formattedCount(entries.count))",
                isSelected: activeScope == .common
            ) {
                scope = .common
            }
            LocalNameFilterAffixKindFilterBar.chip(
                title: "Riêng truyện \(LocalNameFilterAffixKindFilterBar.formattedCount(bookEntries.count))",
                isSelected: activeScope == .book
            ) {
                scope = .book
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HeaderMetrics.horizontalMargin)
        .padding(.top, 6)
    }

    // MARK: - Thao tác

    private func reload() {
        entries = flavor.store.entries()
        bookEntries = bookId.map { flavor.store.bookStore.entries(bookId: $0) } ?? []
        isCustomized = flavor.store.isCustomized
    }

    /// Lưu từ sheet theo luật phạm vi của lõi: store kiểm lại luật + trùng khoá trên dữ liệu mới nhất. `nil` = đã lưu; chuỗi
    /// = lỗi để sheet hiện.
    private func save(_ request: LocalNameFilterSuffixEditorSheet.SaveRequest) -> String? {
        let error = request.save(in: flavor.store, bookId: bookId ?? "")
        reload()
        if let error { return error }
        let verb = request.original == nil ? "Đã thêm" : "Đã lưu"
        let scopeNote = bookId == nil ? "" : (request.scope == .book ? " (riêng truyện)" : " (chung)")
        ToastManager.shared.show(message: "\(verb) \(flavor.lowercasedNoun) \(request.key)\(scopeNote)", type: .success)
        return nil
    }

    /// Xoá một chạm như danh sách họ, ở phạm vi đang xem: Chung ⇒ mọi truyện (mục gốc đã xoá thêm lại được, hoặc "Khôi phục
    /// mặc định"); Riêng truyện ⇒ chỉ truyện này.
    private func delete(_ entry: Entry) {
        let target = activeScope
        let error = flavor.store.delete(key: entry.key, scope: target, bookId: bookId ?? "")
        let scopeNote = target == .book ? " riêng" : ""
        report(error, success: "Đã xoá \(flavor.lowercasedNoun)\(scopeNote) \(entry.key)")
    }

    private func restoreBundled(_ entry: Entry?) {
        guard let entry, entry.bundledValue != nil else { return }
        report(flavor.store.restoreBundledValue(key: entry.key),
               success: "Đã đưa \(flavor.lowercasedNoun) \(entry.key) về bản gốc")
    }

    /// Ngăn kéo › "Xuất file": danh sách của chip phạm vi đang chọn, định dạng file gốc (`chữ Hán=nghĩa|loại|vị trí`).
    private func exportList() {
        let isBook = activeScope == .book
        let content = LocalNameFilterListExport.affixContent(scopeEntries, listName: flavor.noun, isBookScope: isBook)
        do {
            exportedFile = try LocalNameFilterListExport.write(
                content, fileStem: flavor == .prefix ? "TienTo" : "HauTo", isBookScope: isBook
            )
        } catch {
            AppLogger.shared.log("❌ [LọcName] Không xuất được danh sách \(flavor.lowercasedNoun): \(error.localizedDescription)")
            ToastManager.shared.show(message: "Không xuất được file: \(error.localizedDescription)", type: .error)
        }
    }

    /// Tiêu đề popup chọn cách nhập — nói rõ danh sách đích khi màn có hai phạm vi.
    private var importTitle: String {
        guard bookId != nil else { return "Nhập danh sách \(flavor.lowercasedNoun)" }
        return activeScope == .book ? "Nhập \(flavor.lowercasedNoun) riêng truyện" : "Nhập \(flavor.lowercasedNoun) chung"
    }

    /// Ngăn kéo › "Nhập file": file + cách nhập đã chọn (popup hiện sau bộ chọn file, chạy khi popup đóng hẳn) ⇒ nhập vào
    /// danh sách của chip phạm vi đang chọn, cùng định dạng "Xuất file". File nhỏ ⇒ đọc ngay trên main; store ghi một lần.
    private func importFile(_ url: URL, mode: DataImportMode) {
        let target = activeScope
        let result = flavor.store.importFile(at: url, mode: mode, scope: target, bookId: bookId ?? "")
        reload()
        switch result {
        case .success(let outcome):
            let unit = target == .book ? "\(flavor.lowercasedNoun) riêng" : flavor.lowercasedNoun
            ToastManager.shared.show(message: outcome.summary(unit: unit), type: .success)
        case .failure(let failure):
            AppLogger.shared.log("❌ [LọcName] Không nhập được danh sách \(flavor.lowercasedNoun): \(failure.message)")
            ToastManager.shared.show(message: "Lỗi nhập danh sách \(flavor.lowercasedNoun): \(failure.message)", type: .error)
        }
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
