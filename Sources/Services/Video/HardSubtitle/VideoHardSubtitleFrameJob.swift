import CoreGraphics
import Foundation

/// Một lượt đọc phụ đề cứng (1.3.830) — chạy trên hàng đợi nền của `VideoHardSubtitleEngine`, chặn luồng tới khi xong.
///
/// Lấy khung → mặt nạ điểm sáng → giống lần Vision trước ⇒ `.similar`; rỗng (khi được phép) ⇒ `.emptyMask`; còn lại ⇒ Vision.
/// Pixel buffer không rời hàng đợi nền: kết quả chỉ mang mặt nạ, chữ và cỡ khung.
enum VideoHardSubtitleFrameJob {
    enum Result: Sendable {
        /// Chưa gắn output / chưa có khung / khung của thời điểm này đã lấy rồi (đang tạm dừng) / nguồn DRM.
        case noFrame
        case similar(itemSeconds: Double)
        case emptyMask(VideoHardSubtitleBrightMask, itemSeconds: Double)
        case recognized(
            VideoHardSubtitleRecognizer.Recognition?,
            mask: VideoHardSubtitleBrightMask?,
            milliseconds: Double,
            itemSeconds: Double,
            frameSize: CGSize
        )
        case failed(String)
    }

    static func run(
        sampler: VideoHardSubtitleFrameSampler,
        previousMask: VideoHardSubtitleBrightMask?,
        allowsSimilarSkip: Bool,
        allowsEmptySkip: Bool
    ) -> Result {
        guard let frame = sampler.copyLatestFrame() else { return .noFrame }
        let mask = VideoHardSubtitleBrightMask(pixelBuffer: frame.pixelBuffer, stripTopRatio: VideoHardSubtitleRecognizer.stripTopRatio)
        // Xét rỗng TRƯỚC: hai mặt nạ rỗng có Jaccard = 1 ⇒ nếu xét "giống" trước, khung trống sau một khung trống sẽ thành
        // `.similar` (tracker không được báo trống ⇒ bản dịch cũ treo tới lần đọc lại bắt buộc). Rỗng mà không được bỏ qua
        // (dò thưa / chữ màu nhạt) ⇒ chạy Vision.
        if let mask, mask.isNearlyEmpty {
            if allowsEmptySkip { return .emptyMask(mask, itemSeconds: frame.itemSeconds) }
        } else if allowsSimilarSkip, let mask, let previousMask,
                  mask.similarity(to: previousMask) >= VideoHardSubtitleBrightMask.similarThreshold {
            return .similar(itemSeconds: frame.itemSeconds)
        }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let recognition = try VideoHardSubtitleRecognizer.recognize(in: frame.pixelBuffer)
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
            return .recognized(recognition, mask: mask, milliseconds: milliseconds, itemSeconds: frame.itemSeconds, frameSize: frame.size)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
