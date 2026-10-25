import Foundation
import Observation

/// Nơi đọc/ghi kiểu hiển thị danh sách truyện theo `BookListLayoutScope`, lưu trong `UserDefaults`.
///
/// Dùng `@Observable` thay vì `@AppStorage` khoá động: View đọc `layout(for:)` trong `body` là tự vẽ lại khi
/// sheet "Kiểu hiển thị" hay màn Cài đặt ghi, kể cả khi scope của View đổi (Khám phá đổi nguồn) mà không phải
/// dựng lại `@AppStorage` theo khoá mới.
///
/// Khoá: `bookListLayout.mode.<scope>` (rawValue của `BookListLayoutMode`), `bookListLayout.columns.<scope>` và
/// `bookListLayout.rowSize.<scope>` (nấc `BookListRowSize`).
/// Khoá bắt đầu bằng chữ thường nên `BackupSettingsArchiver` tự gói vào bản sao lưu. Khôi phục sao lưu ghi thẳng
/// `UserDefaults`, nên bảng trong RAM nạp lại theo `UserDefaults.didChangeNotification`.
@MainActor
@Observable
final class BookListLayoutPreferences {
    static let shared = BookListLayoutPreferences()

    nonisolated static let columnRange = 2...5
    nonisolated static let defaultColumns = 3

    private(set) var layouts: [BookListLayoutScope: BookListLayout] = [:]

    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    private init() {
        layouts = Self.readAll()
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

    func layout(for scope: BookListLayoutScope) -> BookListLayout {
        layouts[scope] ?? .default
    }

    func setMode(_ mode: BookListLayoutMode, for scope: BookListLayoutScope) {
        var layout = layout(for: scope)
        guard layout.mode != mode else { return }
        layout.mode = mode
        layouts[scope] = layout
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey(scope))
    }

    func setColumns(_ columns: Int, for scope: BookListLayoutScope) {
        var layout = layout(for: scope)
        let clamped = Self.clampColumns(columns)
        guard layout.columns != clamped else { return }
        layout.columns = clamped
        layouts[scope] = layout
        UserDefaults.standard.set(clamped, forKey: Self.columnsKey(scope))
    }

    func setRowSize(_ level: Int, for scope: BookListLayoutScope) {
        var layout = layout(for: scope)
        let size = BookListRowSize(level: level)
        guard layout.rowSize != size else { return }
        layout.rowSize = size
        layouts[scope] = layout
        UserDefaults.standard.set(size.level, forKey: Self.rowSizeKey(scope))
    }

    /// Nút "Đặt lại mặc định" ở màn Cài đặt: xoá khoá ⇒ mọi scope về Danh sách, 3 cột, cỡ dòng mặc định.
    func resetAll() {
        let defaults = UserDefaults.standard
        for scope in BookListLayoutScope.allCases {
            defaults.removeObject(forKey: Self.modeKey(scope))
            defaults.removeObject(forKey: Self.columnsKey(scope))
            defaults.removeObject(forKey: Self.rowSizeKey(scope))
        }
        layouts = Self.readAll()
    }

    nonisolated static func modeKey(_ scope: BookListLayoutScope) -> String { "bookListLayout.mode.\(scope.rawValue)" }
    nonisolated static func columnsKey(_ scope: BookListLayoutScope) -> String { "bookListLayout.columns.\(scope.rawValue)" }
    nonisolated static func rowSizeKey(_ scope: BookListLayoutScope) -> String { "bookListLayout.rowSize.\(scope.rawValue)" }

    nonisolated static func clampColumns(_ value: Int) -> Int {
        min(max(value, columnRange.lowerBound), columnRange.upperBound)
    }

    /// `didChangeNotification` bắn cho **mọi** lần ghi `UserDefaults` của app — chỉ gán khi khác để không làm
    /// mọi danh sách đang hiển thị vẽ lại vô cớ.
    private func reloadIfChanged() {
        let fresh = Self.readAll()
        if fresh != layouts {
            layouts = fresh
        }
    }

    nonisolated private static func readAll() -> [BookListLayoutScope: BookListLayout] {
        let defaults = UserDefaults.standard
        var result: [BookListLayoutScope: BookListLayout] = [:]
        for scope in BookListLayoutScope.allCases {
            let mode = defaults.string(forKey: modeKey(scope)).flatMap(BookListLayoutMode.init(rawValue:)) ?? .list
            let storedColumns = defaults.object(forKey: columnsKey(scope)) as? Int
            let storedRowSize = defaults.object(forKey: rowSizeKey(scope)) as? Int
            result[scope] = BookListLayout(
                mode: mode,
                columns: clampColumns(storedColumns ?? defaultColumns),
                rowSize: BookListRowSize(level: storedRowSize ?? BookListRowSize.defaultLevel)
            )
        }
        return result
    }
}
