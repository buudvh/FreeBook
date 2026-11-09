import SwiftUI

/// Gốc nội dung của kiểu Thanh nghe nhạc (1.3.796), nằm trong `TTSWidgetBarContainerViewController`: thanh bung
/// (`TTSWidgetBarView`) hoặc viên thu gọn (`TTSWidgetBarPillView`) theo `model.isCollapsed`.
///
/// Sheet Hẹn giờ gắn **ở đây** (không ở thanh) để thu gọn lúc sheet đang mở — Reader mở ra, hết 5 giây — không gỡ mất nơi
/// giữ sheet. Ảnh bìa nạp một lần cho cả hai dạng (`TTSCoverImageLoader` của kiểu Đĩa nổi).
struct TTSWidgetBarContentView: View {
    @ObservedObject var model: TTSWidgetBarViewModel
    let rotationState: CoverRotationState
    @ObservedObject private var windowManager = TTSFloatingWidgetWindowManager.shared
    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()
    @StateObject private var info = TTSWidgetBarInfoReader()

    var body: some View {
        // Xoay bìa do Core Animation chạy (`TTSRotatingCoverView`); body chỉ đánh giá lại khi cờ này đổi.
        let isCoverRotating = ttsState.snapshot.isPlaying && windowManager.isWidgetActuallyVisible

        Group {
            if model.isCollapsed {
                TTSWidgetBarPillView(
                    model: model,
                    coverImage: coverLoader.image,
                    rotationState: rotationState,
                    isCoverRotating: isCoverRotating,
                    isPlaying: ttsState.snapshot.isPlaying
                )
            } else {
                TTSWidgetBarView(
                    model: model,
                    info: info,
                    snapshot: ttsState.snapshot,
                    coverImage: coverLoader.image,
                    rotationState: rotationState,
                    isCoverRotating: isCoverRotating
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.isTimerSheetPresented) {
            TTSQuickTimerSheet()
        }
        .onAppear {
            rotationState.syncPlaybackState(isPlaying: ttsState.snapshot.isPlaying, at: Date())
            refreshCover()
        }
        .onChange(of: ttsState.snapshot.playingBookId) { _, _ in
            refreshCover()
        }
        .onChange(of: ttsState.snapshot.playingCoverUrl) { _, _ in
            refreshCover()
        }
    }

    private func refreshCover() {
        coverLoader.load(
            bookId: ttsState.snapshot.playingBookId,
            coverURL: ttsState.snapshot.playingCoverUrl
        )
    }
}
