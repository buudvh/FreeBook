import Foundation
import ImageIO
import UIKit

/// Nhập truyện tranh từ **một** file CBZ/ZIP = cả bộ (người dùng chốt).
///
/// - `prepare` (ngoài main): chuyển file vào `LocalMediaImportWorkspace`, kiểm dung lượng trống, giải nén bằng
///   `BackupZipArchive.extract` (ZIPFoundation chỉ được gọi ở đó), rồi quét ảnh. Không hỗ trợ ZIP có mật khẩu,
///   CBR/RAR/7z.
/// - Chương = mỗi thư mục **trực tiếp** chứa ảnh, xếp theo đường dẫn tên tự nhiên; thư mục bọc ngoài chung bị bỏ khỏi
///   tên. Không có thư mục con ⇒ một chương. Ảnh trong chương xếp theo tên tự nhiên.
/// - Zip-slip: lúc **ghi** do ZIPFoundation chặn (bản 0.9.x mới từ chối entry ra ngoài thư mục đích); bước quét chỉ là
///   lớp thứ hai — có symlink ⇒ huỷ cả lượt nhập (file nén cố ý trỏ ra ngoài), bỏ file ẩn, `__MACOSX/`, file không phải
///   file thường, và file mà đường dẫn thật nằm ngoài thư mục giải nén. Chưa chặn được zip bomb trước khi giải nén
///   (cỡ sau giải nén không đọc được mà không gọi ZIPFoundation ngoài `BackupZipArchive`): đầy ổ ⇒ giải nén lỗi ⇒ dọn
///   cả thư mục làm việc.
/// - `commit` (ngoài main, sau khi hàng `Book` đã tạo): **chuyển** ảnh vào `ComicOfflineStore` (manifest ghi sau
///   cùng), `chapterUrl` của manifest = đúng URL thô trong mục lục (`host` chương nil) để
///   `ComicReaderViewModel.offlinePages` khớp; rồi `ChapterStore.replaceFullTOC`. Trả ảnh bìa (trang đầu, đã thu nhỏ).
enum LocalComicImporter {
    enum ImportError: LocalizedError {
        case notEnoughSpace(String)
        case unreadableArchive(String)
        case noImages

        var errorDescription: String? {
            switch self {
            case .notEnoughSpace(let needed):
                return "Không đủ dung lượng trống để giải nén (cần khoảng \(needed))."
            case .unreadableArchive(let detail):
                return "Không giải nén được file (hỏng hoặc có mật khẩu): \(detail)"
            case .noImages:
                return "Không tìm thấy ảnh nào trong file."
            }
        }
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif", "avif"]
    private static let spaceMargin: Int64 = 50 * 1024 * 1024

    // MARK: - Chuẩn bị

    static func prepare(pickedURL: URL) throws -> LocalComicImportPlan {
        let fileName = pickedURL.lastPathComponent
        let workDirectory = try LocalMediaImportWorkspace.make()
        do {
            let ext = pickedURL.pathExtension.lowercased()
            let archive = try LocalMediaImportWorkspace.adopt(pickedURL, into: workDirectory, as: "source.\(ext.isEmpty ? "zip" : ext)")
            // CBZ thường lưu ảnh không nén ⇒ bản giải nén xấp xỉ cỡ file. Kiểm trước để không đầy ổ giữa chừng.
            let archiveSize = LocalMediaImportWorkspace.fileSize(archive)
            if let available = LocalMediaImportWorkspace.availableCapacity(), available < archiveSize + spaceMargin {
                throw ImportError.notEnoughSpace(ByteCountFormatter.string(fromByteCount: archiveSize + spaceMargin, countStyle: .file))
            }
            let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)
            do {
                try BackupZipArchive.extract(archive: archive, to: extracted)
            } catch {
                throw ImportError.unreadableArchive(error.localizedDescription)
            }
            // Bỏ bản nén ngay để trả lại chỗ trống cho bước chuyển ảnh.
            try? FileManager.default.removeItem(at: archive)
            let scan = try scanChapters(in: extracted)
            AppLogger.shared.log("📥 [ComicImport] \(fileName): \(scan.chapters.count) chương, \(scan.folderCount) thư mục con")
            return LocalComicImportPlan(
                fileName: fileName,
                defaultTitle: (fileName as NSString).deletingPathExtension,
                workDirectory: workDirectory,
                chapters: scan.chapters,
                folderCount: scan.folderCount
            )
        } catch {
            LocalMediaImportWorkspace.discard(workDirectory)
            throw error
        }
    }

