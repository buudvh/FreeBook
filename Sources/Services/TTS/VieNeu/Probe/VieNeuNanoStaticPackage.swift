import CryptoKit
import Foundation

/// Gói graph **tĩnh** của phép thử P1 "So EP cho Nano" (`Scripts/vieneu_nano_static_export.py`): tải từ thư mục
/// `nano-static/` của kho HF `raikiri1498/VieNeu-TTS` (cùng kho với model, `VieNeuModelMirror`) theo `manifest.json`,
/// kiểm dung lượng + sha256 từng file, cất ở `FreeBook/TTS/VieNeu/Static/`.
///
/// Thư mục này nằm trong loại "TTS" của màn Dung lượng (`StorageUsageCategory.tts` = cả `FreeBook/`). WAV + log kết quả
/// (`Results/`) cũng nằm trong đó ⇒ "Xoá gói" dọn sạch. Core ML biên dịch vào thư mục tạm của ORT, tự xoá khi đóng session.
final class VieNeuNanoStaticPackage: Sendable {
    /// Thư mục `nano-static/` của kho mirror, đọc theo nhánh `main` — gói mới, chưa có commit để ghim như
    /// `VieNeuModelMirror.revision`. An toàn vì mọi file được kiểm sha256 theo `manifest.json` tải cùng lượt. Đăng gói
    /// bằng workflow `vieneu-nano-static.yml` (chạy tay) hoặc anh tự `hf upload`.
    static let remoteBaseURL = "https://huggingface.co/\(VieNeuModelMirror.repository)/resolve/main/nano-static/"
    static let manifestName = "manifest.json"
    static let supportedFormat = 1

    struct Manifest: Decodable, Sendable {
        struct File: Decodable, Sendable {
            let name: String
            let bytes: Int64
            let sha256: String
        }

        let format: Int
        let veInlineBucket: Int
        let veExternalBuckets: [Int]
        let codecBucket: Int
        let goldenChunks: Int
        let h1Chunk: Int
        let files: [File]
    }

    enum PackageError: LocalizedError {
        case unsupportedFormat(Int)
        case badURL(String)
        case checksum(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let value): return "manifest định dạng \(value) — app này chỉ hiểu \(VieNeuNanoStaticPackage.supportedFormat)"
            case .badURL(let name): return "URL không hợp lệ cho \(name)"
            case .checksum(let name): return "\(name) sai sha256 — tải lại"
            }
        }
    }

    let directory: URL

    init() throws {
        directory = try VieNeuModelStore().rootURL.appendingPathComponent("Static", isDirectory: true)
    }

    func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    var resultsURL: URL { directory.appendingPathComponent("Results", isDirectory: true) }

    /// Manifest đã tải (nếu có và đúng định dạng).
    var manifest: Manifest? {
        guard let data = try? Data(contentsOf: url(Self.manifestName)),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
              decoded.format == Self.supportedFormat else { return nil }
        return decoded
    }

    /// Đủ mọi file đúng dung lượng (sha256 đã kiểm lúc tải).
    var isComplete: Bool {
        guard let manifest else { return false }
        return manifest.files.allSatisfy { VieNeuTurboModelStore.fileSize(at: url($0.name)) == $0.bytes }
    }

    var bytesOnDisk: Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += VieNeuTurboModelStore.fileSize(at: file)
        }
        return total
    }

    /// Tải manifest rồi mọi file còn thiếu / sai dung lượng. `progress(tên, đã tải, tổng)` theo byte của **cả gói**.
    func download(progress: @escaping @Sendable (String, Int64, Int64) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let manifestURL = URL(string: Self.remoteBaseURL + Self.manifestName) else {
            throw PackageError.badURL(Self.manifestName)
        }
        try await VieNeuTurboModelClient.transfer(
            session: .shared, from: manifestURL, to: url(Self.manifestName), name: Self.manifestName,
            expectedBytes: nil, progress: nil
        )
        let data = try Data(contentsOf: url(Self.manifestName))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.format == Self.supportedFormat else { throw PackageError.unsupportedFormat(manifest.format) }

        let total = manifest.files.reduce(Int64(0)) { $0 + $1.bytes }
        var done: Int64 = 0
        for file in manifest.files {
            let destination = url(file.name)
            if VieNeuTurboModelStore.fileSize(at: destination) == file.bytes {
                done += file.bytes
                progress(file.name, done, total)
                continue
            }
            guard let source = URL(string: Self.remoteBaseURL + file.name) else { throw PackageError.badURL(file.name) }
            let base = done
            try await VieNeuTurboModelClient.transfer(
                session: .shared, from: source, to: destination, name: file.name, expectedBytes: file.bytes,
                progress: { completed, _ in progress(file.name, base + completed, total) }
            )
            guard try Self.sha256(of: destination) == file.sha256 else {
                try? FileManager.default.removeItem(at: destination)
                throw PackageError.checksum(file.name)
            }
            done += file.bytes
            progress(file.name, done, total)
        }
        AppLogger.shared.log("🎙️ [VieNeuProbe] Đã tải gói graph tĩnh: \(manifest.files.count) file, \(total) byte")
    }

    func deleteAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// sha256 đọc từng khối 1 MiB — file 153 MB không được nạp cả vào RAM.
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: 1 << 20), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
