import Foundation

/// Cửa vào duy nhất của mô hình đoán tên Latin (`LocalNameFilterLatinModel`) cho một lượt Lọc name local bật "Ưu tiên
/// tên Latin": gộp các lượt nạp trùng (hai truyện lọc cùng lúc chỉ tải / đọc một lần) và giữ mô hình **yếu** — hết lượt
/// lọc thì RAM được trả, lượt sau đọc lại từ đĩa (~155 KB, vài ms).
///
/// Lượt nạp chạy ở task tách riêng nên một người gọi bị huỷ không làm hỏng lượt của người khác; người gọi bị huỷ vẫn chờ
/// tới khi lượt đó xong (file nhỏ, hết hạn 30 s) rồi tự kiểm `Task.isCancelled`.
actor LocalNameFilterLatinModelGate {
    static let shared = LocalNameFilterLatinModelGate()

    private weak var cached: LocalNameFilterLatinModel?
    private var inFlight: Task<LocalNameFilterLatinModel, Error>?

    private init() {}

    /// Mô hình đã kiểm sha256. Ném lỗi của `LocalNameFilterLatinModelStore.loadData` / `LocalNameFilterLatinModel.init`.
    func model() async throws -> LocalNameFilterLatinModel {
        if let cached { return cached }
        if let inFlight { return try await inFlight.value }
        let task = Task.detached(priority: .userInitiated) {
            let started = Date()
            let data = try await LocalNameFilterLatinModelStore.loadData()
            let model = try LocalNameFilterLatinModel(data: data)
            AppLogger.shared.log("🔎 [LọcName] Nạp mô hình đoán tên Latin \(Int(Date().timeIntervalSince(started) * 1_000)) ms "
                + "(\(model.translitChars.count) chữ phiên âm)")
            // Tập chữ phiên âm dùng thật là bản đóng trong app (`LocalNameFilterTranslitChars`); tập trong file mô hình chỉ
            // để đối chiếu — lệch nghĩa là hai file không cùng một lần học.
            let bundled = LocalNameFilterTranslitChars.set
            if model.translitChars != bundled {
                AppLogger.shared.log("❌ [LọcName] Tập chữ phiên âm của mô hình (\(model.translitChars.count) chữ) lệch tập "
                    + "đóng trong app (\(bundled.count) chữ) — vẫn dùng tập đóng trong app")
            }
            return model
        }
        inFlight = task
        defer { inFlight = nil }
        let model = try await task.value
        cached = model
        return model
    }
}
