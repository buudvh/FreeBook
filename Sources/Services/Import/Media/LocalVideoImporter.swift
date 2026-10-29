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
