import Foundation

/// Giới hạn chuỗi tự bỏ qua chương của TTS.
///
/// Trước đây chương tải lỗi / xử lý lỗi / không có nội dung ⇒ tự nhảy sang chương sau, **không giới hạn**.
/// Khi tiến trình cạn file descriptor thì chương nào cũng lỗi, nên TTS lướt qua cả hàng đợi chương,
/// mỗi chương một toast, tới tận cuối truyện. Nay `maxConsecutiveChapterFailures` chương liên tiếp không
/// phát được thì tạm dừng.
///
/// Bộ đếm `consecutiveChapterFailureCount` về 0 khi một chương thật sự bắt đầu phát (`applyNextChapter`),
/// khi người dùng bắt đầu phát (`startSpeaking`) và khi tạm dừng (`pause`).
extension TTSManager {
    static let maxConsecutiveChapterFailures = 5

    /// Chương `index` vừa được apply và bắt đầu phát ⇒ chuỗi lỗi kết thúc; kèm một lần đếm fd theo chương.
    func noteChapterAdvanceSucceeded(_ index: Int) {
        consecutiveChapterFailureCount = 0
        FileDescriptorCensus.record(event: "chapter=\(index)")
    }

    /// Có chương sau `index` ⇒ chuyển sang; hết truyện ⇒ dừng hẳn + toast.
    func advanceOrFinishBook(after index: Int, finishMessage: String = "📖 Đã phát hết nội dung bộ truyện.") {
        if let nextIdx = nextChapterIndex(after: index) {
            advanceToNextChapter(nextIdx: nextIdx)
        } else {
            stopCurrentPlayback()
            pause()
            TTSPresentationEventCenter.shared.send(.showToast(message: finishMessage, type: .info))
            onChapterFinished?()
        }
    }

    /// Chương `index` không phát được (tải lỗi, xử lý lỗi, hoặc không có nội dung khi `error == nil`).
    /// Chưa tới ngưỡng ⇒ toast `toast` rồi bỏ qua sang chương sau như cũ; tới ngưỡng ⇒ tạm dừng.
    func skipFailedChapter(_ index: Int, toast: String, error: Error?) {
        consecutiveChapterFailureCount += 1
        let failureCount = consecutiveChapterFailureCount
        let errorDetail = error.map(FileDescriptorCensus.describe) ?? "không có nội dung"
        AppLogger.shared.log("❌ [TTSManager] Chương \(index) không phát được (lần \(failureCount) liên tiếp): \(errorDetail)")

        let outOfDescriptors = (error.map(FileDescriptorCensus.isOutOfDescriptors) ?? false)
            || FileDescriptorCensus.isNearLimit()
        if outOfDescriptors {
            FileDescriptorCensus.noteOpenFailure(context: "TTS chương \(index)", error: error)
        }

        guard failureCount >= Self.maxConsecutiveChapterFailures else {
            TTSPresentationEventCenter.shared.send(.showToast(message: toast, type: .info))
            advanceOrFinishBook(
                after: index,
                finishMessage: "⏸️ Chương \(index) không phát được và đã tới cuối truyện. Đã tạm dừng đọc."
            )
            return
        }

        consecutiveChapterFailureCount = 0
        stopCurrentPlayback()
        pause()
        let hint = outOfDescriptors
            ? " App đang mở quá nhiều file — hãy tắt hẳn app rồi mở lại."
            : ""
        TTSPresentationEventCenter.shared.send(.showToast(
            message: "⏸️ Đã tạm dừng đọc: \(failureCount) chương liên tiếp không phát được (tới chương \(index)).\(hint)",
            type: .error
        ))
    }
}
