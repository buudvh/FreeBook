import Combine
import Foundation

/// Trung tâm tiến độ **tải model TTS** cho cả app: nguồn sự thật duy nhất cho ba đường tải
/// (NghiTTS từng giọng, VieNeu 8 file lõi, VieNeu gói graph nhân bản).
///
/// ## Vì sao phải là singleton, không phải `@State` của View
/// Trước 1.3.472, mỗi màn tự giữ tiến độ trong `@State` (`TTSModelManagerView.downloadingStatus`,
/// `VieNeuTTSTestView.downloadProgress`, `VieNeuVoiceLibraryView.downloadProgress`). `Task` tải **không**
/// bị huỷ khi rời màn (không chỗ nào dùng `.task {}`), nên rời màn rồi vào lại thì **tải vẫn chạy mà thanh
/// tiến độ đã mất**. Chuyển trạng thái về đây thì màn chỉ còn là người vẽ.
///
/// ## Center sở hữu `Task`
/// `Task` nằm trong `tasks` của center, không nằm ở View: nhờ vậy lượt tải độc lập hoàn toàn với vòng đời
/// màn, và `guard tasks[id] == nil` chặn được hai lượt tải trùng cho cùng một đích. Đánh đổi đã chọn:
/// **không** có nút huỷ, vì `NghiTTSClient.prefetchModels` và `VieNeuModelClient.prefetch` đều không nhận
/// cancellation — thêm nút huỷ giả sẽ nói dối người dùng.
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

    /// Khoá của ba đích tải. `nghiVoice(id:)` ghép tiền tố nên tra theo giọng luôn tất định.
    public enum Target {
        public static let nghiPrefix = "nghi-"
        public static let vieNeuModel = "vieNeu-model"
        public static let vieNeuClone = "vieNeu-clone"

        public static func nghiVoice(_ voiceId: String) -> String { nghiPrefix + voiceId }
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

    /// Mới nhất ở cuối; View vẽ theo thứ tự này.
    @Published public private(set) var entries: [Entry] = []
    @Published public private(set) var lastNotice: Notice?

    private var tasks: [String: Task<Void, Never>] = [:]

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

    // MARK: - VieNeu (model lõi + gói graph nhân bản)

    /// Tải 8 file lõi của VieNeu-TTS v3 Nano (~343 MB).
    public func startVieNeuModel() {
        let id = Target.vieNeuModel
        let title = "Model VieNeu"
        guard tasks[id] == nil else { return }
        upsert(Entry(id: id, title: title, message: "Bắt đầu tải…", fraction: 0))

        let handler: @Sendable (String, Double) -> Void = { message, fraction in
            Task { @MainActor in
                ModelDownloadCenter.shared.update(id: id, message: message, fraction: fraction)
            }
        }

        tasks[id] = Task { [weak self] in
            var failure: String?
            if let service = VieNeuTTSService.shared {
                do {
                    _ = try await VieNeuModelClient(store: service.modelStore).prefetch(progressHandler: handler)
                } catch {
                    failure = error.localizedDescription
                }
            } else {
                failure = "Không dựng được kho model VieNeu (thư mục Application Support không ghi được)."
            }
            guard let self else { return }
            self.finish(id: id, title: title, failure: failure)
        }
    }

    /// Tải gói graph **nhân bản giọng** của VieNeu (3 file, ~91 MB, tuỳ chọn).
    public func startVieNeuCloneGraphs() {
        let id = Target.vieNeuClone
        let title = "Gói graph nhân bản VieNeu"
        guard tasks[id] == nil else { return }
        upsert(Entry(id: id, title: title, message: "Bắt đầu tải…", fraction: 0))

        let handler: @Sendable (String, Double) -> Void = { message, fraction in
            Task { @MainActor in
                ModelDownloadCenter.shared.update(id: id, message: message, fraction: fraction)
            }
        }

        tasks[id] = Task { [weak self] in
            var failure: String?
            if let service = VieNeuTTSService.shared {
                do {
                    _ = try await VieNeuModelClient(store: service.modelStore)
                        .prefetchCloneGraphs(progressHandler: handler)
                } catch {
                    failure = error.localizedDescription
                }
            } else {
                failure = "Không dựng được kho model VieNeu (thư mục Application Support không ghi được)."
            }
            guard let self else { return }
            self.finish(id: id, title: title, failure: failure)
        }
    }

    // MARK: - Cập nhật nội bộ

    /// Thêm dòng mới hoặc ghi đè dòng cùng `id` tại **đúng vị trí cũ** — để thứ tự dòng không nhảy khi
    /// một lượt tải cập nhật tiến độ.
    private func upsert(_ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    private func update(id: String, message: String, fraction: Double) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].state.isRunning else { return }
        entries[index].message = message
        entries[index].fraction = min(1, max(0, fraction))
    }

    private func finish(id: String, title: String, failure: String?) {
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
