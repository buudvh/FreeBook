import Foundation

/// Tải một tập HLS vào thư mục tập (`VideoOfflineStore`): playlist → biến thể theo `VideoDownloadQuality` + luồng tiếng
/// tách riêng của nhóm `AUDIO` → lần lượt từng khoá / init / đoạn → playlist local (ghi sau media).
///
/// - Tuần tự, một tài nguyên tại một thời điểm (chủ ý — tránh bị nguồn chặn).
/// - Tài nguyên ghi atomic nên file có mặt = đã tải xong; lượt sau cùng chữ ký nguồn (`partial.json`) bỏ qua file đã có.
/// - URI `fbhls://` (playlist con phục vụ kèm của `VideoAudioRenditionComposer`) đọc từ `subPlaylists`, không gọi mạng.
/// - Từ chối luồng trực tiếp và DRM (`VideoHLSOfflinePlanner.PlanError`).
struct VideoHLSDownloader {
    enum Source {
        case remote(URL)
        case text(String, baseURL: URL?)
    }

    struct Outcome {
        let entryFile: String
        let totalBytes: Int64
        let segmentCount: Int
        let qualityLabel: String
    }

    static let entryFileName = "index.m3u8"

    let client: VideoOfflineHTTPClient
    let headers: [String: String]
    let subPlaylists: [String: String]
    let quality: VideoDownloadQuality
    /// `(phần đã xong 0…1, số byte đã có)` — gọi sau mỗi tài nguyên, từ thread nền.
    let progress: (Double, Int64) -> Void

    func download(_ source: Source, into directory: URL) async throws -> Outcome {
        let top = try await loadPlaylist(source)
        guard VideoHLSOfflinePlanner.isPlaylist(top.text) else { throw VideoHLSOfflinePlanner.PlanError.notPlaylist }
        if let method = VideoHLSOfflinePlanner.sessionKeyMethod(in: top.text) {
            throw VideoHLSOfflinePlanner.PlanError.unsupportedEncryption(method)
        }

        var plans: [VideoHLSOfflinePlanner.MediaPlan] = []
        var playlists: [(name: String, text: String)] = []
        var qualityLabel = ""

        if VideoHLSOfflinePlanner.isMaster(top.text) {
            let master = VideoHLSOfflinePlanner.parseMaster(top.text, baseURL: top.baseURL)
            guard let variant = quality.pick(master.variants) else { throw VideoHLSOfflinePlanner.PlanError.empty }
            qualityLabel = variant.label
            AppLogger.shared.log("📥 [VideoOffline] Playlist gốc \(master.variants.count) mức, chọn «\(variant.label.isEmpty ? "-" : variant.label)» (\(quality.title))")

            let video = try await loadPlaylist(uri: variant.uri, parentBase: top.baseURL)
            guard !VideoHLSOfflinePlanner.isMaster(video.text) else { throw VideoHLSOfflinePlanner.PlanError.notPlaylist }
            let videoPlan = try VideoHLSOfflinePlanner.planMedia(video.text, baseURL: video.baseURL, filePrefix: "v")
            plans.append(videoPlan)
            playlists.append(("video.m3u8", videoPlan.playlist))

            var audioFile: String?
            let audio = master.audioRendition(for: variant)
            if let audio, let uri = audio.uri {
                let audioPlaylist = try await loadPlaylist(uri: uri, parentBase: top.baseURL)
                let audioPlan = try VideoHLSOfflinePlanner.planMedia(audioPlaylist.text, baseURL: audioPlaylist.baseURL, filePrefix: "a")
                plans.append(audioPlan)
                playlists.append(("audio.m3u8", audioPlan.playlist))
                audioFile = "audio.m3u8"
                AppLogger.shared.log("📥 [VideoOffline] Kèm luồng tiếng riêng «\(audio.name ?? "-")» (\(audioPlan.segmentCount) đoạn)")
            }
            let localMaster = VideoHLSOfflinePlanner.masterPlaylist(
                variant: variant,
                audio: audioFile == nil ? nil : audio,
                videoFile: "video.m3u8",
                audioFile: audioFile
            )
            playlists.append((Self.entryFileName, localMaster))
        } else {
            let plan = try VideoHLSOfflinePlanner.planMedia(top.text, baseURL: top.baseURL, filePrefix: "v")
            plans.append(plan)
            playlists.append((Self.entryFileName, plan.playlist))
        }

        let signature = ("hls\n" + plans.map(\.signatureSource).joined(separator: "\n--\n")).sha256()
        let resumed = try VideoOfflineStore.beginPartial(in: directory, signature: signature)
        let resources = plans.flatMap(\.resources)
        let segmentCount = plans.reduce(0) { $0 + $1.segmentCount }
        AppLogger.shared.log("📥 [VideoOffline] HLS \(segmentCount) đoạn, \(resources.count) tài nguyên\(resumed ? " (tải tiếp bản dở)" : "")")

        var totalBytes: Int64 = 0
        for (offset, resource) in resources.enumerated() {
            try Task.checkCancellation()
            let target = directory.appendingPathComponent(resource.fileName, isDirectory: false)
            if resumed, let existing = Self.fileSize(target), existing > 0 {
                totalBytes += existing
            } else {
                let data: Data
                do {
                    data = try await client.data(from: resource.url, headers: headers, range: resource.byteRange)
                } catch {
                    if !(error is CancellationError) {
                        AppLogger.shared.log("❌ [VideoOffline] Lỗi tải \(Self.roleLabel(resource.role)) \(resource.fileName) (\(VideoSourceResolution.redact(resource.url))): \(error.localizedDescription)")
                    }
                    throw error
                }
                if resource.role == .key, data.count != 16 {
                    AppLogger.shared.log("⚠️ [VideoOffline] Khoá AES-128 \(resource.fileName) dài \(data.count) byte (thường là 16)")
                }
                try VideoOfflineStore.writeAtomic(data, to: target)
                totalBytes += Int64(data.count)
            }
            progress(Double(offset + 1) / Double(max(1, resources.count)), totalBytes)
        }

        for playlist in playlists {
            let data = Data(playlist.text.utf8)
            try VideoOfflineStore.writeAtomic(data, to: directory.appendingPathComponent(playlist.name, isDirectory: false))
            totalBytes += Int64(data.count)
        }
        return Outcome(entryFile: Self.entryFileName, totalBytes: totalBytes, segmentCount: segmentCount, qualityLabel: qualityLabel)
    }

