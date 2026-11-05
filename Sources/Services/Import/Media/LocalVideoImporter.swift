import AVFoundation
import Foundation
import UIKit

/// Nhập phim từ file video (MP4/MOV/M4V): một hay nhiều file gộp thành **một** phim, tập xếp theo tên file tự nhiên
/// (người dùng chốt).
///
/// - `prepare` (ngoài main): **chuyển** các bản chép của bộ chọn file vào `LocalMediaImportWorkspace` — không chép thêm
///   bản thứ hai của file video lớn.
/// - `commit` (ngoài main, sau khi hàng `Book` đã tạo): chuyển từng file vào `VideoOfflineStore`
///   (`importEpisodeFile` kiểm dung lượng trống khi buộc phải chép), manifest `.file` ghi sau cùng với
///   `episodeUrl` = đúng URL tập trong mục lục (`VideoPlaybackSession+Offline` so bằng `==`), rồi
///   `ChapterStore.replaceFullTOC`. Trả ảnh bìa = một khung hình của tập đầu.
/// - Phim nhập không xuất ra file được và không có server trực tuyến (`LocalMediaPackage`).
enum LocalVideoImporter {
    // MARK: - Chuẩn bị

    static func prepare(pickedURLs: [URL]) throws -> LocalVideoImportPlan {
        let workDirectory = try LocalMediaImportWorkspace.make()
        do {
            let sorted = pickedURLs.sorted {
                LocalMediaImportRoute.naturalLess($0.lastPathComponent, $1.lastPathComponent)
            }
            var episodes: [LocalVideoImportPlan.Episode] = []
            episodes.reserveCapacity(sorted.count)
            for (offset, picked) in sorted.enumerated() {
                let fileName = picked.lastPathComponent
                let ext = picked.pathExtension.lowercased()
                let adopted = try LocalMediaImportWorkspace.adopt(picked, into: workDirectory, as: "\(offset).\(ext)")
                episodes.append(LocalVideoImportPlan.Episode(
                    id: offset,
                    fileName: fileName,
                    title: (fileName as NSString).deletingPathExtension,
                    fileURL: adopted,
                    bytes: LocalMediaImportWorkspace.fileSize(adopted)
                ))
            }
            AppLogger.shared.log("📥 [VideoImport] Nhận \(episodes.count) file video")
            return LocalVideoImportPlan(
                defaultTitle: defaultTitle(for: episodes.map(\.title)),
                workDirectory: workDirectory,
                episodes: episodes
            )
        } catch {
            LocalMediaImportWorkspace.discard(workDirectory)
            LocalMediaImportRoute.discardPickedCopies(pickedURLs)
            throw error
        }
    }

    /// Đuôi video app không phát được (AVPlayer) — có trong ZIP thì bỏ qua và báo số lượng trên sheet.
    private static let unsupportedVideoExtensions: Set<String> = [
        "mkv", "avi", "webm", "flv", "wmv", "ts", "3gp", "mpg", "mpeg", "rmvb", "rm", "vob"
    ]

