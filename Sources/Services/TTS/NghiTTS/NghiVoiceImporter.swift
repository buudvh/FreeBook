import Foundation

/// **Nhập giọng Piper từ file** vào `ModelStore`: mỗi giọng một cặp `<id>.onnx` + `<id>.json` (hoặc `<id>.onnx.json`) cùng
/// tên. Chuyển nguyên logic từ màn "Quản lý model" cũ (`TTSModelManagerView.handleModelImportPick` + `streamCopy`); chỉ
/// thao tác file — toast và lớp phủ "Đang nhập" do View lo. `importPairs` chép file đồng bộ ⇒ gọi trong `Task.detached`.
enum NghiVoiceImporter {
    struct Pair: Sendable {
        let onnxURL: URL
        let jsonURL: URL
        let voiceId: String
    }

    enum PairingError: LocalizedError {
        case noModelFiles
        case needsBoth
        case missingJSON([String])

        var errorDescription: String? {
            switch self {
            case .noModelFiles:
                return "Vui lòng chọn tệp tin model (.onnx) và cấu hình (.json)."
            case .needsBoth:
                return "Cần chọn cả hai tệp .onnx và .json cho model. Vui lòng thử lại."
            case .missingJSON(let names):
                return "Thiếu tệp .json tương ứng cho: \(names.joined(separator: ", "))."
            }
        }
    }

    struct Outcome: Sendable {
        /// Số **file** đã chép (mỗi giọng hai file).
        let copiedFiles: Int
        let errorCount: Int
        let lastErrorMessage: String?

        var importedModels: Int { copiedFiles / 2 }
    }

    /// Ghép các file đã chọn thành từng cặp model + cấu hình theo id (tên file bỏ ký tự lạ, viết thường).
    static func pair(_ urls: [URL]) -> Result<[Pair], PairingError> {
        let validURLs = urls.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "onnx" || ext == "json"
        }
        guard !validURLs.isEmpty else { return .failure(.noModelFiles) }

        let onnxURLs = validURLs.filter { $0.pathExtension.lowercased() == "onnx" }
        let jsonURLs = validURLs.filter { $0.pathExtension.lowercased() == "json" }
        guard !onnxURLs.isEmpty, !jsonURLs.isEmpty else { return .failure(.needsBoth) }

        let jsonById = Dictionary(
            jsonURLs.compactMap { url -> (String, URL)? in
                let id = cleanVoiceId(for: url)
                return id.isEmpty ? nil : (id, url)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var pairs: [Pair] = []
        var missingJSON: [String] = []
        for onnxURL in onnxURLs {
            let id = cleanVoiceId(for: onnxURL)
            if let jsonURL = jsonById[id] {
                pairs.append(Pair(onnxURL: onnxURL, jsonURL: jsonURL, voiceId: id))
            } else {
                missingJSON.append(onnxURL.lastPathComponent)
            }
        }
        guard missingJSON.isEmpty else { return .failure(.missingJSON(missingJSON)) }
        return .success(pairs)
    }

    /// Chép từng cặp vào `ModelStore` (`<id>.onnx` + `<id>.onnx.json`). File lỗi giữa chừng bị dọn; đếm lỗi để View báo.
    static func importPairs(_ pairs: [Pair]) -> Outcome {
        let fileManager = FileManager.default
        var copiedFiles = 0
        var errorCount = 0
        var lastErrorMessage: String?

        for pair in pairs {
            let onnxAccess = pair.onnxURL.startAccessingSecurityScopedResource()
            let jsonAccess = pair.jsonURL.startAccessingSecurityScopedResource()
            defer {
                if onnxAccess { pair.onnxURL.stopAccessingSecurityScopedResource() }
                if jsonAccess { pair.jsonURL.stopAccessingSecurityScopedResource() }
            }

            guard let store = try? ModelStore() else { continue }
            let targets = [
                (source: pair.onnxURL, destination: store.modelURL(for: pair.voiceId, extension: "onnx")),
                (source: pair.jsonURL, destination: store.modelURL(for: pair.voiceId, extension: "onnx.json"))
            ]

            for target in targets {
                var cleanupURL: URL?
                do {
                    let size = try target.source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    if size <= 0 {
                        throw NSError(domain: "NghiVoiceImporter", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Tệp \(target.source.lastPathComponent) rỗng hoặc không đọc được."
                        ])
                    }
                    if target.source.pathExtension.lowercased() == "json" {
                        let data = try Data(contentsOf: target.source)
                        _ = try JSONSerialization.jsonObject(with: data, options: [])
                    }
                    if fileManager.fileExists(atPath: target.destination.path) {
                        try fileManager.removeItem(at: target.destination)
                    }
                    cleanupURL = target.destination
                    try streamCopy(from: target.source, to: target.destination)
                    copiedFiles += 1
                } catch {
                    lastErrorMessage = error.localizedDescription
                    if let cleanup = cleanupURL, fileManager.fileExists(atPath: cleanup.path) {
                        try? fileManager.removeItem(at: cleanup)
                    }
                    errorCount += 1
                }
            }
        }
        AppLogger.shared.log("🗣️ [NghiVoiceImporter] Nhập \(pairs.count) giọng: \(copiedFiles) file, \(errorCount) lỗi")
        return Outcome(copiedFiles: copiedFiles, errorCount: errorCount, lastErrorMessage: lastErrorMessage)
    }

    // MARK: - Nội bộ

    private static func cleanVoiceId(for url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent
        if url.pathExtension.lowercased() == "json", baseName.lowercased().hasSuffix(".onnx") {
            return String(baseName.dropLast(5))
                .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression)
                .lowercased()
        }
        return baseName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression).lowercased()
    }

    /// Chép theo khối 64 KB — model ~60 MB, không nạp cả file vào RAM.
    private static func streamCopy(from sourceURL: URL, to destinationURL: URL) throws {
        guard let inputStream = InputStream(url: sourceURL) else {
            throw NSError(domain: "StreamCopy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể mở input stream"])
        }
        guard let outputStream = OutputStream(url: destinationURL, append: false) else {
            throw NSError(domain: "StreamCopy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không thể mở output stream"])
        }

        inputStream.open()
        defer { inputStream.close() }
        outputStream.open()
        defer { outputStream.close() }

        let bufferSize = 65536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                if let error = inputStream.streamError { throw error }
                throw NSError(domain: "StreamCopy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Lỗi đọc tệp nguồn"])
            } else if bytesRead == 0 {
                break
            }

            var bytesWritten = 0
            while bytesWritten < bytesRead {
                let written = outputStream.write(buffer.advanced(by: bytesWritten), maxLength: bytesRead - bytesWritten)
                if written < 0 {
                    if let error = outputStream.streamError { throw error }
                    throw NSError(domain: "StreamCopy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Lỗi ghi tệp đích"])
                }
                bytesWritten += written
            }
        }
    }
}
