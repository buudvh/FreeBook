import SwiftUI

extension ReaderView {
    internal func scrollToTTSHighlightIfNeeded() {
        guard isSceneActive else { return }
        guard !isAutoScrollDisabled else { return }
        if ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId && ttsState.snapshot.currentParentParagraphIndex >= 0 {
            let targetIdx = ttsState.snapshot.currentParentParagraphIndex
            let chapIdx = ttsState.snapshot.playingChapterIndex
            if chapIdx == chapterIndex {
                let currentGen = ttsAutoScrollGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard self.isSceneActive && self.ttsAutoScrollGeneration == currentGen else { return }
                    self.requestTTSScrollIfNeeded(chapterIndex: chapIdx, paragraphIndex: targetIdx)
                }
            }
        }
    }

    internal func requestTTSScrollIfNeeded(chapterIndex: Int, paragraphIndex: Int) {
        guard isSceneActive else { return }
        guard !isRestoringReaderPosition else { return }
        let isInsideSafeViewport = paragraphTracker.isParagraphInsideSafeViewport(
            bookId: bookId,
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            viewportMinY: readerViewportMinY,
            viewportMaxY: readerViewportMaxY
        )
        if isInsideSafeViewport {
            ReaderEnergyDiagnostics.shared.recordTTSScrollSkippedVisible()
            return
        }

        ReaderEnergyDiagnostics.shared.recordTTSScrollTarget()
        scrollTarget = ScrollTarget(
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            reason: .ttsAuto
        )
    }

    @ViewBuilder
    internal func chapterInlineLoadingView(index: Int) -> some View {
        VStack(spacing: 24) {
            Text(getChapterTitle(at: index))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)

            chapterSkeletonLines
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .onAppear {
            skeletonHandshakeIndex = index
            ReaderEnergyDiagnostics.shared.recordSkeletonPresented(index: index)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang tải \(getChapterTitle(at: index))")
    }

    /// Cổng bắt tay skeleton: subtree nội dung của chương `index` chỉ được dựng khi
    /// (a) chưa từng dựng chương nào, (b) đúng chương đang hiển thị (reload tại chỗ), hoặc
    /// (c) skeleton của chính chương đó đã xuất hiện ít nhất một frame.
    ///
    /// Đây là điều kiện *cấu trúc*, không phải hẹn giờ. Nếu thiếu nó, một lượt commit từ
    /// RAM có thể vừa tháo subtree chương cũ vừa dựng subtree chương mới trong cùng một
    /// update pass; log thiết bị cho thấy pass gộp đó tốn 1.6–3.5 s (không có dòng
    /// `[ReaderPerf] Skeleton`), còn khi đi qua skeleton thì `Present` chỉ cách commit ~20 ms.
    internal func isChapterSubtreeRenderable(_ index: Int) -> Bool {
        guard let rendered = renderedChapterIndex else { return true }
        if rendered == index { return true }
        return skeletonHandshakeIndex == index
    }

    @ViewBuilder
    internal func chapterBootstrapErrorView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
            Button("Quay lại") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    internal var chapterSkeletonLines: some View {
        let widthFactors: [CGFloat] = [1, 0.94, 0.82, 1, 0.9, 0.76, 1, 0.86]
        return GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 36)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(widthFactors.indices, id: \.self) { index in
                    SkeletonView(width: availableWidth * widthFactors[index], height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
        }
        .frame(height: 226)
    }
}
