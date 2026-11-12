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

    /// Mức ưu tiên luồng của lượt đo trong "Đọc liên tục" (Nano 1.3.878, Turbo 1.3.883). iPhone chỉ có 2 lõi hiệu năng;
    /// QoS thấp bị xếp sang lõi tiết kiệm. Đo 1.3.882–884: lõi tiết kiệm chậm gấp đôi **và** tốn CPU hơn (nóng hơn) cho
    /// cả hai engine ⇒ trình đọc Turbo lên `userInitiated` (1.3.885). Trình đọc Nano không ép mức: log trên máy cho thấy
    /// nó vốn chạy nhanh như `userInitiated` (ép mức ở 1.3.884 không đổi gì, gỡ ở 1.3.886).
    enum SoakQoS: String, CaseIterable, Identifiable {
        case utility
        case userInitiated

        var id: String { rawValue }

        var priority: TaskPriority {
            switch self {
            case .utility: return .utility
            case .userInitiated: return .userInitiated
            }
        }

        /// Mức cho hàng đợi của `VieNeuTurboRuntime` (lượt Turbo).
        var dispatchClass: DispatchQoS.QoSClass {
            switch self {
            case .utility: return .utility
            case .userInitiated: return .userInitiated
            }
        }
    }

    // `let` không bị `@Observable` theo dõi — không cần `@ObservationIgnored`.
    let store: VieNeuTurboModelStore?
    let client: VieNeuTurboModelClient?
    /// Dùng chung với trình đọc (`VieNeuTurboTTSService`) — một model 188 MB trong RAM, không phải hai.
    let runtime = VieNeuTurboRuntime.shared
    /// `nil` khi không dựng được thư mục của Nano (nơi đặt `sea_g2p.bin`). Dùng chung với trình đọc như `runtime`.
    let frontend: VieNeuTurboTextFrontend?
    let g2pDictionaryURL: URL?
    let soak = VieNeuTurboSoakRunner()
    /// Phép thử P1 "So EP cho Nano" (Core ML / ANE / XNNPACK) — `VieNeuTurboLab+Nano.startEPProbe`.
    let epProbe = VieNeuNanoEPProbe()
    /// "Đo tự động ORT ↔ Core ML" (P1b) — dùng chung `soak` cho các lượt đọc.
    let autoRun = VieNeuAutoThermalRun()
    /// Mục "Tạo giọng Turbo từ file" (1.3.893).
    let cloneTrial = VieNeuTurboCloneTrial()

    // MARK: File

    private(set) var hasModel = false
    private(set) var hasG2PDictionary = false
    private(set) var bytesOnDisk: Int64 = 0
    private(set) var voices: [VieNeuTurboVoiceManifest.Voice] = []
    private(set) var defaultVoiceId: String?
    private(set) var isDownloading = false
    private(set) var downloadMessage = ""
    /// `nil` = không biết tổng (vòng xoay), còn lại 0…1.
    private(set) var downloadFraction: Double?
    /// Byte của file đang tải (`0 / 0` khi chưa biết) — hàng tải ở Cài đặt TTS hiện "74 / 188 MB".
    private(set) var downloadedBytes: Int64 = 0
    private(set) var downloadTotalBytes: Int64 = 0
    /// Lỗi của lượt tải gần nhất (riêng, không lẫn lỗi đọc thử) — hàng tải ở Cài đặt TTS hiện dưới nút.
    private(set) var downloadError: String?
    private(set) var thermalState = ProcessInfo.processInfo.thermalState

    // MARK: Lựa chọn của người dùng

    var selectedVoiceId = ""
    var threadCount = 2
    var text = VieNeuTurboSampleText.short
    var longText = VieNeuTurboSampleText.long
    var soakEngine: SoakEngine = .turbo
    /// Số luồng ORT và QoS cho lượt Nano — chỉ áp trong lúc đo, **không** ghi vào cài đặt (`+Nano`).
    var nanoThreadCount = Int(VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard))
    var nanoQoS: SoakQoS = .utility
    /// QoS cho lượt Turbo của "Đọc liên tục" (1.3.883) — chỉ áp trong lúc đo. Mặc định = mức của trình đọc
    /// (`VieNeuTurboTTSService.readerQoS`, 1.3.885); chọn `utility` để so với lõi tiết kiệm.
    var turboQoS: SoakQoS = .userInitiated

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
    /// Lượt trả engine Nano về cấu hình người dùng (`endNanoOverride`). Lượt chạy mới phải chờ nó xong, kẻo nó nhả Turbo
    /// / xoá ghi đè luồng giữa chừng lượt vừa bắt đầu.
    @ObservationIgnored var nanoRestoreTask: Task<Void, Never>?
    @ObservationIgnored var didActivateAudioSession = false
    /// Engine Nano đang mang số luồng ghi đè của màn thử — phải trả lại khi dừng / rời màn (`endNanoOverride`).
    @ObservationIgnored var isNanoOverrideActive = false
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?

    static let threadChoices = [1, 2, 3, 4]
    /// Nano: 1 luồng đã bỏ ở 1.3.509 (CPU-time như 2 luồng mà chậm gấp đôi).
    static let nanoThreadChoices = [2, 3, 4]

    private init() {
        let store = try? VieNeuTurboModelStore()
        self.store = store
        self.client = store.map { VieNeuTurboModelClient(store: $0) }
        self.g2pDictionaryURL = (try? VieNeuModelStore())?.url(for: "sea_g2p.bin")
        self.frontend = VieNeuTurboTextFrontend.shared
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

    /// Gồm cả lượt tạo giọng (1.3.893): nó dùng chung runtime audio.cpp và model, không cho đọc thử / xoá model chồng lên.
    var isBusy: Bool {
        isDownloading || isWorking || soak.isRunning || epProbe.isRunning || autoRun.isActive || cloneTrial.isRunning
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
        epProbe.refresh()
        autoRun.refresh()
        cloneTrial.refreshReadiness()
    }

    private func reloadVoices() {
        guard let store, store.hasManifest,
              let manifest = try? VieNeuTurboVoiceManifest.load(from: store.manifestURL) else {
            voices = []
            defaultVoiceId = nil
            return
        }
        voices = manifest.voices
        defaultVoiceId = manifest.defaultVoice?.id
        // Giọng tự tạo (1.3.893) không nằm trong manifest: giữ lựa chọn khi cặp file của nó còn trên máy.
        let keepsCustom = VieNeuTurboModelStore.isCustomVoiceId(selectedVoiceId) && store.hasVoice(voiceId: selectedVoiceId)
        if !keepsCustom, !voices.contains(where: { $0.id == selectedVoiceId }) {
            selectedVoiceId = manifest.defaultVoice?.id ?? ""
        }
    }

    // MARK: - Chia sẻ kết quả

    /// Thân file `.txt` của nút chia sẻ (`VieNeuTurboReportFile` thêm phần đầu: app, máy, giờ).
    func reportText(for kind: VieNeuTurboReportFile.Kind) -> String {
        switch kind {
        case .sample:
            return [statusMessage, lastReport].filter { !$0.isEmpty }.joined(separator: "\n\n")
        case .soak:
            return soak.reportText()
        case .epProbe:
            return epProbe.reportText()
        case .clone:
            return cloneTrial.reportFileText()
        }
    }

    // MARK: - Tải / xoá

    /// Tải những gì còn thiếu: `sea_g2p.bin` (nếu máy chưa có Nano) → manifest giọng → GGUF 188 MB → giọng đang chọn.
    func downloadAll() {
        guard !isDownloading, let client, let store else { return }
        isDownloading = true
        isError = false
        statusMessage = ""
        downloadError = nil
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
                downloadError = statusMessage
                AppLogger.shared.log("❌ [VieNeuTurbo] Tải model lỗi: \(error.localizedDescription)")
            }
            isDownloading = false
            downloadFraction = nil
            downloadMessage = ""
            downloadedBytes = 0
            downloadTotalBytes = 0
            refreshStatus()
        }
    }

    /// Xoá model + manifest + giọng của Turbo. `sea_g2p.bin` giữ nguyên (engine Nano dùng chung).
    func deleteModel() {
        guard !isBusy, let store else { return }
        stopSample()
        // Trình đọc đang đọc bằng Turbo (cùng runtime) ⇒ dừng trước khi nhả runtime và xoá file, kẻo đoạn kế nạp lại
        // đúng file vừa xoá rồi lỗi giữa chừng.
        let tts = TTSManager.shared
        if tts.tool == "vieneu", VieNeuModelChoice.current == .turbo, tts.isPlaying || tts.showFloatingWidget {
            AppLogger.shared.log("⏹️ [VieNeuTurbo] Dừng TTS trước khi xoá model Turbo (trình đọc đang dùng Turbo)")
            tts.stop()
        }
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
            // Trình đọc đang chọn Turbo ⇒ về Nano (không để tải lại model sau này tự bật lại Turbo), nạp lại giọng / engine.
            if VieNeuModelChoice.stored == .turbo {
                VieNeuModelChoice.store(.nano)
                let tts = TTSManager.shared
                if tts.tool == "vieneu" {
                    // Máy chưa có model Nano thì "vieneu" không còn engine nào đọc được ⇒ về Siri (mặc định của app,
                    // luôn có) thay vì để trình đọc trỏ vào engine thiếu model.
                    let nanoReady = VieNeuTTSService.shared?.modelStore.isReady == true
                    tts.tool = nanoReady ? "vieneu" : "system"
                }
            }
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
        downloadedBytes = 0
        downloadTotalBytes = 0
    }

    /// Tiến độ theo byte từ luồng mạng ⇒ nhảy về MainActor.
    private func progressHandler() -> VieNeuTurboModelClient.ByteProgress {
        { [weak self] completed, total in
            Task { @MainActor in
                guard let self, self.isDownloading, total > 0 else { return }
                self.downloadFraction = min(1, Double(completed) / Double(total))
                self.downloadedBytes = completed
                self.downloadTotalBytes = total
            }
        }
    }
}
