import Foundation

/// Kiểm một tiện ích có thay được nguồn đã gỡ của truyện không: chạy chi tiết + toàn bộ mục lục của tiện ích mới trên
/// link chi tiết cũ (cùng lời gọi như `BookSourceChangeCoordinator.fetchSource`), rồi so link chương đã lưu với mục lục
/// mới.
///
/// Gắn lại nguồn giữ nguyên mục lục đã lưu, mà `ChapterStore` khớp chương theo **URL** khi làm mới mục lục. Tiện ích mới
/// trả link chương khác dạng (miền mobile, API…) thì làm mới mục lục sẽ nhân đôi chương, còn chương chưa tải mở bằng
/// link cũ có thể hỏng ⇒ chỉ nhận khi 3 chương mẫu (đầu, đang đọc, cuối) đều có trong mục lục mới.
enum SourceRebindValidator {
    struct Verdict: Sendable {
        let isCompatible: Bool
        /// Host sách ở nguồn mới: host chi tiết → `source` của tiện ích.
        let bookHost: String
    }

    static func check(
        bookId: String,
        title: String,
        detailUrl: String,
        currentChapterIndex: Int,
        oldHost: String?,
        ext: Extension,
        isInteractive: Bool
    ) async throws -> Verdict {
        let context = SourceRuntimeContext(bookId: bookId, bookUrl: detailUrl, bookName: title, isInteractive: isInteractive)
        let detail = try await SourceRuntime.shared.detail(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            url: detailUrl,
            host: ext.sourceUrl,
            configJson: ext.configJson,
            context: context
        )
        let bookHost = ExtensionHostResolver.nonEmpty(detail.host) ?? ext.sourceUrl
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let toc = try await BookDetailLoader.shared.fetchFullTOC(snapshot: snapshot, url: detailUrl, host: bookHost, context: context).chapters
        let stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId).filter { !$0.isSection }
        guard !stored.isEmpty else { return Verdict(isCompatible: true, bookHost: bookHost) }

        var newKeys = Set<String>()
        for chapter in toc {
            newKeys.formUnion(keys(url: chapter.url, host: ExtensionHostResolver.nonEmpty(chapter.host) ?? bookHost))
        }
        let current = stored.first(where: { $0.index == currentChapterIndex })
        let samples = [stored.first, current, stored.last].compactMap { $0 }
        let isCompatible = samples.allSatisfy { chapter in
            let host = ExtensionHostResolver.nonEmpty(chapter.host) ?? oldHost ?? ""
            return !keys(url: chapter.url, host: host).isDisjoint(with: newKeys)
        }
        return Verdict(isCompatible: isCompatible, bookHost: bookHost)
    }

    /// Link nguyên văn (đã trim) + bản tuyệt đối rút gọn: ghép host khi link tương đối, bỏ scheme, `www.` và `/` cuối,
    /// host chữ thường. Hai tiện ích cùng trang có thể trả một bên link tuyệt đối, một bên tương đối, hoặc khác `http`/`https`.
    static func keys(url: String, host: String) -> Set<String> {
        let raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        var result: Set<String> = [raw]
        let base = URL(string: host.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let absolute = URL(string: raw, relativeTo: base)?.absoluteURL,
              let components = URLComponents(url: absolute, resolvingAgainstBaseURL: false),
              var hostName = components.host?.lowercased(), !hostName.isEmpty else {
            return result
        }
        if hostName.hasPrefix("www.") { hostName.removeFirst(4) }
        var text = hostName
        if let port = components.port { text += ":\(port)" }
        text += components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty { text += "?" + query }
        while text.hasSuffix("/") { text.removeLast() }
        result.insert(text)
        return result
    }
}
