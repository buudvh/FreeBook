import Foundation

/// Cost-bounded LRU. The ticket rejects an in-flight insertion after any invalidation.
final class TranslationMemo<Value: Sendable>: @unchecked Sendable {
    private struct Entry {
        let value: Value
        let bookId: String?
        let cost: Int
        var access: UInt64
    }
    private let lock = NSLock()
    private let maxEntries: Int
    private let maxCost: Int
    private var entries: [String: Entry] = [:]
    private var cost = 0
    private var clock: UInt64 = 0
    private var epoch: UInt64 = 0

    init(maxEntries: Int, maxCost: Int) {
        self.maxEntries = maxEntries
        self.maxCost = maxCost
    }

    func lookup(_ key: String) -> (value: Value?, ticket: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[key] {
            clock &+= 1
            entry.access = clock
            entries[key] = entry
            return (entry.value, epoch)
        }
        return (nil, epoch)
    }

    func insert(_ value: Value, key: String, bookId: String?, cost payloadCost: Int, ticket: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        let itemCost = max(1, payloadCost + key.utf16.count * 2)
        guard ticket == epoch, itemCost <= maxCost else { return }
        cost -= entries.removeValue(forKey: key)?.cost ?? 0
        while !entries.isEmpty && (entries.count >= maxEntries || cost + itemCost > maxCost) {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            cost -= entries.removeValue(forKey: oldest)?.cost ?? 0
        }
        clock &+= 1
        entries[key] = Entry(value: value, bookId: bookId, cost: itemCost, access: clock)
        cost += itemCost
    }

    func invalidate(bookId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        epoch &+= 1
        if let bookId {
            for key in entries.keys.filter({ entries[$0]?.bookId == bookId }) {
                cost -= entries.removeValue(forKey: key)?.cost ?? 0
            }
        } else {
            entries.removeAll()
            cost = 0
        }
    }
}
