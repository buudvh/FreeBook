import Foundation

/// Tải kho model Kokoro từ HuggingFace (`raikiri1498/Kokoro-Vietnamese`).
///
/// ## Ba thứ cố ý **không** tải
/// - **`kokoro_vi.pth`** (312 MB): checkpoint PyTorch, chỉ dùng để export ONNX hoặc chạy PyTorch. Tải nó là
///   gấp đôi dung lượng mà suy luận ONNX không được gì.
/// - **`sea_g2p.bin`** (62,8 MB): dùng chung bản của VieNeu — xem doc `KokoroModelStore`. Nhưng vẫn phải
///   **kiểm nó có trên máy chưa**, và kiểm **trước** khi tải 310 MB.
/// - **`kokoro_vi_voicepack.pt`** ở gốc repo: trùng một trong 14 voicepack; app chỉ dùng bản trong
///   `voicepacks/` để danh sách giọng và file tải luôn khớp nhau qua `voices.json`.
///
/// ## Vì sao dùng `download(from:)` chứ không `data(from:)`
/// Graph là 310 MB. `data(from:)` giữ **toàn bộ** phần thân trong RAM trước khi trả về, nên tải graph bằng
/// nó là cộng thêm ~310 MB đỉnh bộ nhớ **ngay trước** lúc nạp model — đúng lúc app đã căng.
final class KokoroModelClient {
    static let repository = "raikiri1498/Kokoro-Vietnamese"
    static let revision = "main"

    enum ClientError: LocalizedError {
        case badStatus(String, Int)
        case emptyCatalog
        case missingSeaG2P

        var errorDescription: String? {
            switch self {
            case .badStatus(let path, let status):
                return "Tải `\(path)` thất bại: HTTP \(status)"
            case .emptyCatalog:
                return "`voices.json` không liệt kê giọng nào — kho weights có thể đã đổi cấu trúc."
            case .missingSeaG2P:
                return "Chưa có `sea_g2p.bin` — hãy tải model **VieNeu** trước, Kokoro dùng chung bộ phiên âm đó."
            }
        }
    }

    let store: KokoroModelStore

    init(store: KokoroModelStore) {
        self.store = store
    }

    static func remoteURL(for path: String) -> URL {
        var url = URL(string: "https://huggingface.co")!
        for component in ([repository, "resolve", revision] + path.split(separator: "/").map(String.init)) {
            url.appendPathComponent(component)
        }
        return url
    }

    /// Tải mọi file còn thiếu. `progress` nhận `(thông điệp, phần trăm 0…1)`.
    ///
    /// File đã có thì **bỏ qua** — nhờ vậy một lần tải đứt giữa đường vẫn tiếp tục được thay vì tải lại
    /// 310 MB. File tải dở không tồn tại trên đĩa vì `download(from:)` chỉ trả về sau khi phần thân đã nằm
    /// trọn ở file tạm, và mình `move` nguyên file đó vào kho.
    func prefetch(progress: @escaping (String, Double) -> Void) async throws {
        // Kiểm `sea_g2p.bin` **trước** mọi thứ: thiếu nó thì engine không phiên âm được, mà bắt người dùng
        // chờ tải xong 310 MB rồi mới báo là việc vô ích.
        guard store.hasSeaG2P else { throw ClientError.missingSeaG2P }

        try await download(remote: KokoroModelStore.voicesName, local: KokoroModelStore.voicesName)
        let voices = (try? KokoroVoiceCatalog.load(from: store.url(for: KokoroModelStore.voicesName))) ?? []
        guard !voices.isEmpty else { throw ClientError.emptyCatalog }

        var plan: [(remote: String, local: String)] = [
            (remote: KokoroModelStore.configName, local: KokoroModelStore.configName),
            (remote: KokoroModelStore.graphName, local: KokoroModelStore.graphName)
        ]
        plan.append(contentsOf: voices.map { (remote: $0.fileName, local: $0.fileName) })

        let fileManager = FileManager.default
        let total = Double(plan.count)
        for (index, item) in plan.enumerated() {
            try Task.checkCancellation()
            let destination = store.url(for: item.local)
            if fileManager.fileExists(atPath: destination.path) {
                progress("Đã có \(item.local)", Double(index + 1) / total)
                continue
            }
            progress("Đang tải \(item.local) (\(index + 1)/\(plan.count))", Double(index) / total)
            try await download(remote: item.remote, local: item.local)
            progress("Xong \(item.local)", Double(index + 1) / total)
        }
    }

    private func download(remote: String, local: String) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: Self.remoteURL(for: remote))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ClientError.badStatus(remote, http.statusCode)
        }
        let destination = store.url(for: local)
        let fileManager = FileManager.default
        // Voicepack nằm trong thư mục con (`voicepacks/…`) nên thư mục đích có thể chưa tồn tại.
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }
}
