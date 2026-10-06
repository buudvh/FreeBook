import Foundation

/// Tải kho model ZeroTTS từ HuggingFace (`zeroweight-ai/ZeroTTS`) về `ZeroTTSModelStore`.
///
/// ## Vì sao dùng `URLSession.download` chứ không `data`
/// Ba graph lớn nhất là 323 MB, 348 MB và 187 MB. `URLSession.data(from:)` giữ **toàn bộ** phần thân trong
/// RAM trước khi trả về, nên tải graph bằng nó là cộng thêm ~348 MB đỉnh bộ nhớ **ngay trước** lúc nạp
/// model — đúng lúc app đã căng. `download(from:)` ghi ra file tạm rồi mình chuyển vào kho, RAM chỉ tốn
/// theo buffer mạng.
///
/// ## Vì sao tải `voices/index.json` trước
/// Số giọng quyết định **tổng số file**, mà tổng đó là mẫu số của thanh tiến trình. Tải manifest trước rồi
/// mới dựng kế hoạch tải là cách duy nhất để phần trăm không nhảy loạn.
final class ZeroTTSModelClient {
    static let repository = "zeroweight-ai/ZeroTTS"
    static let revision = "main"

    enum ClientError: LocalizedError {
        case badStatus(String, Int)
        case emptyCatalog

        var errorDescription: String? {
            switch self {
            case .badStatus(let path, let status):
                return "Tải `\(path)` thất bại: HTTP \(status)"
            case .emptyCatalog:
                return "`voices/index.json` không liệt kê giọng nào — kho weights có thể đã đổi cấu trúc."
            }
        }
    }

    let store: ZeroTTSModelStore

    init(store: ZeroTTSModelStore) {
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
    /// 348 MB. File tải dở không tồn tại trên đĩa vì `download(from:)` chỉ trả về sau khi phần thân đã
    /// nằm trọn ở file tạm, và mình `move` nguyên file đó vào kho.
    func prefetch(progress: @escaping (String, Double) -> Void) async throws {
        try await download(remote: "voices/index.json", local: "voices_index.json")
        let voices = (try? ZeroTTSVoiceCatalog.load(from: store.url(for: "voices_index.json"))) ?? []
        guard !voices.isEmpty else { throw ClientError.emptyCatalog }

        var plan: [(remote: String, local: String)] = ZeroTTSModelStore.remoteToLocal
            .filter { $0.remote != "voices/index.json" }
            .map { (remote: $0.remote, local: $0.local) }
        plan.append(contentsOf: voices.map {
            (remote: "voices/\($0.name)/voice.bin", local: ZeroTTSModelStore.voiceFileName($0.name))
        })

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
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }
}
