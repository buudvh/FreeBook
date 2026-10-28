import Foundation

/// Tốc độ tải chương của một nguồn (1.3.624): nghỉ bao lâu sau mỗi chương tải từ mạng và tải cùng lúc mấy chương của
/// cùng một truyện.
///
/// - Nhớ **theo tiện ích** (`packageId`) trong UserDefaults: giới hạn chặn là của trang nguồn, nên truyện cùng nguồn
///   dùng chung một cấu hình.
/// - Mặc định (không nghỉ, 1 luồng) đúng như trước khi có mục này. Tải tuần tự là chủ ý để tránh bị nguồn chặn;
///   nhiều luồng chỉ là lựa chọn người dùng tự bật.
/// - Tác vụ đọc bản lưu **lúc bắt đầu chạy** (`DownloadManager+ChapterLanes`, `DownloadManager+Comic`), không lưu
///   theo từng tác vụ.
struct DownloadSpeedSettings: Equatable, Sendable {
    /// Số giây mỗi luồng nghỉ sau một chương tải từ mạng (chương đã có trong máy không nghỉ).
    var delaySeconds: Double
    /// Số chương của cùng một truyện được tải cùng lúc.
    var laneCount: Int

    static let `default` = DownloadSpeedSettings(delaySeconds: 0, laneCount: 1)
    static let delayRange: ClosedRange<Double> = 0...10
    static let delayStep: Double = 0.5
    static let laneRange: ClosedRange<Int> = 1...3

    private static let defaultsKey = "downloadSpeedSettingsByPackage"
    private static let delayField = "delay"
    private static let laneField = "lanes"

    /// Giá trị đã kẹp vào dải cho phép, delay làm tròn theo bước 0,5 giây.
    var clamped: DownloadSpeedSettings {
        let steps = (delaySeconds / Self.delayStep).rounded()
        let delay = min(max(steps * Self.delayStep, Self.delayRange.lowerBound), Self.delayRange.upperBound)
        let lanes = min(max(laneCount, Self.laneRange.lowerBound), Self.laneRange.upperBound)
        return DownloadSpeedSettings(delaySeconds: delay, laneCount: lanes)
    }

    var delayNanoseconds: UInt64 {
        UInt64(clamped.delaySeconds * 1_000_000_000)
    }

    /// "Không", "0,5 giây", "2 giây".
    var delayTitle: String {
        let delay = clamped.delaySeconds
        guard delay > 0 else { return "Không" }
        let text = delay.rounded() == delay
            ? String(Int(delay))
            : String(format: "%.1f", delay).replacingOccurrences(of: ".", with: ",")
        return "\(text) giây"
    }

    static func load(packageId: String) -> DownloadSpeedSettings {
        guard let entry = storedMap()[packageId] else { return .default }
        return DownloadSpeedSettings(
            delaySeconds: entry[delayField] ?? Self.default.delaySeconds,
            laneCount: Int(entry[laneField] ?? Double(Self.default.laneCount))
        ).clamped
    }

    /// Bằng mặc định thì xoá mục của nguồn để UserDefaults không giữ bản ghi thừa.
    static func save(_ settings: DownloadSpeedSettings, packageId: String) {
        guard !packageId.isEmpty else { return }
        let value = settings.clamped
        var map = storedMap()
        if value == .default {
            guard map.removeValue(forKey: packageId) != nil else { return }
        } else {
            map[packageId] = [delayField: value.delaySeconds, laneField: Double(value.laneCount)]
        }
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    private static func storedMap() -> [String: [String: Double]] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String: Double]] ?? [:]
    }
}
