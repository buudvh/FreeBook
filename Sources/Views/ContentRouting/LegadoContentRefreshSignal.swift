import Foundation
import Observation

/// Tín hiệu "nạp lại chương đang đọc" của nguồn Legado (`refreshContent()` trong JS của nguồn — U62, spec §14.5).
///
/// `LegadoPresentationEventCenter.stream` chỉ có **một** subscriber (presenter ở root), nên presenter chuyển sự kiện
/// sang đây: bộ đếm theo `packageId` (sự kiện mang `bookSourceUrl` thô, đổi bằng
/// `LegadoSourceIdentity.packageId(forSourceUrl:)`). Trình đọc đang mở của một sách thuộc nguồn đó đọc
/// `serial(packageId:)` (qua `legadoContentRefresh`) và nạp lại chương hiện tại khi số đổi; sách của nguồn khác không bị
/// đụng tới.
///
/// Gom lặp: nguồn gọi `refreshContent()` ngay trong JS `content` của lượt nạp vừa kích hoạt sẽ tạo vòng nạp lại vô tận
/// ⇒ bỏ tín hiệu cùng nguồn đến trong `cooldown` giây kể từ tín hiệu được nhận gần nhất.
@MainActor
@Observable
final class LegadoContentRefreshSignal {
    static let shared = LegadoContentRefreshSignal()
    static let cooldown: TimeInterval = 3

    private var serials: [String: Int] = [:]
    @ObservationIgnored private var lastAccepted: [String: Date] = [:]

    private init() {}

    func notify(sourceKey: String) {
        let packageId = LegadoSourceIdentity.packageId(forSourceUrl: sourceKey)
        let now = Date()
        if let last = lastAccepted[packageId], now.timeIntervalSince(last) < Self.cooldown {
            AppLogger.shared.log("📚 [LegadoRefresh] Bỏ refreshContent lặp lại trong \(Int(Self.cooldown)) giây")
            return
        }
        lastAccepted[packageId] = now
        serials[packageId, default: 0] += 1
    }

    func serial(packageId: String) -> Int {
        serials[packageId] ?? 0
    }
}
