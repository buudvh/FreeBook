import CryptoKit
import Foundation

/// Thư mục model LAC trên máy: `Application Support/translate/LAC/` — cùng gốc `translate/` mà
/// `StorageUsageCategory.translation` ("Từ điển & dịch") đo, nên màn Dung lượng tự tính ~19 MB này vào đó. Sao lưu từ
/// điển chỉ gói các file có tên của nó dưới `translate/` nên **không** mang model theo (tải lại được).
///
/// "Đã cài" = `lac_manifest.json` đúng bản ghim (sha256) + mọi file dữ liệu có mặt với đúng kích thước manifest.
/// Lượt tải ghi manifest **cuối cùng** (`LACModelDownloader`), nên app bị tắt giữa chừng chỉ để lại vài file dữ liệu
/// (lượt sau tải tiếp phần thiếu), không bao giờ một bộ "đã cài" thiếu file.
///
/// Không đặt file tạm `.partial` ở đây: Dọn rác (`JunkScanner+VieNeu`) quét `translate/` và coi mọi `*.partial` là
/// rác. File tải về nằm ở thư mục tạm của hệ thống tới khi kiểm sha256 xong mới chuyển vào.
struct LACModelStore: Sendable {
    let directory: URL
    /// `Application Support/translate/` — thư mục cha, dùng để kiểm lệnh xoá cả thư mục model.
    private let translateRoot: URL

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        translateRoot = support.appendingPathComponent("translate", isDirectory: true)
        directory = translateRoot.appendingPathComponent("LAC", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    var manifestURL: URL { url(for: LACModelMirror.manifestName) }

    /// Manifest đã cài, hoặc `nil` khi chưa cài đủ (thiếu file, sai kích thước, manifest khác bản ghim).
    func installedManifest() -> LACManifest? {
        guard Self.fileSize(at: manifestURL) == LACModelMirror.manifestByteCount,
              let data = try? Data(contentsOf: manifestURL),
              Self.sha256Hex(of: data) == LACModelMirror.manifestSHA256,
              let manifest = try? LACManifest.decode(data) else { return nil }
        for name in LACModelMirror.dataFileNames {
            guard let entry = manifest.files[name], Self.fileSize(at: url(for: name)) == entry.bytes else { return nil }
        }
        return manifest
    }

    /// Có manifest trên đĩa nhưng không phải bản ghim (bản cũ / hỏng) ⇒ lượt tải phải dọn sạch trước.
    var hasStaleManifest: Bool {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return false }
        guard let data = try? Data(contentsOf: manifestURL) else { return true }
        return Self.sha256Hex(of: data) != LACModelMirror.manifestSHA256
    }

    /// Kích thước file chưa đúng manifest ⇒ cần tải.
    func needsDownload(_ name: String, entry: LACManifest.FileEntry) -> Bool {
        Self.fileSize(at: url(for: name)) != entry.bytes
    }

    /// Xoá cả thư mục (file hỏng / bản cũ) rồi tạo lại rỗng. Lỗi chỉ log: lượt sau `installedManifest()` vẫn thấy chưa
    /// cài và tải lại.
    func removeAll() {
        let fileManager = FileManager.default
        do {
            try Self.validatePath(directory, inside: translateRoot)
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.log("❌ 🧠 [LAC] Không xoá được thư mục model: \(error.localizedDescription)")
        }
    }

    /// Kiểm sha256 mọi file dữ liệu so với manifest (lúc nạp; ~19 MB, vài chục ms). Lệch ⇒ `invalidFiles`.
    func verifyChecksums(_ manifest: LACManifest) throws {
        for name in LACModelMirror.dataFileNames {
            guard let entry = manifest.files[name] else { throw LACModelError.invalidFiles("manifest thiếu \(name)") }
            let digest: String
            do {
                digest = try Self.sha256Hex(ofFileAt: url(for: name))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LACModelError.invalidFiles("không đọc được \(name)")
            }
            guard digest == entry.sha256 else { throw LACModelError.invalidFiles("\(name) sai sha256") }
        }
    }

    /// Luật `validatePathSafety(for:)` của `rules.md`: mọi lệnh ghi / chuyển / xoá file model phải trỏ vào trong
    /// `translate/LAC/` (đã giải symlink). Ném `invalidFiles`.
    func validatePathSafety(for targetURL: URL) throws {
        try Self.validatePath(targetURL, inside: directory)
    }

    private static func validatePath(_ targetURL: URL, inside root: URL) throws {
        guard canonicalComponents(targetURL).starts(with: canonicalComponents(root)) else {
            throw LACModelError.invalidFiles("đường dẫn ngoài thư mục model: \(targetURL.lastPathComponent)")
        }
    }

    /// Chỉ giải symlink phần **đã có** trên đĩa: `resolvingSymlinksInPath` bỏ tiền tố `/private` (`/var` → `/private/var`)
    /// cho đường dẫn tồn tại nhưng có thể giữ nó cho file chưa có ⇒ so lệch dù cùng thư mục. File chưa có (manifest sắp
    /// ghi, đích sắp chuyển vào) ⇒ giải thư mục cha (luôn có) rồi ghép tên.
    private static func canonicalComponents(_ url: URL) -> [String] {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath().pathComponents
        }
        return standardized.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            + [standardized.lastPathComponent]
    }

    // MARK: - Tiện ích file

    static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    static func sha256Hex(of data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    /// sha256 đọc theo khối 1 MiB (không nạp cả file vào RAM); huỷ ⇒ `CancellationError`.
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
