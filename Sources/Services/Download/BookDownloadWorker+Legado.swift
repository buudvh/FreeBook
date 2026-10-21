import Foundation

/// Nhánh nguồn Legado của `BookDownloadWorker`: lấy nội dung chương qua `SourceRuntime.chap` thay cho `JSExecutor`
/// giữ sẵn của tiện ích JS.
///
/// Vẫn **tuần tự** từng chương (caller gọi lần lượt, đợi xong mới gọi chương sau) và huỷ được: huỷ task tải truyền
/// xuống engine qua cancellation của Swift; `cancel()` bật cờ để chương đang chờ không trả kết quả về nữa.
extension BookDownloadWorker {
    func fetchLegadoChapterContent(url: String, host: String?, context: SourceRuntimeContext?) async throws -> String {
        let content = try await SourceRuntime.shared.chap(
            localPath: localPath,
            downloadUrl: downloadUrl,
            url: url,
            host: host,
            configJson: configJson,
            context: context
        )
        try Task.checkCancellation()
        guard !isCancelled else { throw CancellationError() }
        return content
    }
}
