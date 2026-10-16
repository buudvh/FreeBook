import Foundation
import os

/// `localStorage` của tiện ích JavaScript, khoá theo **namespace** (`packageId`), lưu ở
/// `extension_store/local_storage.json`.
///
/// Thay khoá `UserDefaults` cũ `"vbook_ext_storage_" + md5(localPath) + "_" + key` (`JSExecutor`): khoá cũ đổi
/// theo đường dẫn tuyệt đối nên mất sạch khi gốc thư mục dữ liệu đổi (1.3.523) và không bao giờ được dọn.
///
/// API **đồng bộ, không chặn lâu** — được gọi thẳng từ thread JavaScriptCore (`@convention(block)`): chỉ giữ
/// lock trong lúc đọc/ghi dictionary RAM. File nạp lười lần đầu truy cập (đọc ngoài lock) và được ghi gom
/// ~2 s trên queue nền; `flush()` ghi ngay (vào background, migrator). Crash trong cửa sổ gom có thể mất lần
/// ghi cuối — chấp nhận, như `UserDefaults` trước đây.
public final class ExtensionLocalStorageStore: @unchecked Sendable {
    public static let shared = ExtensionLocalStorageStore()

    private struct State: Sendable {
        var isLoaded = false
        var data: [String: [String: String]] = [:]
        var isDirty = false
        var isWriteScheduled = false
    }

    /// Cửa sổ gom ghi file sau một thay đổi.
    private static let writeDelay: TimeInterval = 2

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let writeQueue = DispatchQueue(label: "FreeBook.ExtensionLocalStorageStore", qos: .utility)

    private init() {}

    // MARK: - API cho JS bridge

    public func value(namespace: String, key: String) -> String? {
        ensureLoaded()
        return state.withLock { $0.data[namespace]?[key] }
    }

    public func setValue(_ value: String, namespace: String, key: String) {
        ensureLoaded()
        let changed = state.withLock { (s) -> Bool in
            guard s.data[namespace]?[key] != value else { return false }
            s.data[namespace, default: [:]][key] = value
            s.isDirty = true
            return true
        }
        if changed { scheduleWrite() }
    }

    public func removeValue(namespace: String, key: String) {
        ensureLoaded()
        let changed = state.withLock { (s) -> Bool in
            guard s.data[namespace]?[key] != nil else { return false }
            s.data[namespace]?[key] = nil
            if s.data[namespace]?.isEmpty == true { s.data[namespace] = nil }
            s.isDirty = true
            return true
        }
        if changed { scheduleWrite() }
    }

    /// Xoá cả namespace — dùng khi gỡ tiện ích (`ExtensionTransactionCoordinator.deleteExtension`).
    public func removeAll(namespace: String) {
        ensureLoaded()
        let changed = state.withLock { (s) -> Bool in
            guard s.data[namespace] != nil else { return false }
            s.data[namespace] = nil
            s.isDirty = true
            return true
        }
        if changed { scheduleWrite() }
    }

    // MARK: - Backup / migrate

    /// Bản chép toàn bộ dữ liệu — dùng cho backup và migrator.
    public func snapshot() -> [String: [String: String]] {
        ensureLoaded()
        return state.withLock { $0.data }
    }

    /// Restore: **ghi đè cả namespace** có trong `incoming`; namespace không có trong `incoming` giữ nguyên.
    /// Namespace rỗng trong `incoming` ⇒ xoá namespace đó.
    public func merge(_ incoming: [String: [String: String]]) {
        guard !incoming.isEmpty else { return }
        ensureLoaded()
        state.withLock { s in
            for (namespace, values) in incoming {
                s.data[namespace] = values.isEmpty ? nil : values
            }
            s.isDirty = true
        }
        scheduleWrite()
    }

    /// Ghi ngay, đồng bộ (chờ cả lượt ghi đang xếp hàng). Không có gì thay đổi ⇒ không ghi, trả `true`.
    @discardableResult
    public func flush() -> Bool {
        writeQueue.sync { writeIfDirty() }
    }

    // MARK: - Nội bộ

    /// Nạp file lần đầu. Đọc **ngoài** lock để thread JS khác không phải chờ IO; nếu hai thread cùng nạp thì
    /// bản nạp sau bị bỏ (bản trước có thể đã nhận thay đổi).
    private func ensureLoaded() {
        if state.withLock({ $0.isLoaded }) { return }
        let loaded = ExtensionStoreFileIO.read(
            ExtensionStoreEnvelope.LocalStorage.self,
            from: ExtensionStorePaths.localStorageURL,
            label: "local_storage.json"
        )?.storage ?? [:]
        state.withLock { s in
            guard !s.isLoaded else { return }
            s.data = loaded
            s.isLoaded = true
        }
    }

    private func scheduleWrite() {
        let shouldSchedule = state.withLock { (s) -> Bool in
            guard !s.isWriteScheduled else { return false }
            s.isWriteScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        writeQueue.asyncAfter(deadline: .now() + Self.writeDelay) { [weak self] in
            _ = self?.writeIfDirty()
        }
    }

    /// Chỉ chạy trên `writeQueue`.
    private func writeIfDirty() -> Bool {
        let pending = state.withLock { (s) -> [String: [String: String]]? in
            s.isWriteScheduled = false
            guard s.isDirty else { return nil }
            s.isDirty = false
            return s.data
        }
        guard let pending else { return true }
        let ok = ExtensionStoreFileIO.write(
            ExtensionStoreEnvelope.LocalStorage(storage: pending),
            to: ExtensionStorePaths.localStorageURL,
            label: "local_storage.json"
        )
        // Ghi lỗi: đánh dấu bẩn lại để lần thay đổi/flush sau thử tiếp, không mất dữ liệu RAM.
        if !ok { state.withLock { $0.isDirty = true } }
        return ok
    }
}
