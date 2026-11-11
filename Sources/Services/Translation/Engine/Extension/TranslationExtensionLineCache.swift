import Foundation

/// Cache **trong RAM** bản dịch theo từng dòng của tiện ích dịch, dùng chung cho Reader và TTS: hai bên lấy cùng một
/// chữ cho cùng một dòng nên vệt highlight TTS (offset trên chữ đang hiển thị) không lệch.
///
/// Khoá = tiện ích + dấu vân tay (phiên bản + config) + ngôn ngữ + model + kiểu + `source` + truyện + nội dung dòng
/// (hợp đồng: cache theo extension, book, languages, source, model, style, text). Chỉ lưu bản dịch khác rỗng; lỗi
/// không bao giờ vào cache. Tải lại chương / "Thử lại" gọi `invalidate(bookId:)` để gọi lại tiện ích.
final class TranslationExtensionLineCache: @unchecked Sendable {
    static let shared = TranslationExtensionLineCache()

    private let memo = TranslationMemo<String>(maxEntries: 8192, maxCost: 16 * 1024 * 1024)

    private init() {}

    struct Scope: Sendable {
        let context: TranslationExtensionContext
        let bookId: String
        let from: String
        let to: String
        let source: TranslationExtensionSource

        fileprivate var prefix: String {
            [context.packageId, context.fingerprint, from, to, context.model, context.style, source.rawValue, bookId]
                .joined(separator: "|")
        }
    }

    func lookup(_ text: String, scope: Scope) -> (value: String?, ticket: UInt64) {
        memo.lookup(key(text, scope: scope))
    }

    func insert(_ translated: String, for text: String, scope: Scope, ticket: UInt64) {
        guard !translated.isEmpty else { return }
        memo.insert(translated, key: key(text, scope: scope), bookId: scope.bookId,
                    cost: translated.utf16.count * 2, ticket: ticket)
    }

    /// `nil` = xoá hết.
    func invalidate(bookId: String? = nil) {
        memo.invalidate(bookId: bookId)
    }

    private func key(_ text: String, scope: Scope) -> String {
        scope.prefix + "|" + text.md5()
    }
}
