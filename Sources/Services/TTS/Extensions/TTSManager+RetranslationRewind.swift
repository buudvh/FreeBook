import Foundation

/// Lùi / tua về dòng có **chunk chữ cũ** sau một lượt dịch lại khi đang nghe (anh Bửu, 2026-11-20): lượt nối
/// (`+RetranslationSplice`) không đổi được chunk của dòng ≤ mốc (đổi chỉ số chunk đang phát), còn Reader luôn hiện bản mới ⇒
/// đọc lại các dòng đó bằng chunk cũ là đọc chữ khác màn hình. Khi đó thay **cả chương** bằng bản dịch mới đã dựng lúc nối
/// (`TTSRetranslationCoordinator.FullRetranslation`) rồi đọc từ đầu dòng đích — cắt tiếng như mọi lần tua. `chapterContent`
/// đổi ⇒ hết dòng chữ cũ.
///
/// Lối vào: `seekToParagraph` (vạch tua sheet nghe mini), `skipBackward` (sheet, màn khoá). "Nghe từ đây" / nút tai nghe của
/// Reader dựng lại phiên bằng `startSpeaking` với bản dịch sẵn của Reader (đã là bản mới) ⇒ không cần lối này.
extension TTSManager {
    /// Bên gọi **đã dừng tiếng** (`stopCurrentPlayback`). Trả chỉ số chunk để đọc: chunk đầu của cùng dòng trong mảng mới nếu
    /// vừa thay chương, không thì nguyên `chunkIndex`.
    func adoptFullRetranslationIfStale(_ chunkIndex: Int) -> Int {
        let coordinator = TTSRetranslationCoordinator.shared
        guard paragraphs.indices.contains(chunkIndex), let full = coordinator.fullRetranslation, isChunkLayoutCurrent
        else { return chunkIndex }
        let line = paragraphs[chunkIndex].paragraphIndex
        guard coordinator.needsFullRetranslation(from: line) else { return chunkIndex }
        let inputs = currentRetranslationInputs()
        guard sessionTranslationEnabled,
              full.inputs.bookId == inputs.bookId, full.inputs.chapterIndex == inputs.chapterIndex,
              full.inputs.chapterUrl == inputs.chapterUrl, full.inputs.packageId == inputs.packageId,
              full.inputs.convertsTraditional == inputs.convertsTraditional,
              full.inputs.removeDuplicatedTitle == inputs.removeDuplicatedTitle,
              TranslateUtils.translationGenerationToken(for: playingBookId) == full.token else {
            AppLogger.shared.log("🔁 [TTSRetranslate] Lùi về dòng \(line) còn chữ cũ nhưng bản mới đã cũ (phiên / cấu hình / từ điển đổi) ⇒ đọc chunk hiện có")
            return chunkIndex
        }
        // Đổi độ dài chunk / hiện tên chương sau lượt nối ⇒ chia lại từ chữ bản mới như `resumeAfterSettings`.
        let base = full.inputs.chunkLength == inputs.chunkLength && full.inputs.includeChapterTitle == inputs.includeChapterTitle
            ? full.baseParagraphs
            : Self.rechunkedParagraphs(content: full.content, title: full.title,
                                       includeTitle: inputs.includeChapterTitle, chunkLength: inputs.chunkLength)
        let fresh = playbackParagraphs(from: base)
        guard let newIndex = fresh.firstIndex(where: { $0.paragraphIndex >= line }) else { return chunkIndex }

        clearCurrentParagraphPrefetchCache() // mọi chỉ số chunk đổi ⇒ bỏ hết tiếng nạp trước / lượt đang tổng hợp của chương
        paragraphs = fresh
        chapterTitle = full.title
        chapterContent = full.content // didSet ⇒ hết dòng chữ cũ + bỏ bản đầy đủ
        normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(full.content)
        AppLogger.shared.log(
            "🔁 [TTSRetranslate] Lùi về dòng \(line) còn chữ cũ ⇒ thay cả chương \(playingChapterIndex + 1) bằng bản dịch mới "
                + "(chunk \(chunkIndex) → \(newIndex)/\(fresh.count))"
        )
        return newIndex
    }

    /// Chia chunk lại từ chữ đã dịch (dòng giữ id), chèn chunk tên chương — cùng cách `resumeAfterSettings`.
    private static func rechunkedParagraphs(content: String, title: String, includeTitle: Bool, chunkLength: Int) -> [TTSParagraph] {
        let entries = ChapterTextNormalizer.normalizeProcessedContent(content).lines.map {
            TTSLineEntry(lineId: $0.id, originalText: $0.text, translatedText: $0.text, spans: [])
        }
        var chunks = TTSParagraphBuilder.buildFromEntries(entries, chunkLength: chunkLength)
        if includeTitle && !title.isEmpty {
            chunks.insert(TTSParagraph(text: title, range: NSRange(location: 0, length: title.utf16.count), paragraphIndex: -1), at: 0)
        }
        return chunks
    }
}
