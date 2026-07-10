import SwiftUI
import UniformTypeIdentifiers

struct DictionaryListView: View {
    let type: DictType
    let bookId: String?

    @ObservedObject private var cache = DictionaryCache.shared
    @State private var bookEntries: [DictEntry] = []
    @State private var isLoadingBook = false
    @State private var searchText = ""
    @State private var visibleCount = 200
    @State private var editingEntry: DictEntry? = nil
    @State private var showingAddSheet = false
    @State private var showingFileImporter = false
    @State private var toastMessage = ""
    @State private var showingToast = false
    @State private var isToastError = false

    private var isGlobal: Bool { bookId == nil }

    private var allEntries: [DictEntry] {
        if isGlobal {
            switch type {
            case .vietPhrase: return cache.vietPhraseEntries ?? []
            case .names: return cache.namesEntries ?? []
            }
        } else {
            return bookEntries
        }
    }

    private var isLoading: Bool {
        if isGlobal {
            return type == .vietPhrase ? cache.isLoadingVP : cache.isLoadingNames
        }
        return isLoadingBook
    }

    private var matchedEntries: [DictEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return allEntries }
        return allEntries.filter {
            $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
        }
    }

    private var displayedEntries: [DictEntry] {
        Array(matchedEntries.prefix(visibleCount))
    }

    private var navTitle: String {
        let scope = isGlobal ? "Chung" : "Riêng"
        return "\(type.displayName) (\(scope))"
    }

    var body: some View {
        ZStack {
            VStack {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Đang tải từ điển...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        // Stats section
                        Section {
                            if searchText.isEmpty {
                                if displayedEntries.count < allEntries.count {
                                    Text("Hiển thị \(displayedEntries.count)/\(allEntries.count) từ. Cuộn xuống để tải thêm.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Tổng cộng \(allEntries.count) từ.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                if displayedEntries.count < matchedEntries.count {
                                    Text("Hiển thị \(displayedEntries.count)/\(matchedEntries.count) kết quả. Cuộn xuống để tải thêm.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(matchedEntries.count) kết quả cho \"\(searchText)\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Entries
                        Section {
                            ForEach(displayedEntries) { entry in
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
                                    Image(systemName: "pencil")
                                        .foregroundColor(.accentColor)
                                        .font(.subheadline)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingEntry = entry
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteEntry(entry)
                                    } label: {
                                        Label("Xóa", systemImage: "trash")
                                    }
                                }
                                .onAppear {
                                    if entry.id == displayedEntries.last?.id && visibleCount < matchedEntries.count {
                                        visibleCount += 200
                                    }
                                }
                            }
                        } header: {
                            Text("Từ vựng")
                        }
                    }
                    .searchable(text: $searchText, prompt: "Tìm từ...")
                    .onChange(of: searchText) { _, _ in
                        visibleCount = 200
                    }
                    .overlay {
                        if displayedEntries.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Không tìm thấy kết quả cho \"\(searchText)\"")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if displayedEntries.isEmpty && searchText.isEmpty && !isLoading {
                            VStack(spacing: 8) {
                                Image(systemName: "book.closed")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Chưa có từ nào")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Nhấn + để thêm từ mới hoặc import file .txt")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Export
                        if !allEntries.isEmpty {
                            ShareLink(item: exportText()) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        // Import
                        Button {
                            showingFileImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        // Add
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                DictEntrySheet(mode: .add) { key, value in
                    upsertEntry(key: key, value: value)
                }
            }
            .sheet(item: $editingEntry) { entry in
                DictEntrySheet(mode: .edit(key: entry.key, value: entry.value)) { newKey, newValue in
                    if newKey == entry.key {
                        upsertEntry(key: newKey, value: newValue)
                    } else {
                        updateKey(oldKey: entry.key, newKey: newKey, newValue: newValue)
                    }
                }
            }
            .task {
                await loadData()
            }
            .background(
                DocumentPickerPresenter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: [.plainText],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        guard let url = urls.first else { return }
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        importFile(from: url)
                    },
                    onCancel: nil
                )
            )

            // Toast overlay
            if showingToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: isToastError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(isToastError ? .red : .green)
                        Text(toastMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.9)))
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Data Operations

    private func loadData() async {
        if isGlobal {
            await cache.loadIfNeeded(type: type)
        } else {
            isLoadingBook = true
            let entries = await loadBookEntries()
            bookEntries = entries
            isLoadingBook = false
        }
    }

    private func loadBookEntries() async -> [DictEntry] {
        guard let bid = bookId else { return [] }
        let translateDir = TranslationManager.shared.translateDirectory
        let typeFileName = type.fileName

        return await Task.detached(priority: .userInitiated) {
            let bookDir = translateDir.appendingPathComponent("books").appendingPathComponent(bid)
            let datUrl = bookDir.appendingPathComponent("\(typeFileName).dat")
            let txtUrl = bookDir.appendingPathComponent("\(typeFileName).txt")

            var result: [DictEntry] = []

            if FileManager.default.fileExists(atPath: datUrl.path) {
                let dat = DoubleArrayTrie()
                try? dat.load(from: datUrl)
                if dat.isLoaded {
                    result = dat.allEntries().map { DictEntry(key: $0.key, value: $0.value) }
                }
            } else if let content = try? String(contentsOf: txtUrl, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let parts = line.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let k = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let v = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !k.isEmpty && !v.isEmpty {
                            result.append(DictEntry(key: k, value: v))
                        }
                    }
                }
            }

            return result.sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
        }.value
    }

    private func upsertEntry(key: String, value: String) {
        Task {
            do {
                if isGlobal {
                    try await cache.upsertEntry(key: key, value: value, type: type)
                } else {
                    let isName = type == .names
                    try await TranslationManager.shared.saveCustomEntry(
                        word: key, meaning: value, isName: isName, bookId: bookId
                    )
                    let entries = await loadBookEntries()
                    bookEntries = entries
                }
                showToast("Đã lưu: \(key)", isError: false)
            } catch {
                showToast("Lỗi: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func updateKey(oldKey: String, newKey: String, newValue: String) {
        Task {
            do {
                if isGlobal {
                    try await cache.updateKey(oldKey: oldKey, newKey: newKey, newValue: newValue, type: type)
                } else {
                    let isName = type == .names
                    if newKey != oldKey {
                        // Keep oldKey (do not delete), just save newKey
                        try await TranslationManager.shared.saveCustomEntry(
                            word: newKey, meaning: newValue, isName: isName, bookId: bookId
                        )
                    } else {
                        // Save (update) oldKey
                        try await TranslationManager.shared.saveCustomEntry(
                            word: oldKey, meaning: newValue, isName: isName, bookId: bookId
                        )
                    }
                    let entries = await loadBookEntries()
                    bookEntries = entries
                }
                showToast("Đã cập nhật: \(oldKey) → \(newKey)", isError: false)
            } catch {
                showToast("Lỗi: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func deleteEntry(_ entry: DictEntry) {
        Task {
            do {
                if isGlobal {
                    try await cache.deleteEntry(key: entry.key, type: type)
                } else {
                    let isName = type == .names
                    try await TranslationManager.shared.deleteCustomEntry(
                        word: entry.key, isName: isName, bookId: bookId
                    )
                    let entries = await loadBookEntries()
                    bookEntries = entries
                }
                showToast("Đã xóa: \(entry.key)", isError: false)
            } catch {
                showToast("Lỗi: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func importFile(from url: URL) {
        Task {
            do {
                if isGlobal {
                    try await cache.importEntries(from: url, type: type)
                } else {
                    guard let bid = bookId else { return }
                    let bookDir = TranslationManager.shared.translateDirectory
                        .appendingPathComponent("books").appendingPathComponent(bid)
                    try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
                    let datUrl = bookDir.appendingPathComponent("\(type.fileName).dat")
                    try await Task.detached(priority: .userInitiated) {
                        try DoubleArrayTrieBuilder().build(fromTxtFile: url, toDatFile: datUrl)
                    }.value

                    // Clean up .txt if exists
                    let txtUrl = bookDir.appendingPathComponent("\(type.fileName).txt")
                    try? FileManager.default.removeItem(at: txtUrl)

                    TranslateUtils.clearCache()
                    TranslationManager.shared.clearBookDictCache(for: bid)
                    let entries = await loadBookEntries()
                    bookEntries = entries
                }
                showToast("Import thành công!", isError: false)
            } catch {
                showToast("Lỗi import: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func exportText() -> String {
        var content = ""
        for entry in allEntries {
            content += "\(entry.key)=\(entry.value)\n"
        }
        return content
    }

    private func showToast(_ message: String, isError: Bool) {
        toastMessage = message
        isToastError = isError
        withAnimation(.spring()) { showingToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut) { showingToast = false }
            }
        }
    }
}

// MARK: - Add/Edit Sheet

enum DictSheetMode: Identifiable {
    case add
    case edit(key: String, value: String)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let key, _): return "edit_\(key)"
        }
    }
}

struct DictEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: DictSheetMode
    let onSave: (String, String) -> Void

    @State private var key: String
    @State private var value: String

    init(mode: DictSheetMode, onSave: @escaping (String, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _key = State(initialValue: "")
            _value = State(initialValue: "")
        case .edit(let k, let v):
            _key = State(initialValue: k)
            _value = State(initialValue: v)
        }
    }

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isAdd ? "Thêm từ mới" : "Chỉnh sửa") {
                    TextField("Từ gốc (key)", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Nghĩa dịch (value)", text: $value)
                        .autocorrectionDisabled()
                }

                if !isAdd {
                    Section {
                        Text("Nếu thay đổi từ gốc thành từ khác đã tồn tại, nghĩa của từ đó sẽ bị ghi đè.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(isAdd ? "Thêm từ" : "Sửa từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(k, v)
                        dismiss()
                    }
                    .disabled(
                        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}
