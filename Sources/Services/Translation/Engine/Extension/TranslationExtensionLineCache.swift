import Foundation

/// Cache **trong RAM** bản dịch theo từng dòng của tiện ích dịch, dùng chung cho Reader và TTS: hai bên lấy cùng một
/// chữ cho cùng một dòng nên vệt highlight TTS (offset trên chữ đang hiển thị) không lệch.
///
/// - Khoá = tiện ích + dấu vân tay (phiên bản + config) + ngôn ngữ + model + kiểu + `source` + truyện + nội dung dòng
///   (hợp đồng: cache theo extension, book, languages, source, model, style, text). Chỉ lưu bản dịch khác rỗng.
/// - **Lỗi gần đây** (`failureLifetime`) cũng được nhớ, riêng: dòng vừa lỗi ở Reader thì TTS cũng lùi QT (không gọi lại
///   rồi ra chữ khác Reader đang hiện), và đang bị giới hạn lượt thì không gọi dồn. "Thử lại" / tải lại chương gọi
///   `invalidate(bookId:)` xoá cả hai.
/// - Thế hệ theo **từng truyện**: xoá cache của truyện A không làm rơi lượt ghi đang chạy của truyện B.
final class TranslationExtensionLineCache: @unchecked Sendable {
    static let shared = TranslationExtensionLineCache()

    /// Lỗi được nhớ bao lâu (giây).
    static let failureLifetime: TimeInterval = 90
    private static let maxFailures = 4096

    struct Scope: Sendable {
        let context: TranslationExtensionContext
        let bookId: String
        let from: String
        let to: String
        let source: TranslationExtensionSource

        var prefix: String {
            [context.packageId, context.fingerprint, from, to, context.model, context.style, source.rawValue, bookId]
                .joined(separator: "|")
        }
    }

    /// Thế hệ lúc tra; ghi chỉ được nhận khi thế hệ của truyện chưa đổi.
    struct Ticket: Equatable, Sendable {
        fileprivate let global: UInt64
        fileprivate let book: UInt64
    }

    private struct Failure {
        let message: String
        let bookId: String
        let expiry: Date
    }

    private let memo = TranslationMemo<String>(maxEntries: 8192, maxCost: 16 * 1024 * 1024)
    private let lock = NSLock()
    private var globalGeneration: UInt64 = 0
    private var bookGenerations: [String: UInt64] = [:]
    private var failures: [String: Failure] = [:]

    private init() {}

    func lookup(_ text: String, scope: Scope) -> (value: String?, ticket: Ticket) {
        let ticket = currentTicket(bookId: scope.bookId)
        return (memo.lookup(key(text, scope: scope)).value, ticket)
    }

    func ticket(bookId: String) -> Ticket {
        currentTicket(bookId: bookId)
    }

    func insert(_ translated: String, for text: String, scope: Scope, ticket: Ticket) {
        guard !translated.isEmpty, currentTicket(bookId: scope.bookId) == ticket else { return }
        let cacheKey = key(text, scope: scope)
        lock.lock()
        failures[cacheKey] = nil
        lock.unlock()
        let memoTicket = memo.lookup(cacheKey).ticket
        memo.insert(translated, key: cacheKey, bookId: scope.bookId, cost: translated.utf16.count * 2, ticket: memoTicket)
    }

    /// Lỗi còn hạn của dòng; `nil` = chưa lỗi / đã hết hạn.
    func recentFailure(for text: String, scope: Scope) -> String? {
        let cacheKey = key(text, scope: scope)
        lock.lock()
        defer { lock.unlock() }
        guard let failure = failures[cacheKey] else { return nil }
        guard failure.expiry > Date() else {
            failures[cacheKey] = nil
            return nil
        }
        return failure.message
    }

    func recordFailure(_ message: String, for text: String, scope: Scope, ticket: Ticket) {
        let cacheKey = key(text, scope: scope)
        lock.lock()
        defer { lock.unlock() }
        guard ticketLocked(bookId: scope.bookId) == ticket else { return }
        if failures.count >= Self.maxFailures {
            let now = Date()
            failures = failures.filter { $0.value.expiry > now }
            if failures.count >= Self.maxFailures { failures.removeAll() }
        }
        failures[cacheKey] = Failure(message: message, bookId: scope.bookId,
                                     expiry: Date().addingTimeInterval(Self.failureLifetime))
    }

    /// `nil` = xoá hết. Xoá cả bản dịch lẫn lỗi đã nhớ.
    func invalidate(bookId: String? = nil) {
        lock.lock()
        if let bookId {
            bookGenerations[bookId, default: 0] &+= 1
            failures = failures.filter { $0.value.bookId != bookId }
        } else {
            globalGeneration &+= 1
            failures.removeAll()
        }
        lock.unlock()
        memo.invalidate(bookId: bookId)
    }

    // MARK: - Nội bộ

    private func currentTicket(bookId: String) -> Ticket {
        lock.lock()
        defer { lock.unlock() }
        return ticketLocked(bookId: bookId)
    }

    /// Gọi trong lock.
    private func ticketLocked(bookId: String) -> Ticket {
        Ticket(global: globalGeneration, book: bookGenerations[bookId] ?? 0)
    }

    private func key(_ text: String, scope: Scope) -> String {
        scope.prefix + "|" + text.md5()
    }
}
