import Foundation

/// Kế hoạch xuất **một tập đã tải** (`VideoOfflineStore`): các file sẽ ghi, lập từ manifest + playlist trên máy **trước**
/// khi ghi byte nào — thiếu file / khoá hỏng / mã hoá lạ lộ ra sớm, và đếm được số file để `VideoExportWriter` chọn bố
/// cục (một file hay một thư mục).
///
/// - Manifest `.file` (mp4/mov/m4v, cả phim nhập từ file): chép nguyên file, giữ đuôi.
/// - Manifest `.hls`: `index.m3u8` là playlist con (một luồng), hoặc playlist gốc local trỏ `video.m3u8` + `audio.m3u8`
///   khi nguồn tách riêng luồng tiếng ⇒ thêm một file `… (tiếng)`.
/// - Phụ đề trong manifest: chép kèm, tên `<tên tập>.<ngôn ngữ>.<đuôi>` để trình phát ngoài tự nhận. Thiếu file phụ đề
///   thì bỏ qua (không làm hỏng tập).
struct VideoEpisodeExportPlan: Sendable {
    enum Source: Sendable {
        /// Chép nguyên file (video dạng file, phụ đề).
        case copy(URL)
        /// Nối đoạn HLS (`VideoHLSStreamWriter`).
        case hls(VideoHLSLocalStream)
    }

    struct Output: Sendable {
        let source: Source
        /// Gắn sau tên gốc của tập: "" (hình), " (tiếng)", ".vi" (phụ đề)…
        let nameSuffix: String
        let fileExtension: String
        let sourceBytes: Int64
    }

    /// Vị trí 1-based trong danh sách tập đã lên kế hoạch (tính cả tập chưa tải bị bỏ) — tiến độ tác vụ.
    let position: Int
    /// `StoredChapterSnapshot.index` — "Tập N" trong tên file là `episodeIndex + 1` (như sheet tuỳ chọn).
    let episodeIndex: Int
    let title: String
    /// `totalBytes` của manifest — kiểm dung lượng trống trước khi xuất.
    let manifestBytes: Int64
    let outputs: [Output]

    var sourceBytes: Int64 { outputs.reduce(0) { $0 + $1.sourceBytes } }

    var label: String { title.isEmpty ? "Tập \(episodeIndex + 1)" : title }

    static func make(
        bookId: String,
        episodeIndex: Int,
        title: String,
        position: Int,
        manifest: VideoEpisodeManifest
    ) throws -> VideoEpisodeExportPlan {
        let resolve: (String) -> URL? = {
            VideoOfflineStore.existingFileURL(bookId: bookId, episodeIndex: episodeIndex, file: $0)
        }
        var outputs: [Output] = []
        switch manifest.kind {
        case .file:
            guard let url = resolve(manifest.entryFile) else {
                throw VideoHLSLocalStream.StreamError.missingFile(manifest.entryFile)
            }
            outputs.append(Output(source: .copy(url), nameSuffix: "", fileExtension: safeExtension(url, fallback: "mp4"),
                                  sourceBytes: fileSize(url)))
        case .hls:
            let streams = try hlsStreams(entryFile: manifest.entryFile, resolve: resolve)
            outputs.append(Output(source: .hls(streams.video), nameSuffix: "",
                                  fileExtension: streams.video.outputExtension(isAudio: false),
                                  sourceBytes: streams.video.sourceBytes))
            if let audio = streams.audio {
                outputs.append(Output(source: .hls(audio), nameSuffix: " (tiếng)",
                                      fileExtension: audio.outputExtension(isAudio: true),
                                      sourceBytes: audio.sourceBytes))
            }
            let initCount = streams.video.distinctInitCount
            if initCount > 1 {
                AppLogger.shared.log("⚠️ [VideoExport] Tập \(episodeIndex) có \(initCount) init fMP4 khác nhau — file nối có thể không phát liền mạch")
            }
        }

        for subtitle in manifest.subtitles {
            guard let url = resolve(subtitle.file) else {
                AppLogger.shared.log("⚠️ [VideoExport] Tập \(episodeIndex) thiếu file phụ đề đã tải — bỏ qua phụ đề")
                continue
            }
            outputs.append(Output(source: .copy(url), nameSuffix: subtitleSuffix(subtitle),
                                  fileExtension: safeExtension(url, fallback: "srt"), sourceBytes: fileSize(url)))
        }

        return VideoEpisodeExportPlan(
            position: position,
            episodeIndex: episodeIndex,
            title: title,
            manifestBytes: manifest.totalBytes,
            outputs: outputs
        )
    }

    // MARK: - HLS

    private static func hlsStreams(
        entryFile: String,
        resolve: (String) -> URL?
    ) throws -> (video: VideoHLSLocalStream, audio: VideoHLSLocalStream?) {
        let entryText = try playlistText(entryFile, resolve: resolve)
        guard entryText.contains("#EXT-X-STREAM-INF") else {
            return (try VideoHLSLocalStream.parse(entryText, resolve: resolve), nil)
        }
        let references = VideoHLSLocalStream.masterReferences(entryText)
        guard let videoFile = references.video else { throw VideoHLSLocalStream.StreamError.empty }
        let video = try VideoHLSLocalStream.parse(try playlistText(videoFile, resolve: resolve), resolve: resolve)
        let audio = try references.audio.map {
            try VideoHLSLocalStream.parse(try playlistText($0, resolve: resolve), resolve: resolve)
        }
        return (video, audio)
    }

    private static func playlistText(_ file: String, resolve: (String) -> URL?) throws -> String {
        guard !file.contains("://"), let url = resolve(file) else {
            throw VideoHLSLocalStream.StreamError.missingFile((file as NSString).lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw VideoHLSLocalStream.StreamError.empty
        }
        return text
    }

    // MARK: - Tên file

    /// Đuôi chỉ gồm chữ/số (đuôi lạ ⇒ `fallback`).
    private static func safeExtension(_ url: URL, fallback: String) -> String {
        let raw = url.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        return raw.isEmpty || raw.count > 5 ? fallback : raw
    }

    /// `.vi` / `.Tiếng Việt`… — ngôn ngữ trước, nhãn sau; bỏ ký tự không hợp lệ trong tên file.
    private static func subtitleSuffix(_ subtitle: VideoEpisodeManifest.Subtitle) -> String {
        let raw = [subtitle.language, subtitle.label]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let cleaned = raw
            .replacingOccurrences(of: "[\\\\/:*?\"<>|.]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "" : "." + String(cleaned.prefix(30))
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}
