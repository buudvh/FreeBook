import CryptoKit
import Foundation

/// Envelope vận chuyển ngoài `.fbbackup`: chia file để gửi và ghép lại sau khi tải từ Telegram.
public enum BackupMultipartArchive {
    public static let manifestExtension = "fbmanifest"
    public static let defaultPartSize: Int64 = 49 * 1024 * 1024

    public struct Manifest: Codable, Sendable {
        public struct Part: Codable, Sendable {
            public let index: Int
            public let fileName: String
            public let byteCount: Int64
            public let sha256: String
        }

        public let schemaVersion: Int
        public let originalFileName: String
        public let totalByteCount: Int64
        public let sha256: String
        public let partSize: Int64
        public let parts: [Part]
    }

    public struct Package: Sendable {
        public let manifestURL: URL
        public let partURLs: [URL]
        public let workingDirectory: URL

        public func cleanUp() { try? FileManager.default.removeItem(at: workingDirectory) }
    }

    public enum Failure: LocalizedError {
        case invalidManifest
        case invalidSelection(String)
        case unreadable(String)
        case checksum(String)

        public var errorDescription: String? {
            switch self {
            case .invalidManifest: return "Manifest file chia không hợp lệ"
            case .invalidSelection(let message): return message
            case .unreadable(let name): return "Không đọc được \(name)"
            case .checksum(let name): return "Checksum không khớp: \(name)"
            }
        }
    }

    public static func split(archive: URL, partSize: Int64 = defaultPartSize) throws -> Package {
        guard partSize > 0 else { throw Failure.invalidManifest }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freebook-parts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let source = try FileHandle(forReadingFrom: archive)
            defer { try? source.close() }
            var wholeHasher = SHA256()
            var parts: [Manifest.Part] = []
            var partURLs: [URL] = []
            var total: Int64 = 0

            while true {
                let index = parts.count + 1
                let name = archive.lastPathComponent + String(format: ".part%03d", index)
                let url = root.appendingPathComponent(name)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                let output = try FileHandle(forWritingTo: url)
                var partHasher = SHA256()
                var written: Int64 = 0
                while written < partSize {
                    let count = Int(min(1024 * 1024, partSize - written))
                    guard let data = try source.read(upToCount: count), !data.isEmpty else { break }
                    try output.write(contentsOf: data)
                    partHasher.update(data: data)
                    wholeHasher.update(data: data)
                    written += Int64(data.count)
                    total += Int64(data.count)
                }
                try output.close()
                if written == 0 {
                    try? FileManager.default.removeItem(at: url)
                    break
                }
                parts.append(Manifest.Part(index: index, fileName: name, byteCount: written, sha256: hex(partHasher.finalize())))
                partURLs.append(url)
                if written < partSize { break }
            }
            guard !parts.isEmpty else { throw Failure.unreadable(archive.lastPathComponent) }

            let manifest = Manifest(
                schemaVersion: 1,
                originalFileName: archive.lastPathComponent,
                totalByteCount: total,
                sha256: hex(wholeHasher.finalize()),
                partSize: partSize,
                parts: parts
            )
            let manifestURL = root.appendingPathComponent(archive.lastPathComponent)
                .appendingPathExtension(manifestExtension)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            return Package(manifestURL: manifestURL, partURLs: partURLs, workingDirectory: root)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    /// Ghép đúng tập file người dùng chọn vào một file tạm đã xác minh đầy đủ.
    public static func assemble(selectedURLs: [URL]) throws -> URL {
        let manifests = selectedURLs.filter { $0.pathExtension.lowercased() == manifestExtension }
        guard manifests.count == 1,
              let data = try? Data(contentsOf: manifests[0]),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.schemaVersion == 1,
              manifest.originalFileName == URL(fileURLWithPath: manifest.originalFileName).lastPathComponent,
              manifest.originalFileName.lowercased().hasSuffix(".\(BackupPaths.fileExtension)"),
              !manifest.parts.isEmpty,
              manifest.totalByteCount > 0,
              manifest.partSize > 0,
              manifest.parts.map(\.index) == Array(1...manifest.parts.count),
              Set(manifest.parts.map(\.fileName)).count == manifest.parts.count,
              manifest.parts.allSatisfy({
                  $0.byteCount > 0
                      && $0.fileName == URL(fileURLWithPath: $0.fileName).lastPathComponent
                      && $0.fileName.hasPrefix(manifest.originalFileName + ".part")
              })
        else { throw Failure.invalidManifest }

        let selectedByName = Dictionary(grouping: selectedURLs.filter { $0 != manifests[0] }, by: \URL.lastPathComponent)
        let expectedNames = Set(manifest.parts.map(\.fileName))
        let extras = Set(selectedByName.keys).subtracting(expectedNames)
        guard extras.isEmpty else {
            throw Failure.invalidSelection("Có file không thuộc bộ chia: \(extras.sorted().joined(separator: ", "))")
        }
        let missing = expectedNames.filter { selectedByName[$0]?.count != 1 }.sorted()
        guard missing.isEmpty else {
            throw Failure.invalidSelection("Thiếu hoặc trùng phần: \(missing.joined(separator: ", "))")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freebook-assemble-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let partial = root.appendingPathComponent(manifest.originalFileName + ".partial")
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        do {
            let output = try FileHandle(forWritingTo: partial)
            defer { try? output.close() }
            var wholeHasher = SHA256()
            var total: Int64 = 0
            for part in manifest.parts.sorted(by: { $0.index < $1.index }) {
                guard let url = selectedByName[part.fileName]?.first else { throw Failure.unreadable(part.fileName) }
                let input = try FileHandle(forReadingFrom: url)
                var partHasher = SHA256()
                var partBytes: Int64 = 0
                while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    try output.write(contentsOf: chunk)
                    partHasher.update(data: chunk)
                    wholeHasher.update(data: chunk)
                    partBytes += Int64(chunk.count)
                    total += Int64(chunk.count)
                }
                try input.close()
                guard partBytes == part.byteCount, hex(partHasher.finalize()) == part.sha256 else {
                    throw Failure.checksum(part.fileName)
                }
            }
            try output.synchronize()
            guard total == manifest.totalByteCount, hex(wholeHasher.finalize()) == manifest.sha256 else {
                throw Failure.checksum(manifest.originalFileName)
            }
            let completed = root.appendingPathComponent(manifest.originalFileName)
            try FileManager.default.moveItem(at: partial, to: completed)
            return completed
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
