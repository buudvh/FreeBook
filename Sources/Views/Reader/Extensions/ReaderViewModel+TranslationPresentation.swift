import Foundation

extension ReaderViewModel {
    func chapterTitle(at index: Int) -> String {
        if let cached = cache.cache[index], !cached.title.isEmpty { return cached.title }
        if onlineChapters.indices.contains(index) {
            // Chương chưa dựng: tên đã chuyển phồn → giản (chạy cả khi tắt dịch, 1.3.846), chưa dịch như trước.
            return ChineseTextPipeline.convert(onlineChapters[index].name, converts: shouldConvertTraditionalToSimplified)
        }
        return "Chương \(index + 1)"
    }

    func originalChapterTitle(at index: Int) -> String? {
        if let cached = cache.cache[index], !cached.originalTitle.isEmpty { return cached.originalTitle }
        if onlineChapters.indices.contains(index) {
            let title = onlineChapters[index].name
            return title.isEmpty ? nil : title
        }
        return nil
    }

    func cancelObsoleteTranslationRefresh() {
        translationRefreshTask?.cancel()
        translationPresentation.pending = nil
    }

    func setTranslationRefreshDeferred(_ deferred: Bool) {
        translationPresentation.deferred = deferred
        // Panel / menu chọn chữ đang mở (Reader hoãn dựng lại, còn chữ cũ) ⇒ TTS chưa nối bản dịch mới vào chương này.
        TTSRetranslationCoordinator.shared.setReaderHold(
            deferred, owner: translationPresentation, bookId: bookId, chapterIndex: displayedChapterIndex
        )
        guard !deferred, let pending = translationPresentation.pending else { return }
        translationPresentation.pending = nil
        guard isPendingPresentationCurrent(pending) else { return }
        guard TTSRetranslationCoordinator.shared.isPending(bookId: bookId, chapterIndex: pending.index) else {
            applyPreparedTranslation(pending)
            return
        }
        // TTS vừa được nhả và đang nối ⇒ chờ mốc rồi mới áp (dòng đang đọc khỏi nháy chữ mới rồi về chữ cũ).
        Task { [weak self] in
            guard let self else { return }
            await self.waitForTTSRetranslationAnchor(chapterIndex: pending.index, token: pending.token)
            guard self.isPendingPresentationCurrent(pending) else { return }
            if self.translationPresentation.deferred {
                // Panel mở lại trong lúc chờ: trả bản dựng về hàng chờ — `ReaderView` đã thôi hoãn nên không ai dựng lại.
                if self.translationPresentation.pending == nil { self.translationPresentation.pending = pending }
                return
            }
            self.applyPreparedTranslation(pending)
        }
    }

    private func isPendingPresentationCurrent(_ pending: ReaderTranslationPresentation.Prepared) -> Bool {
        pending.index == displayedChapterIndex
            && pending.revision == currentRevision
            && pending.token == TranslateUtils.translationGenerationToken(for: bookId)
            && pending.translationEnabled == isTranslationEnabled
            && pending.convertTraditional == shouldConvertTraditionalToSimplified
    }

    internal func applyPreparedTranslation(_ prepared: ReaderTranslationPresentation.Prepared) {
        let cached = cache.cache[prepared.index] ?? cache.setPlaceholder(prepared.index)
        // TTS đang đọc chương này và vừa nối bản dịch mới (mốc cùng token) ⇒ dòng ≤ mốc hiện đúng chữ TTS đọc.
        let result = alignedWithTTSAnchor(
            prepared.result, chapterIndex: prepared.index, token: prepared.token, displayed: cached.paragraphItems
        )
        let equal = cached.originalTitle == prepared.originalTitle &&
            cached.originalContent == prepared.originalContent &&
            cached.title == result.translatedTitle && cached.content == result.translatedContent &&
            cached.paragraphItems == result.paragraphItems &&
            cached.isTranslationEnabled == prepared.translationEnabled &&
            cached.shouldConvertTraditionalToSimplified == prepared.convertTraditional && cached.state == .loaded
        if !equal {
            cached.originalTitle = prepared.originalTitle
            cached.originalContent = prepared.originalContent
            cached.title = result.translatedTitle
            cached.content = result.translatedContent
            cached.paragraphItems = result.paragraphItems
            cached.isTranslationEnabled = prepared.translationEnabled
            cached.shouldConvertTraditionalToSimplified = prepared.convertTraditional
            cached.state = .loaded
        }
        cached.revision = prepared.revision
        cached.translationToken = prepared.token
        // Báo "đang dịch bằng QT thay thế" theo bản vừa áp (QT / dịch tắt / tiện ích dịch đủ ⇒ xoá báo).
        TranslationFallbackStatusStore.shared.record(result.fallbackStatus, bookId: bookId, chapterIndex: prepared.index)
    }
}
