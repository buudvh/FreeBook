import SwiftUI

struct ManageDefinitionsView: View {
    let word: String
    let bookId: String
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var matches: [DictionaryMatchInfo] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Từ đang chọn")) {
                    Text(word)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Section(header: Text("Các nghĩa hiện tại")) {
                    if matches.isEmpty {
                        Text("Chưa có định nghĩa nào")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(matches) { match in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.source)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fontWeight(.bold)
                                    Text(match.translation)
                                        .font(.body)
                                }
                                
                                Spacer()
                                
                                if isEditableSource(match.source) {
                                    Button(role: .destructive, action: {
                                        deleteMatch(match)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
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
            .onAppear {
                loadMatches()
            }
        }
    }
    
    private func loadMatches() {
        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)
        var list: [DictionaryMatchInfo] = []
        
        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            list.append(DictionaryMatchInfo(source: "Names (Riêng)", translation: match.value))
        }
        
        // 2. Global Names
        if let names = manager.namesDict,
           let match = names.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            list.append(DictionaryMatchInfo(source: "Names (Chung)", translation: match.value))
        }
        
        // 3. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            list.append(DictionaryMatchInfo(source: "VietPhrase (Riêng)", translation: match.value))
        }
        
        // 4. Global VietPhrase
        if let vp = manager.vietPhraseDict,
           let match = vp.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            list.append(DictionaryMatchInfo(source: "VietPhrase (Chung)", translation: match.value))
        }
        
        // 5. PhienAm
        let phienAm = getHanViet(for: word)
        if !phienAm.isEmpty {
            list.append(DictionaryMatchInfo(source: "Phiên âm", translation: phienAm))
        }
        
        self.matches = list
    }
    
    private func getHanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in word {
            list.append(phienAm[String(char)] ?? String(char))
        }
        return list.joined(separator: " ").capitalized
    }
    
    private func isEditableSource(_ source: String) -> Bool {
        return source == "Names (Riêng)" || source == "Names (Chung)" ||
               source == "VietPhrase (Riêng)" || source == "VietPhrase (Chung)"
    }
    
    private func deleteMatch(_ match: DictionaryMatchInfo) {
        let isName = match.source.contains("Names")
        let bid = match.source.contains("Riêng") ? bookId : nil
        
        Task {
            do {
                try await TranslationManager.shared.deleteCustomEntry(word: word, isName: isName, bookId: bid)
                await MainActor.run {
                    loadMatches()
                    onChanged()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi xóa định nghĩa từ: \(error.localizedDescription)")
            }
        }
    }
}
