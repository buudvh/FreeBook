import Foundation

/// Kho file của Kokoro trên máy.
///
/// ## `sea_g2p.bin` **không** nằm trong kho này
/// Nó là tài sản của VieNeu và được **dùng chung**. Đã xác minh bằng mã băm git blob rằng file mà pip
/// `sea-g2p` v0.10.0 dùng (chính gói `vig2p` gọi) và file ở revision VieNeu ghim là **cùng một file**:
/// `411df0016be7f665514db544bc2b76fd3a97b785`, 62 829 820 byte. Tải bản sao thứ hai là lãng phí 62,8 MB.
///
/// Hệ quả: màn thử Kokoro **phụ thuộc** máy phải có model VieNeu. Phụ thuộc **một chiều** — VieNeu không
/// biết gì về Kokoro.
final class KokoroModelStore {
    static let directoryName = "Kokoro"
    static let graphName = "kokoro_vi.onnx"
    static let configName = "config.json"
    static let voicesName = "voices.json"
    /// Tên file phonemizer — sống trong kho **VieNeu**, không phải kho này.
    static let seaG2PName = "sea_g2p.bin"

    /// Ba file luôn bắt buộc. Voicepack bổ sung sau khi đọc được `voices.json`.
    static let coreNames = [graphName, configName, voicesName]

    enum StoreError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let detail): return "Không dựng được kho model Kokoro: \(detail)"
            }
        }
    }

    let rootURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        do {
            let base = try fileManager.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil,
                                           create: true)
            let root = base.appendingPathComponent(Self.directoryName, isDirectory: true)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            self.rootURL = root
        } catch {
            throw StoreError.unavailable(error.localizedDescription)
        }
    }

    func url(for name: String) -> URL { rootURL.appendingPathComponent(name) }

    /// Đường dẫn `sea_g2p.bin` trong kho **VieNeu**. `nil` khi kho VieNeu không dựng được.
    var seaG2PURL: URL? {
        guard let vieNeuStore = try? VieNeuModelStore() else { return nil }
        return vieNeuStore.url(for: Self.seaG2PName)
    }

    var hasSeaG2P: Bool {
        guard let url = seaG2PURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// Đường dẫn voicepack theo `filename` khai trong `voices.json` (ví dụ `voicepacks/ngoc_huyen.pt`).
    func voicepackURL(_ fileName: String) -> URL {
        rootURL.appendingPathComponent(fileName)
    }

    /// Tên các voicepack **đã có** trên đĩa, đọc từ `voices.json`. Rỗng khi chưa có `voices.json`.
    var voicepackNames: [String] {
        guard let catalog = try? KokoroVoiceCatalog.load(from: url(for: Self.voicesName)) else { return [] }
        return catalog
            .filter { fileManager.fileExists(atPath: voicepackURL($0.fileName).path) }
            .map(\.fileName)
    }

    /// Tên các voicepack còn thiếu, đọc từ `voices.json`. Rỗng khi chưa có `voices.json`.
    var missingVoicepackNames: [String] {
        guard let catalog = try? KokoroVoiceCatalog.load(from: url(for: Self.voicesName)) else { return [] }
        return catalog
            .filter { !fileManager.fileExists(atPath: voicepackURL($0.fileName).path) }
            .map(\.fileName)
    }

    /// File còn thiếu.
    ///
    /// `sea_g2p.bin` được ghi kèm chú thích nguồn để màn thử nói đúng việc cần làm — "cần tải model VieNeu
    /// trước" — thay vì để người dùng đi tìm file trong kho Kokoro (nó không bao giờ ở đó).
    var missingNames: [String] {
        var missing = Self.coreNames.filter { !fileManager.fileExists(atPath: url(for: $0).path) }
        missing.append(contentsOf: missingVoicepackNames)
        if !hasSeaG2P { missing.append("\(Self.seaG2PName) (của VieNeu)") }
        return missing
    }

    var isReady: Bool { missingNames.isEmpty }

    /// Tổng dung lượng đã tải trong kho Kokoro. **Không** tính `sea_g2p.bin` của VieNeu.
    var totalBytes: Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(at: rootURL,
                                                                  includingPropertiesForKeys: [.fileSizeKey],
                                                                  options: [.skipsHiddenFiles]) else {
            return 0
        }
        return contents.reduce(Int64(0)) { partial, fileURL in
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    /// Xoá mọi file **trong kho Kokoro**.
    ///
    /// Cố ý **không** xoá `sea_g2p.bin`: nó thuộc kho VieNeu, và xoá nó ở đây là phá engine mặc định của
    /// người dùng từ một nút bấm ở màn thử của engine khác.
    func deleteAll() throws {
        guard let contents = try? fileManager.contentsOfDirectory(at: rootURL,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) else {
            return
        }
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
