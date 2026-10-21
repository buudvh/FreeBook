import Foundation

/// `VideoServer.data` của nguồn Legado: URL tập (`ChapterResult.url` nguyên văn) + ngữ cảnh truyện/tập. Chuỗi JSON
/// **opaque** đối với trình phát — chỉ `SourceRuntime.videoTrack` của nguồn Legado đọc lại.
///
/// Nguồn Legado không có cấu trúc server/tuyến (spec §9.2): mỗi tập đúng **một** server. Nguồn phát được giải ở
/// `videoTrack` **mỗi lần** (kể cả Thử lại / chọn lại server), không giải trước ở `videoServers`: URL phát hay có chữ ký
/// hết hạn (`?sign=…`, spec §9.3).
struct LegadoVideoServerPayload: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    let chapterUrl: String
    let bookId: String?
    let bookUrl: String?
    let bookName: String?
    let bookAuthor: String?
    let chapterTitle: String?
    let chapterIndex: Int?

    init(chapterUrl: String, context: SourceRuntimeContext?) {
        self.version = Self.currentVersion
        self.chapterUrl = chapterUrl
        self.bookId = context?.bookId
        self.bookUrl = context?.bookUrl
        self.bookName = context?.bookName
        self.bookAuthor = context?.bookAuthor
        self.chapterTitle = context?.chapterTitle
        self.chapterIndex = context?.chapterIndex
    }

    var context: SourceRuntimeContext {
        SourceRuntimeContext(
            bookId: bookId,
            bookUrl: bookUrl,
            bookName: bookName,
            bookAuthor: bookAuthor,
            chapterTitle: chapterTitle,
            chapterIndex: chapterIndex
        )
    }

    /// Chuỗi JSON (khoá sắp xếp, ổn định).
    var encoded: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// `nil` khi `data` không phải payload của nguồn Legado (hoặc phiên bản lạ).
    static func decode(_ data: String) -> LegadoVideoServerPayload? {
        guard let bytes = data.data(using: .utf8),
              let payload = try? JSONDecoder().decode(LegadoVideoServerPayload.self, from: bytes),
              payload.version == currentVersion,
              !payload.chapterUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return payload
    }
}
