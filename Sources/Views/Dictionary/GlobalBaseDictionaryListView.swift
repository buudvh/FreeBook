import SwiftUI

/// Danh sách **từ điển gốc** VietPhrase.dat / Names.dat — mở từ thẻ VietPhrase.txt / Name.txt › Sửa ở Cài đặt dịch thuật
/// (anh Bửu: "Sửa vietphrase thì hiển thị danh sách của vietphrase.dat chứ không phải custom vietphrase"; chọn "Lớp sửa đổi,
/// hiện chung", Name cũng vậy).
///
/// Hiện **nghĩa hiệu lực** = từ điển gốc + lớp sửa đổi Chung (`CustomVietPhrase.txt` / `CustomNames.txt`, đọc qua
/// `DictionaryCache`): từ đã sửa hiện nghĩa mới + nhãn "đã sửa"; từ đã xoá (tombstone) ẩn; từ chỉ có ở lớp sửa đổi
/// (tự thêm) đứng **đầu** danh sách, nhãn "đã thêm". Lưu / xoá / thêm **chỉ** ghi lớp sửa đổi bằng đường có sẵn
/// (`DictionaryCache.upsertEntry` / `deleteEntry` ⇒ `TranslationManager.saveCustomEntry` / `deleteCustomEntry`, scope
/// `.term` ⇒ Reader / TTS dịch lại) — **không** ghi lại `.dat`.
///
/// VietPhrase cỡ triệu mục (1.3.1037): mở màn dựng **một lần** `BaseDictionaryIndex` ở nền — 200 khoá đầu hiện ngay khi
/// có, phần sau nạp theo lượt 200 khi cuộn (sớm khi còn 50); nghĩa của hàng tra lúc hàng hiện (lớp sửa đổi trước, rồi cây
/// đã nạp). Tìm theo từ gốc **và** nghĩa chạy trên chỉ mục đó (`BaseDictionaryBrowser.searchUpdates`), chờ 300 ms sau phím
/// cuối, gõ tiếp thì huỷ lượt cũ, kết quả hiện dần, dừng ở 500. Chỉ mục chưa xong thì lượt tìm chờ. Ngăn kéo "…" có
/// "Từ đã sửa / đã xoá" ⇒ danh sách Chung cũ (`DictionaryListView`, xem / khôi phục).
struct GlobalBaseDictionaryListView: View {
    let type: DictType

    @ObservedObject private var cache = DictionaryCache.shared
    @ObservedObject private var translationManager = TranslationManager.shared

    @State private var dictionary: FrozenTrieDictionary?
    @State private var index: BaseDictionaryIndex?
    @State private var isBuildingIndex = false
    /// Khoá gốc đã dựng chuỗi theo thứ tự chỉ mục (chưa lọc từ đã xoá) — nối thêm khi cuộn.
    @State private var pageKeys: [String] = []
    /// Từ chỉ có ở lớp sửa đổi (không có trong gốc) — tính lại khi lớp sửa đổi đổi, không tính mỗi lượt vẽ.
    @State private var addedKeys: [String] = []
    @State private var isLoadingKeys = true
    @State private var searchText = ""
    @State private var searchResult: BaseDictionaryBrowser.SearchResult?
    @State private var isSearching = false
    /// Số khoá gốc cần có trong `pageKeys`.
    @State private var visibleCount = pageSize
    @State private var editingEntry: DictEntry?
    @State private var showingAddSheet = false
    @State private var showingOptionsMenu = false
    @State private var showingCustomList = false

    private static let pageSize = 200
    private static let prefetchDistance = 50

    private var isName: Bool { type == .names }
    private var navTitle: String { isName ? "Names.dat" : "VietPhrase.dat" }

    /// Lớp sửa đổi Chung còn hiệu lực (không gồm tombstone), mới nhất trước.
    private var customEntries: [DictEntry] {
        (isName ? cache.namesEntries : cache.vietPhraseEntries) ?? []
    }

