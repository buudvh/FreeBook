import AVFoundation
import Foundation
import Observation

/// Trạng thái của **màn thử VieNeu Turbo (GGUF qua audio.cpp)** — bước thử để đo tốc độ / CPU / nhiệt của Turbo trên
/// máy thật trước khi quyết có nối vào Reader hay không. View chỉ vẽ; tải file, chạy model, phát tiếng đều ở đây.
///
/// **Singleton** vì lượt tải 188 MB không được mất tiến độ khi rời màn rồi vào lại (bài học của `ModelDownloadCenter`).
/// Runtime audio.cpp (registry / model / session) và bản đồ `sea_g2p.bin` thì nhả khi rời màn (`leaveScreen`), nạp lại
/// ở lượt chạy kế.
///
/// Phần chạy (đọc thử, đọc liên tục, phiên âm thanh) nằm ở `VieNeuTurboLab+Run.swift`; các thuộc tính mà file đó ghi
/// buộc phải để `internal` setter (Swift giới hạn `private(set)` theo file).
@MainActor
@Observable
final class VieNeuTurboLab {
    static let shared = VieNeuTurboLab()

    enum SoakEngine: String, CaseIterable, Identifiable {
        case turbo
        case nano

        var id: String { rawValue }

        var title: String {
            switch self {
            case .turbo: return "Turbo (audio.cpp)"
            case .nano: return "Nano (ONNX)"
            }
        }
    }

    // `let` không bị `@Observable` theo dõi — không cần `@ObservationIgnored`.
    let store: VieNeuTurboModelStore?
    let client: VieNeuTurboModelClient?
    let runtime = VieNeuTurboRuntime()
    /// `nil` khi không dựng được thư mục của Nano (nơi đặt `sea_g2p.bin`).
    let frontend: VieNeuTurboTextFrontend?
    let g2pDictionaryURL: URL?
    let soak = VieNeuTurboSoakRunner()

    // MARK: File

    private(set) var hasModel = false
    private(set) var hasG2PDictionary = false
    private(set) var bytesOnDisk: Int64 = 0
    private(set) var voices: [VieNeuTurboVoiceManifest.Voice] = []
    private(set) var isDownloading = false
    private(set) var downloadMessage = ""
    /// `nil` = không biết tổng (vòng xoay), còn lại 0…1.
    private(set) var downloadFraction: Double?
    private(set) var thermalState = ProcessInfo.processInfo.thermalState

    // MARK: Lựa chọn của người dùng

    var selectedVoiceId = ""
    var threadCount = 2
    var text = VieNeuTurboSampleText.short
    var longText = VieNeuTurboSampleText.long
    var soakEngine: SoakEngine = .turbo

    // MARK: Lượt chạy (ghi ở `+Run`)

    var isWorking = false
    var workingMessage = ""
    var statusMessage = ""
    var isError = false
    var lastReport = ""
    var lastAudioURL: URL?
    var hasSamplePlayer = false
    /// Đang nạp model / engine cho lượt đọc liên tục (chưa bắt đầu phát).
    var isPreparingSoak = false
    var isRuntimeLoaded = false
    @ObservationIgnored var player: AVAudioPlayer?
    @ObservationIgnored var oneShotTask: Task<Void, Never>?
    @ObservationIgnored var runGeneration = 0
    @ObservationIgnored var releaseTask: Task<Void, Never>?
    @ObservationIgnored var didActivateAudioSession = false
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?

    static let threadChoices = [1, 2, 3, 4]

