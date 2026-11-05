import Foundation

/// Nhập từ **một** file ZIP/CBZ ở Kệ sách (1.3.731): giải nén **một lần**, rồi mới quyết định là phim hay truyện tranh.
///
/// - Chuyển file vào `LocalMediaImportWorkspace`, kiểm dung lượng trống (cỡ file + 50 MB), giải nén bằng
///   `BackupZipArchive.extract` (ZIPFoundation chỉ được gọi ở đó), xoá bản nén để trả chỗ trống.
/// - Có ít nhất một file video phát được (MP4/MOV/M4V) ⇒ **một phim**, mỗi video là một tập (người dùng chốt:
///   "tất cả video trong đó là các tập của 1 phim") — `LocalVideoImporter.plan(fromExtracted:…)`. Ảnh lẫn trong ZIP bị
///   bỏ qua.
/// - Không có video ⇒ **truyện tranh** như trước 1.3.731 — `LocalComicImporter.plan(fromExtracted:…)`.
/// - Lỗi ở bất kỳ bước nào ⇒ xoá cả thư mục làm việc.
enum LocalMediaArchiveImporter {
    enum Result: Sendable {
        case comic(LocalComicImportPlan)
        case video(LocalVideoImportPlan)
    }

    private static let spaceMargin: Int64 = 50 * 1024 * 1024

    static func prepare(pickedURL: URL) throws -> Result {
        let fileName = pickedURL.lastPathComponent
        let workDirectory = try LocalMediaImportWorkspace.make()
        do {
            let ext = pickedURL.pathExtension.lowercased()
            let archive = try LocalMediaImportWorkspace.adopt(pickedURL, into: workDirectory, as: "source.\(ext.isEmpty ? "zip" : ext)")
            // CBZ/ZIP phim thường lưu không nén (ảnh JPEG, MP4 đã nén sẵn) ⇒ bản giải nén xấp xỉ cỡ file. Kiểm trước để
            // không đầy ổ giữa chừng.
            let archiveSize = LocalMediaImportWorkspace.fileSize(archive)
            if let available = LocalMediaImportWorkspace.availableCapacity(), available < archiveSize + spaceMargin {
                throw LocalComicImporter.ImportError.notEnoughSpace(
                    ByteCountFormatter.string(fromByteCount: archiveSize + spaceMargin, countStyle: .file)
                )
            }
            let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)
            do {
                try BackupZipArchive.extract(archive: archive, to: extracted)
            } catch {
                throw LocalComicImporter.ImportError.unreadableArchive(error.localizedDescription)
            }
            // Bỏ bản nén ngay để trả lại chỗ trống cho bước chuyển ảnh / video vào kho.
            try? FileManager.default.removeItem(at: archive)

            if let video = try LocalVideoImporter.plan(fromExtracted: extracted, workDirectory: workDirectory, archiveName: fileName) {
                return .video(video)
            }
            return .comic(try LocalComicImporter.plan(fromExtracted: extracted, workDirectory: workDirectory, fileName: fileName))
        } catch {
            LocalMediaImportWorkspace.discard(workDirectory)
            throw error
        }
    }
}