    private var deletedKeys: Set<String> {
        Set(isName ? translationManager.deletedNamesList : translationManager.deletedVietPhraseList)
    }

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List { Group {
            // Tính MỘT lần mỗi lượt vẽ.
            let customValues = Dictionary(customEntries.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            let deleted = deletedKeys
            let rows = displayedKeys(customValues: customValues, deleted: deleted)
            let prefetchId: String? = rows.keys.isEmpty ? nil : rows.keys[max(0, rows.keys.count - Self.prefetchDistance)]
            let lastId = rows.keys.last
            let nextCount = pageKeys.count + Self.pageSize

            Section {
                Text(summary(customValues: customValues, deleted: deleted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                ForEach(rows.keys, id: \.self) { key in
                    row(key: key, customValues: customValues)
                        .onAppear {
                            if rows.hasMore && (key == prefetchId || key == lastId) {
                                visibleCount = max(visibleCount, nextCount)
                            }
                        }
                }
                if trimmedQuery.isEmpty, index == nil, isBuildingIndex, !pageKeys.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Đang đọc tiếp \(navTitle)…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }.glassSheetRows() }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm từ gốc hoặc nghĩa...")
        .task(id: searchTaskID) { await runSearch() }
        .onChange(of: visibleCount) { _, _ in fillPages() }
        .backPageTitle(navTitle)
        .floatingAddButton("Thêm từ mới") { showingAddSheet = true }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingOptionsMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                        .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }
        }
        .sideDrawerMenu(isPresented: $showingOptionsMenu, title: navTitle) {
            SideDrawerActionRow("Từ đã sửa / đã xoá", systemImage: "clock.arrow.circlepath") { showingCustomList = true }
        }
        .navigationDestination(isPresented: $showingCustomList) {
            DictionaryListView(type: type, bookId: nil)
        }
        .sheet(item: $editingEntry) { entry in
            Group {
                DictEntrySheet(
                    mode: .edit(key: entry.key, value: entry.value),
                    dictType: type,
                    existingValue: { key in effectiveMeaning(of: key, customValues: currentCustomValues()) },
                    onSaveSingle: { newKey, newValue in
                        // Đổi từ gốc: như danh sách Chung — giữ mục cũ, thêm mục mới (`DictionaryCache.updateKey`).
                        save(key: newKey, value: newValue)
                    },
                    onAddEntry: { newKey, newValue in save(key: newKey, value: newValue) }
                )
            }
            .appGlassSheet()
        }
        .sheet(isPresented: $showingAddSheet) {
            Group {
                DictEntrySheet(mode: .add, dictType: type, onSaveBatch: { entries in saveBatch(entries) })
            }
            .appGlassSheet()
        }
        .overlay {
            if let overlayTitle {
                ProgressView(overlayTitle)
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await loadIndex() }
        .onChange(of: customEntries) { _, _ in refreshAddedKeys() }
    }

    // MARK: - Dữ liệu hiển thị

    /// Vòng chờ giữa màn: chỉ khi chưa có gì để hiện (trang đầu chưa tới / lượt tìm chưa có kết quả nào).
    private var overlayTitle: String? {
        if isLoadingKeys && pageKeys.isEmpty { return "Đang đọc \(navTitle)…" }
        if isSearching && (searchResult?.keys.isEmpty ?? true) { return "Đang tìm…" }
        return nil
    }

    /// Lượt tìm chạy lại khi chữ đổi **hoặc** chỉ mục vừa xong (lượt gõ lúc chỉ mục đang dựng thì chờ).
    private var searchTaskID: String {
        "\(isWaitingForIndex ? 0 : 1)|\(searchText)"
    }

    private var isWaitingForIndex: Bool {
        index == nil && (isLoadingKeys || isBuildingIndex)
    }

    /// Không tìm: từ tự thêm (chỉ ở lớp sửa đổi) trước, rồi khoá gốc chưa bị xoá đã dựng ở `pageKeys`. Đang tìm: kết quả.
    private func displayedKeys(customValues: [String: String], deleted: Set<String>) -> (keys: [String], hasMore: Bool) {
        if !trimmedQuery.isEmpty {
            // Từ vừa xoá sau lượt tìm thì ẩn luôn, không chờ tìm lại.
            return ((searchResult?.keys ?? []).filter { !deleted.contains($0) }, false)
        }
        let added = Set(addedKeys)
        let base = pageKeys.filter { !deleted.contains($0) && !added.contains($0) }
        let hasMore = index.map { pageKeys.count < $0.count } ?? isBuildingIndex
        return (addedKeys + base, hasMore)
    }

    private func summary(customValues: [String: String], deleted: Set<String>) -> String {
        if isLoadingKeys && pageKeys.isEmpty { return "Đang đọc \(navTitle)…" }
        if !trimmedQuery.isEmpty {
            guard let searchResult else { return "Đang tìm \"\(trimmedQuery)\"…" }
            if !searchResult.isComplete { return "Đang tìm \"\(trimmedQuery)\"… \(searchResult.keys.count) kết quả" }
            return searchResult.isCapped
                ? "\(BaseDictionaryBrowser.searchLimit) kết quả đầu cho \"\(trimmedQuery)\""
                : "\(searchResult.keys.count) kết quả cho \"\(trimmedQuery)\""
        }
        guard let dictionary else {
            return "Chưa có \(navTitle) — nhập file ở thẻ \(isName ? "Name.txt" : "VietPhrase.txt")."
        }
        let added = addedKeys.count
        let edited = customValues.count - added
        let total = (index?.count ?? dictionary.wordCount) + added
        return "\(total) từ · \(edited) đã sửa · \(added) đã thêm · \(deleted.count) đã xoá"
    }

    private func refreshAddedKeys() {
        let snapshot = dictionary
        addedKeys = customEntries.map(\.key).filter { BaseDictionaryBrowser.baseMeaning(of: $0, in: snapshot) == nil }
    }

    private func currentCustomValues() -> [String: String] {
        Dictionary(customEntries.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Lớp sửa đổi trước, rồi từ điển gốc.
    private func effectiveMeaning(of key: String, customValues: [String: String]) -> String? {
        customValues[key] ?? BaseDictionaryBrowser.baseMeaning(of: key, in: dictionary)
    }

    private func row(key: String, customValues: [String: String]) -> some View {
        let custom = customValues[key]
        let base = BaseDictionaryBrowser.baseMeaning(of: key, in: dictionary)
        let meaning = custom ?? base ?? ""
        let badge: String? = custom == nil ? nil : (base == nil ? "đã thêm" : "đã sửa")
        return HStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(key)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.18))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    Text(meaning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { editingEntry = DictEntry(key: key, value: meaning) }

            Button {
                delete(key)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Xoá \(key)")
        }
        .accessibilityAction(named: "Sửa") { editingEntry = DictEntry(key: key, value: meaning) }
    }

    // MARK: - Nạp + tìm

    /// `.task` chạy lại mỗi lần màn hiện lại (vd quay về từ "Từ đã sửa / đã xoá") ⇒ có chỉ mục / đang dựng thì thôi.
    /// Lượt dựng không theo huỷ của `.task`: đi dở rồi quay lại vẫn nhận đúng một chỉ mục.
    private func loadIndex() async {
        await cache.loadIfNeeded(type: type)
        guard index == nil, !isBuildingIndex else { return }
        let loaded = BaseDictionaryBrowser.loadedDictionary(isName: isName)
        dictionary = loaded
        refreshAddedKeys()
        guard let loaded else {
            isLoadingKeys = false
            return
        }
        isBuildingIndex = true
        let built = await BaseDictionaryBrowser.buildIndex(of: loaded, label: navTitle, firstPageSize: Self.pageSize) { keys in
            // Trang đầu có thể tới sau khi chỉ mục đã xong (`fillPages` đã điền) ⇒ chỉ nhận khi còn trống.
            guard pageKeys.isEmpty else { return }
            pageKeys = keys
            isLoadingKeys = false
        }
        index = built
        isBuildingIndex = false
        isLoadingKeys = false
        fillPages()
    }

    /// Dựng chuỗi cho khoá gốc tới `visibleCount` (theo thứ tự chỉ mục, nối tiếp `pageKeys`).
    private func fillPages() {
        guard let index else { return }
        let target = min(index.count, visibleCount)
        guard pageKeys.count < target else { return }
        pageKeys.append(contentsOf: index.keys(in: pageKeys.count..<target))
    }

    /// `.task(id: searchTaskID)`: SwiftUI huỷ lượt cũ khi gõ tiếp ⇒ dòng kết quả ngắt ⇒ huỷ lượt quét nền.
    private func runSearch() async {
        let query = trimmedQuery
        guard !query.isEmpty else {
            searchResult = nil
            isSearching = false
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        searchResult = nil
        isSearching = true
        // Chỉ mục đang dựng ⇒ chờ: `searchTaskID` đổi khi xong, task chạy lại.
        guard !isWaitingForIndex else { return }
        let updates = BaseDictionaryBrowser.searchUpdates(
            query,
            index: index,
            custom: customEntries.map { (key: $0.key, value: $0.value) },
            deleted: deletedKeys,
            workers: BaseDictionaryBrowser.meaningSearchWorkers(),
            label: navTitle
        )
        for await update in updates {
            guard !Task.isCancelled else { return }
            searchResult = update
        }
        guard !Task.isCancelled else { return }
        isSearching = false
    }

    // MARK: - Ghi lớp sửa đổi

    private func save(key: String, value: String) {
        Task {
            do {
                try await cache.upsertEntry(key: key, value: value, type: type)
                ToastManager.shared.show(message: "Đã lưu: \(key)", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Nhiều dòng của "+" ⇒ **một** lượt ghi lớp sửa đổi + một thông báo đổi từ điển (như `DictionaryListView` Chung):
    /// ghi N lần là N lượt dịch lại của Reader / TTS, và hỏng giữa chừng thì ghi dở. Một dòng ⇒ đường `.term` thường.
    private func saveBatch(_ entries: [(key: String, value: String)]) {
        guard !entries.isEmpty else { return }
        if entries.count == 1, let entry = entries.first {
            save(key: entry.key, value: entry.value)
            return
        }
        let records = entries.map { DictionaryTextRecord(key: $0.key, value: $0.value) }
        Task {
            do {
                try await TranslationDictionaryWriter.shared.mutate(isName: isName, bookId: nil) { existing in
                    let keys = Set(records.map(\.key))
                    existing = records + existing.filter { !keys.contains($0.key) }
                }
                cache.refreshFromPublishedState(type: type)
                ToastManager.shared.show(message: "Đã lưu \(entries.count) từ", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Xoá = tombstone ở lớp sửa đổi nếu từ có trong gốc (ẩn khỏi danh sách), hoặc bỏ hẳn từ tự thêm.
    private func delete(_ key: String) {
        Task {
            do {
                try await cache.deleteEntry(key: key, type: type)
                ToastManager.shared.show(message: "Đã xoá: \(key)", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