    // MARK: - Playlist

    private func loadPlaylist(_ source: Source) async throws -> (text: String, baseURL: URL?) {
        switch source {
        case .remote(let url):
            let fetched = try await client.text(from: url, headers: headers)
            return (fetched.text, fetched.finalURL)
        case .text(let text, let baseURL):
            return (VideoDataURI.decode(text)?.text ?? text, baseURL)
        }
    }

    /// URI biến thể/rendition: `fbhls://` ⇒ `subPlaylists`; `data:` ⇒ giải mã; còn lại tải qua mạng (base = URL cuối).
    private func loadPlaylist(uri: String, parentBase: URL?) async throws -> (text: String, baseURL: URL?) {
        if let url = URL(string: uri), url.scheme?.lowercased() == HLSPlaylistResourceLoader.scheme {
            guard let text = subPlaylists[uri] else { throw VideoHLSOfflinePlanner.PlanError.notPlaylist }
            return (text, parentBase)
        }
        if VideoDataURI.isDataURI(uri) {
            guard let decoded = VideoDataURI.decode(uri) else { throw VideoHLSOfflinePlanner.PlanError.notPlaylist }
            return (decoded.text, parentBase)
        }
        guard let url = URL(string: uri), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw VideoHLSOfflinePlanner.PlanError.notPlaylist
        }
        let fetched = try await client.text(from: url, headers: headers)
        return (fetched.text, fetched.finalURL)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private static func roleLabel(_ role: VideoHLSOfflinePlanner.Resource.Role) -> String {
        switch role {
        case .segment: return "đoạn"
        case .initSegment: return "init"
        case .key: return "khoá"
        }
    }
}
