import Foundation

/// Mức chất lượng người dùng chọn ở mục Chất lượng của trình phát, nhớ **theo tiện ích** (1.3.743): phim nào cùng tiện
/// ích thì cùng mức. "Nguồn" = tiện ích (`BookContentLaunch.extensionPackageId`).
///
/// - Một dictionary `UserDefaults` `videoQualityPreferenceByPackage` dạng `[packageId: ["height": …, "bitrate": …]]`.
///   Không lưu `id` của `VideoQualityOption` (ghép từ bitrate của từng playlist, phim khác không khớp): lưu chiều cao để so
///   theo độ phân giải, kèm bitrate cho playlist không khai độ phân giải (`VideoQualityOption.isAtMost`).
/// - Chỉ `VideoPlaybackSession.selectQuality` ghi (chọn "Tự động" ⇒ xoá). Đường ép băng thông khi phát ẩn
///   (`refreshBandwidthLimit`) **không** ghi. `stop()` không xoá.
/// - Bản tải offline vẫn theo `videoDownloadQuality` riêng.
enum VideoQualityPreferenceStore {
    static let defaultsKey = "videoQualityPreferenceByPackage"

    private static let heightKey = "height"
    private static let bitrateKey = "bitrate"

    /// Mức đã nhớ của tiện ích; `nil` = Tự động (chưa chọn, hoặc đã chọn Tự động).
    static func preference(packageId: String) -> VideoQualityOption? {
        guard !packageId.isEmpty,
              let all = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let entry = all[packageId] as? [String: Any] else { return nil }
        let height = (entry[heightKey] as? NSNumber)?.intValue ?? 0
        let bitrate = (entry[bitrateKey] as? NSNumber)?.doubleValue ?? 0
        guard height > 0 || bitrate > 0 else { return nil }
        return VideoQualityOption(width: 0, height: max(0, height), peakBitRate: max(0, bitrate))
    }

    /// Ghi mức vừa chọn; `nil` (Tự động) ⇒ xoá mục của tiện ích.
    static func save(_ option: VideoQualityOption?, packageId: String) {
        guard !packageId.isEmpty else { return }
        var all = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
        if let option {
            let entry: [String: Any] = [heightKey: option.height, bitrateKey: option.peakBitRate]
            all[packageId] = entry
        } else {
            all.removeValue(forKey: packageId)
        }
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }
}
