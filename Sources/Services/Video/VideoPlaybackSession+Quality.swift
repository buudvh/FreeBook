import Foundation
import AVFoundation

/// Mục **Chất lượng** của trình phát (menu `⋯`): đọc các biến thể HLS của item đang phát và cho chọn trần chất lượng.
///
/// - Chỉ có mục khi item là HLS có từ **2** mức trở lên (mp4, playlist một mức, playlist ghép hình + tiếng của
///   `VideoAudioRenditionComposer` ⇒ không có).
/// - Lựa chọn (`selectedQuality`) là **sở thích** giữ qua các tập trong phiên; mức thật sự áp (`appliedQuality`) là mức
///   cao nhất của item hiện tại không vượt lựa chọn đó. `stop()` ⇒ về Tự động.
/// - Áp qua `refreshBandwidthLimit` (`+Lifecycle`): đang phát ẩn thì vẫn ép thấp nhất, hiện lại thì theo lựa chọn.
extension VideoPlaybackSession {
    /// Gọi ngay sau khi item mới vào player: bỏ danh sách cũ rồi đọc `variants` của asset (không chặn main).
    func loadQualityOptions(for item: AVPlayerItem) {
        qualityTask?.cancel()
        qualityOptions = []
        let asset = item.asset
        qualityTask = Task { [weak self] in
            let variants = (try? await asset.load(.variants)) ?? []
            let options = Self.makeQualityOptions(from: variants)
            guard !Task.isCancelled, let self, self.player.currentItem === item else { return }
            self.qualityOptions = options
            self.refreshBandwidthLimit()
            if !options.isEmpty {
                AppLogger.shared.log("🎚️ [VideoPlayer] Có \(options.count) mức chất lượng: \(options.map(\.title).joined(separator: ", "))")
            }
        }
    }

    /// `nil` = Tự động.
    func selectQuality(_ option: VideoQualityOption?) {
        selectedQuality = option
        refreshBandwidthLimit()
        AppLogger.shared.log("🎚️ [VideoPlayer] Chọn chất lượng: \(option?.title ?? "Tự động")")
    }

    /// Mức đang áp cho item hiện tại; `nil` = không giới hạn (Tự động, hoặc item không có mục chất lượng).
    var appliedQuality: VideoQualityOption? {
        guard let selected = selectedQuality, !qualityOptions.isEmpty else { return nil }
        return qualityOptions.first { $0.isAtMost(selected) } ?? qualityOptions.last
    }

    /// Mỗi độ phân giải giữ biến thể bitrate cao nhất, xếp cao → thấp; bỏ biến thể chỉ có tiếng. Dưới 2 mức ⇒ `[]`.
    nonisolated static func makeQualityOptions(from variants: [AVAssetVariant]) -> [VideoQualityOption] {
        var best: [String: VideoQualityOption] = [:]
        for variant in variants {
            guard let rate = variant.peakBitRate ?? variant.averageBitRate, rate > 0 else { continue }
            if variant.videoAttributes == nil, variant.audioAttributes != nil { continue }
            let size = variant.videoAttributes?.presentationSize ?? .zero
            let option = VideoQualityOption(width: Int(size.width), height: Int(size.height), peakBitRate: rate)
            let key = option.height > 0 ? "h\(option.height)" : "b\(Int(rate))"
            if let existing = best[key], existing.peakBitRate >= rate { continue }
            best[key] = option
        }
        let options = best.values.sorted {
            $0.height != $1.height ? $0.height > $1.height : $0.peakBitRate > $1.peakBitRate
        }
        return options.count >= 2 ? options : []
    }
}
