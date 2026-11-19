import Combine
import Foundation

/// Reader theo **mốc dịch lại** của TTS (`TTSRetranslationCoordinator`, anh Bửu 2026-11-19): sửa rule / VP / Name lúc truyện
/// đang nghe thì TTS đọc chữ mới từ dòng sau dòng đang đọc, nên chương TTS đang đọc phải hiện **đúng chữ TTS đọc** ở mọi dòng
/// ≤ mốc — `TTSParagraph.range` (vệt highlight) là offset trên chữ dòng cha mà Reader hiện.
///
/// - Dòng ≤ mốc có trong `pinnedTexts` (TTS đọc chữ khác bản dựng mới): giữ đoạn Reader đang hiện nếu đúng chữ đó (còn span
///   dịch), không thì dựng đoạn từ chữ của TTS (span rỗng — `ReaderSelectionMapper` có đường lùi khi span rỗng).
/// - Dòng khác: đoạn của bản dựng mới.
/// - Chương đang ghim lưu `ttsAnchorStamp` + bản dựng gốc (`unalignedParagraphItems`). Mốc **hết hiệu lực** (TTS dựng lại
///   chữ chương — đọc lại, chuyển chương —, dừng hẳn, đổi phồn → giản / bộ dịch) ⇒ trả về bản gốc ngay, không chờ dựng lại;
///   bản dịch sẵn đưa cho TTS (`ttsSnapshotParagraphItems`) luôn là bản gốc.
/// - TTS không đọc chương này / mốc khác token hay khác cờ dựng ⇒ không ghim (hành vi cũ).
extension ReaderViewModel {
    /// `processAndSaveChapter`, sau khi dựng xong và trước khi áp: TTS đang dịch lại đúng chương này mà chưa có mốc cùng token
    /// ⇒ chờ (tối đa 3 s, thôi ngay khi lượt dựng bị huỷ). Reader đang giữ lượt nối của TTS (panel mở) thì không chờ.
    func waitForTTSRetranslationAnchor(
        chapterIndex: Int,
        token: Int,
        translationEnabled: Bool,
        convertTraditional: Bool
    ) async {
        ensureTTSAnchorSubscription()
        let outcome = await TTSRetranslationCoordinator.shared.waitForAnchor(
            bookId: bookId, chapterIndex: chapterIndex, token: token,
            translationEnabled: translationEnabled, convertsTraditional: convertTraditional
        )
        if case .timedOut = outcome {
            AppLogger.shared.log("⚠️ [TTSRetranslate] Reader chờ mốc của TTS quá 3 s ⇒ áp cả bản mới, nắn lại khi mốc tới (chương \(chapterIndex + 1))")
        }
    }

    /// `applyPreparedTranslation`: bản dựng mới + mốc còn hiệu lực đúng token / cờ dựng ⇒ dòng ≤ mốc đúng chữ TTS đọc.
    /// `stamp` ≠ `nil` ⇔ có dòng bị ghim (lưu cùng bản dựng gốc vào cache).
    func ttsAlignment(
        _ result: ReaderParagraphBuildResult,
        chapterIndex: Int,
        token: Int,
        translationEnabled: Bool,
        convertTraditional: Bool,
        displayed: [ParagraphItem]
    ) -> (result: ReaderParagraphBuildResult, stamp: String?) {
        guard let anchor = TTSRetranslationCoordinator.shared.liveAnchor(
            bookId: bookId, chapterIndex: chapterIndex, token: token,
            translationEnabled: translationEnabled, convertsTraditional: convertTraditional
        ), !anchor.pinnedTexts.isEmpty else { return (result, nil) }
        let merged = Self.mergeParagraphItems(fresh: result.paragraphItems, displayed: displayed, anchor: anchor)
        guard merged != result.paragraphItems else { return (result, nil) }
        let aligned = ReaderParagraphBuildResult(
            translatedTitle: merged.first(where: \.isTitle)?.translated ?? result.translatedTitle,
            translatedContent: Self.joinedContent(of: merged),
            paragraphItems: merged,
            fallbackStatus: result.fallbackStatus
        )
        return (aligned, anchor.contentStamp)
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

    /// Như `translatedContent` của `buildCancellable`: chữ dịch các dòng nội dung, nối bằng xuống dòng.
    static func joinedContent(of items: [ParagraphItem]) -> String {
        items.filter { !$0.isTitle }.map(\.translated).joined(separator: "\n")
    }

    /// Đăng ký một lần mỗi Reader: mốc tới sau khi Reader đã áp bản mới ⇒ nắn lại; TTS dựng lại chữ chương ⇒ kiểm lại các
    /// chương đang ghim.
    func ensureTTSAnchorSubscription() {
        guard translationPresentation.ttsAnchorSubscriptions.isEmpty else { return }
        let coordinator = TTSRetranslationCoordinator.shared
        coordinator.$anchor
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] anchor in self?.realignCachedChapter(with: anchor) }
            .store(in: &translationPresentation.ttsAnchorSubscriptions)
        coordinator.$ttsTextRevision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.restoreChaptersWithDeadTTSAnchor() }
            .store(in: &translationPresentation.ttsAnchorSubscriptions)
    }

    private func liveTTSAnchor(for cached: CachedChapter) -> TTSRetranslationCoordinator.Anchor? {
        TTSRetranslationCoordinator.shared.liveAnchor(
            bookId: bookId, chapterIndex: cached.index, token: cached.translationToken,
            translationEnabled: cached.isTranslationEnabled, convertsTraditional: cached.shouldConvertTraditionalToSimplified
        )
    }

    private func realignCachedChapter(with anchor: TTSRetranslationCoordinator.Anchor) {
        guard anchor.bookId == bookId, !anchor.pinnedTexts.isEmpty,
              let cached = cache.cache[anchor.chapterIndex], cached.state == .loaded,
              cached.ttsAnchorStamp != anchor.contentStamp,
              liveTTSAnchor(for: cached)?.contentStamp == anchor.contentStamp else { return }
        let fresh = cached.unalignedParagraphItems ?? cached.paragraphItems
        let merged = Self.mergeParagraphItems(fresh: fresh, displayed: cached.paragraphItems, anchor: anchor)
        guard merged != fresh else { return }
        cached.unalignedParagraphItems = fresh
        cached.ttsAnchorStamp = anchor.contentStamp
        apply(items: merged, to: cached)
        AppLogger.shared.log("🔁 [TTSRetranslate] Reader nắn chương \(anchor.chapterIndex + 1) theo mốc tới muộn (L=\(anchor.boundaryLineId))")
    }

    /// Chương đang ghim chữ theo một mốc không còn hiệu lực ⇒ trả về bản dựng gốc (đủ bản mới, cùng token đã dựng).
    func restoreChaptersWithDeadTTSAnchor() {
        for cached in cache.cache.values {
            guard let stamp = cached.ttsAnchorStamp, liveTTSAnchor(for: cached)?.contentStamp != stamp else { continue }
            let fresh = cached.unalignedParagraphItems
            cached.ttsAnchorStamp = nil
            cached.unalignedParagraphItems = nil
            guard let fresh else { continue }
            apply(items: fresh, to: cached)
            AppLogger.shared.log("🔁 [TTSRetranslate] Mốc của TTS hết hiệu lực ⇒ chương \(cached.index + 1) về bản dịch mới đầy đủ")
        }
    }

    private func apply(items: [ParagraphItem], to cached: CachedChapter) {
        cached.paragraphItems = items
        cached.content = Self.joinedContent(of: items)
        if let title = items.first(where: \.isTitle) { cached.title = title.translated }
    }
}
