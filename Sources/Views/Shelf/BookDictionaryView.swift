import SwiftUI
import UniformTypeIdentifiers

struct BookDictEntry: Identifiable, Hashable {
    var id: String { "\(isName ? "name" : "vp")_\(word)" }
    let word: String
    let meaning: String
    let isName: Bool
}

struct BookDictionaryView: View {
    let bookId: String
    
    @State private var entries: [BookDictEntry] = []
    @State private var searchQuery = ""
    
    // Form thêm từ mới
    @State private var newWord = ""
    @State private var newMeaning = ""
    @State private var isNameType = false
    
    @State private var showingFileImporter = false
    @State private var importType = "vietphrase" // "vietphrase", "names"
    
    var filteredEntries: [BookDictEntry] {
        if searchQuery.isEmpty {
            return entries
        }
        return entries.filter {
            $0.word.localizedCaseInsensitiveContains(searchQuery) ||
            $0.meaning.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Mẫu thêm từ mới
            VStack(alignment: .leading, spacing: 12) {
                Text("Thêm Từ Điển Riêng")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    TextField("Chữ gốc (Hán)", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    TextField("Nghĩa dịch (Việt)", text: $newMeaning)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                HStack {
                    Picker("Loại", selection: $isNameType) {
                        Text("VietPhrase").tag(false)
                        Text("Tên riêng (Name)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    
                    Spacer()
                    
                    Button(action: addEntry) {
                        Text("Thêm Từ")
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(newWord.isEmpty || newMeaning.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(newWord.isEmpty || newMeaning.isEmpty)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            
            // Tìm kiếm & Danh sách
            SearchBar(text: $searchQuery, placeholder: "Tìm kiếm từ đã thêm...")
                .padding(.vertical, 8)
            
            List {
                Section(header: Text("Từ Điển Riêng (\(filteredEntries.count))")) {
                    if filteredEntries.isEmpty {
                        Text("Không tìm thấy từ nào")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                            .padding(.vertical)
                    } else {
                        ForEach(filteredEntries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.word)
                                        .font(.body)
                                        .fontWeight(.bold)
                                    Text(entry.meaning)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(entry.isName ? "Name" : "VietPhrase")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(entry.isName ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                                    .foregroundColor(entry.isName ? .orange : .blue)
                                    .cornerRadius(4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteEntry(entry)
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
        .navigationTitle("Từ Điển Truyện")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        importType = "vietphrase"
                        showingFileImporter = true
                    }) {
                        Label("Nhập VietPhrase (.txt)", systemImage: "arrow.down.doc")
                    }
                    Button(action: {
                        importType = "names"
                        showingFileImporter = true
                    }) {
                        Label("Nhập Names (.txt)", systemImage: "arrow.down.doc")
                    }
                    
                    if !entries.isEmpty {
                        ShareLink(item: exportContent()) {
                            Label("Xuất từ điển riêng", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            loadEntries()
        }
        .background(
            DocumentPickerPresenter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false,
                onPick: { urls in
                    guard let selectedUrl = urls.first else { return }
                    let accessing = selectedUrl.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            selectedUrl.stopAccessingSecurityScopedResource()
                        }
                    }
                    Task {
                        do {
                            let datFileName = (importType == "names") ? "Names.dat" : "VietPhrase.dat"
                            let bookDir = TranslationManager.shared.translateDirectory.appendingPathComponent("books").appendingPathComponent(bookId)
                            try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
                            let datUrl = bookDir.appendingPathComponent(datFileName)
                            
                            try DoubleArrayTrieBuilder().build(fromTxtFile: selectedUrl, toDatFile: datUrl)
                            
                            let txtFileName = (importType == "names") ? "Names.txt" : "VietPhrase.txt"
                            let txtUrl = bookDir.appendingPathComponent(txtFileName)
                            try? FileManager.default.removeItem(at: txtUrl)
                            
                            TranslateUtils.clearCache()
                            TranslationManager.shared.clearBookDictCache(for: bookId)
                            loadEntries()
                        } catch {
                            // AppLogger.shared.log("❌ Lỗi import từ điển truyện: \(error.localizedDescription)")
                        }
                    }
                },
                onCancel: nil
            )
        )
    }
    
    private func loadEntries() {
        let bookDir = TranslationManager.shared.translateDirectory.appendingPathComponent("books").appendingPathComponent(bookId)
        let vpDatUrl = bookDir.appendingPathComponent("VietPhrase.dat")
        let namesDatUrl = bookDir.appendingPathComponent("Names.dat")
        let vpTxtUrl = bookDir.appendingPathComponent("VietPhrase.txt")
        let namesTxtUrl = bookDir.appendingPathComponent("Names.txt")
        
        var temp: [BookDictEntry] = []
        
        // Load VietPhrase
        if FileManager.default.fileExists(atPath: vpDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: vpDatUrl)
            if dat.isLoaded {
                for entry in dat.allEntries() {
                    temp.append(BookDictEntry(word: entry.key, meaning: entry.value, isName: false))
                }
            }
        } else if let content = try? String(contentsOf: vpTxtUrl, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.components(separatedBy: "=")
                if parts.count >= 2 {
                    let w = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let m = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !w.isEmpty {
                        temp.append(BookDictEntry(word: w, meaning: m, isName: false))
                    }
                }
            }
        }
        
        // Load Names
        if FileManager.default.fileExists(atPath: namesDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: namesDatUrl)
            if dat.isLoaded {
                for entry in dat.allEntries() {
                    temp.append(BookDictEntry(word: entry.key, meaning: entry.value, isName: true))
                }
            }
        } else if let content = try? String(contentsOf: namesTxtUrl, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.components(separatedBy: "=")
                if parts.count >= 2 {
                    let w = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let m = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !w.isEmpty {
                        temp.append(BookDictEntry(word: w, meaning: m, isName: true))
                    }
                }
            }
        }
        
        self.entries = temp
    }
    
    private func addEntry() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = newMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !word.isEmpty && !meaning.isEmpty else { return }
        
        Task {
            do {
                try await TranslationManager.shared.saveCustomEntry(word: word, meaning: meaning, isName: isNameType, bookId: bookId)
                await MainActor.run {
                    newWord = ""
                    newMeaning = ""
                    loadEntries()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi lưu từ điển: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteEntry(_ entry: BookDictEntry) {
        Task {
            do {
                try await TranslationManager.shared.deleteCustomEntry(word: entry.word, isName: entry.isName, bookId: bookId)
                await MainActor.run {
                    loadEntries()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi xóa từ: \(error.localizedDescription)")
            }
        }
    }
    
    private func exportContent() -> String {
        var content = ""
        for entry in entries {
            content += "\(entry.word)=\(entry.meaning)\n"
        }
        return content
    }
}

// Thanh tìm kiếm đơn giản
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
