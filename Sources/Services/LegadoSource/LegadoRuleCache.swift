import Foundation

/// Cache LRU nhỏ, an toàn nhiều luồng — dùng cho rule đã biên dịch và regex đã compile.
///
/// Không dùng `NSCache` vì `NSCache` không giữ thứ tự truy cập và có thể xả sớm ngoài tầm kiểm soát,
/// còn ở đây chi phí biên dịch rule nhỏ nhưng số lần gọi rất lớn (mỗi chương một lượt).
public final class LegadoRuleCache<Value>: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var storage: [String: Value] = [:]
    private var order: [String] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public func value(for key: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = storage[key] else { return nil }
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        return value
    }

    public func set(_ value: Value, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if storage[key] == nil {
            order.append(key)
        } else if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        storage[key] = value
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    public func removeAll() {
        lock.lock()
        storage.removeAll()
        order.removeAll()
        lock.unlock()
    }
}
