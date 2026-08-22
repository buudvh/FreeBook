import Foundation

/// Cài đặt của Visible Browser đọc từ `UserDefaults`.
/// Là nguồn duy nhất khai key lưu trữ để View (`@AppStorage`) và Service dùng chung.
enum VisibleBrowserSettings {
    /// Bật: trình duyệt hiển thị **mới** khởi tạo ngay ở chế độ thu nhỏ (widget nổi).
    /// Tắt: giữ nguyên hành vi cũ — hiện toàn màn hình khi mở.
    static let openMinimizedKey = "openVisibleBrowserMinimized"

    static var opensMinimized: Bool {
        UserDefaults.standard.bool(forKey: openMinimizedKey)
    }
}