    private init() {
        let store = try? VieNeuTurboModelStore()
        self.store = store
        self.client = store.map { VieNeuTurboModelClient(store: $0) }
        let g2pURL = (try? VieNeuModelStore())?.url(for: "sea_g2p.bin")
        self.g2pDictionaryURL = g2pURL
        self.frontend = g2pURL.map { VieNeuTurboTextFrontend(dictionaryURL: $0) }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            Task { @MainActor in
                self?.thermalState = state
                AppLogger.shared.log("🎙️ [VieNeuTurbo] Nhiệt đổi: \(VieNeuTurboSoakStats.thermalName(state))")
            }
        }
        refreshStatus()
    }

    // MARK: - Trạng thái

    /// Đủ để chạy Turbo: model đúng dung lượng + bộ phiên âm + danh sách giọng. File giọng của từng giọng tải lúc chạy.
    var isTurboReady: Bool {
        hasModel && hasG2PDictionary && !voices.isEmpty
    }

    var isBusy: Bool {
        isDownloading || isWorking || soak.isRunning
    }

    var selectedVoice: VieNeuTurboVoiceManifest.Voice? {
        voices.first { $0.id == selectedVoiceId }
    }

    func refreshStatus() {
        hasModel = store?.hasModel ?? false
        hasG2PDictionary = frontend?.hasDictionary ?? false
        bytesOnDisk = store?.totalBytes ?? 0
        thermalState = ProcessInfo.processInfo.thermalState
        reloadVoices()
    }

    private func reloadVoices() {
        guard let store, store.hasManifest,
              let manifest = try? VieNeuTurboVoiceManifest.load(from: store.manifestURL) else {
            voices = []
            return
        }
        voices = manifest.voices
        if !voices.contains(where: { $0.id == selectedVoiceId }) {
            selectedVoiceId = manifest.defaultVoice?.id ?? ""
        }
    }

    // MARK: - Tải / xoá

    /// Tải những gì còn thiếu: `sea_g2p.bin` (nếu máy chưa có Nano) → manifest giọng → GGUF 188 MB → giọng đang chọn.
    func downloadAll() {
        guard !isDownloading, let client, let store else { return }
        isDownloading = true
        isError = false
        statusMessage = ""
        let g2pURL = g2pDictionaryURL
        Task { [weak self] in
            guard let self else { return }
            do {
                if let g2pURL, !FileManager.default.fileExists(atPath: g2pURL.path) {
                    setDownload("Đang tải sea_g2p.bin (bộ phiên âm, ~63 MB)…", fraction: 0)
                    try await VieNeuTurboModelClient.downloadG2PDictionary(to: g2pURL, progress: progressHandler())
                }
                setDownload("Đang tải danh sách giọng…", fraction: nil)
                try await client.downloadManifest()
                reloadVoices()
                if !store.hasModel {
                    setDownload("Đang tải model GGUF q8_0 (188 MB)…", fraction: 0)
                    try await client.downloadModel(progress: progressHandler())
                }
                let voiceId = selectedVoiceId.isEmpty ? VieNeuTurboModelStore.fallbackVoiceId : selectedVoiceId
                setDownload("Đang tải giọng \(voiceId)…", fraction: nil)
                try await client.downloadVoice(voiceId: voiceId)
                statusMessage = "Đã tải xong model Turbo."
            } catch {
                isError = true
                statusMessage = "Tải thất bại: \(error.localizedDescription)"
                AppLogger.shared.log("❌ [VieNeuTurbo] Tải model lỗi: \(error.localizedDescription)")
            }
            isDownloading = false
            downloadFraction = nil
            downloadMessage = ""
            refreshStatus()
        }
    }

    /// Xoá model + manifest + giọng của Turbo. `sea_g2p.bin` giữ nguyên (engine Nano dùng chung).
    func deleteModel() {
        guard !isBusy, let store else { return }
        stopSample()
        Task { [weak self] in
            guard let self else { return }
            await runtime.release()
            isRuntimeLoaded = false
            do {
                try store.deleteAll()
                isError = false
                statusMessage = "Đã xoá model Turbo (giữ sea_g2p.bin của Nano)."
                lastReport = ""
            } catch {
                isError = true
                statusMessage = "Xoá thất bại: \(error.localizedDescription)"
            }
            refreshStatus()
        }
    }

    /// Giọng chưa có trên máy ⇒ tải cặp file của nó (vài KB) trước khi chạy.
    func ensureVoice(_ voiceId: String) async throws {
        guard let store, let client else { throw VieNeuTurboRuntime.RuntimeError.notLoaded }
        guard !store.hasVoice(voiceId: voiceId) else { return }
        workingMessage = "Đang tải giọng \(voiceId)…"
        try await client.downloadVoice(voiceId: voiceId)
        bytesOnDisk = store.totalBytes
    }

    private func setDownload(_ message: String, fraction: Double?) {
        downloadMessage = message
        downloadFraction = fraction
    }

    /// Tiến độ theo byte từ luồng mạng ⇒ nhảy về MainActor.
    private func progressHandler() -> VieNeuTurboModelClient.ByteProgress {
        { [weak self] completed, total in
            Task { @MainActor in
                guard let self, self.isDownloading, total > 0 else { return }
                self.downloadFraction = min(1, Double(completed) / Double(total))
            }
        }
    }
}
