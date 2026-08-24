import SwiftUI

struct ManageDefinitionsView: View {
    let word: String
    let bookId: String
    @Binding var matches: [DictionaryMatchInfo]
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Toàn bộ thao tác sửa nằm trong bản nháp; đĩa chỉ được ghi một lần lúc đóng màn.
    @State private var draft: ManageDefinitionsDraft
    @State private var hasSaved = false

    init(word: String, bookId: String, matches: Binding<[DictionaryMatchInfo]>, onChanged: @escaping () -> Void) {
        self.word = word
        self.bookId = bookId
        self._matches = matches
        self.onChanged = onChanged
        self._draft = State(initialValue: ManageDefinitionsDraft(matches: matches.wrappedValue))
    }

    private func getHanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in word {
            list.append(phienAm[String(char)] ?? String(char))
        }
        return list.joined(separator: " ").lowercased()
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
            .onDisappear {
                saveAllChangesToDisk()
            }
        }
    }

    @ViewBuilder
    private func makeDictionarySection(title: String, source: String) -> some View {
        let rows = draft.rows(for: source)

        Section {
            if rows.isEmpty {
                Text("Chưa có định nghĩa nào")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ManageDefinitionRowView(
                        text: textBinding(rowId: row.id, source: source),
                        isDeleted: row.isDeleted,
                        canMoveUp: index > 0,
                        canMoveDown: index < rows.count - 1,
                        onMoveUp: { draft.move(source: source, from: index, by: -1) },
                        onMoveDown: { draft.move(source: source, from: index, by: 1) },
                        onInsertAbove: { draft.insertEmptyRow(source: source, at: index) },
                        onToggleDeleted: { draft.setDeleted(!row.isDeleted, rowId: row.id, source: source) }
                    )
                }
            }

            Button {
                draft.appendEmptyRow(source: source)
            } label: {
                Label("Thêm nghĩa ở cuối", systemImage: "plus.circle.fill")
                    .foregroundColor(.green)
            }
            .buttonStyle(.borderless)
        } header: {
            Text(title)
        }
    }

    /// Ô nhập đọc/ghi thẳng vào bản nháp theo `id` của hàng — không dùng chỉ số vì hàng đổi chỗ được.
    private func textBinding(rowId: UUID, source: String) -> Binding<String> {
        Binding(
            get: { draft.text(rowId: rowId, source: source) },
            set: { draft.setText($0, rowId: rowId, source: source) }
        )
    }

    // MARK: - Lưu

    private func saveAllChangesToDisk() {
        guard !hasSaved else { return }
        hasSaved = true

        let originals = matches
        let snapshot = draft

        Task {
            for source in ManageDefinitionsDraft.editableSources {
                let isName = source.contains("Names")
                let isRieng = source.contains("Riêng")
                let bid = isRieng ? bookId : nil

                let originalTranslation = originals.first(where: { $0.source == source })?.translation ?? ""
                let originalMeanings = ManageDefinitionsDraft.splitMeanings(originalTranslation)
                let finalMeanings = snapshot.activeMeanings(for: source)
                guard finalMeanings != originalMeanings else { continue }

                do {
                    if finalMeanings.isEmpty {
                        try await TranslationManager.shared.deleteCustomEntry(
                            word: word,
                            isName: isName,
                            bookId: bid
                        )
                    } else {
                        try await TranslationManager.shared.saveCustomEntry(
                            word: word,
                            meaning: finalMeanings.joined(separator: "/"),
                            isName: isName,
                            bookId: bid
                        )
                    }
                } catch {
                    AppLogger.shared.log(
                        "⚠️ [ManageDefinitions] Không lưu được nghĩa của '\(word)' ở \(source): \(error.localizedDescription)"
                    )
                }
            }

            await MainActor.run {
                self.matches = Self.mergedMatches(originals: originals, draft: snapshot)
                self.onChanged()
            }
        }
    }

    /// Ghép lại danh sách cho màn gọi: nhóm chỉ đọc (Phiên âm, Xưng hô, Luật nhân…) giữ nguyên,
    /// bốn nhóm sửa được lấy theo bản nháp và biến mất nếu không còn nghĩa nào.
    private static func mergedMatches(
        originals: [DictionaryMatchInfo],
        draft: ManageDefinitionsDraft
    ) -> [DictionaryMatchInfo] {
        var result: [DictionaryMatchInfo] = []
        var handled: Set<String> = []

        for match in originals {
            guard ManageDefinitionsDraft.editableSources.contains(match.source) else {
                result.append(match)
                continue
            }
            handled.insert(match.source)
            let meanings = draft.activeMeanings(for: match.source)
            guard !meanings.isEmpty else { continue }
            result.append(DictionaryMatchInfo(source: match.source, translation: meanings.joined(separator: "/")))
        }

        for source in ManageDefinitionsDraft.editableSources where !handled.contains(source) {
            let meanings = draft.activeMeanings(for: source)
            guard !meanings.isEmpty else { continue }
            result.append(DictionaryMatchInfo(source: source, translation: meanings.joined(separator: "/")))
        }

        return result
    }
}
