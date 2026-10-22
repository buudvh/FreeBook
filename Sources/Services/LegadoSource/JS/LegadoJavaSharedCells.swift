import Foundation

/// Ô số dùng chung **toàn tiến trình** cho `AtomicLong`/`AtomicInteger` mà nguồn đặt vào `java.lang.System.getProperties()`
/// (spec §6.9). Nguồn dùng bảng đó làm bộ giới hạn nhịp xuyên tác vụ: khoá `com.user.RateLimiter.nextTime.<khoá nguồn><bước>`,
/// vòng `get`/`compareAndSet` rồi `LockSupport.parkNanos`. Mỗi tác vụ của engine có `JSContext` riêng (§6.1), nên giá trị phải
/// sống ngoài ngữ cảnh, nếu không giới hạn nhịp mất tác dụng giữa các chương. Chỉ giữ số, tối đa `capacity` ô, không ghi đĩa;
/// ô không bao giờ bị xoá (ô đã gắn với một đối tượng JS phải còn đó, nếu không vòng `compareAndSet` của nguồn quay mãi).
final class LegadoJavaSharedCells: @unchecked Sendable {
    static let shared = LegadoJavaSharedCells()

    private let lock = NSLock()
    private var cells: [String: Double] = [:]
    private static let capacity = 512

    func value(_ key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return cells[key]
    }

    /// Gắn ô `key`: chưa có ⇒ tạo với `value`; đã có ⇒ giữ nguyên, hoặc ghi đè khi `replace` (`put`). Trả giá trị hiện tại
    /// của ô; `nil` khi bảng đầy (JS giữ giá trị cục bộ của nó).
    func bind(_ key: String, _ value: Double, replace: Bool) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        if let current = cells[key], !replace { return current }
        guard cells[key] != nil || cells.count < Self.capacity else { return nil }
        cells[key] = value
        return value
    }

    func set(_ key: String, _ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        if cells[key] != nil { cells[key] = value }
    }

    /// So theo số nguyên (|hiện tại − mong đợi| < 0,5): giá trị đi qua JSON hai chiều, sai số biểu diễn không được làm vòng
    /// `compareAndSet` của nguồn thất bại mãi.
    func compareAndSet(_ key: String, expect: Double, update: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let current = cells[key], abs(current - expect) < 0.5 else { return false }
        cells[key] = update
        return true
    }

    /// Cộng `delta`, trả (cũ, mới). Ô không có ⇒ (0, delta) và không tạo; kết quả không hữu hạn ⇒ giữ nguyên.
    func add(_ key: String, _ delta: Double) -> (old: Double, new: Double) {
        lock.lock()
        defer { lock.unlock() }
        let old = cells[key] ?? 0
        let new = old + delta
        guard new.isFinite else { return (old, old) }
        if cells[key] != nil { cells[key] = new }
        return (old, new)
    }

    /// Đặt `value`, trả giá trị cũ (ô không có ⇒ 0, không tạo).
    func swap(_ key: String, _ value: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        let old = cells[key] ?? 0
        if cells[key] != nil { cells[key] = value }
        return old
    }
}
