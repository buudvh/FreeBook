import Combine
import Foundation

/// Reader theo **mốc dịch lại** của TTS (`TTSRetranslationCoordinator`, anh Bửu 2026-11-19): sửa rule / VP / Name lúc truyện
/// đang nghe thì TTS đọc chữ mới từ dòng sau dòng đang đọc, nên chương TTS đang đọc phải hiện **đúng chữ TTS đọc** ở mọi dòng
/// ≤ mốc — `TTSParagraph.range` (vệt highlight) là offset trên chữ dòng cha mà Reader hiện.
///
/// - Dòng ≤ mốc có trong `pinnedTexts` (TTS đọc chữ khác bản dựng mới): giữ đoạn Reader đang hiện nếu đúng chữ đó (còn span
///   dịch), không thì dựng đoạn từ chữ của TTS (span rỗng — `ReaderSelectionMapper` có đường lùi khi span rỗng).
/// - Dòng khác: đoạn của bản dựng mới.
/// - TTS không đọc chương này / mốc khác token / TTS đã dựng lại chương ⇒ không đổi gì (hành vi cũ).
extension ReaderViewModel {
    /// `processAndSaveChapter`, sau khi dựng xong và trước khi áp: TTS đang dịch lại đúng chương này mà chưa có mốc cùng token
    /// ⇒ chờ (tối đa 3 s). Reader đang giữ lượt nối của TTS (panel mở) thì không chờ — TTS đang chờ chính Reader.
    func waitForTTSRetranslationAnchor(chapterIndex: Int, token: Int) async {
        ensureTTSAnchorSubscription()
        let outcome = await TTSRetranslationCoordinator.shared.waitForAnchor(
            bookId: bookId, chapterIndex: chapterIndex, token: token
        )
        if case .timedOut = outcome {
            AppLogger.shared.log("⚠️ [TTSRetranslate] Reader chờ mốc của TTS quá 3 s ⇒ áp cả bản mới, nắn lại khi mốc tới (chương \(chapterIndex + 1))")
        }
    }

    /// `applyPreparedTranslation`: bản dựng mới + mốc còn hiệu lực cùng token ⇒ dòng ≤ mốc đúng chữ TTS đọc.
    func alignedWithTTSAnchor(
        _ result: ReaderParagraphBuildResult,
        chapterIndex: Int,
        token: Int,
        displayed: [ParagraphItem]
    ) -> ReaderParagraphBuildResult {
        guard let anchor = TTSRetranslationCoordinator.shared.liveAnchor(bookId: bookId, chapterIndex: chapterIndex, token: token),
              !anchor.pinnedTexts.isEmpty else { return result }
        let merged = Self.mergeParagraphItems(fresh: result.paragraphItems, displayed: displayed, anchor: anchor)
        guard merged != result.paragraphItems else { return result }
        return ReaderParagraphBuildResult(
            translatedTitle: merged.first(where: \.isTitle)?.translated ?? result.translatedTitle,
            translatedContent: merged.filter { !$0.isTitle }.map(\.translated).joined(separator: "\n"),
            paragraphItems: merged,
            fallbackStatus: result.fallbackStatus
        )
    }

    static func mergeParagraphItems(
        fresh: [ParagraphItem],
        displayed: [ParagraphItem],
        anchor: TTSRetranslationCoordinator.Anchor
    ) -> [ParagraphItem] {
        var displayedById: [Int: ParagraphItem] = [:]
        for item in displayed where displayedById[item.id] == nil { displayedById[item.id] = item }
        return fresh.map { item in
            guard item.id <= anchor.boundaryLineId, let ttsText = anchor.pinnedTexts[item.id] else { return item }
            if let shown = displayedById[item.id], shown.original == item.original,
               shown.translated.trimmingCharacters(in: .whitespacesAndNewlines) == ttsText { return shown }
            if item.translated.trimmingCharacters(in: .whitespacesAndNewlines) == ttsText { return item }
            return ParagraphItem(id: item.id, original: item.original, translated: ttsText, isTitle: item.isTitle, translationSpans: [])
        }
    }

    /// Đăng ký một lần mỗi Reader: mốc tới sau khi Reader đã áp bản mới (chờ quá 3 s, hoặc Reader dựng chương trước khi TTS
    /// bắt đầu dịch lại) ⇒ nắn lại chương đó trong cache.
    func ensureTTSAnchorSubscription() {
        guard translationPresentation.ttsAnchorSubscription == nil else { return }
        translationPresentation.ttsAnchorSubscription = TTSRetranslationCoordinator.shared.$anchor
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] anchor in
                self?.realignCachedChapter(with: anchor)
            }
    }

    private func realignCachedChapter(with anchor: TTSRetranslationCoordinator.Anchor) {
        guard anchor.bookId == bookId, !anchor.pinnedTexts.isEmpty,
              let cached = cache.cache[anchor.chapterIndex], cached.state == .loaded,
              cached.translationToken == anchor.token,
              cached.isTranslationEnabled == isTranslationEnabled,
              TTSRetranslationCoordinator.shared.liveAnchor(
                  bookId: bookId, chapterIndex: anchor.chapterIndex, token: anchor.token
              ) != nil else { return }
        let merged = Self.mergeParagraphItems(fresh: cached.paragraphItems, displayed: cached.paragraphItems, anchor: anchor)
        guard merged != cached.paragraphItems else { return }
        cached.paragraphItems = merged
        cached.content = merged.filter { !$0.isTitle }.map(\.translated).joined(separator: "\n")
        if let title = merged.first(where: \.isTitle) { cached.title = title.translated }
        AppLogger.shared.log("🔁 [TTSRetranslate] Reader nắn chương \(anchor.chapterIndex + 1) theo mốc tới muộn (L=\(anchor.boundaryLineId))")
    }
}
