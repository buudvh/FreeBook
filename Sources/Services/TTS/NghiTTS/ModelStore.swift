import Foundation

public struct CacheSummary: Codable {
    public let voicesCached: Bool
    public let modelCount: Int
    public let totalBytes: Int64
}

public final class ModelStore {
    private let fileManager: FileManager
    public let rootURL: URL
    public let modelsURL: URL
    private let voicesCacheURL: URL

    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.rootURL = appSupport.appendingPathComponent("FreeBook/TTS", isDirectory: true)
        self.modelsURL = rootURL.appendingPathComponent("Models", isDirectory: true)
        self.voicesCacheURL = rootURL.appendingPathComponent("voices.json")
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
    }

    public func cacheSummary() -> CacheSummary {
        let files = (try? fileManager.contentsOfDirectory(
            at: modelsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let totalBytes = files.reduce(Int64(0)) { partial, url in
            let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
            return partial + Int64(size)
        }

        let modelCount = files.filter { $0.pathExtension == "onnx" }.count
        return CacheSummary(
            voicesCached: fileManager.fileExists(atPath: voicesCacheURL.path),
            modelCount: modelCount,
            totalBytes: totalBytes
        )
    }

    public func readCachedVoices() -> [String]? {
        guard let data = try? Data(contentsOf: voicesCacheURL) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    public func writeCachedVoices(_ voices: [String]) throws {
        let data = try JSONEncoder().encode(voices)
        try data.write(to: voicesCacheURL, options: [.atomic])
    }

    public func modelURL(for voiceId: String, extension ext: String) -> URL {
        modelsURL.appendingPathComponent(voiceId).appendingPathExtension(ext)
    }

    public func modelExists(for voiceId: String) -> Bool {
        fileManager.fileExists(atPath: modelURL(for: voiceId, extension: "onnx").path)
            && fileManager.fileExists(atPath: modelURL(for: voiceId, extension: "onnx.json").path)
    }

    public func bytesForVoice(_ voiceId: String) -> Int64 {
        ["onnx", "onnx.json"].reduce(Int64(0)) { partial, ext in
            let url = modelURL(for: voiceId, extension: ext)
            let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    public func getLocalVoiceIDs() -> [String] {
        let files = (try? fileManager.contentsOfDirectory(
            at: modelsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        
        let onnxFiles = files.filter { $0.pathExtension == "onnx" }
        var voiceIds: [String] = []
        for file in onnxFiles {
            let voiceId = file.deletingPathExtension().lastPathComponent
            if modelExists(for: voiceId) {
                voiceIds.append(voiceId)
            }
        }
        return voiceIds
    }

    public func deleteModel(for voiceId: String) throws {
        let onnxURL = modelURL(for: voiceId, extension: "onnx")
        let jsonURL = modelURL(for: voiceId, extension: "onnx.json")
        if fileManager.fileExists(atPath: onnxURL.path) {
            try fileManager.removeItem(at: onnxURL)
        }
        if fileManager.fileExists(atPath: jsonURL.path) {
            try fileManager.removeItem(at: jsonURL)
        }
    }
}
