import SwiftUI

/// Chế độ **Sửa từ** của danh sách VP/Name (`DictEntrySheet` mode `.edit`), bố cục theo panel Dịch của Reader
/// (`ReaderDefinitionOverlayView`) nhưng **không** có phần rule (nghĩa rule, chip rule, nút thêm rule) và không có bộ
/// chọn NE/VP · R/C: loại và phạm vi cố định theo danh sách (badge chỉ đọc ở header); chuyển phạm vi là nút "Chuyển"
/// của hàng. Panel Reader vẽ chữ trắng trên nền tối; ở đây dùng màu hệ thống (`.primary`/`.secondary`) cùng độ mờ.
///
/// Vùng chọn là `NSRange` UTF-16 trên từ gốc đang hiển thị (`displayKey`), giống Reader trên câu gốc. Không có câu
/// bao quanh nên nới rộng dừng ở hai đầu từ gốc; thu hẹp không dưới 1 ký tự.
///
/// Lưu (chọn "Giữ từ cũ"):
/// - cụm chọn = từ gốc ban đầu ⇒ cập nhật nghĩa của mục đang sửa (`onUpdate(originalKey, …)`);
/// - từ gốc gõ lại bằng nút bút chì, vùng chọn = cả từ mới ⇒ đổi từ gốc như cũ (`onUpdate(từ mới, …)` ⇒ `updateKey`);
/// - vùng chọn là một phần ⇒ mục đang sửa **giữ nguyên**, thêm mục mới = cụm đang chọn (`onAddEntry`).
struct DictEntryEditSheet: View {
    /// Ba cách lưu, suy từ vùng chọn và từ gốc (xem chú thích của type).
    enum SaveAction: Equatable {
        case update
        case rename(String)
        case addNew(String)
    }

    // `internal`: chế độ danh sách (`+List`) chỉ đóng sheet khi store lưu được.
    @Environment(\.dismiss) var dismiss

    let originalKey: String
    let originalValue: String
    let dictType: DictType
    /// Truyện của danh sách Riêng; `nil` = danh sách Chung. Quyết định badge phạm vi, token và nghĩa gợi ý.
    let scopeBookId: String?
    /// Truyện cho chip nghĩa "(Riêng)" và màn quản lý nghĩa (⚙) — như `DictEntrySheet.chipBookId`.
    let chipBookId: String?
    /// Nghĩa hiện có của một từ gốc trong **chính danh sách này**; `nil` = chưa có.
    let existingValue: (String) -> String?
    let onUpdate: (String, String) -> Void
    let onAddEntry: (String, String) -> Void
    let onDefinitionsChanged: () -> Void
    /// Chữ thay cho badge "loại · phạm vi" ở header; `nil` = suy từ `dictType` + `scopeBookId`. Danh sách name AI
    /// (`ReaderAINameReviewSheet+Edit`, 1.3.780) chưa có loại — Name hay VP chọn lúc Lưu — nên ghi "AI · Riêng truyện";
    /// danh sách Pronouns gốc (`BaseDictionaryListView`, 1.3.1067) ghi "Pronouns · Chung".
    let badgeText: String?
    /// Danh sách `chữ Hán = …` ngoài từ điển (đuôi, "Không phải name", họ, token tùy chọn) — xem `DictEntryEditListMode`
    /// và `DictEntryEditSheet+List.swift`. `nil` = từ điển VP / Name / Pronouns / name AI, hành vi như cũ.
    let listMode: DictEntryEditListMode?
    /// Hàng phụ ở chế độ từ điển, đặt sau aa…AA (vd hàng "Tiền tố" / "Hậu tố" khi mở từ màn duyệt Lọc name local). `nil` =
    /// không có.
    let accessoryRows: AnyView?
    /// `true` ⇒ nơi mở đổi `originalValue` khi sheet đang mở (màn duyệt ghép lại nghĩa sau khi thêm hậu tố) thì ô nghĩa theo,
    /// **trừ khi** người dùng đã gõ nghĩa khác giá trị cũ. Mặc định `false` = như cũ.
    let followsOriginalValue: Bool

