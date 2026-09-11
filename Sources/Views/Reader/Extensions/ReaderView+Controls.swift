import SwiftUI

extension ReaderView {
    @ViewBuilder
    internal func chapterNavigationErrorView(
        failure: ReaderChapterLoadFailure,
        viewModel vm: ReaderViewModel
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.red)

            Text(translateChapterTitleIfNeeded(failure.chapterTitle))
                .font(.title3.weight(.semibold))
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(failure.sourceMessage)
                .font(.subheadline)
                .foregroundColor(selectedTheme.textColor.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { vm.retryPendingNavigation() }) {
                HStack(spacing: 8) {
                    if vm.isRetryingNavigation {
                        ProgressView().tint(selectedTheme.textColor)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Tải lại")
                }
                .font(.body.weight(.semibold))
                .foregroundColor(selectedTheme.textColor)
                .frame(minWidth: 132, minHeight: 44)
                .background(selectedTheme.textColor.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(vm.isRetryingNavigation)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    internal func completeReaderPositionRestore(after delay: TimeInterval = 0) {
        guard isRestoringReaderPosition else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Không xoá frame map ở đây: các đoạn đang hiển thị không onAppear lại nên
            // map rỗng làm tick TTS đầu tiên luôn thấy "ngoài viewport" ⇒ một cú scroll thừa.
            // isRestoringReaderPosition đã chặn mọi consumer trong lúc restore.
            isRestoringReaderPosition = false
        }
    }

    internal func restoreReaderPositionIfNeeded(proxy: ScrollViewProxy, chapter: CachedChapter) {
        guard !chapter.isPositionRestored else {
            // Chương này đã restore ở lần hiển thị trước nên không có cú scroll nào để chờ.
            // Phải nhả cờ tại đây, nếu không isRestoringReaderPosition kẹt true cả session
            // và mọi consumer (auto-scroll TTS, lưu tiến độ theo cuộn) chết im lặng.
            completeReaderPositionRestore()
            schedulePrepareTTS()
            return
        }
        chapter.isPositionRestored = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let savedPIdx = getSavedParagraphIndex(for: chapter.index)
            let hasValidParagraph = chapter.paragraphItems.contains(where: { $0.id == savedPIdx })
            if savedPIdx >= 0 && hasValidParagraph {
                proxy.scrollTo("paragraph-\(chapter.index)-\(savedPIdx)", anchor: .top)
            } else {
                proxy.scrollTo("chapter-\(chapter.index)", anchor: .top)
            }
            completeReaderPositionRestore()
            schedulePrepareTTS()
        }
    }

    /// Next/Prev đi qua đúng cùng một cửa với chọn chương từ danh sách (`requestChapter(at:)`)
    /// — đường duy nhất người dùng báo là không đơ: cờ restore được đặt và frame map được
    /// xoá *trước* khi phát yêu cầu, nên không consumer nào đọc vị trí cũ giữa hai chương.
    /// Khi chương đích đúng là chương TTS đang phát, đoạn hạ cánh là đoạn đang đọc; cú cuộn
    /// sâu đó được `scheduleDeepLandingScroll` dời sang turn sau để không chặn chuyển chương.
    internal func stepChapterHonoringTTS(by offset: Int, source: ReaderNavigationSource) {
        let snapshot = ttsState.snapshot
        let isTTSOwningThisBook = snapshot.isPlaying && snapshot.playingBookId == bookId
        let baseIndex = viewModel?.pendingNavigationIndex ?? viewModel?.displayedChapterIndex ?? chapterIndex
        let targetIndex = baseIndex + offset
        guard targetIndex >= 0 && targetIndex < totalChaptersCount else { return }

        let landsOnPlayingParagraph = isTTSOwningThisBook &&
            snapshot.playingChapterIndex == targetIndex &&
            snapshot.currentParentParagraphIndex >= 0 &&
            !isAutoScrollDisabled

        requestChapter(
            at: targetIndex,
            paragraphIndex: landsOnPlayingParagraph ? snapshot.currentParentParagraphIndex : -1,
            source: source,
            persistProgress: !isTTSOwningThisBook
        )
    }

    /// Cuộn sâu tới đoạn hạ cánh ở một turn run loop SAU khi chương đã hiện — cùng mẫu trì
    /// hoãn 0.15 s với `restoreReaderPositionIfNeeded`. Timer chỉ nổ khi main thread rảnh,
    /// tức sau khi subtree chương mới đã dựng và present xong.
    internal func scheduleDeepLandingScroll(_ commit: ReaderNavigationCommit) {
        guard commit.paragraphIndex >= 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let vm = viewModel,
                  vm.navigationCommit?.generation == commit.generation,
                  vm.pendingNavigationIndex == nil,
                  vm.displayedChapterIndex == commit.chapterIndex else { return }
            // Giữ cờ restore qua cú cuộn thứ hai: auto-scroll TTS và lưu tiến độ theo cuộn
            // không được đọc vị trí giữa đường của cú nhảy sâu.
            isRestoringReaderPosition = true
            scrollTarget = ScrollTarget(
                chapterIndex: commit.chapterIndex,
                paragraphIndex: commit.paragraphIndex,
                reason: .initialRestore
            )
        }
    }

