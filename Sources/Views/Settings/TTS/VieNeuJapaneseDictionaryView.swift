import SwiftUI
import UniformTypeIdentifiers

/// Màn **từ điển phiên âm tiếng Nhật của VieNeu-TTS**.
///
/// ## Độc lập hoàn toàn với từ điển của NghiTTS
/// Dữ liệu nằm ở `VieNeuJapaneseDictionary` (file `FreeBook/TTS/phien-am-tieng-nhat.plist`), **không** có
/// nút sao chép giữa hai bên: sửa bên này không bao giờ làm đổi cách đọc bên kia (người dùng chốt
/// 2026-10-01). Khoá luôn được **gấp dấu phụ** trước khi lưu — lúc đọc app tra bằng khoá đã gấp, nên khoá
/// còn macron là mục chết.
///
/// ## Hai công tắc áp dụng **không** nằm ở đây — có ý
/// "Áp dụng từ điển phiên âm VieNeu" và "Tự động phiên âm tiếng Nhật" chỉ có ở *Cài đặt TTS → Quản lý riêng
/// của trình đọc*. Màn này chỉ hiện **dòng trạng thái**, vì cả hai cờ mặc định **TẮT** ⇒ vừa thêm từ xong
/// sẽ chưa nghe thấy khác, và đó là chỗ dễ tưởng tính năng hỏng nhất.
///
/// ## Vì sao dùng lại `EditWordSheet` của màn NghiTTS
/// Trần "1 type chính / file" của `check_architecture.py`: khai thêm một `struct` sửa-từ ở file này là một
/// vi phạm mới. `EditWordSheet` (`TTSDictionaryEditView.swift:519`) đã `internal` nên dùng lại được.
struct VieNeuJapaneseDictionaryView: View {
    struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @State private var allWords: [String: String] = [:]
    @State private var sortedKeys: [String] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingAddSheet = false
    @State private var showingFileImporter = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingDownloadConfirmation = false
    @State private var exportDocumentToShare: ExportDocument? = nil
    @State private var visibleCount = 100
    @State private var editingKey: String? = nil
    @State private var editingValue = ""

