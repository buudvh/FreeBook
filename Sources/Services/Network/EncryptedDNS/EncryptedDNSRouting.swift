import Foundation

/// Bản chụp **có khoá** của việc định tuyến DNS mã hoá, đọc được từ thread bất kỳ (thread JS của `JSExecutor`, thread
/// engine Legado, hàng đợi của `EncryptedDNSRelay`). Bên ghi duy nhất là `EncryptedDNSRepository` (1.3.831).
///
/// - `activeResolver`: máy chủ DoH đang dùng; `nil` = không ai cần DNS mã hoá, hoặc lượt dò lỗi nên đang lùi về DNS
///   thường ⇒ request đi đường thường, proxy nội bộ (nếu vẫn được dùng) tra tên bằng DNS thường.
/// - `isGlobalApplied`: công tắc "Bật cho cả app" đang áp lên `NWParameters.PrivacyContext.default` ⇒ `URLSession`
///   dùng chung đã tra qua DoH, không cần vòng qua proxy.
/// - `hasEnabledSources`: có tiện ích / nguồn Legado bật cờ riêng — cho `EncryptedDNSSessionRouter` thoát sớm (khỏi tra
///   bản ghi tiện ích ở mỗi `fetch`) khi không ai bật.
enum EncryptedDNSRouting {
    struct Snapshot: Equatable, Sendable {
        var activeResolver: EncryptedDNSResolver?
        var isGlobalApplied: Bool
        var hasEnabledSources: Bool
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var snapshot = Snapshot(activeResolver: nil, isGlobalApplied: false, hasEnabledSources: false)
    }

    private static let storage = Storage()

    static var current: Snapshot {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.snapshot
    }

    static var activeResolver: EncryptedDNSResolver? { current.activeResolver }

    /// Chỉ `EncryptedDNSRepository` gọi.
    static func update(_ snapshot: Snapshot) {
        storage.lock.lock()
        storage.snapshot = snapshot
        storage.lock.unlock()
    }
}
