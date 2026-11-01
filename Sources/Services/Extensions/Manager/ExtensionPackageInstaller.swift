import Foundation
import ZIPFoundation

/// Cài gói tiện ích (.zip) theo kiểu **dựng ở thư mục tạm rồi mới thay**.
///
/// Giải nén, tìm `plugin.json` và giải mã script (`ExtensionScriptDecoder`) đều chạy trong một thư mục tạm riêng;
/// chỉ khi mọi bước thành công mới đổi chỗ vào `extensions/`. Zip hỏng, thiếu `plugin.json` hay script mã hoá không
/// đọc được ⇒ bản đang cài không bị đụng tới, cài mới lỗi cũng không để lại thư mục dở trong `extensions/`.
enum ExtensionPackageInstaller {

    /// Cài/cập nhật từ kho: **toàn bộ** thư mục giải nén thay `destination` (giữ đúng cấu trúc zip như trước).
    ///
    /// - Returns: thư mục chứa `plugin.json` bên trong `destination` — là thư mục con khi zip bọc mọi thứ trong một
    ///   thư mục (vd `twkan/twkan`).
    static func install(archive: URL, replacing destination: URL) throws -> URL {
        try withStagedPackage(archive: archive) { root, mainFolder in
            try replace(destination, with: root)
            // Không cắt tiền tố đường dẫn: thư mục con có thể được trả về dạng `/private/var/...` trong khi `root`
            // là `/var/...`. `findMainFolder` chỉ xuống một cấp ⇒ tên thư mục con là đủ.
            guard mainFolder.path != root.path else { return destination }
            return destination.appendingPathComponent(mainFolder.lastPathComponent, isDirectory: true)
        }
    }

    /// Giải nén `archive` vào thư mục tạm mới, tìm thư mục chính, giải mã script rồi gọi `body(root, mainFolder)`.
    ///
    /// `body` đọc metadata từ bản đã dựng và gọi `replace(_:with:)` để đưa vào `extensions/`. Thư mục tạm luôn bị
    /// xoá khi xong, dù thành công hay ném lỗi.
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
        guard fileManager.fileExists(atPath: mainFolder.appendingPathComponent("plugin.json").path) else {
            throw NSError(domain: "ExtensionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp plugin.json trong file zip"])
        }
        try ExtensionScriptDecoder.decodeScripts(in: mainFolder)

        return try body(root, mainFolder)
    }

    /// Đưa `item` (đã dựng xong ở thư mục tạm) vào `destination`, thay bản đang có nếu có.
    ///
    /// Bản cũ được dời sang một thư mục dự phòng trong thư mục tạm của hệ thống — **không** nằm trong `extensions/`
    /// nên không bị coi là tiện ích — rồi mới chuyển bản mới vào; thành công thì xoá dự phòng. Chuyển bản mới thất
    /// bại ⇒ trả bản cũ về chỗ rồi ném lại lỗi gốc. Thư mục dự phòng nằm ngoài thư mục làm việc của
    /// `withStagedPackage` nên nếu trả về cũng thất bại thì bản cũ vẫn còn đó (đường dẫn có trong log).
    static func replace(_ destination: URL, with item: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        var backup: URL?
        if fileManager.fileExists(atPath: destination.path) {
            let aside = fileManager.temporaryDirectory
                .appendingPathComponent("ExtensionBackup-\(UUID().uuidString)", isDirectory: true)
            try fileManager.moveItem(at: destination, to: aside)
            backup = aside
        }

        do {
            try fileManager.moveItem(at: item, to: destination)
        } catch {
            if let backup {
                do {
                    try fileManager.moveItem(at: backup, to: destination)
                } catch let restoreError {
                    AppLogger.shared.log("❌ [ExtensionPackageInstaller] Không trả được bản cũ về \(destination.lastPathComponent), bản cũ còn ở \(backup.path): \(restoreError.localizedDescription)")
                }
            }
            throw error
        }

        if let backup {
            try? fileManager.removeItem(at: backup)
        }
    }

    /// Thư mục chứa `plugin.json`: chính `url`, hoặc thư mục con **một cấp** đầu tiên có `plugin.json` (zip bọc mọi
    /// thứ trong một thư mục). Không thấy ⇒ trả `url`.
    static func findMainFolder(at url: URL) -> URL {
        let pluginJsonUrl = url.appendingPathComponent("plugin.json")
        if FileManager.default.fileExists(atPath: pluginJsonUrl.path) {
            return url
        }

        // Nếu không thấy, duyệt các thư mục con
        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let subPluginUrl = item.appendingPathComponent("plugin.json")
                    if FileManager.default.fileExists(atPath: subPluginUrl.path) {
                        return item
                    }
                }
            }
        }
        return url
    }
}
