import AVFoundation
import Foundation
import Observation

/// **"Đo tự động ORT ↔ Core ML"** của màn thử VieNeu (P1b): bấm một lần, máy tự làm hết —
///
/// 1. tải gói `nano-coreml/` nếu thiếu, **chuẩn bị Core ML** (biên dịch, nạp lại, đo RAM, tự kiểm golden —
///    `VieNeuCoreMLPreparer`);
/// 2. ba lượt **Nano ORT → Nano Core ML → Nano ORT** (A-B-A: lượt sau bắt đầu khi máy còn ấm hơn, chạy ORT hai đầu để
///    thấy thứ tự có lệch kết quả không). Trước **mỗi** lượt chờ máy mát (`nominal`) giữ liền 10 phút; mỗi lượt đọc liên
///    tục cùng văn bản (giọng Mai Anh, tổng hợp 1,15, phát 1,5× — anh Bửu chọn) tới khi lên "nóng" thì đọc thêm 5 đoạn
///    rồi dừng; "rất nóng" dừng ngay; tối đa 15 phút;
/// 3. ghi **một** file báo cáo (cập nhật sau mỗi bước, nên dừng giữa chừng vẫn còn số).
///
/// Khoá màn / rời màn thử vẫn chạy: phát vòng lặng giữ app sống lúc chờ (app có background audio). Có TTS / nhạc / phim
/// khác phát giữa chừng ⇒ dừng cả lượt đo ("bị gián đoạn"), không ra số sai. Lượt đọc dùng `VieNeuTurboLab.soak` (màn
/// thử hiện số từng phút như "Đọc liên tục").
@MainActor
@Observable
final class VieNeuAutoThermalRun {
    enum Engine: String, Sendable {
        case ort
        case coreML

