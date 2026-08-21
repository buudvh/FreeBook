import Foundation

public final class ModelStore {
    private let fileManager: FileManager
    public let rootURL: URL
    public let modelsURL: URL

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
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
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
