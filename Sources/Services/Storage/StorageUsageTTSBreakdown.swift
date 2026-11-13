import Foundation

/// Dòng con của loại "Giọng đọc & từ điển TTS" (`Application Support/FreeBook`): **một** lượt duyệt cả cây, mỗi file vào
/// đúng một dòng ⇒ tổng các dòng = số của loại (loại TTS lấy luôn tổng này, không đo lần hai).
///
/// Thứ tự xét: rác (mục của `JunkScanner` nằm dưới `FreeBook/`) trước, rồi theo thư mục owner. Bố cục chép từ owner
/// (`JunkPaths`): `TTS/VieNeu/{Models,Assets}` = Nano (kể cả graph nhân bản Nano + gói nhân bản Turbo cất chung `Models/`),
/// `TTS/VieNeu/CoreML` = Tăng tốc Core ML, `TTS/VieNeuTurbo/{Models,Voices}` = Turbo, hai `CustomVoices/` = giọng nhân bản,
/// `TTS/Models` = Piper (NghiTTS), file nằm ngay trong `TTS/` = từ điển (phiên âm NghiTTS / VieNeu, bộ thay thế ký tự, bản
/// phiên âm lại + bản sao lưu của nó), còn lại = "Khác của TTS".
enum StorageUsageTTSBreakdown {
    struct Result {
        let totalBytes: Int64
        /// Chỉ dòng > 0 byte, theo thứ tự hiện.
        let details: [StorageUsageDetail]
    }

    private static let order: [StorageUsageDetail.Kind] = [
        .vieNeuNano, .vieNeuNanoCoreML, .vieNeuTurbo, .clonedVoices, .nghiTTS, .ttsDictionaries, .ttsJunk, .ttsOther
    ]

    /// `root` = thư mục của loại TTS (`StorageUsageCategory.tts`); `junk` = lượt quét rác cùng lần đo.
    static func measure(root: URL, junk: JunkScanResult) -> Result {
        let base = StorageRelativePath(root: root)
        let junkKeys = junk.relativeKeys(under: root)
        var bytes: [StorageUsageDetail.Kind: Int64] = [:]
        var total: Int64 = 0

        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(StorageUsageScanner.sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let item as URL in enumerator {
                let size = StorageUsageScanner.fileSize(item)
                guard size > 0 else { continue }
                total += size
                let kind = base.relative(item).map { classify($0, junkKeys: junkKeys) } ?? .ttsOther
                bytes[kind, default: 0] += size
            }
        }

        let rawCounts: [StorageUsageDetail.Kind: Int?] = [
            .vieNeuNano: nanoVoiceCount(),
            .vieNeuTurbo: turboVoiceCount(),
            .nghiTTS: piperVoiceCount()
        ]
        let counts = rawCounts.compactMapValues { $0 }
        let details = order.compactMap { kind -> StorageUsageDetail? in
            guard let value = bytes[kind], value > 0 else { return nil }
            return StorageUsageDetail(kind: kind, bytes: value, count: counts[kind])
        }
        return Result(totalBytes: total, details: details)
    }

    // MARK: - Phân loại

    private static func classify(_ relative: String, junkKeys: Set<String>) -> StorageUsageDetail.Kind {
        if isJunk(relative, junkKeys: junkKeys) { return .ttsJunk }
        func inside(_ folder: String) -> Bool { StorageRelativePath.isSameOrInside(relative, folder) }
        if inside("TTS/VieNeu/CustomVoices") || inside("TTS/VieNeuTurbo/CustomVoices") { return .clonedVoices }
        if inside("TTS/VieNeu/CoreML") { return .vieNeuNanoCoreML }
        if inside("TTS/VieNeu/Models") || inside("TTS/VieNeu/Assets") { return .vieNeuNano }
        if inside("TTS/VieNeuTurbo/Models") || inside("TTS/VieNeuTurbo/Voices") { return .vieNeuTurbo }
        if inside("TTS/Models") { return .nghiTTS }
        if relative.hasPrefix("TTS/"), !relative.dropFirst("TTS/".count).contains("/") { return .ttsDictionaries }
        return .ttsOther
    }

    /// File là mục rác hoặc nằm trong một thư mục rác (dò từng thư mục cha).
    private static func isJunk(_ relative: String, junkKeys: Set<String>) -> Bool {
        guard !junkKeys.isEmpty else { return false }
        var candidate = Substring(relative)
        while !candidate.isEmpty {
            if junkKeys.contains(String(candidate)) { return true }
            guard let slash = candidate.lastIndex(of: "/") else { break }
            candidate = candidate[..<slash]
        }
        return false
    }

    // MARK: - Đếm giọng (rẻ: chỉ liệt kê thư mục, không đọc file lớn)

    /// Gói model Nano tải một lần cả 11 giọng có sẵn (`voices_v3_nano.json`) ⇒ có file đó là có đủ danh sách dựng sẵn.
    private static func nanoVoiceCount() -> Int? {
        let catalog = JunkPaths.vieNeuRoot
            .appendingPathComponent("Assets", isDirectory: true)
            .appendingPathComponent("voices_v3_nano.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: catalog.path) else { return nil }
        return VieNeuBuiltinVoiceList.nano.count
    }

    /// Mỗi giọng Turbo đã tải là một thư mục `VieNeuTurbo/Voices/<id>/` (`VieNeuTurboModelStore.voiceDirectory`).
    private static func turboVoiceCount() -> Int? {
        let voices = JunkPaths.vieNeuTurboRoot.appendingPathComponent("Voices", isDirectory: true)
        let count = JunkScanner.children(of: voices).filter(JunkScanner.isDirectory).count
        return count > 0 ? count : nil
    }

    /// Như `ModelStore.getLocalVoiceIDs()`: mỗi `<id>.onnx` có kèm `<id>.onnx.json` trong `TTS/Models/` (không gọi
    /// `ModelStore()` vì init của nó tạo thư mục).
    private static func piperVoiceCount() -> Int? {
        let models = JunkPaths.ttsRoot.appendingPathComponent("Models", isDirectory: true)
        let names = Set(JunkScanner.children(of: models).map(\.lastPathComponent))
        let count = names.filter { $0.hasSuffix(".onnx") && names.contains($0 + ".json") }.count
        return count > 0 ? count : nil
    }
}