        var title: String {
            switch self {
            case .ort: return "Nano ORT CPU (như trình đọc)"
            case .coreML: return "Nano Core ML CPU-only (fp32)"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case downloading
        case preparing
        case settling(Int)
        case running(Int)
        case finished
        case stopped
        case failed
    }

    enum RunError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    static let voiceName = "Mai Anh"
    static let synthesisSpeed = 1.15
    static let playbackRate: Float = 1.5
    static let legPlan: [Engine] = [.ort, .coreML, .ort]
    /// Máy phải giữ `nominal` liền chừng này trước mỗi lượt (pin + vỏ còn ấm sau "nóng" dù cảm biến đã về mát).
    static let settleHoldSeconds: TimeInterval = 600
    /// Chờ quá chừng này mà vẫn chưa đủ ⇒ chạy luôn, ghi chú vào báo cáo.
    static let settleMaxSeconds: TimeInterval = 2_700
    static let legMaxSeconds: TimeInterval = 900
    static let chunksAfterSerious = 5

    let package: VieNeuCoreMLPackage?

    private(set) var phase: Phase = .idle
    var statusLine = ""
    var errorMessage: String?
    var downloadFraction: Double?
    var prepareLines: [String] = []
    var coreMLPassed = false
    var legs: [VieNeuAutoThermalLeg] = []
    /// Lượt đang chạy — ghi vào báo cáo mỗi phút, để app bị tắt giữa lượt vẫn còn số.
    var currentLeg: VieNeuAutoThermalLeg?
    var voiceUsed = ""
    var preloadNote = ""
    private(set) var savedReportURL: URL?
    private(set) var packageBytes: Int64 = 0
    private(set) var cacheBytes: Int64 = 0
    @ObservationIgnored var startedAt = Date()
    @ObservationIgnored var backend: VieNeuCoreMLFlowBackend?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var keepAlivePlayer: AVAudioPlayer?

    init() {
        package = try? VieNeuCoreMLPackage()
        refresh()
    }

    var isActive: Bool {
        switch phase {
        case .downloading, .preparing, .settling, .running: return true
        case .idle, .finished, .stopped, .failed: return false
        }
    }

    var hasReport: Bool { savedReportURL != nil }

    func refresh() {
        packageBytes = package?.packageBytes ?? 0
        cacheBytes = package?.cacheBytes ?? 0
    }

    // MARK: - Điều khiển

    func start(lab: VieNeuTurboLab) {
        guard !isActive, let package else { return }
        phase = .downloading
        statusLine = "Đang chuẩn bị…"
        errorMessage = nil
        downloadFraction = nil
        prepareLines = []
        coreMLPassed = false
        legs = []
        currentLeg = nil
        preloadNote = ""
        savedReportURL = nil
        startedAt = Date()
        runTask = Task { [weak self] in
            await self?.run(lab: lab, package: package)
        }
    }

    func stop() {
        guard isActive else { return }
        statusLine = "Đang dừng…"
        runTask?.cancel()
    }

    /// Xoá gói + cache biên dịch + báo cáo.
    func deleteData() {
        guard !isActive, let package else { return }
        backend?.releaseSessions()
        backend = nil
        try? package.deleteAll()
        savedReportURL = nil
        refresh()
    }

    func setPhase(_ newPhase: Phase) {
        phase = newPhase
    }

    // MARK: - Lượt chạy

    private func run(lab: VieNeuTurboLab, package: VieNeuCoreMLPackage) async {
        do {
            guard let service = VieNeuTTSService.shared, service.modelStore.isReady else {
                throw RunError.message("Chưa tải model VieNeu Nano — tải ở màn Cài đặt VieNeu TTS.")
            }
            await lab.prepareForAutoRun()
            startKeepAlive()
            let manifest = try await ensurePackage(package)
            try checkDiskSpace(package: package, manifest: manifest)
            let voice = Self.resolveVoice(service: service)
            voiceUsed = voice
            statusLine = "Đang nạp engine Nano (giọng \(voice))…"
            try await service.prepare(voice: voice)
            // Ghim `fast` (8 bước, sway −1) cho cả 3 lượt: Core ML nhanh sẽ làm bộ tự thích nghi nâng lên `high`.
            await service.setLabModeOverride(.fast)

            setPhase(.preparing)
            let backend = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: 64)
            self.backend = backend
            let progress: @Sendable (String) -> Void = { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .preparing else { return }
                    self.statusLine = line
                }
            }
            let report = try await Task.detached(priority: .userInitiated) {
                try VieNeuCoreMLPreparer.prepare(backend: backend, progress: progress)
            }.value
            prepareLines = report.lines
            coreMLPassed = report.passed
            backend.releaseSessions() // nhả RAM; lượt Core ML nạp lại (ấm) khi cần
            refresh()
            saveReport()

            for (index, engine) in Self.legPlan.enumerated() {
                try Task.checkCancellation()
                if engine == .coreML, !coreMLPassed {
                    legs.append(VieNeuAutoThermalLeg(index: index, engine: engine, skippedReason: "Core ML không qua tự kiểm"))
                    continue
                }
                if engine == .coreML {
                    try await preloadCoreML()
                }
                setPhase(.settling(index))
                let settle = try await settle(beforeLeg: index)
                setPhase(.running(index))
                let leg = try await runLeg(
                    index: index, engine: engine, settle: settle, lab: lab, service: service, voice: voice
                )
                legs.append(leg)
                if engine == .coreML {
                    backend?.releaseSessions() // lượt ORT sau bắt đầu cùng trạng thái RAM như lượt đầu
                }
                saveReport()
            }
            setPhase(.finished)
            statusLine = "Xong 3 lượt — chia sẻ file báo cáo."
        } catch is CancellationError {
            setPhase(.stopped)
            statusLine = "Đã dừng giữa chừng — báo cáo giữ phần đã đo."
        } catch {
            setPhase(.failed)
            errorMessage = error.localizedDescription
            statusLine = "Dừng vì lỗi."
            AppLogger.shared.log("❌ [VieNeuAutoRun] \(error.localizedDescription) — \(ProcessMemoryProbe.snapshot().summary)")
        }
        lab.soak.stop(reason: "kết thúc đo tự động")
        await VieNeuTTSService.shared?.setLabModeOverride(nil)
        stopKeepAlive()
        backend?.releaseSessions()
        refresh()
        saveReport()
        AppLogger.shared.log("🎙️ [VieNeuAutoRun] Kết thúc: \(statusLine)")
    }