    // `internal` (không `private`): các hàng ở `DictEntryEditSheet+Rows.swift` dùng chung trạng thái này.
    @State var workingKey: String
    @State var isEditingKey = false
    @FocusState var isKeyFieldFocused: Bool
    @State var selectionOffset = 0
    @State var selectionLength: Int
    @State var meaning: String
    /// Nghĩa của **cả từ gốc**, nhớ riêng để chọn thử một phần rồi quay lại không mất chữ người dùng vừa sửa.
    @State var wholeKeyMeaning: String
    /// Người dùng đã sửa nghĩa của cụm (một phần) đang chọn ⇒ kết quả tra về muộn không được đè lên.
    @State var isSubMeaningEdited = false
    /// Chế độ có nghĩa gợi ý (`DictEntryEditListMode.suggestedMeaning`): người dùng đã tự gõ / chạm chip ⇒ đổi vùng chọn
    /// không ghi đè ô nghĩa nữa.
    @State var isSuggestedMeaningEdited = false
    @State var isLoadingMeaning = false
    @State var tokens: [TranslationWordToken] = []
    @State var chips: [SuggestionChip] = []
    @State var dictionaryMatches: [DictionaryMatchInfo] = []
    /// Nghĩa đang có của từ đích khi lưu khác mục đang sửa (để cảnh báo ghi đè).
    @State var targetExistingValue: String? = nil
    /// Chế độ danh sách: lỗi store trả về lúc lưu; xoá khi người dùng sửa tiếp.
    @State var listSaveError: String? = nil
    @State var searchEngines: [SearchEngine] = []
    @State var lookupRoute: ReaderLookupRoute? = nil
    @State var showingSearchEngineConfig = false
    @State var showingManageDefinitions = false
    @State var manageWord = ""
    /// Từ gốc mà vùng chọn và token đang bám — đổi khi `displayKey` thật sự đổi (không tính khoảng trắng hai đầu).
    @State private var selectionKey: String
    @State private var tokenGeneration = 0
    @State private var selectionGeneration = 0
    @State private var hasAppeared = false
    /// Nấc vừa khít khi có hàng phụ (`+FittedDetent`).
    @State var fitting = FittedDetent()

