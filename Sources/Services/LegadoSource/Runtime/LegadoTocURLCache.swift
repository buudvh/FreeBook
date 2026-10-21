import Foundation

/// Danh sách URL chương của vài mục lục Legado vừa tải (trong bộ nhớ), để luồng nội dung tìm **URL chương kế** — URL
/// dừng của vòng `nextContentUrl` (spec §5.6). Sau khi app khởi động lại thì tra `ChapterStore` thay thế.
final class LegadoTocURLCache: @unchecked Sendable {
    static let shared = LegadoTocURLCache()
    private static let capacity = 8

    private let lock = NSLock()
    private var lists: [String: [String]] = [:]
    private var order: [String] = []

    func store(_ urls: [String], packageId: String, bookUrl: String) {
        let key = LegadoBookStateStore.memoryKey(packageId: packageId, bookUrl: bookUrl)
        lock.lock()
        lists[key] = urls
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.capacity {
            lists.removeValue(forKey: order.removeFirst())
        }
        lock.unlock()
    }

    /// URL chương ngay sau `chapterUrl`; `index` (nếu có) được thử trước để khỏi dò cả danh sách.
    func nextURL(after chapterUrl: String, index: Int?, packageId: String, bookUrl: String) -> String? {
        let key = LegadoBookStateStore.memoryKey(packageId: packageId, bookUrl: bookUrl)
        lock.lock()
        let urls = lists[key]
        lock.unlock()
        guard let urls, !urls.isEmpty else { return nil }
        var position: Int?
        if let index, urls.indices.contains(index), urls[index] == chapterUrl {
            position = index
        } else {
            position = urls.firstIndex(of: chapterUrl)
        }
        guard let position, position + 1 < urls.count else { return nil }
        return urls[position + 1]
    }
}
