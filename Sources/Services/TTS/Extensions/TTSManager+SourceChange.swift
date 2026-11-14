import Foundation

/// Đổi nguồn lúc đang nghe truyện cũ (1.3.946, anh Bửu chọn "tự chuyển nghe sang truyện mới"). Trước đây đang nghe thì
/// lượt đổi nguồn **giữ** truyện cũ để khỏi ngắt quãng ⇒ hai truyện tách đôi: TTS và Reader mở từ đĩa nghe vẫn là truyện
/// cũ, VP / Name riêng lưu lúc đó vào truyện cũ, truyện mới không bao giờ nhận được.
extension TTSManager {
    /// `BookSourceChangeCoordinator` gọi ngay sau mốc chốt (truyện cũ chưa bị dọn — dọn sau ~1,2 s). Phiên đang đọc truyện
    /// cũ ⇒ dừng **ngay** (để `BookStorageManager` xoá được truyện cũ) rồi đọc tiếp truyện mới ở **cùng chỉ số chương** (đổi
    /// nguồn chép chương theo vị trí) từ đầu dòng đang đọc (chương đã tải chép nguyên văn nên trùng dòng; chương tải mới từ
    /// nguồn mới thì gần đúng). Phiên đang tạm dừng ⇒ chỉ dừng hẳn, bấm nghe lại ở truyện mới.
    func continueListeningAfterSourceChange(
        fromBookId oldBookId: String,
        toBookId newBookId: String,
        source: BookSourceChangeCoordinator.SourceSnapshot,
        ext: Extension
    ) {
        guard !oldBookId.isEmpty, playingBookId == oldBookId, showFloatingWidget || isPlaying else { return }
        let wasPlaying = isPlaying
        let chapterIndex = playingChapterIndex
        let paragraphIndex = max(currentParentParagraphIndex, -1)
        stop()
        guard wasPlaying else {
            AppLogger.shared.log("[SourceChange] TTS đang tạm dừng ⇒ dừng phiên của truyện cũ \(oldBookId)")
            TTSPresentationEventCenter.shared.send(.showToast(
                message: "Đã chuyển sang nguồn mới — bấm nghe để đọc tiếp", type: .info
            ))
            return
        }
        let queue = source.chapters.map { TTSChapterInfo(title: $0.title, url: $0.url, index: $0.index, host: $0.host) }
        guard let chapter = queue.first(where: { $0.index == chapterIndex }) else {
            AppLogger.shared.log("❌ [SourceChange] Nguồn mới không có chương \(chapterIndex + 1) ⇒ dừng nghe")
            TTSPresentationEventCenter.shared.send(.showToast(
                message: "Nguồn mới không có chương \(chapterIndex + 1) — đã dừng nghe", type: .error
            ))
            return
        }
        let extensionInfo = TTSExtensionInfo(
            packageId: ext.packageId, localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson
        )
        let book = source.createSnapshot
        AppLogger.shared.log("[SourceChange] TTS chuyển sang truyện mới \(newBookId), chương \(chapterIndex + 1), dòng \(paragraphIndex)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let request = ChapterContentRequest(
                bookId: newBookId,
                chapterIndex: chapter.index,
                title: chapter.title,
                url: chapter.url,
                host: chapter.host,
                bookMetadata: nil,
                extensionInfo: extensionInfo,
                forceRefresh: false
            )
            do {
                let result = try await ChapterContentRepository.shared.load(request)
                // Trong lúc tải người dùng đã bắt đầu nghe truyện khác ⇒ thôi.
                guard self.playingBookId.isEmpty || self.playingBookId == newBookId else { return }
                self.startSpeaking(
                    bookId: newBookId,
                    chapters: queue,
                    currentIndex: chapter.index,
                    chapterContent: result.document.text.content,
                    startParagraphIndex: paragraphIndex,
                    bookTitle: book.title,
                    coverUrl: book.coverUrl,
                    bookDetailUrl: book.detailUrl,
                    bookSourceName: book.sourceName,
                    extensionInfo: extensionInfo,
                    translationPackageId: ext.packageId,
                    author: book.author
                )
            } catch {
                AppLogger.shared.log("❌ [SourceChange] Không tải được chương \(chapterIndex + 1) ở nguồn mới: \(error.localizedDescription)")
                TTSPresentationEventCenter.shared.send(.showToast(
                    message: "Không tải được chương \(chapterIndex + 1) ở nguồn mới — đã dừng nghe", type: .error
                ))
            }
        }
    }
}
