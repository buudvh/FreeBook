import Foundation

/// Kho **trong bộ nhớ** theo nguồn, sống tới khi app thoát (spec §5.7 mục 2 và 5, §6.7):
///
/// - biến rule (`java.put`/`@put`) khi **không** có ngữ cảnh sách (đánh giá `searchUrl`, `exploreUrl`, header, `jsLib`);
/// - `cache.putMemory/getFromMemory/deleteMemory` (giá trị lưu dạng văn bản JSON).
///
/// Dùng chung giữa mọi phiên của cùng nguồn (registry theo `bookSourceUrl`); an toàn đa luồng.
final class LegadoSourceSessionStore: @unchecked Sendable {
    private static let registryLock = NSLock()
    private static var registry: [String: LegadoSourceSessionStore] = [:]

    private let lock = NSLock()
    private var ruleVariables: [String: String] = [:]
    private var memory: [String: String] = [:]

    static func shared(forSourceKey key: String) -> LegadoSourceSessionStore {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[key] { return existing }
        let store = LegadoSourceSessionStore()
        registry[key] = store
        return store
    }

    func ruleVariable(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return ruleVariables[key]
    }

    func setRuleVariable(_ value: String, forKey key: String) {
        lock.lock()
        ruleVariables[key] = value
        lock.unlock()
    }

    func memoryValue(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return memory[key]
    }

    func setMemoryValue(_ value: String, forKey key: String) {
        lock.lock()
        memory[key] = value
        lock.unlock()
    }

    func removeMemoryValue(forKey key: String) {
        lock.lock()
        memory.removeValue(forKey: key)
        lock.unlock()
    }
}
