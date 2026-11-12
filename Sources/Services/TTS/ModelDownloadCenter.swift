import Combine
import Foundation

/// Trung tâm tiến độ **tải model TTS** cho cả app: nguồn sự thật duy nhất cho các đường tải
/// (NghiTTS từng giọng, VieNeu 8 file lõi, VieNeu gói graph nhân bản, gói nhân bản giọng Turbo).
///
/// ## Vì sao phải là singleton, không phải `@State` của View
/// Trước 1.3.472, mỗi màn tự giữ tiến độ trong `@State` (`TTSModelManagerView.downloadingStatus`,
/// `VieNeuTTSTestView.downloadProgress`, `VieNeuVoiceLibraryView.downloadProgress`). `Task` tải **không**
/// bị huỷ khi rời màn (không chỗ nào dùng `.task {}`), nên rời màn rồi vào lại thì **tải vẫn chạy mà thanh
/// tiến độ đã mất**. Chuyển trạng thái về đây thì màn chỉ còn là người vẽ.
///
/// ## Center sở hữu `Task`
/// `Task` nằm trong `tasks` của center, không nằm ở View: nhờ vậy lượt tải độc lập hoàn toàn với vòng đời
/// màn, và `guard tasks[id] == nil` chặn được hai lượt tải trùng cho cùng một đích.
///
/// **Huỷ** (1.3.899) chỉ có ở các đích VieNeu (`cancel(id:)`, nút ■ của sheet chọn giọng): đường tải của chúng
/// (`VieNeuTurboModelClient.transfer`) dùng `URLSession` async, huỷ `Task` là dừng file đang tải. NghiTTS vẫn không
/// huỷ được (`NghiTTSClient.prefetchModels` không nhận cancellation).
///
/// Các đích VieNeu (model Nano, gói nhân bản, model / giọng Turbo) **chạy lần lượt** — xem `ModelDownloadCenter+VieNeu`.
///
/// ## Vì sao không phải `TTSManager`
/// `TTSManager.swift` đang vượt trần ratchet (3970/3470) và bị `check_architecture.py` chặn tăng dòng;
/// nhét thêm trạng thái tải model vào đó là vừa vỡ trần vừa trộn trách nhiệm.
///
/// ## Không hiện toast ở đây
/// `Sources/Services/**` không được gọi `ToastManager` (luật `SERVICE_TOAST_COUPLING`). Kết quả lượt tải
/// được phát ra qua `lastNotice` để `MainTabView` — nơi luôn sống — hiện toast, nhờ vậy toast hiện kể cả
/// khi người dùng đã rời màn bấm tải.
@MainActor
public final class ModelDownloadCenter: ObservableObject {
    public static let shared = ModelDownloadCenter()

    /// Khoá của các đích tải. `nghiVoice(id:)` ghép tiền tố nên tra theo giọng luôn tất định.
    public enum Target {
        public static let nghiPrefix = "nghi-"
        public static let vieNeuModel = "vieNeu-model"
        public static let vieNeuClone = "vieNeu-clone"
        /// Gói nhân bản giọng VieNeu Turbo (`speaker_encoder.onnx` + `denoiser.onnx`, 1.3.892).
        public static let vieNeuTurboClone = "vieNeu-turbo-clone"
        /// Model Turbo không kèm giọng nào (GGUF + `sea_g2p.bin` + manifest, 1.3.899).
        public static let vieNeuTurboModel = "vieNeu-turbo-model"
        public static let vieNeuTurboVoicePrefix = "vieNeu-turbo-voice-"

        public static func nghiVoice(_ voiceId: String) -> String { nghiPrefix + voiceId }

        /// Một giọng Turbo (1.3.899): model nếu thiếu + cặp file của giọng — mỗi giọng một dòng tiến độ.
        public static func vieNeuTurboVoice(_ voiceId: String) -> String { vieNeuTurboVoicePrefix + voiceId }
    }

    public enum State: Equatable {
        case running
        case finished
        case failed(String)

        public var isRunning: Bool { self == .running }

        public var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    /// Một dòng tiến độ. Đủ nhỏ để View vẽ thẳng, không chạm đĩa.
    public struct Entry: Identifiable, Equatable {
        public let id: String
        public let title: String
        public var message: String
        public var fraction: Double?
        public var state: State
        public let startedAt: Date
        /// Byte đã tải / tổng byte của cả lượt (1.3.899, chỉ đích VieNeu); `0` khi không theo byte.
        public var completedBytes: Int64 = 0
        public var totalBytes: Int64 = 0
        /// Đang chờ lượt tải VieNeu khác xong (các đích VieNeu chạy lần lượt).
        public var isQueued = false

        public init(
            id: String,
            title: String,
            message: String = "",
            fraction: Double? = nil,
            state: State = .running,
            startedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.message = message
            self.fraction = fraction
            self.state = state
            self.startedAt = startedAt
        }
    }

    /// Kết quả một lượt tải, để View (không phải service) hiện toast. `id` mới mỗi lượt nên hai lượt
    /// liên tiếp cho cùng một đích vẫn kích hoạt `onChange` ở phía View.
    public struct Notice: Equatable, Identifiable {
        public let id: UUID
        public let message: String
        public let isError: Bool

