import SwiftUI

/// Nút tai nghe nổi của Reader + sheet hỏi khi bấm trúng chương TTS đang phát (`ReaderTTSSameChapterSheet`).
///
/// Thứ tự quyết định của nút — chỉ thêm bước 3, các bước khác giữ nguyên hành vi cũ:
/// 1. TTS đang **tạm dừng** truyện này và đoạn đang dừng còn trong vùng an toàn của màn hình ⇒ phát tiếp đúng chunk.
/// 2. Tính đoạn sẽ đọc: đoạn trên cùng màn hình (`getTopVisible` → `topVisible`) → đoạn đã lưu → tiến độ view model → -1.
/// 3. TTS **đang phát** đúng truyện + đúng chương của đoạn đó ⇒ mở sheet hỏi, chưa đụng phiên TTS.
/// 4. Còn lại: dừng phiên đang có rồi đọc từ đoạn đó.
///
/// Chỉ nút tai nghe hỏi: "Nghe" của menu bôi đen là chỗ người dùng tự chọn nên đọc ngay; đang tạm dừng thì không hỏi.
extension ReaderView {
    internal func handleReaderHeadphoneTap(geometry: GeometryProxy) {
        if canResumePausedTTSInPlace {
            ttsManager.resume()
            return
        }
        let target = headphoneTTSTarget(geometry: geometry)
        let state = ttsState.snapshot
        if state.isPlaying, state.playingBookId == bookId, state.playingChapterIndex == target.chapterIndex {
            ttsSameChapterPrompt = ReaderTTSSameChapterSheet.Prompt(
                chapterIndex: target.chapterIndex,
                viewingParagraphIndex: target.paragraphIndex,
                bookId: bookId,
                bookTitle: readerBookDisplayTitle,
                chapterTitle: getChapterTitle(at: target.chapterIndex),
                coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
                readsChapterTitle: showChapterTitle
            )
            return
        }
        restartTTS(at: target.chapterIndex, paragraphIndex: target.paragraphIndex)
    }

    /// Gắn sheet hỏi lên tầng sheet gốc của Reader (cùng chỗ với `withSelectionSheets`).
    internal func withTTSSameChapterPrompt<Base: View>(_ base: Base) -> some View {
        base.sheet(item: $ttsSameChapterPrompt) { prompt in
            ReaderTTSSameChapterSheet(
                prompt: prompt,
                isPlaying: ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId,
                height: $ttsSameChapterSheetHeight
            ) { choice in
                ttsSameChapterPrompt = nil
                applyTTSSameChapterChoice(choice, prompt: prompt)
            }
        }
    }

    // MARK: - Lựa chọn

    private func applyTTSSameChapterChoice(
        _ choice: ReaderTTSSameChapterSheet.Choice,
        prompt: ReaderTTSSameChapterSheet.Prompt
    ) {
        switch choice {
        case .continueCurrent:
            continueCurrentTTS(fallback: prompt)
        case .fromViewingParagraph:
            restartTTS(at: prompt.chapterIndex, paragraphIndex: prompt.viewingParagraphIndex)
        case .fromChapterStart:
            // -1 = chunk đầu (tên chương nếu TTS đọc tên chương) — `TTSChunkPositionMapper.targetChunkIndex`.
            restartTTS(at: prompt.chapterIndex, paragraphIndex: -1)
        }
    }

    /// Không dựng lại phiên đang đọc: chỉ đưa trang về đoạn đang đọc + bật lại tự cuộn (cùng đường nhảy của widget); bị
    /// tạm dừng giữa lúc sheet mở thì phát tiếp. Phiên đã tắt trong lúc đó ⇒ đọc từ đoạn đang xem như bấm nút thường.
    private func continueCurrentTTS(fallback prompt: ReaderTTSSameChapterSheet.Prompt) {
        let state = ttsState.snapshot
        guard state.playingBookId == bookId, state.isPlaying || state.showFloatingWidget else {
            restartTTS(at: prompt.chapterIndex, paragraphIndex: prompt.viewingParagraphIndex)
            return
        }
        if !state.isPlaying {
            ttsManager.resume()
        }
        jumpToPlayingTTSPosition(
            chapterIndex: state.playingChapterIndex,
            paragraphIndex: max(ttsHighlight.currentParentParagraphIndex, 0)
        )
    }

    // MARK: - Nút tai nghe (chuyển nguyên văn từ `ReaderView+Controls`)

    /// Dừng phiên đang có (đang đọc hoặc còn widget) rồi đọc từ đoạn chỉ định.
    private func restartTTS(at index: Int, paragraphIndex: Int) {
        if ttsState.snapshot.isPlaying || ttsState.snapshot.showFloatingWidget {
            ttsManager.stop()
        }
        startTTS(at: index, paragraphIndex: paragraphIndex)
    }

    /// Đoạn nút tai nghe sẽ đọc: đoạn trên cùng vùng nhìn của chương đang mở → đoạn trên cùng bất kỳ → đoạn đã lưu →
    /// tiến độ của view model → -1 (đầu chương).
    private func headphoneTTSTarget(geometry: GeometryProxy) -> (chapterIndex: Int, paragraphIndex: Int) {
        let viewportTopY = geometry.frame(in: .global).minY + geometry.safeAreaInsets.top + 20
        if let top = paragraphTracker.getTopVisible(viewportTopY: viewportTopY, currentBookId: bookId, currentChapterIndex: chapterIndex) {
            return (top.chapterIndex, top.paragraphIndex)
        }
        if let top = paragraphTracker.topVisible {
            return (top.chapterIndex, top.paragraphIndex)
        }
        let savedPIdx = getSavedParagraphIndex(for: chapterIndex)
        if savedPIdx >= 0 {
            return (chapterIndex, savedPIdx)
        }
        if let vm = viewModel, vm.readingContext.chapterIndex == chapterIndex, vm.readingContext.paragraphIndex >= 0 {
            return (chapterIndex, vm.readingContext.paragraphIndex)
        }
        return (chapterIndex, -1)
    }

    /// TTS đang **tạm dừng** truyện này và đoạn đang dừng vẫn nằm trong vùng an toàn của màn hình (cùng điều kiện
    /// tự cuộn) ⇒ nút tai nghe phát tiếp đúng chunk đang dừng. Người dùng đã kéo trang đi chỗ khác thì giữ hành vi
    /// cũ: dừng phiên và đọc từ đoạn trên cùng màn hình.
    private var canResumePausedTTSInPlace: Bool {
        let state = ttsState.snapshot
        guard !state.isPlaying, state.showFloatingWidget,
              state.playingBookId == bookId,
              state.playingChapterIndex == chapterIndex else { return false }
        return paragraphTracker.isParagraphInsideSafeViewport(
            bookId: bookId,
            chapterIndex: chapterIndex,
            paragraphIndex: ttsHighlight.currentParentParagraphIndex,
            viewportMinY: readerViewportMinY,
            viewportMaxY: readerViewportMaxY
        )
    }
}
