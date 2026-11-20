import SwiftUI
import UniformTypeIdentifiers

/// Danh sách **sửa thẳng từ điển gốc** PhienAm (`ChinesePhienAmWords.txt`) hoặc Pronouns (`Pronouns.dat`) — mở từ thẻ
/// PhienAm.txt / Pronouns.txt › Sửa ở Cài đặt dịch thuật. Hàng kiểu VP/Name (`DictionaryEntryRow`): dòng 1 `.headline`
/// từ gốc, dòng 2 `.subheadline` nghĩa màu phụ, icon [Xoá]; **chạm thân hàng** mở sheet sửa. "+" nổi thêm mục; ngăn
/// kéo "…" có Nhập file (chọn file trước, popup 3 cách nhập sau kèm tên file — `dataImportFilePicker` ⇒
/// `GlobalDictionaryImporter`) / Xuất file (`GlobalDictionaryTextExporter`).
///
/// Khác VP / Name Chung (chỉ lớp custom): ở đây lưu là ghi **cả file gốc** qua `GlobalDictionaryEditor` (dựng lại
/// `.dat` / ghi lại text, nạp lại riêng từ điển đó, xoá cache dịch). Nhập file cũng đi qua hàng đợi đó; trong lúc nhập,
/// "+", chạm hàng và nút xoá bị khoá (lớp "Đang nhập…" chỉ là vòng quay giữa màn). PhienAm cỡ vài chục nghìn dòng: nạp một lần sắp
/// theo khoá, lọc trên RAM, `List` hiện theo lượt 200 hàng (nạp sớm khi còn 50 hàng tới cuối).
struct BaseDictionaryListView: View {
    typealias Kind = GlobalDictionaryCardController.Kind

    /// `.phienAm` hoặc `.pronouns`.
    let kind: Kind

    private struct SharedExport: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    @State private var entries: [DictEntry] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var visibleCount = pageSize
    @State private var editingEntry: DictEntry?
    @State private var showingAddSheet = false
    @State private var showingOptionsMenu = false
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var sharedExport: SharedExport?

    private static let pageSize = 200
    private static let prefetchDistance = 50

    private var navTitle: String { kind == .phienAm ? "Phiên âm (Chung)" : "Pronouns (Chung)" }

