import Foundation
import Observation

/// Nơi đọc/ghi cỡ từng bố cục của trang Khám phá theo loại nguồn (truyện chữ / truyện tranh / video / âm thanh), lưu trong
/// `UserDefaults`. Cùng khuôn với `BookListLayoutPreferences`: `@Observable` để View đọc `sizes(for:)` trong `body`
/// là tự vẽ lại khi sheet "Kiểu hiển thị" hay màn Cài đặt ghi.
///
/// Khoá: `exploreLayoutSize_<kind>_<scope>` (vd `exploreLayoutSize_grid_video`), giá trị là nấc 1…7; thiếu khoá = nấc
/// mặc định. Khoá bắt đầu bằng chữ thường nên `BackupSettingsArchiver` tự gói vào bản sao lưu; khôi phục ghi thẳng
/// `UserDefaults` nên bảng trong RAM nạp lại theo `UserDefaults.didChangeNotification`.
@MainActor
@Observable
final class ExploreLayoutSizePreferences {
    static let shared = ExploreLayoutSizePreferences()

    /// Trang Khám phá luôn thuộc đúng một loại nguồn ⇒ không có `.all`. `sizes(for: .all)` trả cỡ mặc định.
    nonisolated static let scopes: [BookListLayoutScope] = [.text, .comic, .video, .audio]

    private(set) var table: [BookListLayoutScope: ExploreLayoutSizes] = [:]

    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    private init() {
        table = Self.readAll()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadIfChanged()
            }
        }
    }

    func sizes(for scope: BookListLayoutScope) -> ExploreLayoutSizes {
        table[scope] ?? .default
    }

    func setLevel(_ level: Int, kind: ExploreLayoutSizeKind, for scope: BookListLayoutScope) {
        guard Self.scopes.contains(scope) else { return }
        var sizes = sizes(for: scope)
        let size = ExploreLayoutSize(level: level)
        guard sizes[kind] != size else { return }
        sizes[kind] = size
        table[scope] = sizes
        UserDefaults.standard.set(size.level, forKey: Self.key(kind, scope))
    }

    /// "Đặt lại mặc định" ở Cài đặt › Kiểu hiển thị: xoá khoá ⇒ mọi bố cục về nấc mặc định.
    func resetAll() {
        let defaults = UserDefaults.standard
        for scope in Self.scopes {
            for kind in ExploreLayoutSizeKind.allCases {
                defaults.removeObject(forKey: Self.key(kind, scope))
            }
        }
        table = Self.readAll()
    }

    nonisolated static func key(_ kind: ExploreLayoutSizeKind, _ scope: BookListLayoutScope) -> String {
        "exploreLayoutSize_\(kind.rawValue)_\(scope.rawValue)"
    }

    /// `didChangeNotification` bắn cho **mọi** lần ghi `UserDefaults` của app — chỉ gán khi khác để trang Khám phá
    /// không vẽ lại vô cớ.
    private func reloadIfChanged() {
        let fresh = Self.readAll()
        if fresh != table {
            table = fresh
        }
    }

    nonisolated private static func readAll() -> [BookListLayoutScope: ExploreLayoutSizes] {
        let defaults = UserDefaults.standard
        var result: [BookListLayoutScope: ExploreLayoutSizes] = [:]
        for scope in scopes {
            var sizes = ExploreLayoutSizes.default
            for kind in ExploreLayoutSizeKind.allCases {
                if let stored = defaults.object(forKey: key(kind, scope)) as? Int {
                    sizes[kind] = ExploreLayoutSize(level: stored)
                }
            }
            result[scope] = sizes
        }
        return result
    }
}
