import SwiftUI

/// Nút tai nghe nổi của Reader + sheet hỏi khi bấm trúng chương TTS đang phát (`ReaderTTSSameChapterSheet`, trình bày qua
/// `OverlaySheetPresenter` ⇒ nằm trên mọi viên thuốc từ 1.3.868).
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
            openTTSQuickControlsAfterListen()
            return
        }
        let target = headphoneTTSTarget(geometry: geometry)
        let state = ttsState.snapshot
        if state.isPlaying, state.playingBookId == bookId, state.playingChapterIndex == target.chapterIndex {
            let prompt = ReaderTTSSameChapterSheet.Prompt(
                chapterIndex: target.chapterIndex,
                viewingParagraphIndex: target.paragraphIndex,
                bookId: bookId,
                bookTitle: readerBookDisplayTitle,
                chapterTitle: getChapterTitle(at: target.chapterIndex),
                coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
                readsChapterTitle: showChapterTitle
            )
            // Sheet nằm trên mọi viên thuốc (2026-11-11, anh Bửu: không ẩn đĩa, cho nó dưới sheet); chọn ⇒ đóng sheet xong
            // mới làm. Không trình bày được (đang có sheet phủ khác / chưa có scene) ⇒ sheet thường của Reader như cũ.
            let presented = OverlaySheetPresenter.shared.present {
                ReaderTTSSameChapterPromptHost(prompt: prompt) { choice in
                    OverlaySheetPresenter.shared.dismiss {
                        applyTTSSameChapterChoice(choice, prompt: prompt)
                    }
                }
            }
            if !presented {
                ttsSameChapterPrompt = prompt
            }
            return
        }
        restartTTS(at: target.chapterIndex, paragraphIndex: target.paragraphIndex)
        openTTSQuickControlsAfterListen()
    }

    /// Bấm nghe trong Reader — nút tai nghe (kể cả sau khi chọn ở sheet "đang đọc chương này") và "Nghe" của bôi đen ⇒ mở
    /// sheet nghe mini của đĩa (1.3.944, anh Bửu). Phiên chưa bật thì manager chờ đĩa TTS có mặt rồi mới mở.
    internal func openTTSQuickControlsAfterListen() {
        MediaDiscWindowManager.shared.presentQuickControlsWhenReady()
    }

    /// Đường lùi: sheet hỏi gắn lên tầng sheet gốc của Reader (cùng chỗ với `withSelectionSheets`) — chỉ dùng khi
    /// `OverlaySheetPresenter` không trình bày được; đường chính là sheet phủ trên mọi viên thuốc.
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
            showChapterStartForRestartedTTS(chapterIndex: prompt.chapterIndex)
        }
        openTTSQuickControlsAfterListen()
    }

    /// Người hỏi thường đang ở giữa chương (hay đã kéo trang ⇒ tự cuộn bị tắt): tiếng đọc về đầu chương thì trang cũng phải
    /// về và đi theo. Bật lại tự cuộn như lệnh nhảy của widget, rồi cuộn tới đầu chương (`paragraphIndex` -1 ⇒
    /// `ReaderScrollCoordinator` cuộn tới mốc `chapter-N`) — tên chương không có highlight nên tự cuộn không tự kéo tới.
    private func showChapterStartForRestartedTTS(chapterIndex index: Int) {
        reenableTTSAutoScrollFromWidgetJump()
        if index != chapterIndex {
            requestChapter(at: index, paragraphIndex: 0, source: .ttsSync, persistProgress: false)
        } else {
            scrollTarget = ScrollTarget(chapterIndex: index, paragraphIndex: -1)
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
