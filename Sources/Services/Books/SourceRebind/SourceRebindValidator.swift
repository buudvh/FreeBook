import Foundation

/// Kiểm một tiện ích có thay được nguồn đã gỡ của truyện không: chạy chi tiết + toàn bộ mục lục của tiện ích mới trên
/// link chi tiết cũ (cùng lời gọi như `BookSourceChangeCoordinator.fetchSource`), rồi so 3 chương mẫu đã lưu (đầu, đang
/// đọc, cuối) với mục lục mới.
///
/// - `.sameLinks`: link chương mẫu đều có trong mục lục mới ⇒ gắn lại nguồn tại chỗ được (`ChapterStore` khớp chương
///   theo URL khi làm mới mục lục, nên link phải giữ nguyên).
/// - `.samePositions`: link khác dạng nhưng tên chương ở đúng vị trí đó trùng nhau — hai tiện ích cùng trang dựng link
///   chương khác nhau (vd qimao: `api-bc.wtzw.com/chapter?chapterId=…` với `www.qimao.com/shuku/<id>-<chương>/`). Gắn tại
///   chỗ thì chương chưa tải mở bằng link cũ hỏng và làm mới mục lục nhân đôi chương ⇒ phải đi luồng Đổi nguồn (mục lục
///   mới, chép chương đã tải theo vị trí).
/// - `.different`: lệch cả link lẫn tên ⇒ không tự chuyển.
enum SourceRebindValidator {
    enum Match: Sendable {
        case sameLinks
        case samePositions
        case different
    }

    struct Verdict: Sendable {
        let match: Match
        /// Host sách ở nguồn mới: host chi tiết → `source` của tiện ích.
        let bookHost: String
        /// Chương mẫu đầu tiên lệch (link + tên, cũ và mới) và số chương hai bên — chỉ để ghi log.
        let mismatchSummary: String
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
        // Dòng tiêu đề nhóm tập (truyện tranh/video) không có link chương; `index` vẫn là vị trí trong mục lục.
        let stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId).filter { !$0.isSection }
        guard !stored.isEmpty else { return Verdict(match: .sameLinks, bookHost: bookHost, mismatchSummary: "") }

        var newKeys = Set<String>()
        for chapter in toc {
            newKeys.formUnion(keys(url: chapter.url, host: ExtensionHostResolver.nonEmpty(chapter.host) ?? bookHost))
        }
        let current = stored.first(where: { $0.index == currentChapterIndex })
        let samples = [stored.first, current, stored.last].compactMap { $0 }
        let linkMismatch = samples.first { chapter in
            let host = ExtensionHostResolver.nonEmpty(chapter.host) ?? oldHost ?? ""
            return keys(url: chapter.url, host: host).isDisjoint(with: newKeys)
        }
        guard let linkMismatch else { return Verdict(match: .sameLinks, bookHost: bookHost, mismatchSummary: "") }

        let titleMismatch = samples.first { chapter in
            !toc.indices.contains(chapter.index) || normalizedTitle(toc[chapter.index].name) != normalizedTitle(chapter.title)
        }
        let probe = titleMismatch ?? linkMismatch
        let newChapter = toc.indices.contains(probe.index) ? toc[probe.index] : nil
        let summary = "chương \(probe.index + 1): link cũ \(probe.url) | mới \(newChapter?.url ?? "—"); "
            + "tên cũ \"\(probe.title)\" | mới \"\(newChapter?.name ?? "—")\"; \(stored.count)/\(toc.count) chương"
        return Verdict(match: titleMismatch == nil ? .samePositions : .different, bookHost: bookHost, mismatchSummary: summary)
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

    /// Tên chương để so vị trí: bỏ khoảng trắng hai đầu, gộp khoảng trắng giữa, chữ thường (tiện ích này trim, tiện
    /// ích kia giữ nguyên tên của API).
    static func normalizedTitle(_ title: String) -> String {
        title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }
}