    private static func scanChapters(in extracted: URL) throws -> (chapters: [LocalComicImportPlan.Chapter], folderCount: Int) {
        let root = extracted.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw ImportError.noImages
        }
        var groups: [[String]: [URL]] = [:]
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
                AppLogger.shared.log("❌ [ComicImport] File nén chứa symlink (\(name)) — huỷ lượt nhập")
                throw ImportError.unreadableArchive("file nén chứa liên kết tượng trưng")
            }
            guard values?.isRegularFile == true, !name.hasPrefix("."),
                  imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(rootPath + "/") else {
                AppLogger.shared.log("⚠️ [ComicImport] Bỏ qua file nằm ngoài thư mục giải nén: \(name)")
                continue
            }
            let folder = resolved.deletingLastPathComponent().path.dropFirst(rootPath.count)
            let components = folder.split(separator: "/").map(String.init)
            groups[components, default: []].append(resolved)
        }
        guard !groups.isEmpty else { throw ImportError.noImages }

        let folders = groups.keys.sorted(by: pathLess)
        let wrapper = commonPrefix(of: folders)
        var chapters: [LocalComicImportPlan.Chapter] = []
        chapters.reserveCapacity(folders.count)
        for (offset, key) in folders.enumerated() {
            let folderPath = key.dropFirst(wrapper.count).joined(separator: " / ")
            let pages = (groups[key] ?? []).sorted {
                LocalMediaImportRoute.naturalLess($0.lastPathComponent, $1.lastPathComponent)
            }
            let title: String
            if !folderPath.isEmpty {
                title = folderPath
            } else {
                title = folders.count == 1 ? "Chương 1" : "Ảnh ngoài thư mục"
            }
            chapters.append(LocalComicImportPlan.Chapter(id: offset, title: title, folderPath: folderPath, pages: pages))
        }
        let folderCount = folders.filter { $0.count > wrapper.count }.count
        return (chapters, folderCount)
    }

    /// Xếp đường dẫn thư mục theo từng cấp, mỗi cấp so tên tự nhiên; thư mục cha đứng trước thư mục con.
    private static func pathLess(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            return LocalMediaImportRoute.naturalLess(left, right)
        }
        return lhs.count < rhs.count
    }

    /// Thư mục bọc ngoài chung của mọi chương (vd cả bộ nằm trong `Ten truyen/`).
    private static func commonPrefix(of paths: [[String]]) -> [String] {
        guard var prefix = paths.first else { return [] }
        for path in paths.dropFirst() {
            var length = 0
            while length < prefix.count, length < path.count, prefix[length] == path[length] {
                length += 1
            }
            prefix = Array(prefix.prefix(length))
        }
        return prefix
    }

    // MARK: - Ghi

    /// Gọi ngoài main **sau khi** hàng `Book` đã tạo. Lỗi giữa chừng ⇒ caller xoá sách (`BookStorageManager` dọn cả
    /// `comics/`, mục lục, bìa) và thư mục làm việc. Trả JPEG bìa đã thu nhỏ (caller ghi bằng `ImageCacheManager`).
    static func commit(
        _ plan: LocalComicImportPlan,
        bookId: String,
        progress: @Sendable (Int, Int) async -> Void
    ) async throws -> Data? {
        let total = plan.chapters.count
        var snapshots: [ChapterMetadataSnapshot] = []
        snapshots.reserveCapacity(total)
        for chapter in plan.chapters {
            let directory = try ComicOfflineStore.prepareChapterDirectory(bookId: bookId, chapterIndex: chapter.id)
            var pages: [ComicChapterManifest.Page] = []
            pages.reserveCapacity(chapter.pages.count)
            for (offset, source) in chapter.pages.enumerated() {
                pages.append(try ComicOfflineStore.importPage(movingFrom: source, pageNumber: offset + 1, chapterDirectory: directory))
            }
            let url = chapterURL(bookId: bookId, index: chapter.id)
            let manifest = ComicChapterManifest(chapterUrl: url, pages: pages, completedAt: Date())
            try ComicOfflineStore.saveManifest(manifest, bookId: bookId, chapterIndex: chapter.id)
            snapshots.append(ChapterMetadataSnapshot(
                title: chapter.title,
                url: url,
                index: chapter.id,
                host: nil,
                titleTrans: TranslateUtils.translateChapterTitle(chapter.title, bookId: bookId)
            ))
            await progress(chapter.id + 1, total)
        }
        _ = try await ChapterStore.shared.replaceFullTOC(bookId: bookId, chapters: snapshots, protectedTTS: nil)

        guard let firstPage = ComicOfflineStore.manifest(bookId: bookId, chapterIndex: 0)?.pages.first else { return nil }
        let coverURL = ComicOfflineStore.pageFileURL(bookId: bookId, chapterIndex: 0, file: firstPage.file)
        return coverThumbnail(at: coverURL)
    }

    /// URL chương trong mục lục — cùng mẫu với truyện chữ nhập từ file.
    static func chapterURL(bookId: String, index: Int) -> String {
        "local://\(bookId)/chapter/\(index)"
    }

    /// Bìa từ trang đầu: thu nhỏ bằng ImageIO (không giải mã cả ảnh lớn), cạnh dài tối đa 1024px.
    private static func coverThumbnail(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
    }
}
