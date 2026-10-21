import Foundation

/// Lấy nội dung chương từ nguồn — cổng chung của Reader, TTS và tải một chương. Tách khỏi
/// `ChapterContentRepository.swift` (file legacy đang chạm baseline dòng).
///
/// Đi qua `SourceRuntime`: tiện ích JS nhận nguyên tham số như trước, nguồn Legado chạy engine Legado với ngữ cảnh
/// sách/chương lấy từ `request` (`bookId` là id sách thật — nguồn Legado đọc trạng thái đã ghi theo id này).
///
/// `request.isInteractive` (chỉ Reader bật, cho chương **đang mở**): nguồn Legado được trình bày trình duyệt / ô mã xác
/// minh, và hạn chờ của **nguồn Legado** nới lên `interactiveTimeoutNanoseconds` — người dùng có thể đang vượt
/// Cloudflare trong `startBrowserAwait` (engine tự giới hạn 600 s; request mạng của engine có hạn riêng); hạn 30 s sẽ huỷ
/// phiên và đóng trình duyệt dưới tay người dùng. Tiện ích JS giữ hạn 30 s.
extension ChapterContentRepository {
    static let interactiveTimeoutNanoseconds: UInt64 = 620_000_000_000

    func fetchFromExtension(
        request: ChapterContentRequest,
        extensionInfo: TTSExtensionInfo
    ) async throws -> String {
        let context = SourceRuntimeContext(
            bookId: request.bookId,
            bookUrl: request.bookMetadata?.detailUrl,
            bookName: request.bookMetadata?.title,
            bookAuthor: request.bookMetadata?.author,
            chapterTitle: request.title,
            chapterIndex: request.chapterIndex,
            isInteractive: request.isInteractive
        )
        let waitsForUser = request.isInteractive && SourceRuntime.shared.isLegado(localPath: extensionInfo.localPath)
        let timeout: UInt64 = waitsForUser ? Self.interactiveTimeoutNanoseconds : 30_000_000_000
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await SourceRuntime.shared.chap(
                    localPath: extensionInfo.localPath,
                    downloadUrl: extensionInfo.downloadUrl,
                    url: request.url,
                    host: ExtensionHostResolver.chapterHost(chapterHost: request.host, bookHost: request.bookMetadata?.host, packageId: extensionInfo.packageId),
                    configJson: extensionInfo.configJson ?? "{}",
                    context: context
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw ChapterContentRepositoryError.timedOut
            }
            guard let result = try await group.next() else {
                throw ChapterContentRepositoryError.emptyContent
            }
            group.cancelAll()
            return result
        }
    }
}
