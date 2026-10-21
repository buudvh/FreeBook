import Foundation

/// Giới hạn nhịp request theo `concurrentRate` của nguồn (spec §4.1), dùng chung giữa **mọi** phiên của cùng một nguồn
/// trong tiến trình (registry theo khoá nguồn). Gồm cả `java.ajax` trong JS.
///
/// - `"N"`: khoảng cách tối thiểu N ms giữa hai lần truy cập.
/// - `"N/M"`: tối đa N lần trong cửa sổ trượt M ms.
/// - `0`, rỗng, không parse được ⇒ không giới hạn (`shared` trả `nil`).
///
/// Mỗi lời gọi **đặt chỗ** thời điểm của mình dưới khoá rồi mới ngủ (ngoài khoá), nên nhiều phiên song song vẫn
/// xếp hàng đúng nhịp. Không đoán "số luồng" — đúng như tài liệu.
final class LegadoRateLimiter {
    private enum Rule {
        case interval(TimeInterval)
        case window(count: Int, period: TimeInterval)
    }

    private static let registryLock = NSLock()
    private static var registry: [String: (rate: String, limiter: LegadoRateLimiter)] = [:]

    private let rule: Rule
    private let lock = NSLock()
    private var nextAllowed = Date.distantPast
    private var reservations: [Date] = []

    private init(rule: Rule) {
        self.rule = rule
    }

    /// Limiter dùng chung của nguồn; `nil` khi không giới hạn.
    static func shared(forSourceKey key: String, rate: String) -> LegadoRateLimiter? {
        guard let rule = parse(rate) else { return nil }
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[key], existing.rate == rate { return existing.limiter }
        let limiter = LegadoRateLimiter(rule: rule)
        registry[key] = (rate: rate, limiter: limiter)
        return limiter
    }

    private static func parse(_ raw: String) -> Rule? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let count = Int(parts[0]), let period = Double(parts[1]), count > 0, period > 0 {
            return .window(count: count, period: period / 1000)
        }
        if parts.count == 1, let interval = Double(parts[0]), interval > 0 {
            return .interval(interval / 1000)
        }
        return nil
    }

    /// Chờ tới lượt (trên thread engine; có kiểm huỷ).
    func acquire(cancellation: LegadoEngineCancellation) throws {
        let wait = reserve()
        if wait > 0 { try cancellation.sleep(wait) }
    }

    private func reserve() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        switch rule {
        case .interval(let interval):
            let start = max(now, nextAllowed)
            nextAllowed = start.addingTimeInterval(interval)
            return start.timeIntervalSince(now)
        case .window(let count, let period):
            reservations.removeAll { $0 < now.addingTimeInterval(-period) }
            var slot = now
            if reservations.count >= count {
                slot = max(now, reservations[reservations.count - count].addingTimeInterval(period))
            }
            reservations.append(slot)
            return slot.timeIntervalSince(now)
        }
    }
}
