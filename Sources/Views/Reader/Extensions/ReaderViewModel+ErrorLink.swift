import Foundation

extension ReaderViewModel {
    /// Link "Mở link lỗi" cho chương `index` vừa tải lỗi — luôn là **chương đích** của lượt điều hướng lỗi (chuyển chương
    /// lỗi thì `displayedChapterIndex` vẫn là chương cũ). Thứ tự: `fetch` lỗi / gần nhất của lượt chạy script (`error`) →
    /// URL chương đó (tương đối thì ghép theo host chương → host sách → `sourceUrl`, như lúc tải) → URL chi tiết truyện.
    /// Tra URL giống `loadChapterContentFromExtension`: sách đã lưu đọc `ChapterStore`, sách online đọc `onlineChapters`.
    func chapterErrorLink(at index: Int, error: Error?) async -> SourceErrorLink? {
        var chapterURL: String?
        var chapterHost: String?
        if localBook != nil {
            if let chapter = await fetchChapterSnapshot(at: index) {
                chapterURL = chapter.url
                chapterHost = ExtensionHostResolver.chapterHost(
                    chapterHost: chapter.host, bookHost: localBook?.host, packageId: extensionPackageId
                )
            }
        } else if onlineChapters.indices.contains(index) {
            let chapter = onlineChapters[index]
            chapterURL = chapter.url
            chapterHost = ExtensionHostResolver.chapterHost(
                chapterHost: chapter.host, bookHost: onlineChapters.first?.host, packageId: extensionPackageId
            )
        }
        let detailURL = localBook?.detailUrl ?? bookDetailUrl
        return SourceErrorLink.resolve(from: error, fallbacks: [chapterURL, detailURL], host: chapterHost)
    }
}
