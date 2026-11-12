import Foundation

/// Kho file của **bước thử VieNeu-TTS v3 Turbo** (GGUF q8_0 chạy qua audio.cpp).
///
/// Bố cục, tách hẳn khỏi `VieNeu/` của Nano để xoá bên này không đụng bên kia:
/// - `Application Support/FreeBook/TTS/VieNeuTurbo/Models/vieneu-v3-turbo-q8_0.gguf` (187.917.664 byte)
/// - `Application Support/FreeBook/TTS/VieNeuTurbo/Voices/manifest.json`
/// - `Application Support/FreeBook/TTS/VieNeuTurbo/Voices/<id>/ref_codes.txt` + `speaker.emb.txt`
/// - `Application Support/FreeBook/TTS/VieNeuTurbo/CustomVoices/` — giọng **người dùng tự tạo** (1.3.892, id `custom_…`,
///   chủ là `VieNeuTurboCustomVoiceStore`): cùng cặp file trong `<id>/` + index `voices_custom.json`. Tách khỏi `Voices/`
///   (giọng tải về) nên `deleteAll` không bao giờ chạm tới.
///
/// `sea_g2p.bin` **không** nằm ở đây: Turbo đọc đúng bộ phiên âm của Nano (`VieNeuModelStore.url(for:)`), chung một
/// file 62,8 MB thay vì hai bản. Màn Dung lượng đã phủ thư mục này qua `StorageUsageCategory.tts` (= cả `FreeBook/`).
///
/// Mọi file tải từ kho mirror `VieNeuModelMirror` (ghim commit, từ 1.3.888), thư mục `turbo/`. Đây là bản sao nguyên
/// văn thư mục `gguf/` của `pnnbao-ump/VieNeu-TTS-v3-Turbo` @ `61b85e3d937fbbacb387714180e8182823512523` ⇒ file đã
/// tải từ nguồn cũ vẫn khớp (cùng `modelByteCount`); upstream đổi file cũng không làm app tự hỏng.
final class VieNeuTurboModelStore: Sendable {
    static let modelFileName = "vieneu-v3-turbo-q8_0.gguf"
    /// Dung lượng đúng của file GGUF (header `X-Linked-Size` của HuggingFace; trùng ở kho gốc lẫn kho mirror).
    static let modelByteCount: Int64 = 187_917_664
    static let manifestFileName = "manifest.json"
    static let referenceCodesFileName = "ref_codes.txt"
    static let speakerEmbeddingFileName = "speaker.emb.txt"
    /// Giọng mặc định của manifest — tải cùng model để bấm "Đọc thử" được ngay.
    static let fallbackVoiceId = "minh_quan_pro"
    /// Tiền tố id giọng tự tạo — giọng tải về không có id nào như vậy (25 giọng của manifest đang ghim).
    static let customVoiceIdPrefix = "custom_"

    let rootURL: URL
    let modelsURL: URL
    let voicesURL: URL
    /// Giọng tự tạo — **không** tạo thư mục ở `init` (đường đọc); `VieNeuTurboCustomVoiceStore` tạo lúc ghi.
    let customVoicesURL: URL

    init(fileManager: FileManager = .default) throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.rootURL = appSupport.appendingPathComponent("FreeBook/TTS/VieNeuTurbo", isDirectory: true)
        self.modelsURL = rootURL.appendingPathComponent("Models", isDirectory: true)
        self.voicesURL = rootURL.appendingPathComponent("Voices", isDirectory: true)
        self.customVoicesURL = rootURL.appendingPathComponent("CustomVoices", isDirectory: true)
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: voicesURL, withIntermediateDirectories: true)
    }

    // MARK: - Nguồn tải

    /// `path` theo bố cục của kho gốc (`gguf/…`); kho mirror đặt nó dưới `turbo/`.
    static func remoteURL(path: String) -> URL? {
        VieNeuModelMirror.url(path: "turbo/\(path)")
    }

    static var modelRemotePath: String { "gguf/\(modelFileName)" }
    static var manifestRemotePath: String { "gguf/voices/\(manifestFileName)" }

    static func voiceRemotePath(voiceId: String, fileName: String) -> String {
        "gguf/voices/\(voiceId)/\(fileName)"
    }

    /// Id giọng đi thẳng vào đường dẫn file ⇒ chỉ nhận chữ ASCII, số, `_`, `-` (chặn `..` / `/` từ manifest).
    static func isSafeVoiceId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-")
        }
    }

    /// Id của giọng tự tạo (`custom_…`) — file nằm ở `CustomVoices/<id>/`, không bao giờ tải từ kho mirror.
    static func isCustomVoiceId(_ id: String) -> Bool {
        id.hasPrefix(customVoiceIdPrefix) && isSafeVoiceId(id)
    }

    // MARK: - Đường dẫn

    var modelURL: URL { modelsURL.appendingPathComponent(Self.modelFileName) }
    var manifestURL: URL { voicesURL.appendingPathComponent(Self.manifestFileName) }

    /// Giọng tải về ⇒ `Voices/<id>/`; giọng tự tạo ⇒ `CustomVoices/<id>/`. Mọi đường đọc giọng (trình đọc, màn thử)
    /// đi qua đây nên cả hai loại dùng chung `referenceCodesURL` / `speakerEmbeddingURL` / `hasVoice`.
    func voiceDirectory(voiceId: String) -> URL {
        let parent = Self.isCustomVoiceId(voiceId) ? customVoicesURL : voicesURL
        return parent.appendingPathComponent(voiceId, isDirectory: true)
    }

    func referenceCodesURL(voiceId: String) -> URL {
        voiceDirectory(voiceId: voiceId).appendingPathComponent(Self.referenceCodesFileName)
    }

    func speakerEmbeddingURL(voiceId: String) -> URL {
        voiceDirectory(voiceId: voiceId).appendingPathComponent(Self.speakerEmbeddingFileName)
    }

    // MARK: - Trạng thái

    /// Đủ **đúng** 187.917.664 byte mới tính là có model — file cụt (tải đứt rồi ai đó chép tay) không lọt qua.
    var hasModel: Bool {
        Self.fileSize(at: modelURL) == Self.modelByteCount
    }

    var hasManifest: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    func hasVoice(voiceId: String) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: referenceCodesURL(voiceId: voiceId).path)
            && fileManager.fileExists(atPath: speakerEmbeddingURL(voiceId: voiceId).path)
    }

    /// Dung lượng cả thư mục `VieNeuTurbo/` (model + manifest + mọi giọng đã tải + giọng tự tạo, kể cả file `.partial`).
    var totalBytes: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    // MARK: - Xoá

    /// Xoá model + manifest + mọi giọng **tải về**. Lượt tải đang chạy bị màn thử chặn nút xoá, nên xoá cả cây con ở
    /// đây an toàn (khác `VieNeuModelStore.deleteAll`, nơi lượt tải nền có thể chạy song song). `sea_g2p.bin` của Nano
    /// giữ nguyên — engine Nano vẫn cần nó. `CustomVoices/` (giọng người dùng tự tạo) **không** bị đụng: tải lại model
    /// là giọng đó đọc được ngay.
    func deleteAll() throws {
        let fileManager = FileManager.default
        for directory in [modelsURL, voicesURL] {
            let children = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for child in children {
                try fileManager.removeItem(at: child)
            }
        }
    }

    static func fileSize(at url: URL) -> Int64 {
        Int64(((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0)
    }
}