    private var matchedKeys: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sortedKeys }
        return sortedKeys.filter { $0.contains(query) }
    }

    private var filteredKeys: [String] {
        Array(matchedKeys.prefix(visibleCount))
    }

    var body: some View {
        ZStack {
            VStack {
                if isLoading {
                    ProgressView("Đang tải từ điển...")
                        .frame(maxHeight: .infinity)
                } else {
                    listContent
                }
            }
        }
        .navigationTitle("Từ điển phiên âm VieNeu-TTS")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .searchable(text: $searchText, prompt: "Tìm từ")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingDownloadConfirmation = true
                    } label: {
                        Label("Tải từ điển từ HuggingFace", systemImage: "arrow.down.circle")
                    }
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Nhập từ file…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        export(asJSON: false)
                    } label: {
                        Label("Xuất .plist", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        export(asJSON: true)
                    } label: {
                        Label("Xuất .json", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        Label("Xoá tất cả phiên âm", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWordSheet(initialKey: searchText, showSuggestions: true, target: .vieNeu) { key, val, _ in
                addWord(key: key, value: val)
            }
        }
        .sheet(isPresented: $showingFileImporter) {
            DocumentPicker(
                allowedContentTypes: [.propertyList, .json, .plainText],
                allowsMultipleSelection: false,
                onPick: { urls in
                    showingFileImporter = false
                    guard let selectedURL = urls.first else { return }
                    let ext = selectedURL.pathExtension.lowercased()
                    guard ext == "plist" || ext == "json" else {
                        ToastManager.shared.show(message: "Vui lòng chọn tệp từ điển (.plist hoặc .json).", type: .error)
                        return
                    }
                    let hasAccess = selectedURL.startAccessingSecurityScopedResource()
                    importDictionary(from: selectedURL, hasAccess: hasAccess)
                },
                onCancel: { showingFileImporter = false }
            )
        }
        .sheet(item: Binding(
            get: { editingKey.map { EditableEntry(key: $0, value: editingValue) } },
            set: { editingKey = $0?.key; editingValue = $0?.value ?? "" }
        )) { entry in
            EditWordSheet(key: entry.key, value: entry.value) { newValue in
                addWord(key: entry.key, value: newValue)
            }
        }
        .sheet(item: $exportDocumentToShare) { doc in
            ShareSheet(activityItems: [doc.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Xuất từ điển thành công!", type: .success)
                } else if let error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .confirmationDialog(
            "Xoá toàn bộ từ điển tiếng Nhật của VieNeu?",
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Xoá tất cả (\(allWords.count) mục)", role: .destructive) { deleteAll() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Chỉ xoá từ điển của VieNeu, **không** đụng từ điển của NghiTTS. Không khôi phục được.")
        }
        .confirmationDialog(
            "Tải từ điển từ HuggingFace?",
            isPresented: $showingDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Tải về và trộn") { downloadDictionary() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Bản tải về được **trộn** với bản dưới máy; mục bạn đã thêm hoặc sửa **không** bị ghi đè.")
        }
        .task { await loadDictionary() }
    }

    /// Bọc khoá + giá trị cho `sheet(item:)`.
    private struct EditableEntry: Identifiable {
        var id: String { key }
        let key: String
        let value: String
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var listContent: some View {
        List {
            statusSection

            if allWords.isEmpty {
                Section {
                    Text("Chưa có từ nào. Bấm **Tải từ điển từ HuggingFace** ở góc trên, hoặc bấm “Thêm từ mới”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       allWords[searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] == nil {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Thêm mới phiên âm cho '\(searchText)'", systemImage: "plus.circle.fill")
                        }
                    }
                    ForEach(filteredKeys, id: \.self) { key in
                        row(key: key)
                    }
                    if filteredKeys.count < matchedKeys.count {
                        Button("Hiển thị thêm 100 từ (\(filteredKeys.count)/\(matchedKeys.count))") {
                            visibleCount += 100
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Từ vựng (\(allWords.count) từ)")
                } footer: {
                    Text("Khoá được lưu ở dạng **đã gấp dấu phụ** (`otōto` → `ototo`) — đúng cách app tra lúc đọc. Bấm một dòng để sửa cách đọc; vuốt để xoá.")
                }
            }
        }
    }

    @ViewBuilder
    private func row(key: String) -> some View {
        Button {
            editingKey = key
            editingValue = allWords[key] ?? ""
        } label: {
            HStack {
                Text(key)
                    .foregroundStyle(.primary)
                Spacer()
                Text(allWords[key] ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteWord(key)
            } label: {
                Label("Xoá", systemImage: "trash")
            }
        }
    }

    /// Dòng trạng thái 2 công tắc — **chỉ đọc**, không có công tắc ở màn này (chúng ở Cài đặt TTS).
    @ViewBuilder
    private var statusSection: some View {
        Section {
            LabeledContent("Áp dụng từ điển", value: JapaneseFlags.dictionaryEnabled ? "Đang bật" : "Đang tắt")
            LabeledContent("Tự động phiên âm tiếng Nhật", value: JapaneseFlags.transliterationEnabled ? "Đang bật" : "Đang tắt")
        } footer: {
            if JapaneseFlags.dictionaryEnabled {
                Text("Từ khớp trong bảng này được đọc theo đúng cột phải.")
            } else {
                Text("Đang **tắt** áp dụng ⇒ thêm từ ở đây vẫn **chưa** nghe thấy khác. Bật ở **Cài đặt TTS → Quản lý riêng của trình đọc**.")
            }
        }
    }

    /// Đọc thẳng `UserDefaults` mỗi lần vẽ — hai cờ này do màn Cài đặt TTS ghi, không phải `@State` ở đây.
    private enum JapaneseFlags {
        static var dictionaryEnabled: Bool {
            UserDefaults.standard.bool(forKey: VieNeuJapanesePreprocessor.dictionaryEnabledKey)
        }
        static var transliterationEnabled: Bool {
            UserDefaults.standard.bool(forKey: VieNeuJapanesePreprocessor.japaneseTransliterationEnabledKey)
        }
    }

    // MARK: - Hành động

    private func loadDictionary() async {
        isLoading = true
        let map = await VieNeuJapaneseDictionary.shared.all()
        allWords = map
        sortedKeys = map.keys.sorted()
        isLoading = false
    }

    private func persist(_ words: [String: String], successMessage: String) {
        _ = Task {
            do {
                try await VieNeuJapaneseDictionary.shared.replaceAll(words)
                await loadDictionary()
                ToastManager.shared.show(message: successMessage, type: .success)
            } catch {
                ToastManager.shared.show(message: "Lưu thất bại: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func addWord(key: String, value: String) {
        let normalized = VieNeuJapaneseDictionary.normalizedKey(key)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !trimmed.isEmpty else { return }
        var words = allWords
        words[normalized] = trimmed
        persist(words, successMessage: "Đã thêm phiên âm: \(normalized)")
    }

    private func deleteWord(_ key: String) {
        var words = allWords
        words.removeValue(forKey: key)
        persist(words, successMessage: "Đã xoá: \(key)")
    }

    private func deleteAll() {
        persist([:], successMessage: "Đã xoá toàn bộ từ điển VieNeu.")
    }

    private func downloadDictionary() {
        isLoading = true
        _ = Task {
            do {
                try await VieNeuJapaneseDictionary.shared.downloadInitialDictionary()
                await loadDictionary()
                ToastManager.shared.show(message: "Tải từ điển từ HuggingFace thành công!", type: .success)
            } catch {
                ToastManager.shared.show(message: "Không thể tải từ điển: \(error.localizedDescription)", type: .error)
            }
            isLoading = false
        }
    }

    private func export(asJSON: Bool) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            ToastManager.shared.show(message: "Không định vị được thư mục cache.", type: .error)
            return
        }
        let url = caches.appendingPathComponent(asJSON ? "vieneu-japanese-words.json" : VieNeuJapaneseDictionary.fileName)
        do {
            let data: Data
            if asJSON {
                data = try JSONSerialization.data(withJSONObject: allWords, options: [.prettyPrinted, .sortedKeys])
            } else {
                data = try PropertyListSerialization.data(fromPropertyList: allWords, format: .xml, options: 0)
            }
            try data.write(to: url, options: .atomic)
            exportDocumentToShare = ExportDocument(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
        }
    }

    private func importDictionary(from url: URL, hasAccess: Bool) {
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            ToastManager.shared.show(message: "Không đọc được file.", type: .error)
            return
        }
        let parsed: [String: String]?
        if url.pathExtension.lowercased() == "plist" {
            parsed = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String]
        } else {
            parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
        }
        guard let imported = parsed, !imported.isEmpty else {
            ToastManager.shared.show(message: "File không phải từ điển .plist/.json hợp lệ.", type: .error)
            return
        }
        // Chuẩn hoá khoá rồi **trộn**: mục trùng khoá lấy bản vừa nhập.
        var words = allWords
        for (rawKey, rawValue) in imported {
            let key = VieNeuJapaneseDictionary.normalizedKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            words[key] = value
        }
        persist(words, successMessage: "Đã nhập \(imported.count) mục (tổng \(words.count)).")
    }
}