        public init(message: String, isError: Bool) {
            self.id = UUID()
            self.message = message
            self.isError = isError
        }
    }

    /// Mới nhất ở cuối; View vẽ theo thứ tự này. `internal(set)` vì `ModelDownloadCenter+VieNeu.swift` ghi.
    @Published public internal(set) var entries: [Entry] = []
    @Published public internal(set) var lastNotice: Notice?

    /// `internal` (không `private`) vì `ModelDownloadCenter+VieNeu.swift` dùng — Swift giới hạn `private` theo file.
    var tasks: [String: Task<Void, Never>] = [:]
    /// Mã của lượt đang giữ mỗi đích: lượt đã bị huỷ (rồi bấm tải lại cùng đích) không được ghi đè dòng của lượt mới.
    var tokens: [String: UUID] = [:]
    /// Lượt VieNeu xếp cuối hàng — lượt mới chờ nó xong mới chạy.
    var vieNeuTail: Task<Void, Never>?

    private init() {}

    // MARK: - Truy vấn

    public var isBusy: Bool { entries.contains { $0.state.isRunning } }

    public func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Tiến độ 0…1 của một đích, `nil` khi không có lượt nào (hoặc chưa biết tổng).
    public func fraction(id: String) -> Double? {
        entry(id: id)?.fraction
    }

    public func isRunning(id: String) -> Bool {
        entry(id: id)?.state.isRunning ?? false
    }

    // MARK: - Dọn dòng

    /// Nút "Bỏ qua" trên dòng kết quả. Không cho xoá dòng đang chạy — dòng đó là thông tin thật.
    public func dismiss(_ id: String) {
        guard !isRunning(id: id) else { return }
        entries.removeAll { $0.id == id }
    }

    public func clearNotice() {
        lastNotice = nil
    }

    // MARK: - NghiTTS (từng giọng)

    /// Tải model cho **một hay nhiều giọng** NghiTTS. Mỗi giọng một `Entry` riêng (người dùng chốt
    /// 2026-10-07) nên "Tải tất cả" hiện đúng bấy nhiêu dòng tiến độ, mỗi dòng tiến độc lập.
    public func startNghiVoiceDownloads(_ voices: [Voice]) {
        guard !voices.isEmpty else { return }
        guard TTSManager.shared.nghiTTSClient != nil else {
            lastNotice = Notice(message: "Chưa sẵn sàng tải model NghiTTS — hãy mở lại app", isError: true)
            return
        }

        for voice in voices {
            let id = Target.nghiVoice(voice.id)
            let title = "Giọng \(voice.name)"
            guard tasks[id] == nil else { continue }
            upsert(Entry(id: id, title: title, message: "Bắt đầu tải…", fraction: 0))

            // Closure tiến độ phải `@Sendable` (nó chạy trong `prefetchModels`, ngoài MainActor) và
            // **không** capture `self` mà đi qua `shared` — cùng khuôn `RephoneticizeTask.start()`.
            let handler: @Sendable (String, Double) -> Void = { message, fraction in
                Task { @MainActor in
                    ModelDownloadCenter.shared.update(id: id, message: message, fraction: fraction)
                }
            }

            // Lấy client **trong** task, không capture từ ngoài: `NghiTTSClient` không `Sendable`, nên
            // capture nó qua ranh giới `Task` là chỗ dễ vỡ khi bật kiểm tra concurrency chặt hơn.
            tasks[id] = Task { [weak self] in
                var failure: String?
                if let client = TTSManager.shared.nghiTTSClient {
                    do {
                        _ = try await client.prefetchModels(voices: [voice.name], progressHandler: handler)
                    } catch {
                        failure = error.localizedDescription
                    }
                } else {
                    failure = "Chưa sẵn sàng tải model NghiTTS — hãy mở lại app"
                }
                guard let self else { return }
                self.finish(id: id, title: title, failure: failure)
            }
        }
    }

    // MARK: - Cập nhật nội bộ

    /// Thêm dòng mới hoặc ghi đè dòng cùng `id` tại **đúng vị trí cũ** — để thứ tự dòng không nhảy khi
    /// một lượt tải cập nhật tiến độ.
    func upsert(_ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    func update(id: String, message: String, fraction: Double) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].state.isRunning else { return }
        entries[index].message = message
        entries[index].fraction = min(1, max(0, fraction))
    }

    func finish(id: String, title: String, failure: String?) {
        tasks[id] = nil
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            // Dòng đã bị dọn giữa chừng: vẫn phải báo kết quả, nếu không người dùng mất thông tin.
            lastNotice = failure.map { Notice(message: "Tải \(title) thất bại: \($0)", isError: true) }
                ?? Notice(message: "Đã tải xong \(title)", isError: false)
            return
        }

        if let failure {
            entries[index].state = .failed(failure)
            entries[index].message = failure
            entries[index].fraction = nil
            lastNotice = Notice(message: "Tải \(title) thất bại: \(failure)", isError: true)
        } else {
            entries[index].state = .finished
            entries[index].message = "Đã tải xong"
            entries[index].fraction = 1
            lastNotice = Notice(message: "Đã tải xong \(title)", isError: false)
        }
        AppLogger.shared.log("⬇️ [ModelDownload] \(title): \(failure ?? "xong")")
    }
}