    internal var readerBookDisplayTitle: String {
        DisplayTextFormatter.titleCase(translateMetaIfNeeded(localBook?.title ?? bookTitle ?? "FreeBook"))
    }

    internal var readerPresentedChapterIndex: Int {
        viewModel?.pendingNavigationIndex ?? viewModel?.displayedChapterIndex ?? chapterIndex
    }

    internal var readerChapterDisplayTitle: String {
        getChapterTitle(at: readerPresentedChapterIndex)
    }

    internal var readerProgressPercent: Double {
        guard totalChaptersCount > 0 else { return 0 }
        return (Double(readerPresentedChapterIndex + 1) / Double(totalChaptersCount)) * 100
    }

    internal var readerChromeBackground: Color {
        selectedTheme.scrimColor
    }

    /// Áp cấu hình "hiện tên chương trong nội dung" cho truyện này. Cờ được lưu theo `bookId` vì
    /// `ReaderViewModel` (và `TTSManager`) đọc thẳng từ UserDefaults lúc dựng đoạn — đổi `@State`
    /// mà không lưu thì màn hình không đổi gì. Người gọi đã cập nhật `showChapterTitle` nên hàm
    /// này **không** toggle lần nữa.
    internal func applyShowChapterTitle(_ newValue: Bool) {
        UserDefaults.standard.set(newValue, forKey: "showChapterTitle_\(bookId)")
        viewModel?.invalidateParagraphLayoutForCachedChapters()
    }

    /// Cùng hợp đồng với `applyShowChapterTitle` cho cờ bỏ tiêu đề chương trùng ở đầu nội dung.
    internal func applyRemoveDuplicatedTitle(_ newValue: Bool) {
        UserDefaults.standard.set(newValue, forKey: "removeDuplicatedTitle_\(bookId)")
        viewModel?.invalidateParagraphLayoutForCachedChapters()
    }

    internal func reloadCurrentChapterFromMenu() {
        paragraphTracker.removeAll()
        isRestoringReaderPosition = true
        viewModel?.reloadDisplayedChapter()
    }

