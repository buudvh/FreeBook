import Foundation
import ZIPFoundation

/// Cài gói tiện ích (.zip) theo kiểu **dựng ở thư mục tạm rồi mới ghi**.
///
/// Giải nén, tìm `plugin.json` và giải mã script (`ExtensionScriptDecoder`) đều chạy trong một thư mục tạm riêng; chỉ khi
/// mọi bước thành công mới gom thư mục chính thành **một file** `extensions/js/<packageId>.json` (`ExtensionPackageWriter`,
/// ghi nguyên tử, ghi đè bản cũ). Zip hỏng, thiếu `plugin.json`, script mã hoá không đọc được hay file không giải mã được
/// thành chữ ⇒ bản đang cài không bị đụng tới, cài mới lỗi cũng không để lại gì trong `extensions/`.
enum ExtensionPackageInstaller {

    /// Cài/cập nhật từ kho: gom thư mục chính của zip thành `js/<packageId>.json`.
    ///
    /// - Returns: file gói đã ghi.
    static func install(archive: URL, packageId: String) throws -> URL {
        try withStagedPackage(archive: archive) { _, mainFolder in
            try ExtensionPackageWriter.install(directory: mainFolder, packageId: packageId)
        }
    }

    /// Giải nén `archive` vào thư mục tạm mới, tìm thư mục chính, giải mã script rồi gọi `body(root, mainFolder)`.
    ///
    /// `body` đọc metadata từ bản đã dựng rồi ghi gói (`ExtensionPackageWriter.install`). Thư mục tạm luôn bị xoá khi
    /// xong, dù thành công hay ném lỗi.
    static func withStagedPackage<T>(archive: URL, _ body: (_ root: URL, _ mainFolder: URL) throws -> T) throws -> T {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true, attributes: nil)
        defer {
            try? fileManager.removeItem(at: workDirectory)
        }

        // Giải nén từ bản chép trong thư mục tạm (như luồng import zip cũ) để không phụ thuộc vòng đời file nguồn.
        let archiveCopy = workDirectory.appendingPathComponent("package.zip")
        try fileManager.copyItem(at: archive, to: archiveCopy)

        let root = workDirectory.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        try fileManager.unzipItem(at: archiveCopy, to: root)

        let mainFolder = findMainFolder(at: root)
        guard ExtensionPackageReader.isPresent(localPath: mainFolder.path) else {
            throw NSError(domain: "ExtensionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp plugin.json trong file zip"])
        }
        try ExtensionScriptDecoder.decodeScripts(in: mainFolder)

        return try body(root, mainFolder)
    }

    /// Thư mục chứa `plugin.json`: chính `url`, hoặc thư mục con **một cấp** đầu tiên có `plugin.json` (zip bọc mọi
    /// thứ trong một thư mục). Không thấy ⇒ trả `url`.
    static func findMainFolder(at url: URL) -> URL {
        if ExtensionPackageReader.isPresent(localPath: url.path) {
            return url
        }

        // Nếu không thấy, duyệt các thư mục con
        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue,
                   ExtensionPackageReader.isPresent(localPath: item.path) {
                    return item
                }
            }
        }
        return url
    }
}
