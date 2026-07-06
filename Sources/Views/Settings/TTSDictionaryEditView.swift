import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct TTSDictionaryEditView: View {
    @ObservedObject var ttsManager = TTSManager.shared
    @State private var allWords: [String: String] = [:]
    @State private var sortedKeys: [String] = []
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingKey: String? = nil
    @State private var editingValue: String = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var exportURL: URL? = nil
    @State private var exportJsonURL: URL? = nil
    @State private var exportCsvURL: URL? = nil
    
    @State private var showingFileImporter = false
    @State private var showingDownloadConfirmation = false
    @State private var toastMessage = ""
    @State private var showingToast = false
    @State private var isToastError = false
    @State private var visibleCount = 100

    private func showToast(_ message: String, isError: Bool) {
        toastMessage = message
        isToastError = isError
        withAnimation(.spring()) {
            showingToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut) {
                    showingToast = false
                }
            }
        }
    }

    var matchedKeys: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return sortedKeys
        } else {
            return sortedKeys.filter { $0.contains(query) }
        }
    }

    var filteredKeys: [String] {
        return Array(matchedKeys.prefix(visibleCount))
    }

    var body: some View {
        ZStack {
            VStack {
                if isLoading {
                    ProgressView("Đang tải từ điển...")
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        if searchText.isEmpty {
                            Section {
                                if filteredKeys.count < sortedKeys.count {
                                    Text("Hiển thị \(filteredKeys.count)/\(sortedKeys.count) từ. Cuộn xuống để tải thêm.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Đã hiển thị toàn bộ \(sortedKeys.count) từ.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Section {
                                if filteredKeys.count < matchedKeys.count {
                                    Text("Hiển thị \(filteredKeys.count)/\(matchedKeys.count) từ kết quả. Cuộn xuống để tải thêm.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Đã hiển thị toàn bộ \(matchedKeys.count) từ kết quả.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Section {
                            ForEach(filteredKeys, id: \.self) { key in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(allWords[key] ?? "")
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
                                    editingKey = key
                                    editingValue = allWords[key] ?? ""
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteWord(key: key)
                                    } label: {
                                        Label("Xóa", systemImage: "trash")
                                    }
                                }
                                .onAppear {
                                    if key == filteredKeys.last && visibleCount < matchedKeys.count {
                                        visibleCount += 100
                                    }
                                }
                            }
                        } header: {
                            Text("Từ vựng (\(allWords.count) từ)")
                        }
                    }
                    .searchable(text: $searchText, prompt: "Tìm từ...")
                    .onChange(of: searchText) { oldValue, newValue in
                        visibleCount = 100
                    }
                    .overlay {
                        if filteredKeys.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Không tìm thấy kết quả cho \"\(searchText)\"")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Sửa từ điển")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            if let plistURL = exportURL {
                                ShareLink("Property List (.plist)", item: plistURL)
                            }
                            if let jsonURL = exportJsonURL {
                                ShareLink("JSON (.json)", item: jsonURL)
                            }
                            if let csvURL = exportCsvURL {
                                ShareLink("CSV (.csv)", item: csvURL)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            showingFileImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .sheet(isPresented: $showingFileImporter) {
                            DocumentPicker(
                                allowedContentTypes: [.propertyList, .json, .commaSeparatedText, .plainText],
                                allowsMultipleSelection: false,
                                onPick: { urls in
                                    guard let selectedURL = urls.first else { return }
                                    let ext = selectedURL.pathExtension.lowercased()
                                    if ext != "plist" && ext != "json" && ext != "csv" && ext != "txt" {
                                        showToast("Vui lòng chọn tệp từ điển (.plist, .json, hoặc .csv/.txt).", isError: true)
                                        return
                                    }
                                    let hasAccess = selectedURL.startAccessingSecurityScopedResource()
                                    importDictionary(from: selectedURL, hasAccess: hasAccess)
                                },
                                onCancel: {
                                    showingFileImporter = false
                                }
                            )
                        }

                        Button {
                            showingDownloadConfirmation = true
                        } label: {
                            Image(systemName: "arrow.down.to.line")
                        }
                        .alert("Xác nhận tải lại", isPresented: $showingDownloadConfirmation) {
                            Button("Hủy", role: .cancel) {}
                            Button("Tải lại", role: .destructive) {
                                downloadDictionaries()
                            }
                        } message: {
                            Text("Hành động này sẽ tải lại từ điển gốc từ HuggingFace và ghi đè tất cả các từ vựng tùy chỉnh bạn đã thêm. Bạn có chắc chắn muốn tiếp tục?")
                        }

                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .sheet(isPresented: $showingAddSheet) {
                            AddWordSheet(onAdd: { key, val in
                                addWord(key: key, value: val)
                            })
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { editingKey.map { EditingEntry(key: $0, value: editingValue) } },
                set: { editingKey = $0?.key; editingValue = $0?.value ?? "" }
            )) { entry in
                EditWordSheet(key: entry.key, value: entry.value) { newVal in
                    updateWord(key: entry.key, value: newVal)
                }
            }
            .task {
                await loadDictionary()
            }
            
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
                    .background(
                        Capsule()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.9))
                    )
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func loadDictionary() async {
        isLoading = true
        let map = await TextPreprocessor.shared.getWordMap()
        allWords = map
        sortedKeys = map.keys.sorted()
        
        let fm = FileManager.default
        if let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let plistURL = cachesURL.appendingPathComponent("non-vietnamese-words.plist")
            let jsonURL = cachesURL.appendingPathComponent("dictionary.json")
            let csvURL = cachesURL.appendingPathComponent("dictionary.csv")
            
            if let plistData = try? PropertyListSerialization.data(fromPropertyList: map, format: .xml, options: 0) {
                try? plistData.write(to: plistURL, options: .atomic)
                exportURL = plistURL
            }
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: map, options: [.prettyPrinted, .sortedKeys]) {
                try? jsonData.write(to: jsonURL, options: .atomic)
                exportJsonURL = jsonURL
            }
            
            let csvString = generateCSV(from: map)
            if let csvData = csvString.data(using: .utf8) {
                try? csvData.write(to: csvURL, options: .atomic)
                exportCsvURL = csvURL
            }
        }
        
        isLoading = false
    }

    private func downloadDictionaries() {
        isLoading = true
        Task {
            do {
                try await ttsManager.nghiTTSClient?.downloadDictionaries()
                await loadDictionary()
                showToast("Tải từ điển từ HuggingFace thành công!", isError: false)
            } catch {
                showToast("Không thể tải từ điển: \(error.localizedDescription)", isError: true)
            }
            isLoading = false
        }
    }

    private func parseCSV(data: Data) throws -> [String: String] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CSVParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể đọc tệp CSV dưới dạng UTF-8."])
        }
        
        var dict: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            var fields: [String] = []
            var currentField = ""
            var insideQuotes = false
            
            let chars = Array(trimmed)
            var idx = 0
            while idx < chars.count {
                let char = chars[idx]
                
                if char == "\"" {
                    if insideQuotes && idx + 1 < chars.count && chars[idx + 1] == "\"" {
                        currentField.append("\"")
                        idx += 2
                        continue
                    } else {
                        insideQuotes.toggle()
                    }
                } else if char == "," && !insideQuotes {
                    fields.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentField = ""
                } else {
                    currentField.append(char)
                }
                idx += 1
            }
            fields.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
            
            if fields.count >= 2 {
                let key = fields[0]
                let val = fields[1]
                
                if (key == "Từ gốc" || key.lowercased() == "key" || key.lowercased() == "original") &&
                   (val == "Thay thế" || val.lowercased() == "value" || val.lowercased() == "replacement") {
                    continue
                }
                
                if !key.isEmpty {
                    dict[key.lowercased()] = val
                }
            }
        }
        
        if dict.isEmpty {
            throw NSError(domain: "CSVParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tệp CSV không chứa dữ liệu từ điển hợp lệ hoặc sai cấu trúc."])
        }
        return dict
    }
    
    private func generateCSV(from dict: [String: String]) -> String {
        var csvContent = "Từ gốc,Thay thế\n"
        let sortedKeys = dict.keys.sorted()
        for key in sortedKeys {
            let val = dict[key] ?? ""
            let escapedKey = key.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedVal = val.replacingOccurrences(of: "\"", with: "\"\"")
            csvContent += "\"\(escapedKey)\",\"\(escapedVal)\"\n"
        }
        return csvContent
    }

    private func importDictionary(from url: URL, hasAccess: Bool) {
        isLoading = true
        Task {
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = resourceValues.fileSize ?? 0
                if fileSize <= 0 {
                    throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp tin từ điển trống hoặc không hợp lệ."])
                }
                if fileSize > 5_242_880 { // 5MB
                    throw NSError(domain: "DictionaryEditView", code: 413, userInfo: [NSLocalizedDescriptionKey: "Kích thước tệp tin từ điển vượt quá giới hạn 5MB."])
                }
                
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension.lowercased()
                
                var importedWords: [String: String] = [:]
                
                if ext == "plist" {
                    guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
                        throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp .plist không hợp lệ. Vui lòng chọn tệp chứa định dạng [String: String]."])
                    }
                    importedWords = dict
                } else if ext == "json" {
                    let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = jsonObject as? [String: String] {
                        importedWords = dict
                    } else if let dictAny = jsonObject as? [String: Any] {
                        for (key, value) in dictAny {
                            if let stringValue = value as? String {
                                importedWords[key] = stringValue
                            } else if let numberValue = value as? NSNumber {
                                importedWords[key] = numberValue.stringValue
                            } else if let boolValue = value as? Bool {
                                importedWords[key] = String(boolValue)
                            }
                        }
                        if importedWords.isEmpty {
                            throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp .json không hợp lệ. Vui lòng chọn tệp chứa dạng cặp khóa-giá trị phẳng [String: String]."])
                        }
                    } else {
                        throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp .json không hợp lệ. Vui lòng chọn tệp chứa dạng cặp khóa-giá trị phẳng [String: String]."])
                    }
                } else if ext == "csv" || ext == "txt" {
                    importedWords = try parseCSV(data: data)
                } else {
                    throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Định dạng tệp không được hỗ trợ."])
                }
                
                guard let localWordsURL = TextPreprocessor.getWordsURL() else {
                    throw NSError(domain: "DictionaryEditView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không thể định vị đường dẫn lưu từ điển."])
                }
                
                let plistData = try PropertyListSerialization.data(fromPropertyList: importedWords, format: .xml, options: 0)
                try plistData.write(to: localWordsURL, options: .atomic)
                
                await TextPreprocessor.shared.loadResources()
                await loadDictionary()
                
                showToast("Nhập từ điển thành công! Đã cập nhật \(importedWords.count) từ.", isError: false)
            } catch {
                showToast("Lỗi nhập từ điển: \(error.localizedDescription)", isError: true)
            }
            isLoading = false
        }
    }

    private func addWord(key: String, value: String) {
        Task {
            do {
                try await TextPreprocessor.shared.updateWord(key: key, value: value)
                await loadDictionary()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateWord(key: String, value: String) {
        Task {
            do {
                try await TextPreprocessor.shared.updateWord(key: key, value: value)
                await loadDictionary()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteWord(key: String) {
        Task {
            do {
                try await TextPreprocessor.shared.deleteWord(key: key)
                await loadDictionary()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct EditingEntry: Identifiable {
    let id: String
    let key: String
    let value: String

    init(key: String, value: String) {
        self.id = key
        self.key = key
        self.value = value
    }
}

struct AddWordSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var value = ""
    @State private var validationError: String? = nil

    let onAdd: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin từ mới") {
                    TextField("Từ gốc (tiếng Anh/Nhật, e.g. apple)", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: key) { oldValue, newValue in
                            validateKey(newValue)
                        }

                    TextField("Phiên âm tiếng Việt (e.g. ép pô)", text: $value)
                        .autocorrectionDisabled()
                }

                if let validationError = validationError {
                    Section {
                        Text(validationError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Thêm từ mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onAdd(key, value)
                        dismiss()
                    }
                    .disabled(key.trimmed.isEmpty || value.trimmed.isEmpty || validationError != nil)
                }
            }
        }
    }

    private func validateKey(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(" ") {
            validationError = "Từ gốc không được chứa khoảng trắng"
        } else if trimmed.rangeOfCharacter(from: CharacterSet.punctuationCharacters) != nil {
            validationError = "Từ gốc không được chứa dấu câu"
        } else {
            validationError = nil
        }
    }
}

struct EditWordSheet: View {
    @Environment(\.dismiss) var dismiss
    let key: String
    @State private var value: String
    let onSave: (String) -> Void

    init(key: String, value: String, onSave: @escaping (String) -> Void) {
        self.key = key
        self._value = State(initialValue: value)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sửa phiên âm") {
                    LabeledContent("Từ gốc", value: key)
                        .foregroundStyle(.secondary)

                    TextField("Phiên âm tiếng Việt", text: $value)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Sửa từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(value)
                        dismiss()
                    }
                    .disabled(value.trimmed.isEmpty)
                }
            }
        }
    }
}