    /// Nút "làm mới màn hình" riêng cho E-Ink. Chỉ hiện khi mode bật và công tắc phụ mở (xem ReaderView).
    /// Gọi `EInkRefreshOverlay.flash()` — nháy đen/trắng toàn màn hình để xoá ghosting. Ngoài E-Ink,
    /// người dùng không bao giờ thấy nút này, nhưng vẫn dùng chung `readerEdgeButton` để giữ style viền.
    @ViewBuilder
    internal var readerEInkRefreshControl: some View {
        readerEdgeButton(
            icon: "arrow.clockwise",
            tint: selectedTheme.textColor.opacity(0.9),
            action: { EInkRefreshOverlay.shared.flash() }
        )
        .accessibilityLabel("Làm mới màn hình E-Ink")
        .padding(8)
        .background {
            if EInkModeSettings.shared.isEnabled {
                Circle().fill(EInkPalette.paper)
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if EInkModeSettings.shared.isEnabled {
                Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
            }
        }
        .einkShadow(Color.black.opacity(0.18), radius: 12, y: 4)
        .padding(.trailing, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    internal func readerTTSControl(geometry: GeometryProxy) -> some View {
        readerEdgeButton(
            icon: "headphones",
            tint: selectedTheme.textColor.opacity(0.9),
            action: {
                if ttsState.snapshot.isPlaying || ttsState.snapshot.showFloatingWidget {
                    ttsManager.stop()
                }
                let viewportTopY = geometry.frame(in: .global).minY + geometry.safeAreaInsets.top + 20
                if let top = paragraphTracker.getTopVisible(viewportTopY: viewportTopY, currentBookId: bookId, currentChapterIndex: chapterIndex) {
                    startTTS(at: top.chapterIndex, paragraphIndex: top.paragraphIndex)
                } else if let top = paragraphTracker.topVisible {
                    startTTS(at: top.chapterIndex, paragraphIndex: top.paragraphIndex)
                } else {
                    let savedPIdx = getSavedParagraphIndex(for: chapterIndex)
                    let targetPIdx: Int
                    if savedPIdx >= 0 {
                        targetPIdx = savedPIdx
                    } else if let vm = viewModel, vm.readingContext.chapterIndex == chapterIndex, vm.readingContext.paragraphIndex >= 0 {
                        targetPIdx = vm.readingContext.paragraphIndex
                    } else {
                        targetPIdx = -1
                    }
                    startTTS(at: chapterIndex, paragraphIndex: targetPIdx)
                }
            }
        )
        .accessibilityLabel(isTTSPlayingThisBook ? "Dừng đọc thành tiếng" : "Đọc thành tiếng")
        .padding(8)
        .background {
            if EInkModeSettings.shared.isEnabled {
                Circle().fill(EInkPalette.paper)
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if EInkModeSettings.shared.isEnabled {
                Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
            }
        }
        .einkShadow(Color.black.opacity(0.18), radius: 12, y: 4)
        .padding(.trailing, 8)
        .padding(.bottom, 12)
    }

    internal func readerEdgeButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        // Nút nổi trên nội dung. Trên e-ink nền đen 12% chỉ ra xám nhạt còn icon thì đen — thay bằng
        // **đĩa trắng viền đen** để nút vẫn tách khỏi chữ phía sau mà không cần mảng xám nào.
        let isEInk = EInkModeSettings.shared.isEnabled
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isEInk ? EInkPalette.ink : tint)
                .frame(width: 44, height: 44)
                .background {
                    if isEInk {
                        Circle().fill(EInkPalette.paper)
                    } else {
                        Circle().fill(Color.black.opacity(selectedTheme == .dark ? 0.34 : 0.12))
                    }
                }
                .overlay {
                    if isEInk {
                        Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
                    }
                }
        }
    }

    /// `NSRange` (UTF-16) của từ khoá tìm trong đoạn `item`, hoặc `nil` khi đoạn này không phải
    /// đoạn vừa được nhảy tới. Range tính lại mỗi lần render trên **chuỗi đang hiển thị**, nên bật/
    /// tắt dịch giữa đường chỉ làm vệt tự dời hoặc tự mất, không bao giờ trỏ sai chỗ.
    internal func searchHighlightRange(
        for item: ParagraphItem,
        chapterIndex: Int,
        isTranslationEnabled: Bool
    ) -> NSRange? {
        guard let highlight = searchHighlight,
              highlight.chapterIndex == chapterIndex,
              highlight.paragraphIndex == item.id else { return nil }
        let displayed = ParagraphCardView.displayText(for: item, isTranslationEnabled: isTranslationEnabled)
        return ReaderSearchMatcher.firstHighlightRange(of: highlight.query, in: displayed)
    }

    /// Người dùng tự kéo trang trong lúc TTS đang đọc truyện này ⇒ tắt cuộn theo highlight.
    /// Không có cú kéo nào thì không đổi gì, nên tính năng này vô hình với người không dùng tới.
    ///
    /// Ba cửa chặn để không tự tắt oan: đang bôi đen chữ (kéo để nới vùng chọn), đang khôi phục
    /// vị trí đọc (cú cuộn sâu của máy), và trạng thái đã tắt sẵn. Cú cuộn tự động của TTS không
    /// bao giờ tới được đây vì đầu dò chỉ nổ theo `UIPanGestureRecognizer` — xem
    /// `ReaderUserScrollDetector`.
    internal func handleUserScrollWhilePlaying() {
        guard !isAutoScrollDisabled else { return }
        guard isTTSPlayingThisBook else { return }
        guard !isRestoringReaderPosition else { return }
        guard !showingFloatingMenu else { return }

        isAutoScrollDisabled = true
        // Vô hiệu mọi cú cuộn TTS đã hẹn giờ trước đó, kể cả cú đang chờ trong scrollTarget.
        ttsAutoScrollGeneration += 1
        if scrollTarget?.reason == .ttsAuto {
            scrollTarget = nil
        }
        AppLogger.shared.log("[Reader] Người dùng tự cuộn khi TTS đang đọc — tắt cuộn theo highlight")
    }

    /// Nhảy từ widget TTS là lệnh quay lại vệt đang nghe, nên bật lại cuộn theo highlight nếu phiên
    /// Reader trước đó đã tắt do tìm kiếm hoặc người dùng tự kéo trang.
    internal func reenableTTSAutoScrollFromWidgetJump() {
        guard isAutoScrollDisabled else { return }
        isAutoScrollDisabled = false
        ttsAutoScrollGeneration += 1
        AppLogger.shared.log("[Reader] Widget TTS yêu cầu nhảy tới highlight — bật lại cuộn theo highlight")
    }
}