    private var matchedEntries: [DictEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query) }
    }

    var body: some View {
        List { Group {
            // Tính MỘT lần mỗi lượt vẽ: lọc cả từ điển và mốc nạp sớm không chạy lại trong `onAppear` của từng hàng.
            let matched = matchedEntries
            let shown = Array(matched.prefix(visibleCount))
            let hasMore = shown.count < matched.count
            let prefetchId: DictEntry.ID? = shown.isEmpty ? nil : shown[max(0, shown.count - Self.prefetchDistance)].id
            let lastId = shown.last?.id
            let nextCount = shown.count + Self.pageSize

            Section {
                Text(isLoading ? "Đang tải…"
                     : (searchText.isEmpty ? "Tổng cộng \(entries.count) mục." : "\(matched.count) kết quả cho \"\(searchText)\""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                ForEach(shown) { entry in
                    row(entry)
                        .onAppear {
                            if hasMore && (entry.id == prefetchId || entry.id == lastId) {
                                visibleCount = max(visibleCount, nextCount)
                            }
                        }
                }
            }
        }.glassSheetRows() }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm từ gốc hoặc nghĩa...")
        .onChange(of: searchText) { _, _ in visibleCount = Self.pageSize }
        .backPageTitle(navTitle)
        .floatingAddButton("Thêm mục mới") {
            guard !isImporting else { return }
            showingAddSheet = true
        }
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
            SideDrawerActionRow("Nhập file (\(kind.title))", systemImage: "square.and.arrow.down") { showingFilePicker = true }
                .disabled(isImporting)
            SideDrawerActionRow("Xuất file (\(kind.title))", systemImage: "square.and.arrow.up") { exportFile() }
                .disabled(entries.isEmpty)
        }
        .sheet(item: $editingEntry) { entry in
            Group {
                BaseDictionaryEntrySheet(title: "Sửa mục", originalKey: entry.key, originalValue: entry.value) { key, value in
                    save(key: key, value: value, replacing: entry.key)
                }
            }
            .appGlassSheet()
        }
        .sheet(isPresented: $showingAddSheet) {
            Group {
                BaseDictionaryEntrySheet(title: "Thêm mục") { key, value in
                    save(key: key, value: value, replacing: nil)
                }
            }
            .appGlassSheet()
        }
        .sheet(item: $sharedExport, onDismiss: { cleanUpExport() }) { export in
            ShareSheet(activityItems: [export.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Đã xuất \(kind.title)", type: .success)
                } else if let error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .dataImportFilePicker(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text],
            title: "Nhập \(kind.title)"
        ) { url, mode in
            importFile(url, mode: mode)
        }
        .overlay {
            if isImporting {
                ProgressView("Đang nhập…")
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await reload() }
    }

    private func row(_ entry: DictEntry) -> some View {
        HStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.key)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(entry.value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isImporting { editingEntry = entry } }

            Button {
                delete(entry)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .disabled(isImporting)
            .accessibilityLabel("Xoá \(entry.key)")
        }
        .accessibilityAction(named: "Sửa") { if !isImporting { editingEntry = entry } }
    }

    // MARK: - Thao tác

    private func reload() async {
        do {
            let loaded = try await GlobalDictionaryEditor.shared.entries(type: kind.rawValue)
            entries = loaded.map { DictEntry(key: $0.key, value: $0.value) }
        } catch {
            ToastManager.shared.show(message: "Lỗi đọc \(kind.title): \(error.localizedDescription)", type: .error)
        }
        isLoading = false
    }

    private func save(key: String, value: String, replacing oldKey: String?) {
        guard !isImporting else { return }
        Task {
            do {
                try await GlobalDictionaryEditor.shared.save(key: key, value: value, replacing: oldKey, type: kind.rawValue)
                entries.removeAll { $0.key == key || $0.key == oldKey }
                entries.insert(DictEntry(key: key, value: value), at: 0)
                ToastManager.shared.show(message: "Đã lưu: \(key)", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi lưu: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func delete(_ entry: DictEntry) {
        guard !isImporting else { return }
        Task {
            do {
                try await GlobalDictionaryEditor.shared.delete(key: entry.key, type: kind.rawValue)
                entries.removeAll { $0.key == entry.key }
                ToastManager.shared.show(message: "Đã xoá: \(entry.key)", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi xoá: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// File + cách nhập đã chọn (popup hiện sau bộ chọn file, chạy khi popup đóng hẳn).
    private func importFile(_ url: URL, mode: DataImportMode) {
        guard !isImporting else { return }
        isImporting = true
        Task {
            do {
                let outcome = try await GlobalDictionaryEditor.shared.importFile(at: url, type: kind.rawValue, mode: mode)
                await reload()
                let message = mode == .replaceAll
                    ? "Đã thay \(kind.title) bằng \(outcome.importedCount) mục."
                    : "Đã nhập: thêm \(outcome.added), cập nhật \(outcome.updated)."
                ToastManager.shared.show(message: message, type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi nhập \(kind.title): \(error.localizedDescription)", type: .error)
            }
            isImporting = false
        }
    }

    private func exportFile() {
        let type = kind.rawValue
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try GlobalDictionaryTextExporter.export(type: type) }
            }.value
            switch result {
            case .success(let url):
                sharedExport = SharedExport(url: url)
            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ToastManager.shared.show(message: "Lỗi xuất \(kind.title): \(message)", type: .error)
            }
        }
    }

    /// `sheet(item:)` đặt `nil` trước `onDismiss` ⇒ xoá mọi file xuất tạm của loại này còn lại trong thư mục tạm.
    private func cleanUpExport() {
        let prefix = kind == .phienAm ? "PhienAm_" : "Pronouns_"
        let tempDirectory = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)) ?? []
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".txt") {
            try? FileManager.default.removeItem(at: tempDirectory.appendingPathComponent(name))
        }
    }
}
