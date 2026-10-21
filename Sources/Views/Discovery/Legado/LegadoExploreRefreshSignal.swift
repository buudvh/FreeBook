import Foundation
import Observation

/// Tín hiệu "làm mới khám phá" của nguồn Legado (`java.refreshExplore()` / `source.refreshExplore()`, spec §11.5).
///
/// `LegadoPresentationEventCenter.stream` chỉ có **một** subscriber (presenter ở root) — màn Khám phá không được lặp
/// stream lần hai, nên presenter chuyển sự kiện sang đây: bộ đếm theo `packageId` (sự kiện mang `bookSourceUrl` thô,
/// đổi bằng `LegadoSourceIdentity.packageId(forSourceUrl:)`). Màn điều khiển khám phá đọc `serial(packageId:)` trong
/// `body` và tải lại danh mục khi số đổi.
@MainActor
@Observable
final class LegadoExploreRefreshSignal {
    static let shared = LegadoExploreRefreshSignal()

    private var serials: [String: Int] = [:]

    private init() {}

    func notify(sourceKey: String) {
        let packageId = LegadoSourceIdentity.packageId(forSourceUrl: sourceKey)
        serials[packageId, default: 0] += 1
    }

    func serial(packageId: String) -> Int {
        serials[packageId] ?? 0
    }
}
