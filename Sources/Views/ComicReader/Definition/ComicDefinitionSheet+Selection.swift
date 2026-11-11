import SwiftUI

/// Vùng chọn, tra nghĩa, lưu Name / VP và tra nhanh của `ComicDefinitionSheet` — chép từ `ReaderView+Selection` /
/// `ReaderView+DefinitionLoading` (bỏ phần của panel Xoá từ rác / Copy gốc mà màn truyện tranh không có).
///
/// `selectedWordOffset/Length` là `NSRange` UTF-16 trên **câu gốc** (chữ Trung OCR), như Reader.
extension ComicDefinitionSheet {

    // MARK: - Nới / thu vùng chọn

    func expandSelectionLeft() {
        guard selectedWordOffset > 0 else { return }
        selectedWordOffset -= 1
        selectedWordLength += 1
        updateEditorFromSelection()
    }

    func shrinkSelectionLeft() {
        guard selectedWordLength > 1 else { return }
        selectedWordOffset += 1
        selectedWordLength -= 1
        updateEditorFromSelection()
    }

    func shrinkSelectionRight() {
        guard selectedWordLength > 1 else { return }
        selectedWordLength -= 1
        updateEditorFromSelection()
    }

    func expandSelectionRight() {
        guard selectedWordOffset + selectedWordLength < (sentence as NSString).length else { return }
        selectedWordLength += 1
        updateEditorFromSelection()
    }

    /// Cụm đang chọn ⇒ ô nghĩa + chip + loại / phạm vi theo ghim mặc định, rồi tra lại.
    func updateEditorFromSelection() {
        saveAsNameType = pinnedSaveAsNameType
        saveToBookSpecific = pinnedSaveToBookSpecific
        let ns = sentence as NSString
        guard selectedWordOffset >= 0, selectedWordOffset + selectedWordLength <= ns.length else { return }
        selectedTextForDefinition = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        definitionSession.meaningRevision += 1
        loadDefinitionData()
    }

    /// Cụm chữ **gốc** đang chọn — điền sẵn mẫu cho nút `+` rule.
    func selectedOriginalText() -> String {
        let ns = sentence as NSString
        let range = NSRange(location: selectedWordOffset, length: selectedWordLength)
        guard selectedWordOffset >= 0, selectedWordLength > 0, NSMaxRange(range) <= ns.length else { return "" }
        return ns.substring(with: range)
    }

    /// Người dùng gõ ô nghĩa ⇒ tăng `meaningRevision` để kết quả tra về muộn không đè lên.
    var meaningBinding: Binding<String> {
        Binding(get: { customMeaning }, set: {
            definitionSession.meaningRevision += 1
            customMeaning = $0
        })
    }

    // MARK: - Tra nghĩa

    func currentSnapshot() -> ReaderDefinitionSession.SelectionSnapshot? {
        guard !sentence.isEmpty else { return nil }
        let length16 = sentence.utf16.count
        let location = max(0, min(selectedWordOffset, length16))
        let length = max(0, min(selectedWordLength, length16 - location))
        return ReaderDefinitionSession.SelectionSnapshot(
            sentence: sentence,
            word: selectedTextForDefinition,
            range: NSRange(location: location, length: length),
            mode: translationMode,
            convertTraditional: request.convertsTraditional,
            generation: TranslateUtils.translationGenerationToken(for: bookId)
        )
    }

    /// Như `ReaderView.loadDefinitionData`: một lượt tra trên `ReaderDefinitionWorker`, lượt mới huỷ lượt cũ; kết quả về khi
    /// vùng chọn / từ điển đã đổi ⇒ tra lại.
    func loadDefinitionData(preservingMeaning: Bool = false) {
        guard let snapshot = currentSnapshot() else { return }
        definitionSession.task?.cancel()
        let requestID = UUID()
        definitionSession.requestID = requestID
        definitionSession.loadingSnapshot = snapshot
        let editRevision = definitionSession.meaningRevision
        let workerRequest = ReaderDefinitionWorker.Request(
            sentence: snapshot.sentence,
            word: snapshot.word,
            bookId: bookId,
            mode: snapshot.mode,
            convertTraditional: snapshot.convertTraditional
        )
        let worker = definitionSession.worker
        definitionSession.loading = true
        definitionSession.task = Task { @MainActor in
            do {
                let result = try await CancellableTranslationWork.run {
                    try await worker.load(workerRequest, includesDefinitionData: true)
                }
                guard definitionSession.requestID == requestID else { return }
                guard currentSnapshot() == snapshot,
                      result.generation == TranslateUtils.translationGenerationToken(for: bookId) else {
                    loadDefinitionData(preservingMeaning: preservingMeaning)
                    return
                }
                let loaded = ReaderDefinitionSession.SelectionSnapshot(
                    sentence: snapshot.sentence,
                    word: snapshot.word,
                    range: snapshot.range,
                    mode: snapshot.mode,
                    convertTraditional: snapshot.convertTraditional,
                    generation: result.generation
                )
                withTransaction(Transaction(animation: nil)) {
                    translationTokens = result.tokens
                    dictionaryMatches = result.matches
                    suggestionChips = result.suggestions
                    definitionSession.hasRules = result.hasRules
                    definitionSession.rulesEnabled = result.rulesEnabled
                    if !preservingMeaning, definitionSession.meaningRevision == editRevision {
                        customMeaning = result.meaning
                    }
                    definitionSession.displayedSnapshot = loaded
                    definitionSession.loadingSnapshot = nil
                    definitionSession.loading = false
                }
            } catch is CancellationError {
                // Lượt mới / đóng sheet giữ trạng thái loading kế tiếp.
            } catch {
                if definitionSession.requestID == requestID {
                    definitionSession.loadingSnapshot = nil
                    definitionSession.loading = false
                }
            }
        }
    }

    // MARK: - Lưu

    /// Lưu cụm đang chọn thành Name / VP (riêng truyện hoặc chung); xong mà người dùng chưa đổi gì nữa ⇒ đóng sheet.
    func saveDefinition() {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = customMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !meaning.isEmpty, !definitionSession.saving else { return }
        let book = saveToBookSpecific ? bookId : nil
        let isName = saveAsNameType
        let session = definitionSession.identity
        let revision = definitionSession.meaningRevision
        definitionSession.saving = true
        Task { @MainActor in
            do {
                try await TranslationManager.shared.saveCustomEntry(word: word, meaning: meaning, isName: isName, bookId: book)
                guard definitionSession.identity == session else { return }
                definitionSession.saving = false
                if definitionSession.meaningRevision == revision, selectedTextForDefinition == word {
                    dismiss()
                }
            } catch {
                if definitionSession.identity == session { definitionSession.saving = false }
                ToastManager.shared.show(message: "Không lưu được định nghĩa: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - Tra nhanh

    /// Mở công cụ tìm với cụm gốc đang chọn — chỉ `http(s)`, như `ReaderView.performQuickLookup`.
    func performQuickLookup(using engine: SearchEngine) {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let rawUrl = engine.urlTemplate.replacingOccurrences(of: "%s", with: word)
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        lookupRoute = ReaderLookupRoute(urlString: url.absoluteString)
    }
}
