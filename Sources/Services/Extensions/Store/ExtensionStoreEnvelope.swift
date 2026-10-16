import Foundation

/// Vỏ JSON của các file trong `extension_store/` — mọi file đều mang `schemaVersion` để bản sau đổi shape
/// được mà không phải đoán. Gom trong một namespace để giữ đúng luật "một type chính mỗi file".
///
/// `Date` mã hoá bằng `secondsSince1970` (số thực) chứ không ISO-8601: ISO mặc định cắt phần lẻ giây, mà
/// thứ tự ghim (`pinnedAt`) cần độ phân giải dưới giây.
public enum ExtensionStoreEnvelope {
    public static let currentSchemaVersion = 1

    /// `installed.json`.
    public struct Installed: Codable, Sendable {
        public var schemaVersion: Int
        /// `true` khi dữ liệu SwiftData cũ đã được chuyển (hoặc không có gì để chuyển) — migrator không chạy lại.
        public var migratedFromLegacy: Bool
        public var extensions: [Extension]

        public init(
            schemaVersion: Int = ExtensionStoreEnvelope.currentSchemaVersion,
            migratedFromLegacy: Bool,
            extensions: [Extension]
        ) {
            self.schemaVersion = schemaVersion
            self.migratedFromLegacy = migratedFromLegacy
            self.extensions = extensions
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, migratedFromLegacy, extensions
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? ExtensionStoreEnvelope.currentSchemaVersion
            migratedFromLegacy = try c.decodeIfPresent(Bool.self, forKey: .migratedFromLegacy) ?? false
            extensions = try c.decodeIfPresent([Extension].self, forKey: .extensions) ?? []
        }
    }

    /// `repositories.json`.
    public struct Repositories: Codable, Sendable {
        public var schemaVersion: Int = ExtensionStoreEnvelope.currentSchemaVersion
        public var repositories: [ExtensionRepositoryRecord]

        public init(repositories: [ExtensionRepositoryRecord]) {
            self.repositories = repositories
        }
    }

    /// `registry/<sha256>.json`.
    public struct Registry: Codable, Sendable {
        public var schemaVersion: Int = ExtensionStoreEnvelope.currentSchemaVersion
        public var snapshot: ExtensionRegistrySnapshot

        public init(snapshot: ExtensionRegistrySnapshot) {
            self.snapshot = snapshot
        }
    }

    /// `local_storage.json` — `[namespace (packageId): [key: value]]`.
    public struct LocalStorage: Codable, Sendable {
        public var schemaVersion: Int = ExtensionStoreEnvelope.currentSchemaVersion
        public var storage: [String: [String: String]]

        public init(storage: [String: [String: String]]) {
            self.storage = storage
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