    enum ArchiveError: LocalizedError {
        case unsupportedVideosOnly(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedVideosOnly(let formats):
                return "File nén chỉ có video \(formats) — app chỉ phát được MP4/MOV/M4V."
            }
        }
    }

    /// Phim từ thư mục đã giải nén của một file ZIP (`LocalMediaArchiveImporter`, 1.3.731). `nil` ⇒ không có video nào
    /// (caller nhập thành truyện tranh). Mọi file MP4/MOV/M4V ở mọi cấp thư mục là một tập, xếp theo **đường dẫn** tên tự
    /// nhiên ("Tập 2" trước "Tập 10"); tên tập = tên file bỏ đuôi; tên phim mặc định = tên file ZIP bỏ đuôi. File đã nằm
    /// trong thư mục làm việc nên `commit` chuyển thẳng vào kho, không chép thêm.
    ///
    /// Cùng lớp an toàn với bước quét ảnh của truyện tranh: có symlink ⇒ huỷ cả lượt; bỏ file ẩn, `__MACOSX/` và file
    /// mà đường dẫn thật nằm ngoài thư mục giải nén.
    static func plan(fromExtracted extracted: URL, workDirectory: URL, archiveName: String) throws -> LocalVideoImportPlan? {
        let root = extracted.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return nil }
        var videos: [(relativePath: String, url: URL)] = []
        var skippedFormats: [String: Int] = [:]
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if name.hasPrefix(".") || name == "__MACOSX" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isSymbolicLink == true {
                AppLogger.shared.log("❌ [VideoImport] File nén chứa symlink (\(name)) — huỷ lượt nhập")
                throw LocalComicImporter.ImportError.unreadableArchive("file nén chứa liên kết tượng trưng")
            }
            guard values?.isRegularFile == true, !name.hasPrefix(".") else { continue }
            let ext = url.pathExtension.lowercased()
            if unsupportedVideoExtensions.contains(ext) {
                skippedFormats[ext.uppercased(), default: 0] += 1
                continue
            }
            guard LocalMediaImportRoute.videoExtensions.contains(ext) else { continue }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(rootPath + "/") else {
                AppLogger.shared.log("⚠️ [VideoImport] Bỏ qua file nằm ngoài thư mục giải nén: \(name)")
                continue
            }
            videos.append((String(resolved.path.dropFirst(rootPath.count + 1)), resolved))
        }

        let skippedCount = skippedFormats.values.reduce(0, +)
        guard !videos.isEmpty else {
            guard skippedCount > 0 else { return nil }
            throw ArchiveError.unsupportedVideosOnly(skippedFormats.keys.sorted().joined(separator: "/"))
        }
        videos.sort { pathLess($0.relativePath, $1.relativePath) }
        let episodes = videos.enumerated().map { (offset, video) -> LocalVideoImportPlan.Episode in
            let fileName = video.url.lastPathComponent
            return LocalVideoImportPlan.Episode(
                id: offset,
                fileName: fileName,
                title: (fileName as NSString).deletingPathExtension,
                fileURL: video.url,
                bytes: LocalMediaImportWorkspace.fileSize(video.url)
            )
        }
        let defaultTitle = (archiveName as NSString).deletingPathExtension
        AppLogger.shared.log("📥 [VideoImport] \(archiveName): \(episodes.count) tập, bỏ qua \(skippedCount) file không hỗ trợ")
        return LocalVideoImportPlan(
            defaultTitle: defaultTitle.isEmpty ? self.defaultTitle(for: episodes.map(\.title)) : defaultTitle,
            workDirectory: workDirectory,
            episodes: episodes,
            skippedCount: skippedCount
        )
    }

    /// So đường dẫn tương đối theo từng cấp, mỗi cấp so tên tự nhiên ("Phần 2/…" trước "Phần 10/…"); trùng hết phần
    /// chung thì đường dẫn ngắn hơn đứng trước.
    private static func pathLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: "/").map(String.init)
        let right = rhs.split(separator: "/").map(String.init)
        for (a, b) in zip(left, right) where a != b {
            return LocalMediaImportRoute.naturalLess(a, b)
        }
        return left.count < right.count
    }

    /// Một file ⇒ tên file. Nhiều file ⇒ phần đầu chung của các tên ("Phim A - Tập 1", "Phim A - Tập 2" ⇒ "Phim A"),
    /// quá ngắn thì lấy tên file đầu.
    private static func defaultTitle(for titles: [String]) -> String {
        guard var prefix = titles.first else { return "" }
        guard titles.count > 1 else { return prefix }
        for title in titles.dropFirst() {
            prefix = String(zip(prefix, title).prefix { $0.0 == $0.1 }.map { $0.0 })
        }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_.([{#"))
        var trimmed = prefix.trimmingCharacters(in: separators)
        for marker in ["Tập", "tập", "Ep", "ep", "EP", "E"] where trimmed.hasSuffix(" " + marker) {
            trimmed = String(trimmed.dropLast(marker.count)).trimmingCharacters(in: separators)
            break
        }
        return trimmed.count >= 2 ? trimmed : (titles.first ?? "")
    }

    // MARK: - Ghi

    /// Gọi ngoài main **sau khi** hàng `Book` đã tạo. Lỗi giữa chừng ⇒ caller xoá sách (`BookStorageManager` dọn cả
    /// `videos/`, mục lục, bìa) và thư mục làm việc. Trả JPEG bìa (caller ghi bằng `ImageCacheManager`).
    static func commit(
        _ plan: LocalVideoImportPlan,
        bookId: String,
        progress: @Sendable (Int, Int) async -> Void
    ) async throws -> Data? {
        let total = plan.episodes.count
        var snapshots: [ChapterMetadataSnapshot] = []
        snapshots.reserveCapacity(total)
        for episode in plan.episodes {
            let stored = try VideoOfflineStore.importEpisodeFile(movingFrom: episode.fileURL, bookId: bookId, episodeIndex: episode.id)
            let url = episodeURL(bookId: bookId, index: episode.id)
            let manifest = VideoEpisodeManifest(
                version: VideoEpisodeManifest.currentVersion,
                episodeUrl: url,
                episodeTitle: episode.title,
                serverTitle: "Trên máy",
                kind: .file,
                entryFile: stored.file,
                qualityLabel: "",
                totalBytes: stored.bytes,
                segmentCount: 1,
                subtitles: [],
                timeSkips: [],
                completedAt: Date()
            )
            try VideoOfflineStore.saveManifest(manifest, bookId: bookId, episodeIndex: episode.id)
            snapshots.append(ChapterMetadataSnapshot(
                title: episode.title,
                url: url,
                index: episode.id,
                host: nil,
                titleTrans: TranslateUtils.translateChapterTitle(episode.title, bookId: bookId)
            ))
            await progress(episode.id + 1, total)
        }
        _ = try await ChapterStore.shared.replaceFullTOC(bookId: bookId, chapters: snapshots, protectedTTS: nil)

        guard let first = plan.episodes.first,
              let manifest = VideoOfflineStore.manifest(bookId: bookId, episodeIndex: first.id) else { return nil }
        let fileURL = VideoOfflineStore.fileURL(bookId: bookId, episodeIndex: first.id, file: manifest.entryFile)
        return await coverFrame(of: fileURL)
    }

    /// URL tập trong mục lục.
    static func episodeURL(bookId: String, index: Int) -> String {
        "local://\(bookId)/episode/\(index)"
    }

    /// Khung hình ở giây thứ 5 (phim ngắn hơn thì khung đầu), cạnh dài tối đa 1024px.
    private static func coverFrame(of url: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        for seconds in [5.0, 0.0] {
            if let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                return UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.85)
            }
        }
        AppLogger.shared.log("⚠️ [VideoImport] Không lấy được khung hình làm bìa: \(url.lastPathComponent)")
        return nil
    }
}
