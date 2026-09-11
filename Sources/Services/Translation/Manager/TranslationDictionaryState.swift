import Foundation

/// Short lock scopes protect publication; each reader receives value snapshots, never a loader.
final class TranslationDictionaryState: @unchecked Sendable {
    struct Global: Sendable {
        var vietPhrase: FrozenTrieDictionary?
        var names: FrozenTrieDictionary?
        var pronouns: FrozenTrieDictionary?
        var luatNhan: FrozenTrieDictionary?
        var customVietPhrase: FrozenTrieDictionary?
        var customNames: FrozenTrieDictionary?
        var phienAm: [String: String] = [:]
        var deletedVietPhrase: Set<String> = []
        var deletedNames: Set<String> = []
        var deletedVietPhraseList: [String] = []
        var deletedNamesList: [String] = []
        var customVPRecords: [DictionaryTextRecord] = []
        var customNameRecords: [DictionaryTextRecord] = []
    }

    struct Book: Sendable {
        let vietPhrase: FrozenTrieDictionary?
        let names: FrozenTrieDictionary?
    }

    private let lock = NSLock()
    private var global = Global()
    private var books: [String: Book] = [:]
    private var order: [String] = []
    private var loadRevision: UInt64 = 0
    private var publicationRevision: UInt64 = 0

    func revision() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return publicationRevision
    }

    func read() -> Global {
        lock.lock()
        defer { lock.unlock() }
        return global
    }

    func snapshot() -> (global: Global, revision: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (global, publicationRevision)
    }

    func update(_ change: (inout Global) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&global)
        publicationRevision &+= 1
    }

    func invalidate(bookId: String?) {
        lock.lock()
        defer { lock.unlock() }
        loadRevision &+= 1
        publicationRevision &+= 1
        if let bookId {
            books.removeValue(forKey: bookId)
            order.removeAll { $0 == bookId }
        } else {
            books.removeAll()
            order.removeAll()
        }
    }

    func book(_ bookId: String, directory: URL) -> Book {
        while true {
            lock.lock()
            if let hit = books[bookId] {
                order.removeAll { $0 == bookId }
                order.append(bookId)
                lock.unlock()
                return hit
            }
            let revision = loadRevision
            lock.unlock()
            func load(_ name: String) -> FrozenTrieDictionary? {
                let loader = TextDictionary()
                guard (try? loader.load(from: directory.appendingPathComponent(name))) != nil,
                      loader.wordCount > 0 else { return nil }
                return loader.frozen()
            }
            let loaded = Book(vietPhrase: load("VietPhrase.txt"), names: load("Names.txt"))
            lock.lock()
            guard revision == loadRevision else { lock.unlock(); continue }
            books[bookId] = loaded
            order.removeAll { $0 == bookId }
            order.append(bookId)
            while order.count > 3 { books.removeValue(forKey: order.removeFirst()) }
            lock.unlock()
            return loaded
        }
    }
}
