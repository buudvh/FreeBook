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
/// VietPhrase cỡ triệu mục: mở màn đọc **mảng khoá** một lần ở nền (`BaseDictionaryBrowser.keys`, duyệt cây không giữ
/// nghĩa); nghĩa của hàng tra lúc hàng hiện (lớp sửa đổi trước, rồi cây đã nạp). Danh sách hiện theo lượt 200 hàng (nạp
/// sớm khi còn 50). Tìm theo từ gốc **và** nghĩa chạy nền, chờ 300 ms sau phím cuối, gõ tiếp thì huỷ lượt cũ, dừng ở 500
/// kết quả. Ngăn kéo "…" có "Từ đã sửa / đã xoá" ⇒ danh sách Chung cũ (`DictionaryListView`, xem / khôi phục).
struct GlobalBaseDictionaryListView: View {
    let type: DictType

    @ObservedObject private var cache = DictionaryCache.shared
    @ObservedObject private var translationManager = TranslationManager.shared

    @State private var dictionary: FrozenTrieDictionary?
    @State private var baseKeys: [String] = []
    /// Từ chỉ có ở lớp sửa đổi (không có trong gốc) — tính lại khi lớp sửa đổi đổi, không tính mỗi lượt vẽ.
    @State private var addedKeys: [String] = []
    @State private var isLoadingKeys = true
    @State private var searchText = ""
    @State private var searchResult: BaseDictionaryBrowser.SearchResult?
    @State private var isSearching = false
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
            let nextCount = rows.keys.count + Self.pageSize

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
            }
        }.glassSheetRows() }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm từ gốc hoặc nghĩa...")
        .task(id: searchText) { await runSearch() }
        .backPageTitle(navTitle)
        .floatingAddButton("Thêm từ mới") { showingAddSheet = true }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingOptionsMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
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
            if isLoadingKeys || isSearching {
                ProgressView(isLoadingKeys ? "Đang đọc \(navTitle)…" : "Đang tìm…")
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await loadKeys() }
        .onChange(of: customEntries) { _, _ in refreshAddedKeys() }
    }

    // MARK: - Dữ liệu hiển thị

    /// Không tìm: từ tự thêm (chỉ ở lớp sửa đổi) trước, rồi khoá gốc chưa bị xoá — cắt ở `visibleCount`. Đang tìm: kết quả.
    private func displayedKeys(customValues: [String: String], deleted: Set<String>) -> (keys: [String], hasMore: Bool) {
        if !trimmedQuery.isEmpty {
            // Từ vừa xoá sau lượt tìm thì ẩn luôn, không chờ tìm lại.
            return ((searchResult?.keys ?? []).filter { !deleted.contains($0) }, false)
        }
        var keys = addedKeys
        var index = 0
        while keys.count < visibleCount, index < baseKeys.count {
            let key = baseKeys[index]
            index += 1
            if !deleted.contains(key) { keys.append(key) }
        }
        return (keys, index < baseKeys.count)
    }

    private func summary(customValues: [String: String], deleted: Set<String>) -> String {
        if isLoadingKeys { return "Đang đọc \(navTitle)…" }
        if !trimmedQuery.isEmpty {
            guard let searchResult else { return "Đang tìm \"\(trimmedQuery)\"…" }
            return searchResult.isCapped
                ? "\(BaseDictionaryBrowser.searchLimit) kết quả đầu cho \"\(trimmedQuery)\""
                : "\(searchResult.keys.count) kết quả cho \"\(trimmedQuery)\""
        }
        if dictionary == nil { return "Chưa có \(navTitle) — nhập file ở thẻ \(isName ? "Name.txt" : "VietPhrase.txt")." }
        let added = addedKeys.count
        let edited = customValues.count - added
        return "\(baseKeys.count + added) từ · \(edited) đã sửa · \(added) đã thêm · \(deleted.count) đã xoá"
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

    private func loadKeys() async {
        await cache.loadIfNeeded(type: type)
        guard baseKeys.isEmpty else { return }
        let loaded = BaseDictionaryBrowser.loadedDictionary(isName: isName)
        dictionary = loaded
        refreshAddedKeys()
        if let loaded {
            baseKeys = await Task.detached(priority: .userInitiated) {
                BaseDictionaryBrowser.keys(of: loaded)
            }.value
        }
        isLoadingKeys = false
    }

    /// `.task(id: searchText)`: SwiftUI huỷ lượt cũ khi gõ tiếp ⇒ huỷ luôn task nền đang duyệt cây.
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
        let snapshot = self.dictionary
        let custom = customEntries.map { (key: $0.key, value: $0.value) }
        let deleted = deletedKeys
        let worker = Task.detached(priority: .userInitiated) {
            BaseDictionaryBrowser.search(query, in: snapshot, custom: custom, deleted: deleted)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, let result else { return }
        searchResult = result
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

    private func saveBatch(_ entries: [(key: String, value: String)]) {
        guard !entries.isEmpty else { return }
        Task {
            do {
                for entry in entries {
                    try await cache.upsertEntry(key: entry.key, value: entry.value, type: type)
                }
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
