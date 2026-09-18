import SwiftUI

extension ReaderView {
    func currentDefinitionSnapshot() -> ReaderDefinitionSession.SelectionSnapshot? {
        guard !originalSentence.isEmpty else { return nil }
        let location = max(0, min(selectedWordOffset, originalSentence.utf16.count))
        let length = max(0, min(selectedWordLength, originalSentence.utf16.count - location))
        return ReaderDefinitionSession.SelectionSnapshot(
            sentence: originalSentence,
            word: selectedTextForDefinition,
            range: NSRange(location: location, length: length),
            mode: translationMode,
            convertTraditional: shouldConvertTraditionalToSimplified,
            generation: TranslateUtils.translationGenerationToken(for: bookId)
        )
    }

    func isDefinitionDataCurrent() -> Bool {
        guard let current = currentDefinitionSnapshot(),
              let displayed = definitionSession.displayedSnapshot else {
            return false
        }
        return current == displayed
    }

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
                    showingDefinitionSheet = false
                    checkAndReleaseDeferredTranslationRefresh()
                }
            } catch {
                if definitionSession.identity == session { definitionSession.saving = false }
                ToastManager.shared.show(message: "Không lưu được định nghĩa: \(error.localizedDescription)", type: .error)
            }
        }
    }

    var definitionMeaningBinding: Binding<String> {
        Binding(get: { customMeaning }, set: {
            definitionSession.meaningRevision += 1
            customMeaning = $0
        })
    }

    func loadDefinitionData(preservingMeaning: Bool = false) {
        guard showingDefinitionSheet || showingCopyOriginalSheet else { return }
        guard let snapshot = currentDefinitionSnapshot() else { return }
        definitionSession.task?.cancel()
        let requestID = UUID()
        definitionSession.requestID = requestID
        definitionSession.loadingSnapshot = snapshot
        let editRevision = definitionSession.meaningRevision
        let request = ReaderDefinitionWorker.Request(sentence: snapshot.sentence, word: snapshot.word,
            bookId: bookId, mode: snapshot.mode, convertTraditional: snapshot.convertTraditional)
        let includesDefinitionData = showingDefinitionSheet
        let worker = definitionSession.worker
        definitionSession.loading = true
        definitionSession.task = Task { @MainActor in
            do {
                let result = try await CancellableTranslationWork.run {
                    try await worker.load(request, includesDefinitionData: includesDefinitionData)
                }
                guard definitionSession.requestID == requestID,
                      showingDefinitionSheet || showingCopyOriginalSheet else { return }
                guard currentDefinitionSnapshot() == snapshot else {
                    loadDefinitionData(preservingMeaning: preservingMeaning)
                    return
                }
                guard result.generation == TranslateUtils.translationGenerationToken(for: bookId) else {
                    loadDefinitionData(preservingMeaning: preservingMeaning)
                    return
                }
                var loadedSnapshot = snapshot
                loadedSnapshot = ReaderDefinitionSession.SelectionSnapshot(
                    sentence: snapshot.sentence,
                    word: snapshot.word,
                    range: snapshot.range,
                    mode: snapshot.mode,
                    convertTraditional: snapshot.convertTraditional,
                    generation: result.generation
                )
                withTransaction(Transaction(animation: nil)) {
                    translationTokens = result.tokens
                    translationTokensSource = "\(result.generation)|\(snapshot.sentence)"
                    if includesDefinitionData {
                        dictionaryMatches = result.matches
                        suggestionChips = result.suggestions
                        definitionSession.hasRules = result.hasRules
                        definitionSession.rulesEnabled = result.rulesEnabled
                        if !preservingMeaning, definitionSession.meaningRevision == editRevision {
                            customMeaning = result.meaning
                        }
                    }
                    definitionSession.displayedSnapshot = loadedSnapshot
                    definitionSession.loadingSnapshot = nil
                    definitionSession.loading = false
                }
            } catch is CancellationError {
                // Yêu cầu mới/đóng panel sở hữu trạng thái loading tiếp theo.
            } catch {
                if definitionSession.requestID == requestID {
                    definitionSession.loadingSnapshot = nil
                    definitionSession.loading = false
                }
            }
        }
    }

    func refreshDefinitionRules() {
        guard showingDefinitionSheet else { return }
        guard !originalSentence.isEmpty else { return }
        definitionSession.ruleTask?.cancel()
        let sessionID = definitionSession.identity
        let text = originalSentence
        let book = bookId
        let worker = definitionSession.worker
        definitionSession.loadingRules = true
        definitionSession.ruleTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                let result = try await CancellableTranslationWork.run {
                    try await worker.traces(sentence: text, bookId: book, selection: NSRange(location: 0, length: 0))
                }
                guard showingDefinitionSheet,
                      definitionSession.identity == sessionID,
                      originalSentence == text else { return }
                guard result.generation == TranslateUtils.translationGenerationToken(for: book) else {
                    refreshDefinitionRules()
                    return
                }
                withTransaction(Transaction(animation: nil)) {
                    ruleTraces = result.values
                    definitionSession.loadingRules = false
                    if let focusedRuleTraceID, !ruleTraces.contains(where: { $0.id == focusedRuleTraceID }) {
                        self.focusedRuleTraceID = nil
                    }
                }
            } catch is CancellationError {
            } catch {
                if definitionSession.identity == sessionID { definitionSession.loadingRules = false }
            }
        }
    }
}
