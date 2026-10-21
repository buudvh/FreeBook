import Foundation

/// Hàm media của facade, **cùng nhãn tham số** với `ExtensionManager+Media` (thêm `context` cuối, mặc định `nil`).
///
/// - Tiện ích JS ⇒ chuyển **nguyên tham số** sang `ExtensionManager.shared` (`context` bị bỏ qua).
/// - Nguồn Legado ⇒ luồng tranh (spec §8) / video (spec §9) của `LegadoSourceRuntime`. Media không bao giờ đi qua
///   pipeline chữ (`chap`, `ChapterContentRepository`, `cleanHTML`, JunkFilter, dịch, TTS).
extension SourceRuntime {
    /// Tên "script" giả gắn vào `ComicPageSource.script` khi nguồn Legado có `imageDecode`: `ComicImageScriptRunner` thấy
    /// tên này thì gọi `legadoDecodedImage` thay vì tìm file JS trong thư mục tiện ích.
    public static let legadoImageDecodeScriptName = "__legado_image_decode__"

    /// Danh sách ảnh của một chương truyện tranh.
    public func comicPages(
        localPath: String,
        downloadUrl: String = "",
        url: String,
        host: String? = nil,
        configJson: String = "{}",
        context: SourceRuntimeContext? = nil
    ) async throws -> [ComicPageSource] {
        if let target = try legadoTarget(localPath) {
            return try await legadoCall("comicPages", url) {
                try await LegadoSourceRuntime.comicPages(target, chapterUrl: url, context: context)
            }
        }
        return try await ExtensionManager.shared.comicPages(localPath: localPath, downloadUrl: downloadUrl, url: url, host: host, configJson: configJson)
    }

    /// Danh sách server phát của một tập. Nguồn Legado: đúng một server, `data` mang URL tập + ngữ cảnh (không mạng).
    public func videoServers(
        localPath: String,
        downloadUrl: String = "",
        url: String,
        host: String? = nil,
        configJson: String = "{}",
        context: SourceRuntimeContext? = nil
    ) async throws -> [VideoServer] {
        if let target = try legadoTarget(localPath) {
            return LegadoSourceRuntime.videoServers(target, chapterUrl: url, context: context)
        }
        return try await ExtensionManager.shared.videoServers(localPath: localPath, downloadUrl: downloadUrl, url: url, host: host, configJson: configJson)
    }

    /// Nguồn phát của một server. Nguồn Legado: giải lại nguồn phát của tập **mỗi lần gọi** (URL phát có chữ ký hết hạn).
    /// Log chỉ ghi độ dài `data`.
    public func videoTrack(
        localPath: String,
        downloadUrl: String = "",
        data: String,
        configJson: String = "{}"
    ) async throws -> VideoTrack {
        if let target = try legadoTarget(localPath) {
            guard let payload = LegadoVideoServerPayload.decode(data) else {
                throw LegadoRuntimeError.invalidMediaData
            }
            return try await legadoCall("videoTrack", "data: \(data.utf16.count) ký tự") {
                try await LegadoSourceRuntime.videoTrack(target, payload: payload)
            }
        }
        return try await ExtensionManager.shared.videoTrack(localPath: localPath, downloadUrl: downloadUrl, data: data, configJson: configJson)
    }

    /// Byte ảnh (đã chạy `imageDecode`) của một trang tranh nguồn Legado — `link` là `ComicPageSource.link` nguyên văn.
    /// Chỉ ghi log khi lỗi, và chỉ tên miền (URL ảnh có thể mang token).
    func legadoDecodedImage(localPath: String, link: String) async throws -> Data {
        guard let target = try legadoTarget(localPath) else {
            throw LegadoRuntimeError.invalidMediaData
        }
        do {
            return try await LegadoSourceRuntime.decodedImage(target, link: link)
        } catch {
            if !(error is CancellationError) {
                let host = LegadoURLResolver.host(of: link) ?? "?"
                AppLogger.shared.log("❌ [SourceRuntime][Legado] imageDecode \(host): \(LegadoCorpusErrorClassifier.redact(error.localizedDescription))")
            }
            throw error
        }
    }
}
