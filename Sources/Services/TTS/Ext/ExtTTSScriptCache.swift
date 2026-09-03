import CryptoKit
import Foundation

/// Nội dung `tts.js` + config đã trộn + fingerprint của một extension TTS, giữ trong RAM và chỉ dựng
/// lại khi file trên đĩa hoặc config người dùng đổi.
///
/// **Vì sao cần**: mỗi đoạn văn (2–4 giây một lần, suốt cả truyện) trước 1.3.330 đi qua
/// `ExtensionManager.ttsGenerate` **và** `getTTSRuntimeFingerprint`, hai hàm này cộng lại làm
/// **4 lần đọc `plugin.json` + 2 lần đọc trọn `tts.js` + 4 lần parse JSON + 2 lần serialize** — toàn
/// bộ đều cho ra cùng một kết quả. `getTTSRuntimeFingerprint` cũ còn đọc script **trước** khi tra
/// cache nên cache chỉ tiết kiệm SHA256, không tiết kiệm I/O.
///
/// Đường nóng bây giờ là **hai lần `stat()`** (plugin.json + script) để kiểm hạn cache.
final class ExtTTSScriptCache: @unchecked Sendable {
    static let shared = ExtTTSScriptCache()

    /// Không đặt tên `Bundle` — trùng `Foundation.Bundle` là mời gọi nhầm lẫn ở mọi file dùng nó.
    struct Payload: Sendable {
        let scriptContent: String
        let configurationData: Data
        /// Băm của (script + config + đường dẫn). Dùng làm danh tính runtime **và** làm phần
        /// `extensionFingerprint` của `TTSSynthesisIdentity`.
        let fingerprint: String
    }

    /// Mốc kiểm hạn. `plugin.json` cũng phải được canh: nó quyết định *tên* file script, nên đổi nó
    /// mà chỉ canh `tts.js` là dùng mãi script cũ.
    private struct Stamp: Equatable {
        let configJson: String
        let pluginModifiedAt: TimeInterval
        let scriptModifiedAt: TimeInterval
    }

    private struct Entry {
        let stamp: Stamp
        let scriptURL: URL
        let payload: Payload
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    private init() {}

    func payload(localPath: String, configJson: String) throws -> Payload {
        let pluginModifiedAt = Self.modifiedAt(
            URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json").path
        )

        lock.lock()
        let cached = entries[localPath]
        lock.unlock()

        if let cached, cached.stamp.configJson == configJson,
           cached.stamp.pluginModifiedAt == pluginModifiedAt,
           cached.stamp.scriptModifiedAt == Self.modifiedAt(cached.scriptURL.path) {
            return cached.payload
        }

        let scriptURL = try ExtensionManager.shared.getScriptPath(extensionPath: localPath, scriptKey: "tts")
        let scriptData = try Data(contentsOf: scriptURL)
        guard let scriptContent = String(data: scriptData, encoding: .utf8) else {
            throw NSError(
                domain: "ExtTTSScriptCache",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Script TTS không đọc được bằng UTF-8"]
            )
        }
        let configs = ExtensionManager.shared.getCombinedConfigs(localPath: localPath, configJson: configJson)
        let configurationData = try JSONSerialization.data(withJSONObject: configs, options: [.sortedKeys])

        let payload = Payload(
            scriptContent: scriptContent,
            configurationData: configurationData,
            fingerprint: Self.fingerprint(
                scriptData: scriptData,
                configurationData: configurationData,
                localPath: localPath
            )
        )
        let stamp = Stamp(
            configJson: configJson,
            pluginModifiedAt: pluginModifiedAt,
            scriptModifiedAt: Self.modifiedAt(scriptURL.path)
        )

        lock.lock()
        entries[localPath] = Entry(stamp: stamp, scriptURL: scriptURL, payload: payload)
        lock.unlock()
        return payload
    }

    func invalidateAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    // MARK: - Phụ trợ

    /// `0` khi không đọc được thuộc tính: coi như "mốc lạ" nên cache tự dựng lại, không bao giờ
    /// giữ bản cũ vì một lần `stat` thất bại.
    private static func modifiedAt(_ path: String) -> TimeInterval {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let date = attributes?[.modificationDate] as? Date
        return date?.timeIntervalSince1970 ?? 0
    }

    /// Băm có độ dài đi kèm từng phần để hai chuỗi ghép khác nhau không ra cùng digest.
    private static func fingerprint(scriptData: Data, configurationData: Data, localPath: String) -> String {
        var hasher = SHA256()

        var scriptLength = UInt64(scriptData.count).littleEndian
        hasher.update(data: Data(bytes: &scriptLength, count: 8))
        hasher.update(data: scriptData)

        var configLength = UInt64(configurationData.count).littleEndian
        hasher.update(data: Data(bytes: &configLength, count: 8))
        hasher.update(data: configurationData)

        let pathData = Data(localPath.utf8)
        var pathLength = UInt64(pathData.count).littleEndian
        hasher.update(data: Data(bytes: &pathLength, count: 8))
        hasher.update(data: pathData)

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
