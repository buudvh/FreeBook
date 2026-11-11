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

            Text(chapterHeaderTitle(at: failure.targetChapterIndex, rawTitle: failure.chapterTitle))
                .font(.title3.weight(.semibold))
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(failure.sourceMessage)
                .font(.subheadline)
                .foregroundColor(selectedTheme.textColor.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let link = failure.errorLink {
                // Như `ErrorLinkCaption` nhưng theo màu theme đọc (`.secondary` lệch tông trên theme sáng/trầm ấm).
                Text(link.displayText)
                    .font(.caption2)
                    .foregroundColor(selectedTheme.textColor.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("Link lỗi: \(link.displayText)")
            }

            // Hai nút một hàng; chữ to (Dynamic Type) không đủ chỗ thì xếp dọc.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { chapterErrorActions(failure: failure, viewModel: vm) }
                VStack(spacing: 10) { chapterErrorActions(failure: failure, viewModel: vm) }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `[Tải lại] [Mở link lỗi]` của khối lỗi tải chương. Nút link tự dựng theo kiểu nút "Tải lại" (màu theme đọc) thay
    /// cho `ErrorLinkButton` (chữ trắng cố định — mất trên theme sáng); bấm ⇒ `.errorLinkBrowser` ở `ReaderView` mở trình
    /// duyệt, đóng ⇒ chép cookie ⇒ `retryPendingNavigation()`.
    @ViewBuilder
    private func chapterErrorActions(failure: ReaderChapterLoadFailure, viewModel vm: ReaderViewModel) -> some View {
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

        if let link = failure.errorLink {
            Button(action: { openingChapterErrorLink = link }) {
                Label(ErrorLinkButton.title, systemImage: ErrorLinkButton.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundColor(selectedTheme.textColor)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(selectedTheme.textColor.opacity(0.1))
                    .cornerRadius(8)
            }
            .disabled(vm.isRetryingNavigation)
            .accessibilityLabel(ErrorLinkButton.accessibilityText)
            .accessibilityHint(link.displayText)
        }
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
            ttsHighlight.currentParentParagraphIndex >= 0 &&
            !isAutoScrollDisabled

        requestChapter(
            at: targetIndex,
            paragraphIndex: landsOnPlayingParagraph ? ttsHighlight.currentParentParagraphIndex : -1,
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

    /// Bộ dịch tiện ích ⇒ bản tiện ích (`source = detail`) khi đã có, tạm hiện bản QT (1.3.853).
    internal var readerBookDisplayTitle: String {
        let original = localBook?.title ?? bookTitle ?? "Tàng Công Các"
        let shown = titleTranslations.book.text(original, kind: .meta, quick: translateMetaIfNeeded(original))
        return DisplayTextFormatter.titleCase(shown)
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
        selectedTheme == .dark ? Color.black.opacity(0.78) : Color.white.opacity(0.72)
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
        // Hợp đồng tiện ích dịch: tải lại chương bỏ qua cache bản dịch (cache RAM theo dòng của truyện, cả lỗi đã nhớ).
        TranslationExtensionLineCache.shared.invalidate(bookId: bookId)
        // TTS bỏ bản chuẩn bị sẵn; đang đọc đúng chương này bằng tiện ích dịch ⇒ đọc lại theo bản dịch mới.
        ttsManager.refreshExtensionTranslation(bookId: bookId, chapterIndex: viewModel?.displayedChapterIndex ?? chapterIndex)
        viewModel?.reloadDisplayedChapter()
    }

    /// Nút nổi góc dưới phải của Reader: nút tai nghe. Đĩa nghe góc dưới phải (nhạc / TTS kiểu Đĩa góc dưới, cửa sổ riêng
    /// của `MediaDiscWindowManager`, 1.3.808) tự đứng ngay trên nó nhờ neo `.mediaDiscAnchor(.button)` — thay hai nút đĩa
    /// riêng của Reader (1.3.792 / 1.3.806).
    internal func readerEdgeControls(geometry: GeometryProxy) -> some View {
        readerTTSControl(geometry: geometry)
    }

    @ViewBuilder
    internal func readerTTSControl(geometry: GeometryProxy) -> some View {
        readerEdgeButton(
            icon: "headphones",
            tint: selectedTheme.textColor.opacity(0.9),
            // Tạm dừng tại chỗ ⇒ phát tiếp; trúng chương đang phát ⇒ sheet hỏi; còn lại đọc từ đoạn trên cùng màn hình.
            action: { handleReaderHeadphoneTap(geometry: geometry) }
        )
        .accessibilityLabel("Đọc thành tiếng")
        .mediaDiscAnchor(.button)
        // Tâm nút giữ đúng chỗ cũ (nút cũ 60pt = 44pt + đệm kính 8pt, lề phải 8 / dưới 12).
        .padding(.trailing, 12)
        .padding(.bottom, 16)
    }

    /// Nút tròn 52pt nền kính theo Cài đặt › Giao diện (1.3.636) — cùng kiểu với nút "+" nổi của màn danh sách.
    internal func readerEdgeButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 52, height: 52)
                .background { FloatingGlassBackground(isDark: selectedTheme == .dark, outline: tint) }
                .contentShape(Circle())
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

    /// Đầu dò UIKit nằm **trong** content của khung cuộn chương: kéo tay khi TTS đang đọc (`ReaderUserScrollDetector`).
    /// Không tiêu thụ touch nên không đụng bôi đen chữ. Chạm 1/3 hai bên để chuyển chương (1.3.643) đã bỏ ở 1.3.667 —
    /// đổi chương chỉ bằng nút Chương trước/sau và mục lục.
    internal var readerScrollProbes: some View {
        ReaderUserScrollDetector { handleUserScrollWhilePlaying() }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
    }

    /// Nhảy từ widget TTS là lệnh quay lại vệt đang nghe, nên bật lại cuộn theo highlight nếu phiên
    /// Reader trước đó đã tắt do tìm kiếm hoặc người dùng tự kéo trang.
    internal func reenableTTSAutoScrollFromWidgetJump() {
        guard isAutoScrollDisabled else { return }
        isAutoScrollDisabled = false
        ttsAutoScrollGeneration += 1
        AppLogger.shared.log("[Reader] Widget TTS yêu cầu nhảy tới highlight — bật lại cuộn theo highlight")
    }

    /// Đưa Reader về chỗ TTS đang đọc: bật lại cuộn theo highlight, khác chương ⇒ mở chương đó, cùng chương ⇒ cuộn tới
    /// đoạn. Dùng chung cho lệnh nhảy của widget (`navigateReaderToPlayingChapter`) và "Đọc tiếp chỗ đang đọc" của sheet
    /// hỏi khi bấm nút tai nghe trúng chương đang phát.
    internal func jumpToPlayingTTSPosition(chapterIndex targetIndex: Int, paragraphIndex: Int) {
        reenableTTSAutoScrollFromWidgetJump()
        if targetIndex != chapterIndex {
            requestChapter(
                at: targetIndex,
                paragraphIndex: paragraphIndex,
                source: .ttsSync,
                persistProgress: false
            )
        } else if paragraphIndex >= 0 {
            scrollTarget = ScrollTarget(chapterIndex: targetIndex, paragraphIndex: paragraphIndex)
        }
    }
}
