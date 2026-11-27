import SwiftUI

/// Màn "Quản lý nghĩa từ" kiểu chip (1.3.981): các nhóm từ điển sửa được (Name / VP Riêng + Chung, rồi Pronoun Chung —
/// `ManageDefinitionsDraft.editableSources`) nằm trong **một** thẻ, mỗi nghĩa là một viên con nhộng
/// (`ManageDefinitionChipView`). Bấm chip ⇒ ô sửa hiện dưới nhóm; nút góc chip xoá nhanh / hoàn tác.
///
/// Đóng màn ⇒ ghi nhóm đã đổi: Name / VP vào lớp sửa đổi (`saveCustomEntry` / `deleteCustomEntry`); Pronoun ghi thẳng
/// **file Pronouns gốc** qua hàng đợi `GlobalDictionaryEditor` (cùng đường danh sách Pronouns: dựng lại `.dat`, nạp lại
/// riêng Pronouns, xoá cache dịch), nghĩa nối bằng `/`, hết nghĩa ⇒ xoá mục.
struct ManageDefinitionsView: View {
    /// Chip đang mở ô sửa. Khoá theo `id` của hàng — hàng đổi chỗ được nên không dùng chỉ số.
    private struct Selection: Equatable {
        let source: String
        let rowId: UUID
    }

    let word: String
    let bookId: String
    @Binding var matches: [DictionaryMatchInfo]
    let onChanged: () -> Void

    /// Toàn bộ thao tác sửa nằm trong bản nháp; đĩa chỉ được ghi một lần lúc đóng màn.
    @State private var draft: ManageDefinitionsDraft
    @State private var hasSaved = false
    @State private var selection: Selection?
    @FocusState private var isEditorFocused: Bool

    /// Tính một lần lúc mở: `body` chạy lại theo từng ký tự gõ, không tra `phienAmMap` ở đó.
    private let hanViet: String
    /// Nghĩa của từng nhóm lúc mở màn — chỉ để đếm số nhóm đã sửa cho dòng trạng thái.
    private let initialMeanings: [String: [String]]

    init(word: String, bookId: String, matches: Binding<[DictionaryMatchInfo]>, onChanged: @escaping () -> Void) {
        self.word = word
        self.bookId = bookId
        self._matches = matches
        self.onChanged = onChanged
        let draft = ManageDefinitionsDraft(matches: matches.wrappedValue)
        self._draft = State(initialValue: draft)
        self.hanViet = Self.makeHanViet(for: word)
        self.initialMeanings = Dictionary(
            uniqueKeysWithValues: ManageDefinitionsDraft.editableSources.map { ($0, draft.activeMeanings(for: $0)) }
        )
    }