    init(
        originalKey: String,
        originalValue: String,
        dictType: DictType,
        scopeBookId: String?,
        chipBookId: String?,
        existingValue: @escaping (String) -> String?,
        onUpdate: @escaping (String, String) -> Void,
        onAddEntry: @escaping (String, String) -> Void,
        onDefinitionsChanged: @escaping () -> Void,
        badgeText: String? = nil,
        listMode: DictEntryEditListMode? = nil,
        initialSelection: NSRange? = nil,
        accessoryRows: AnyView? = nil,
        followsOriginalValue: Bool = false
    ) {
        self.badgeText = badgeText
        self.listMode = listMode
        self.accessoryRows = accessoryRows
        self.followsOriginalValue = followsOriginalValue
        self.originalKey = originalKey
        self.originalValue = originalValue
        self.dictType = dictType
        self.scopeBookId = scopeBookId
        self.chipBookId = chipBookId
        self.existingValue = existingValue
        self.onUpdate = onUpdate
        self.onAddEntry = onAddEntry
        self.onDefinitionsChanged = onDefinitionsChanged
        let trimmedKey = originalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyLength = (trimmedKey as NSString).length
        // Vùng chọn ban đầu (mặc định cả từ); ngoài biên ⇒ cả từ.
        let selection = initialSelection.flatMap { range -> NSRange? in
            range.location >= 0 && range.length > 0 && range.location + range.length <= keyLength ? range : nil
        } ?? NSRange(location: 0, length: keyLength)
        _workingKey = State(initialValue: originalKey)
        _selectionKey = State(initialValue: trimmedKey)
        _selectionOffset = State(initialValue: selection.location)
        _selectionLength = State(initialValue: selection.length)
        let initialMeaning = listMode?.suggestedMeaning.map { suggest in
            suggest((trimmedKey as NSString).substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines))
        } ?? originalValue
        _meaning = State(initialValue: initialMeaning)
        _wholeKeyMeaning = State(initialValue: originalValue)
        // Danh sách, thêm mục mới (khoá rỗng): mở sẵn ô gõ chữ gốc.
        _isEditingKey = State(initialValue: listMode != nil && trimmedKey.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    // Nền trong suốt vẫn nhận chạm để tắt bàn phím — như panel Dịch.
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture {
                        KeyboardDismissPreference.dismissOnTapOutsideIfEnabled()
                    })
                    .dictEntryEditMeasuredHeight(FittedContentHeightKey.self) { fittedContentHeightDidChange($0) }
            }
            .scrollDismissesKeyboard(.interactively)
            .dictEntryEditMeasuredHeight(FittedViewportHeightKey.self) { fittedViewportHeightDidChange($0) }
            .pageTitle(isAddingListEntry ? "Thêm từ" : "Sửa từ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { headerTrailingView }
            }
            .onAppear(perform: handleAppear)
            .onChange(of: workingKey) { _, _ in keyDidChange() }
            .onChange(of: meaning) { _, newValue in meaningDidChange(newValue) }
            .onChange(of: originalValue) { oldValue, newValue in originalValueDidChange(from: oldValue, to: newValue) }
            .sheet(isPresented: $showingManageDefinitions) { manageDefinitionsSheet.appGlassSheet() }
            .sheet(isPresented: $showingSearchEngineConfig, onDismiss: { searchEngines = SearchEngine.loadEngines() }) {
                Group {
                    NavigationStack { SearchEnginesConfigView(isPresentedAsSheet: true) }
                        .presentationDragIndicator(.visible)
                }
                .appGlassSheet()
            }
            .fullScreenCover(item: $lookupRoute) { route in
                BypassWebView(urlString: route.urlString)
            }
        }
        .confirmDiscardOnSwipe(isDirty: isDirty)
        // Có hàng phụ (lọc local) ⇒ nấc vừa khít nội dung; danh sách chỉ `.large` (ô chữ gốc tự focus, nấc nửa màn để bàn
        // phím che nút "Thêm" và các hàng phụ); còn lại `.medium` + `.large` — `+FittedDetent`.
        .dictEntryEditDetents(fits: usesFittedDetent, isListMode: listMode != nil, fitting: $fitting)
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: 8) {
            // Hai `Group` để mỗi khối `@ViewBuilder` không quá 10 con (như panel Dịch).
            Group {
                if isEditingKey { keyFieldView }
                originalKeyRowView
                translatedTokensRowView
                if showsMeaningRows {
                    meaningInputView
                    suggestionChipsView
                }
            }
            Group {
                if showsMeaningRows { caseButtonsView }
                listExtraRowsView
                if listMode == nil, let accessoryRows { accessoryRows }
                noticeView
                updateButtonView
                Divider()
                quickLookupLinksView
            }
        }
    }

    // MARK: - Trạng thái suy ra

    var trimmedOriginalKey: String { originalKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displayKey: String { workingKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    var keyLength: Int { (displayKey as NSString).length }
    var isWholeSelection: Bool { selectionOffset == 0 && selectionLength == keyLength }

    var selectedText: String {
        let ns = displayKey as NSString
        guard selectionOffset >= 0, selectionLength > 0, selectionOffset + selectionLength <= ns.length else { return "" }
        return ns.substring(with: NSRange(location: selectionOffset, length: selectionLength))
    }

    /// Từ gốc sẽ được ghi khi bấm Cập nhật (cụm đang chọn, bỏ khoảng trắng hai đầu).
    var saveTargetKey: String { selectedText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var saveAction: SaveAction? {
        let target = saveTargetKey
        guard !target.isEmpty else { return nil }
        if target == trimmedOriginalKey { return .update }
        return isWholeSelection ? .rename(target) : .addNew(target)
    }

    var isSaveDisabled: Bool {
        saveAction == nil || isLoadingMeaning
            || (showsMeaningRows && meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || listValidationError != nil
    }

    private var isDirty: Bool {
        displayKey != trimmedOriginalKey
            || wholeKeyMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
                != originalValue.trimmingCharacters(in: .whitespacesAndNewlines)
            || isSubMeaningEdited
            || isListExtraDirty
    }

    /// Mọi thay đổi nghĩa do **người dùng** (gõ, chip, dán, xoá, aa…AA) đi qua đây; đổi do vùng chọn thì gán thẳng.
    var meaningBinding: Binding<String> {
        Binding(get: { meaning }, set: { editMeaning($0) })
    }

    func editMeaning(_ value: String) {
        if !isWholeSelection { isSubMeaningEdited = true }
        if listMode?.suggestedMeaning != nil { isSuggestedMeaningEdited = true }
        meaning = value
    }

    // MARK: - Vùng chọn

    func select(offset: Int, length: Int) {
        guard offset >= 0, length > 0, offset + length <= keyLength else { return }
        selectionOffset = offset
        selectionLength = length
        selectionDidChange()
    }

    /// Nhích theo **trọn chữ** như Reader (`ComposedTextSelection`, 1.3.1080).
    func expandSelectionLeft() { stepSelection(ComposedTextSelection.expandLeft) }

    func shrinkSelectionLeft() { stepSelection(ComposedTextSelection.shrinkLeft) }

    func shrinkSelectionRight() { stepSelection(ComposedTextSelection.shrinkRight) }

    func expandSelectionRight() { stepSelection(ComposedTextSelection.expandRight) }

    private func stepSelection(_ step: (NSRange, String) -> NSRange?) {
        guard let next = step(NSRange(location: selectionOffset, length: selectionLength), displayKey) else { return }
        select(offset: next.location, length: next.length)
    }

    /// Như `updateEditorFromSelection` của Reader: vùng chọn đổi ⇒ ô nghĩa hiện nghĩa của cụm mới. Cả từ gốc ⇒ nghĩa
    /// của mục (kể cả chữ người dùng đã sửa); cụm đã có trong danh sách ⇒ nghĩa đang lưu; còn lại ⇒ dịch cụm đó.
    private func selectionDidChange() {
        listSaveError = nil
        if let suggest = listMode?.suggestedMeaning {
            // Nghĩa theo gợi ý của phần đang chọn (vd phiên âm của đuôi), người dùng đã tự gõ thì giữ.
            targetExistingValue = nil
            if !isSuggestedMeaningEdited { meaning = suggest(saveTargetKey) }
            refreshSelectionData(needsMeaning: false)
            return
        }
        isSubMeaningEdited = false
        let target = saveTargetKey
        targetExistingValue = (target.isEmpty || target == trimmedOriginalKey) ? nil : existingValue(target)
        if isWholeSelection {
            meaning = wholeKeyMeaning
            refreshSelectionData(needsMeaning: false)
        } else if let existing = targetExistingValue {
            meaning = existing
            refreshSelectionData(needsMeaning: false)
        } else {
            refreshSelectionData(needsMeaning: true)
        }
    }

    private func keyDidChange() {
        let key = displayKey
        guard key != selectionKey else { return }
        selectionKey = key
        selectionOffset = 0
        selectionLength = (key as NSString).length
        selectionDidChange()
        refreshTokens()
    }

    /// `followsOriginalValue`: nơi mở đổi nghĩa (ghép lại) ⇒ ô nghĩa theo khi người dùng chưa gõ khác giá trị cũ.
    private func originalValueDidChange(from oldValue: String, to newValue: String) {
        guard followsOriginalValue, oldValue != newValue else { return }
        let old = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wholeKeyMeaning.trimmingCharacters(in: .whitespacesAndNewlines) == old else { return }
        wholeKeyMeaning = newValue
        if isWholeSelection { meaning = newValue }
    }

    private func meaningDidChange(_ newValue: String) {
        let cleaned = newValue.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        if cleaned != newValue { meaning = cleaned }
        if isWholeSelection { wholeKeyMeaning = cleaned }
        listSaveError = nil
    }

    // MARK: - Tra (ngoài main)

    private func handleAppear() {
        // `onAppear` chạy lại sau khi đóng trình duyệt tra cứu (cover) — chỉ nạp lần đầu.
        guard !hasAppeared else { return }
        hasAppeared = true
        searchEngines = SearchEngine.loadEngines()
        refreshTokens()
        refreshSelectionData(needsMeaning: false)
        // Ô nhập đã có sẵn trong cây view (thêm mục mới của danh sách) — focus ở lượt sau như `toggleKeyEditing`.
        if isEditingKey { DispatchQueue.main.async { isKeyFieldFocused = true } }
    }

    func refreshTokens() {
        tokenGeneration += 1
        let ticket = tokenGeneration
        let key = displayKey
        let book = scopeBookId
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                DictEntryEditLookup.tokens(for: key, bookId: book)
            }.value
            guard ticket == tokenGeneration else { return }
            tokens = result
        }
    }

    /// Chip + `matches` của cụm đang chọn, kèm nghĩa gợi ý khi `needsMeaning`. Lượt cũ về muộn bị bỏ.
    func refreshSelectionData(needsMeaning: Bool) {
        selectionGeneration += 1
        let ticket = selectionGeneration
        let word = selectedText
        let meaningBook = scopeBookId
        let chipBook = chipBookId
        // Không có ô nghĩa ("Không phải name") ⇒ không tra nghĩa, nút lưu khỏi chớp tắt khi đổi vùng chọn.
        let needsMeaning = needsMeaning && showsMeaningRows
        isLoadingMeaning = needsMeaning
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                DictEntryEditLookup.selection(
                    word: word, meaningBookId: meaningBook, chipBookId: chipBook, needsMeaning: needsMeaning
                )
            }.value
            guard ticket == selectionGeneration else { return }
            dictionaryMatches = result.matches
            chips = result.chips
            isLoadingMeaning = false
            if let suggested = result.meaning, !isSubMeaningEdited {
                meaning = suggested
            }
        }
    }

    // MARK: - Lưu

    func handleSave() {
        if listMode != nil {
            saveToList()
            return
        }
        let value = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let action = saveAction, !value.isEmpty, !isLoadingMeaning else { return }
        switch action {
        case .update:
            onUpdate(originalKey, value)
        case .rename(let newKey):
            onUpdate(newKey, value)
        case .addNew(let newKey):
            onAddEntry(newKey, value)
        }
        dismiss()
    }
}
