import Foundation

public final class BookDetailCacheManager {
    public static let shared = BookDetailCacheManager()
    
    private var cache: [String: BookDetailCacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5 phút
    private let queue = DispatchQueue(label: "BookDetailCacheManager.queue", attributes: .concurrent)
    
    private init() {}
    
    public struct BookDetailCacheEntry {
        let title: String
        let author: String
        let coverUrl: String
        let desc: String
        let detail: String
        let genres: [CategoryResult]
        let suggests: [CategoryResult]
        let comments: [CategoryResult]
        let host: String
        let timestamp: Date
    }
    
    public func getCache(for bookId: String) -> BookDetailCacheEntry? {
        return queue.sync {
            guard let entry = cache[bookId] else { return nil }
            if Date().timeIntervalSince(entry.timestamp) > cacheTimeout {
                cache.removeValue(forKey: bookId)
                return nil
            }
            return entry
        }
    }
    
    public func setCache(for bookId: String, entry: BookDetailCacheEntry) {
        queue.async(flags: .barrier) {
            self.cache[bookId] = entry
        }
    }
    
    public func clearCache(for bookId: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: bookId)
        }
    }
    
    public func clearAllCache() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}