    private static func makeHanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        return word.map { phienAm[String($0)] ?? String($0) }
            .joined(separator: " ")
            .lowercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    wordHeader
                    groupsCard
                    statusLine
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .pageTitle("Quản lý nghĩa từ")
            .presentationDragIndicator(.visible)
            .onDisappear {
                saveAllChangesToDisk()
            }
        }
    }

    // MARK: - Bố cục

    private var wordHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(word)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(2)
            Text(hanViet)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word), phiên âm \(hanViet)")
    }

    private var groupsCard: some View {
        let sources = ManageDefinitionsDraft.editableSources
        return VStack(spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.element) { index, source in
                if index > 0 {
                    Divider()
                        .padding(.leading, 12)
                }
                group(for: source)
            }
        }
        .background(AppGlassSheetModifier.rowFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func group(for source: String) -> some View {
        let selectedRowId = selection?.source == source ? selection?.rowId : nil
        return ManageDefinitionGroupView(
            dictionaryName: Self.dictionaryName(for: source),
            scopeName: source.hasSuffix("(Riêng)") ? "Riêng" : "Chung",
            isBookScope: source.hasSuffix("(Riêng)"),
            rows: draft.rows(for: source),
            selectedRowId: selectedRowId,
            editorText: textBinding(rowId: selectedRowId, source: source),
            editorFocus: $isEditorFocused,
            onTapRow: { tapRow($0, source: source) },
            onToggleDeleted: { toggleDeleted($0, source: source) },
            onAdd: { addRow(source: source) },
            onMoveSelected: { moveSelected(by: $0) },
            onSubmit: { select(nil) }
        )
    }

    /// Nhãn nhóm (dòng 1 của cột nhãn). Pronoun chỉ có bản chung nên dòng 2 luôn "Chung".
    private static func dictionaryName(for source: String) -> String {
        if source == ManageDefinitionsDraft.pronounSource { return "Pronoun" }
        return source.hasPrefix("Names") ? "Name" : "VP"
    }

    private var statusLine: some View {
        let changed = ManageDefinitionsDraft.editableSources.filter {
            draft.activeMeanings(for: $0) != (initialMeanings[$0] ?? [])
        }.count
        return Text(changed == 0 ? "Thay đổi được lưu khi đóng" : "Đã sửa \(changed) nhóm · lưu khi đóng")
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Ô sửa đọc/ghi thẳng vào bản nháp theo `id` của hàng — không dùng chỉ số vì hàng đổi chỗ được.
    private func textBinding(rowId: UUID?, source: String) -> Binding<String> {
        Binding(
            get: { rowId.map { draft.text(rowId: $0, source: source) } ?? "" },
            set: { newValue in
                guard let rowId else { return }
                draft.setText(newValue, rowId: rowId, source: source)
            }
        )
    }

    // MARK: - Thao tác

    /// Bấm thân chip: chip đã xoá ⇒ hoàn tác; chip đang chọn ⇒ đóng ô sửa; còn lại ⇒ chọn để sửa.
    private func tapRow(_ row: ManageDefinitionsDraft.Row, source: String) {
        if row.isDeleted {
            draft.setDeleted(false, rowId: row.id, source: source)
            return
        }
        let target = Selection(source: source, rowId: row.id)
        select(selection == target ? nil : target)
    }

    /// Đổi chip đang chọn. Chip vừa thêm mà bỏ trống thì gỡ luôn khi rời nó, để không sót lại chip "Nghĩa…".
    private func select(_ target: Selection?) {
        if let current = selection, current != target,
           draft.isDiscardableBlank(rowId: current.rowId, source: current.source) {
            draft.removeRow(rowId: current.rowId, source: current.source)
        }
        selection = target
        guard target != nil else {
            isEditorFocused = false
            return
        }
        // Ô sửa của nhóm khác vừa được chèn vào cây view ở lượt vẽ này — đặt focus ở lượt sau.
        DispatchQueue.main.async { isEditorFocused = true }
    }

    /// Nút góc chip: xoá mềm (hoàn tác được tới khi đóng màn) hoặc hoàn tác. Chip trống vừa thêm thì gỡ hẳn.
    private func toggleDeleted(_ row: ManageDefinitionsDraft.Row, source: String) {
        if row.isDeleted {
            draft.setDeleted(false, rowId: row.id, source: source)
            return
        }
        if selection == Selection(source: source, rowId: row.id) {
            selection = nil
            isEditorFocused = false
        }
        if draft.isDiscardableBlank(rowId: row.id, source: source) {
            draft.removeRow(rowId: row.id, source: source)
        } else {
            draft.setDeleted(true, rowId: row.id, source: source)
        }
    }

    private func addRow(source: String) {
        // Gỡ chip trống đang chọn (nếu có) **trước** khi thêm, để bấm `+` liên tiếp không đẻ ra một dãy chip trống.
        select(nil)
        let rowId = draft.appendEmptyRow(source: source)
        select(Selection(source: source, rowId: rowId))
    }

    private func moveSelected(by offset: Int) {
        guard let selection,
              let index = draft.rows(for: selection.source).firstIndex(where: { $0.id == selection.rowId }) else {
            return
        }
        draft.move(source: selection.source, from: index, by: offset)
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
                // Cùng phép tách với bản nháp (Pronoun tách thêm `|`) — khác nhau là mục không đụng tới vẫn bị ghi lại.
                let originalMeanings = ManageDefinitionsDraft.splitMeanings(originalTranslation, source: source)
                let finalMeanings = snapshot.activeMeanings(for: source)
                guard finalMeanings != originalMeanings else { continue }

                do {
                    if source == ManageDefinitionsDraft.pronounSource {
                        // Pronoun không có lớp sửa đổi: **không** rơi xuống `saveCustomEntry` (sẽ ghi vào VP Chung).
                        try await Self.savePronounMeanings(finalMeanings, word: word)
                    } else if finalMeanings.isEmpty {
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
                        "❌ [ManageDefinitions] Không lưu được nghĩa của '\(word)' ở \(source): \(error.localizedDescription)"
                    )
                }
            }

            await MainActor.run {
                self.matches = Self.mergedMatches(originals: originals, draft: snapshot)
                self.onChanged()
            }
        }
    }

    /// Ghi nhóm Pronoun thẳng vào file Pronouns gốc qua hàng đợi `GlobalDictionaryEditor` (như danh sách Pronouns):
    /// còn nghĩa ⇒ `từ=nghĩa1/nghĩa2…` đè mục cũ; hết nghĩa ⇒ xoá mục. Editor tự nạp lại riêng Pronouns, xoá cache dịch.
    private static func savePronounMeanings(_ meanings: [String], word: String) async throws {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = meanings.joined(separator: "/")
        let editor = GlobalDictionaryEditor.shared
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await editor.delete(key: key, type: "pronouns")
        } else {
            try await editor.save(key: key, value: value, replacing: nil, type: "pronouns")
        }
    }

    /// Ghép lại danh sách cho màn gọi: nhóm chỉ đọc (Phiên âm) giữ nguyên,
    /// các nhóm sửa được lấy theo bản nháp và biến mất nếu không còn nghĩa nào.
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
