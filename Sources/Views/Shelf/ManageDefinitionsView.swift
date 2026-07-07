import SwiftUI

struct ManageDefinitionsView: View {
    let word: String
    let bookId: String
    @Binding var matches: [DictionaryMatchInfo]
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private var filteredMatches: [DictionaryMatchInfo] {
        matches.filter { match in
            !match.source.contains("Pronouns") && !match.source.contains("LuatNhan")
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Từ đang chọn")) {
                    Text(word)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Section(header: Text("Các nghĩa hiện tại")) {
                    if filteredMatches.isEmpty {
                        Text("Chưa có định nghĩa nào")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredMatches) { match in
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
        }
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
                    onChanged()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi xóa định nghĩa từ: \(error.localizedDescription)")
            }
        }
    }
}
