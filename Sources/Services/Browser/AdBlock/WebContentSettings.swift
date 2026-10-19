import Foundation

/// Cài đặt chung của chặn quảng cáo / chế độ hiển thị cho webview, đọc từ `UserDefaults`.
/// Là nguồn duy nhất khai khoá lưu trữ để View (`@AppStorage`) và Service dùng chung.
///
/// Phía Service đọc bằng `object(forKey:) as? Bool ?? <mặc định>` thay vì `bool(forKey:)`: nếu vì lý do nào đó
/// `registerDefaults()` chưa chạy, `bool(forKey:)` trả `false` và **âm thầm tắt** chặn quảng cáo.
enum WebContentSettings {
    /// Chặn quảng cáo chung (trình duyệt + webview tiện ích). Mặc định bật.
    static let adBlockEnabledKey = "webAdBlockEnabled"
    /// Chặn cửa sổ bật lên — chỉ trình duyệt người dùng. Mặc định bật.
    static let popupBlockingEnabledKey = "webPopupBlockingEnabled"
    /// Chế độ hiển thị mặc định của trình duyệt người dùng: `true` = Máy tính. Mặc định Điện thoại.
    static let browserDefaultDesktopKey = "webBrowserDefaultDesktop"
    /// `[Int]` filterId đang bật. Mặc định các bộ `defaultEnabled` của `AdBlockFilter.catalog`.
    static let enabledFilterIdsKey = "webAdBlockEnabledFilterIds"

    /// Gọi trong `FreeBookApp.init`, **trước** mọi chỗ tạo webview.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            adBlockEnabledKey: true,
            popupBlockingEnabledKey: true,
            browserDefaultDesktopKey: false,
            enabledFilterIdsKey: AdBlockFilter.defaultEnabledIds,
        ])
    }

    static var adBlockEnabled: Bool {
        UserDefaults.standard.object(forKey: adBlockEnabledKey) as? Bool ?? true
    }

    static var popupBlockingEnabled: Bool {
        UserDefaults.standard.object(forKey: popupBlockingEnabledKey) as? Bool ?? true
    }

    static var browserDefaultDesktop: Bool {
        UserDefaults.standard.object(forKey: browserDefaultDesktopKey) as? Bool ?? false
    }

    /// Chỉ giữ id có trong danh mục. Khoá vắng mặt / sai kiểu ⇒ các bộ bật sẵn (cùng lý do như `?? true`).
    static var enabledFilterIds: Set<Int> {
        guard let raw = UserDefaults.standard.array(forKey: enabledFilterIdsKey) else {
            return Set(AdBlockFilter.defaultEnabledIds)
        }
        let known = Set(AdBlockFilter.catalog.map(\.id))
        let ids = raw.compactMap { ($0 as? NSNumber)?.intValue }
        return Set(ids).intersection(known)
    }

    /// Chỉ `AdBlockRuleListProvider.setFilter` gọi — ghi theo thứ tự danh mục cho dễ đọc khi chẩn đoán.
    static func setEnabledFilterIds(_ ids: Set<Int>) {
        let ordered = AdBlockFilter.catalog.map(\.id).filter { ids.contains($0) }
        UserDefaults.standard.set(ordered, forKey: enabledFilterIdsKey)
    }
}
