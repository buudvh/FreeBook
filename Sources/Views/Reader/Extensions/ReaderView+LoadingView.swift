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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang tải \(getChapterTitle(at: index))")
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
