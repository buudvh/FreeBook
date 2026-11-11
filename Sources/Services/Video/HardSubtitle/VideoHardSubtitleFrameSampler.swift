import AVFoundation
import CoreVideo
import Foundation
import QuartzCore

/// Gắn `AVPlayerItemVideoOutput` vào item đang phát và lấy khung hình mới nhất (dịch phụ đề cứng, 1.3.830).
///
/// - Lấy được khung cả với HLS (khác audio tap); nguồn có DRM thì không có khung ⇒ `copyLatestFrame()` trả `nil`.
/// - Xin buffer 4:2:0 full range để `VideoHardSubtitleBrightMask` đọc thẳng mặt phẳng độ sáng.
/// - `attach` / `detach` trên main (thêm / gỡ output của item); `copyLatestFrame()` gọi ở hàng đợi nền — `output` được giữ
///   sau khoá nên hai phía không giẫm nhau.
final class VideoHardSubtitleFrameSampler: @unchecked Sendable {
    /// Một khung hình. Buffer chỉ dùng trên hàng đợi nền, không gửi về main.
    struct Frame {
        let pixelBuffer: CVPixelBuffer
        let itemSeconds: Double
        let size: CGSize
    }

    private let lock = NSLock()
    private var output: AVPlayerItemVideoOutput?
    private weak var item: AVPlayerItem?

    @MainActor
    func attach(to item: AVPlayerItem) {
        detach()
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        item.add(output)
        lock.withLock {
            self.output = output
            self.item = item
        }
    }

    @MainActor
    func detach() {
        let (output, item) = lock.withLock { () -> (AVPlayerItemVideoOutput?, AVPlayerItem?) in
            let pair = (self.output, self.item)
            self.output = nil
            self.item = nil
            return pair
        }
        if let output, let item, item.outputs.contains(where: { $0 === output }) {
            item.remove(output)
        }
    }

    @MainActor
    func isAttached(to item: AVPlayerItem) -> Bool {
        lock.withLock { self.output != nil && self.item === item }
    }

    /// Khung đang hiển thị lúc gọi. `nil` khi chưa gắn, chưa có khung, hoặc khung của thời điểm này đã lấy rồi (đang tạm dừng).
    func copyLatestFrame() -> Frame? {
        guard let output = lock.withLock({ self.output }) else { return nil }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard itemTime.isValid, itemTime.isNumeric else { return nil }
        guard let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else { return nil }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        return Frame(pixelBuffer: buffer, itemSeconds: itemTime.seconds, size: size)
    }
}
