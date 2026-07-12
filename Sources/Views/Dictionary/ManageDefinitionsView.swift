import SwiftUI

struct ManageDefinitionsView: View {
    let word: String
    let bookId: String
    @Binding var matches: [DictionaryMatchInfo]
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var localMatches: [DictionaryMatchInfo] = []
    @State private var deletedMeanings: [String: Set<String>] = [:]
    @State private var hasSaved = false
    
    init(word: String, bookId: String, matches: Binding<[DictionaryMatchInfo]>, onChanged: @escaping () -> Void) {
        self.word = word
        self.bookId = bookId
        self._matches = matches
        self.onChanged = onChanged
        self._localMatches = State(initialValue: matches.wrappedValue)
    }
    
    // State nhập nghĩa ở cuối section
    @State private var newNamesRieng = ""
    @State private var newNamesChung = ""
    @State private var newVPRieng = ""
    @State private var newVPChung = ""
    
    // State dùng cho việc chèn nghĩa mới trước một nghĩa hiện tại
    @State private var showingInsertAlert = false
    @State private var insertMeaningText = ""
    @State private var targetSource = ""
    @State private var targetIndex = 0
    @State private var targetMeaningName = ""
    
    private func getHanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in word {
            list.append(phienAm[String(char)] ?? String(char))
        }
        return list.joined(separator: " ").lowercased()
    }
    
    private func splitMeanings(_ translation: String) -> [String] {
        let clean = translation.replacingOccurrences(of: "¦", with: "/")
        return clean.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Từ đang chọn")) {
                    Text(word)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Section(header: Text("Phiên âm")) {
                    Text(getHanViet(for: word))
                        .font(.body)
                }
                
                makeDictionarySection(title: "Name (Riêng)", source: "Names (Riêng)")
                makeDictionarySection(title: "Name (Chung)", source: "Names (Chung)")
                makeDictionarySection(title: "VietPhrase (Riêng)", source: "VietPhrase (Riêng)")
                makeDictionarySection(title: "VietPhrase (Chung)", source: "VietPhrase (Chung)")
            }
            .navigationTitle("Quản lý nghĩa từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
            // Hộp thoại nhập nghĩa mới chèn trước một nghĩa hiện tại
            .alert("Thêm nghĩa mới", isPresented: $showingInsertAlert) {
                TextField("Nhập nghĩa...", text: $insertMeaningText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Thêm", action: {
                    insertMeaningAtTarget()
                })
                Button("Hủy", role: .cancel, action: {})
            } message: {
                Text("Nghĩa mới sẽ được chèn trước '\(targetMeaningName)'")
            }
            .onDisappear {
                saveAllChangesToDisk()
            }
        }
    }
    
    @ViewBuilder
    private func makeDictionarySection(title: String, source: String) -> some View {
        let match = localMatches.first(where: { $0.source == source })
        let meanings = match != nil ? splitMeanings(match!.translation) : []
        
        Section(header: Text(title)) {
            if meanings.isEmpty {
                Text("Chưa có định nghĩa nào")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(meanings.enumerated()), id: \.offset) { index, meaning in
                    let isDeleted = deletedMeanings[source]?.contains(meaning) ?? false
                    HStack {
                        Text(meaning)
                            .font(.body)
                            .strikethrough(isDeleted)
                            .foregroundColor(isDeleted ? .secondary : .primary)
                        
                        Spacer()
                        
                        if isDeleted {
                            Button(action: {
                                restoreSingleMeaning(meaningToRestore: meaning, source: source)
                            }) {
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            // Nút thêm trước nghĩa này
                            Button(action: {
                                targetSource = source
                                targetIndex = index
                                targetMeaningName = meaning
                                insertMeaningText = ""
                                showingInsertAlert = true
                            }) {
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                            }
                            .buttonStyle(.borderless)
                            
                            // Nút xóa nghĩa này
                            Button(role: .destructive, action: {
                                deleteSingleMeaning(meaningToRemove: meaning, source: source)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 6)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            
            // Hàng nhập thêm nghĩa ở cuối section
            HStack {
                if source == "Names (Riêng)" {
                    TextField("Thêm nghĩa ở cuối...", text: $newNamesRieng)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            addSingleMeaning(newMeaning: newNamesRieng, source: source)
                        }
                    Button(action: {
                        addSingleMeaning(newMeaning: newNamesRieng, source: source)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newNamesRieng.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else if source == "Names (Chung)" {
                    TextField("Thêm nghĩa ở cuối...", text: $newNamesChung)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            addSingleMeaning(newMeaning: newNamesChung, source: source)
                        }
                    Button(action: {
                        addSingleMeaning(newMeaning: newNamesChung, source: source)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newNamesChung.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else if source == "VietPhrase (Riêng)" {
                    TextField("Thêm nghĩa ở cuối...", text: $newVPRieng)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            addSingleMeaning(newMeaning: newVPRieng, source: source)
                        }
                    Button(action: {
                        addSingleMeaning(newMeaning: newVPRieng, source: source)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newVPRieng.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else if source == "VietPhrase (Chung)" {
                    TextField("Thêm nghĩa ở cuối...", text: $newVPChung)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            addSingleMeaning(newMeaning: newVPChung, source: source)
                        }
                    Button(action: {
                        addSingleMeaning(newMeaning: newVPChung, source: source)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newVPChung.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func getMeanings(for source: String) -> [String] {
        guard let match = localMatches.first(where: { $0.source == source }) else { return [] }
        return splitMeanings(match.translation)
    }
    
    private func setMeanings(for source: String, meanings: [String]) {
        let newTranslation = meanings.joined(separator: "/")
        if let idx = localMatches.firstIndex(where: { $0.source == source }) {
            localMatches[idx] = DictionaryMatchInfo(source: source, translation: newTranslation)
        } else {
            localMatches.append(DictionaryMatchInfo(source: source, translation: newTranslation))
        }
    }
    
    private func deleteSingleMeaning(meaningToRemove: String, source: String) {
        if deletedMeanings[source] == nil {
            deletedMeanings[source] = []
        }
        deletedMeanings[source]?.insert(meaningToRemove)
    }
    
    private func restoreSingleMeaning(meaningToRestore: String, source: String) {
        deletedMeanings[source]?.remove(meaningToRestore)
    }
    
    private func addSingleMeaning(newMeaning: String, source: String) {
        let trimmed = newMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var currentMeanings = getMeanings(for: source)
        if !currentMeanings.contains(trimmed) {
            currentMeanings.append(trimmed)
        }
        
        deletedMeanings[source]?.remove(trimmed)
        setMeanings(for: source, meanings: currentMeanings)
        
        switch source {
        case "Names (Riêng)": newNamesRieng = ""
        case "Names (Chung)": newNamesChung = ""
        case "VietPhrase (Riêng)": newVPRieng = ""
        case "VietPhrase (Chung)": newVPChung = ""
        default: break
        }
    }
    
    private func insertMeaningAtTarget() {
        let trimmed = insertMeaningText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var currentMeanings = getMeanings(for: targetSource)
        if targetIndex >= 0 && targetIndex <= currentMeanings.count {
            currentMeanings.insert(trimmed, at: targetIndex)
        } else {
            currentMeanings.append(trimmed)
        }
        
        deletedMeanings[targetSource]?.remove(trimmed)
        setMeanings(for: targetSource, meanings: currentMeanings)
        insertMeaningText = ""
    }
    
    private func saveAllChangesToDisk() {
        guard !hasSaved else { return }
        hasSaved = true
        
        Task {
            let sources = ["Names (Riêng)", "Names (Chung)", "VietPhrase (Riêng)", "VietPhrase (Chung)"]
            
            for source in sources {
                let isName = source.contains("Names")
                let isRieng = source.contains("Riêng")
                let bid = isRieng ? bookId : nil
                
                let originalMatch = matches.first(where: { $0.source == source })
                let originalMeanings = originalMatch != nil ? splitMeanings(originalMatch!.translation) : []
                
                let currentMeanings = getMeanings(for: source)
                let deletedForSource = deletedMeanings[source] ?? []
                let finalMeanings = currentMeanings.filter { !deletedForSource.contains($0) }
                
                if finalMeanings != originalMeanings {
                    do {
                        if finalMeanings.isEmpty {
                            try await TranslationManager.shared.deleteCustomEntry(word: word, isName: isName, bookId: bid)
                        } else {
                            let newTranslation = finalMeanings.joined(separator: "/")
                            try await TranslationManager.shared.saveCustomEntry(word: word, meaning: newTranslation, isName: isName, bookId: bid)
                        }
                    } catch {
                        // Log error
                    }
                }
            }
            
            await MainActor.run {
                self.matches = self.localMatches.map { match in
                    let deletedForSource = self.deletedMeanings[match.source] ?? []
                    let currentMeanings = self.splitMeanings(match.translation)
                    let finalMeanings = currentMeanings.filter { !deletedForSource.contains($0) }
                    return DictionaryMatchInfo(source: match.source, translation: finalMeanings.joined(separator: "/"))
                }
                onChanged()
            }
        }
    }
}