    private func ensurePackage(_ package: VieNeuCoreMLPackage) async throws -> VieNeuCoreMLPackage.Manifest {
        if !package.isComplete {
            setPhase(.downloading)
            statusLine = "Đang tải gói Core ML…"
            try await package.download { [weak self] name, done, total in
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .downloading else { return }
                    self.downloadFraction = total > 0 ? min(1, Double(done) / Double(total)) : nil
                    self.statusLine = "Đang tải \(name)…"
                }
            }
            downloadFraction = nil
            refresh()
        }
        guard let manifest = package.manifest, package.isComplete else {
            throw RunError.message("Gói Core ML tải về chưa đủ — thử lại.")
        }
        return manifest
    }

    /// Nạp sẵn session Core ML (từ bản biên dịch) **trước** lúc chờ mát — nhiệt / CPU của bước nạp tan trong 10 phút chờ.
    private func preloadCoreML() async throws {
        guard let backend else { return }
        statusLine = "Nạp sẵn session Core ML (trước lúc chờ mát)…"
        let ms = try await Task.detached(priority: .userInitiated) { try backend.preload() }.value
        let cap = backend.currentSessionCap
        let total = backend.preloadOrder.count
        var note = String(format: "nạp sẵn %ld/%ld session trong %.1f s · ", min(cap, total), total, ms / 1_000)
        note += ProcessMemoryProbe.snapshot().summary
        if cap < total {
            note += " · ⚠️ RAM chỉ đủ giữ \(cap) session — bucket hiếm phải nạp lại giữa lượt"
        }
        preloadNote = note
    }

    /// Cache biên dịch cần thêm vài trăm MB; thiếu chỗ thì báo trước thay vì để Core ML lỗi giữa chừng.
    private func checkDiskSpace(package: VieNeuCoreMLPackage, manifest: VieNeuCoreMLPackage.Manifest) throws {
        let needed = VieNeuCoreMLPreparer.requiredCacheMB(manifest) - Double(package.cacheBytes) / 1_048_576 + 300
        let values = try? package.rootURL.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        let availableMB = Double(available) / 1_048_576
        if availableMB < needed {
            throw RunError.message(String(format: "Máy còn trống %.0f MB, cần khoảng %.0f MB cho bản biên dịch Core ML.",
                                          availableMB, needed))
        }
    }

    /// "Mai Anh" nếu có trong danh sách giọng của Nano, không thì giọng mặc định (ghi rõ trong báo cáo).
    static func resolveVoice(service: VieNeuTTSService) -> String {
        let names = (try? service.availableVoices().map(\.name)) ?? []
        if names.contains(voiceName) { return voiceName }
        return service.defaultVoiceName ?? names.first ?? voiceName
    }

    // MARK: - Giữ app sống

    func startKeepAlive() {
        if keepAlivePlayer == nil {
            let silence = [Float](repeating: 0, count: 24_000)
            keepAlivePlayer = try? AVAudioPlayer(data: WAVEncoder.encodePCM16(samples: silence, sampleRate: 24_000))
            keepAlivePlayer?.numberOfLoops = -1
            keepAlivePlayer?.volume = 0
        }
        keepAlivePlayer?.play()
    }

    func stopKeepAlive() {
        keepAlivePlayer?.stop()
    }

    // MARK: - Báo cáo

    func saveReport() {
        guard let package else { return }
        do {
            try FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
            let url = savedReportURL ?? package.resultsURL.appendingPathComponent(Self.reportFileName(startedAt))
            try Data(reportText().utf8).write(to: url, options: .atomic)
            savedReportURL = url
        } catch {
            AppLogger.shared.log("❌ [VieNeuAutoRun] Không ghi được báo cáo: \(error.localizedDescription)")
        }
    }
}
