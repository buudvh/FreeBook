import Foundation

/// Xuất truyện tranh ra **CBZ**: ZIP stored (không nén lại ảnh) qua `ZipStoreWriter` + `ExportStagingFile` — ghi dần
/// xuống `.part`, chỉ đổi tên thành file thật khi xong; lỗi/huỷ thì bỏ `.part`.
///
/// Mỗi chương một thư mục `0001/`, ảnh `0001.jpg`… theo thứ tự manifest. Tên entry chỉ dùng ASCII vì `ZipStoreWriter`
/// không bật cờ UTF-8 (bit 11) — tên chương tiếng Việt/Trung sẽ hiện sai ở app đọc. Đọc từng ảnh một (map bộ nhớ),
/// không giữ cả chương trong RAM. Vượt 4 GB ⇒ `ExportRenderError.archiveTooLarge` (không có ZIP64).
enum ComicCbzExportWriter {
    static func write(
        chapters: [ComicExportChapter],
        to target: URL,
        onChapterDone: (ComicExportChapter) async -> Void,
        isCancelled: () async -> Bool
    ) async throws -> URL {
        let staging = try ExportStagingFile(targetURL: target)
        let writer = ZipStoreWriter(staging: staging)
        do {
            for chapter in chapters {
                if await isCancelled() { throw CancellationError() }
                let folder = String(format: "%04d", chapter.ordinal)
                for (offset, page) in chapter.pages.enumerated() {
                    let data = try Data(contentsOf: page, options: .mappedIfSafe)
                    let ext = page.pathExtension.isEmpty ? "img" : page.pathExtension.lowercased()
                    try writer.addEntry(name: "\(folder)/\(String(format: "%04d", offset + 1)).\(ext)", data: data)
                }
                await onChapterDone(chapter)
            }
            guard writer.entryCount > 0 else { throw ExportRenderError.emptyExport }
            return try writer.finish()
        } catch {
            writer.discard()
            throw error
        }
    }
}
