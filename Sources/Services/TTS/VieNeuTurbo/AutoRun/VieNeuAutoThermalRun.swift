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
    enum Engine: String, Sendable, Codable {
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
    /// Lượt đo trước dừng đột ngột (app bị giết) ⇒ vài dòng cuối của nhật ký từng bước; `nil` khi lượt trước kết thúc êm.
    private(set) var abruptNote: String?
    /// Lượt đo trước chưa xong mà đã qua bước chuẩn bị ⇒ chỉ số lượt sẽ chạy tiếp (0-based); `nil` = không chạy tiếp được.
    private(set) var resumeNextLeg: Int?
    var resumeNotes: [String] = []
    @ObservationIgnored var startedAt = Date()
    @ObservationIgnored var backend: VieNeuCoreMLFlowBackend?
    /// Tiến độ lưu xuống máy (`VieNeuAutoRunProgress`) — ghi sau mỗi bước để Chạy tiếp.
    @ObservationIgnored var progress: VieNeuAutoRunProgress?
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
        abruptNote = isActive ? nil : trailURL.flatMap { VieNeuAutoRunTrail.abruptEnding($0) }
        resumeNextLeg = isActive ? nil : Self.resumableLeg(package: package)
    }

    /// File nhật ký từng bước (`VieNeuAutoRunTrail`) — có ⇒ chia sẻ được kể cả khi lượt đo chết giữa chừng.
    var trailURL: URL? {
        package.map { VieNeuAutoRunTrail.url(in: $0) }
    }

    var hasTrail: Bool {
        trailURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Ghi một bước vào nhật ký (ép xuống đĩa), kèm app đang mở màn hay chạy nền / khoá màn.
    func trail(_ step: String) {
        guard let trailURL else { return }
        VieNeuAutoRunTrail.append(trailURL, "\(step) · \(Self.appStateName())")
    }

    // MARK: - Điều khiển

    /// `resume`: chạy tiếp lượt đo trước (bỏ bước tải + biên dịch, chạy từ lượt chưa xong) — xem `+Resume`.
    func start(lab: VieNeuTurboLab, resume: Bool = false) {
        guard !isActive, let package else { return }
        phase = .downloading
        statusLine = "Đang chuẩn bị…"
        errorMessage = nil
        downloadFraction = nil
        currentLeg = nil
        preloadNote = ""
        savedReportURL = nil
        let previous = abruptNote
        abruptNote = nil
        resumeNextLeg = nil
        let resuming = resume && restoreForResume(package: package)
        if !resuming {
            prepareLines = []
            coreMLPassed = false
            legs = []
            resumeNotes = []
            startedAt = Date()
            progress = nil
            VieNeuAutoRunProgress.delete(at: VieNeuAutoRunProgress.url(in: package))
            // Lượt trước chết giữa chừng ⇒ giữ dòng cuối của nó vào nhật ký mới trước khi ghi đè.
            VieNeuAutoRunTrail.reset(VieNeuAutoRunTrail.url(in: package), header: VieNeuTurboReportFile.header()
                + (previous.map { "\nLượt trước dừng đột ngột ở:\n\($0)" } ?? ""))
            trail("bắt đầu đo tự động")
        }
        runTask = Task { [weak self] in
            await self?.run(lab: lab, package: package, resuming: resuming)
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
        try? package.deleteAll() // gồm cả tiến độ (Results/) ⇒ hết Chạy tiếp
        progress = nil
        savedReportURL = nil
        refresh()
    }

    func setPhase(_ newPhase: Phase) {
        phase = newPhase
    }

    // MARK: - Lượt chạy

    private func run(lab: VieNeuTurboLab, package: VieNeuCoreMLPackage, resuming: Bool) async {
        do {
            guard let service = VieNeuTTSService.shared, service.modelStore.isReady else {
                throw RunError.message("Chưa tải model VieNeu Nano — tải ở màn Cài đặt VieNeu TTS.")
            }
            await lab.prepareForAutoRun()
            startKeepAlive()
            trail("đã dừng TTS / nhả Turbo")
            let manifest = try await ensurePackage(package)
            try checkDiskSpace(package: package, manifest: manifest)
            let voice = resuming ? voiceUsed : Self.resolveVoice(service: service)
            voiceUsed = voice
            // Ghim `fast` (8 bước, sway −1) cho cả 3 lượt: Core ML nhanh sẽ làm bộ tự thích nghi nâng lên `high`.
            await service.setLabModeOverride(.fast)

            if resuming {
                try await prepareForResume(package: package, manifest: manifest, service: service, voice: voice)
            } else {
                try await prepareFresh(package: package, manifest: manifest, service: service, voice: voice)
            }

            for (index, engine) in Self.legPlan.enumerated() where !completedLegIndices.contains(index) {
                try Task.checkCancellation()
                if engine == .coreML, !coreMLPassed {
                    legs.append(VieNeuAutoThermalLeg(index: index, engine: engine, skippedReason: "Core ML không qua tự kiểm"))
                    continue
                }
                setPhase(.settling(index))
                trail("chờ mát trước lượt \(index + 1) (\(engine.title))")
                let settle = try await settle(beforeLeg: index)
                setPhase(.running(index))
                let sessions = engine == .coreML ? " · giữ \(backend?.loadedSessionCount ?? 0) session Core ML" : ""
                trail("bắt đầu lượt \(index + 1) (\(engine.title))\(sessions)")
                let leg = try await runLeg(
                    index: index, engine: engine, settle: settle, lab: lab, service: service, voice: voice
                )
                legs.append(leg)
                if engine == .coreML {
                    backend?.releaseSessions() // lượt ORT sau bắt đầu cùng trạng thái RAM như lượt đầu
                }
                progress?.legs = legs
                progress?.inProgressLeg = nil
                saveProgress()
                saveReport()
                trail("xong lượt \(index + 1): \(leg.endReason)")
            }
            setPhase(.finished)
            statusLine = "Xong 3 lượt — chia sẻ file báo cáo."
        } catch is CancellationError {
            setPhase(.stopped)
            statusLine = "Đã dừng giữa chừng — bấm Chạy tiếp để đo tiếp, báo cáo giữ phần đã đo."
        } catch {
            setPhase(.failed)
            errorMessage = error.localizedDescription
            statusLine = "Dừng vì lỗi — bấm Chạy tiếp để đo tiếp."
            AppLogger.shared.log("❌ [VieNeuAutoRun] \(error.localizedDescription) — \(ProcessMemoryProbe.snapshot().summary)")
        }
        lab.soak.stop(reason: "kết thúc đo tự động")
        await VieNeuTTSService.shared?.setLabModeOverride(nil)
        stopKeepAlive()
        backend?.releaseSessions()
        progress?.legs = legs
        progress?.inProgressLeg = nil
        progress?.finished = phase == .finished
        saveProgress()
        trail("\(VieNeuAutoRunTrail.endMarker): \(statusLine)\(errorMessage.map { " — \($0)" } ?? "")")
        refresh()
        saveReport()
        AppLogger.shared.log("🎙️ [VieNeuAutoRun] Kết thúc: \(statusLine)")
    }

    /// Bước chuẩn bị đầy đủ (lượt đo mới): nhả engine Nano, biên dịch / nạp / tự kiểm / nạp sẵn Core ML, nạp lại engine.
    private func prepareFresh(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        service: VieNeuTTSService,
        voice: String
    ) async throws {
        setPhase(.preparing)
        // Nhả engine Nano (~280 MB) trong lúc biên dịch / tự kiểm như phép thử P1 — bản 1.3.890 giữ nó và app bị giết.
        statusLine = "Nhả engine Nano để Core ML có chỗ biên dịch…"
        _ = await Task.detached(priority: .utility) { service.releaseEngineRuntime() }.value
        trail("đã nhả engine Nano, bắt đầu chuẩn bị Core ML")
        let backend = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: 64)
        self.backend = backend
        let trailURL = VieNeuAutoRunTrail.url(in: package)
        let onProgress: @Sendable (String) -> Void = { [weak self] line in
            VieNeuAutoRunTrail.append(trailURL, line) // ghi **trước** bước nặng, ngay trên luồng chuẩn bị
            Task { @MainActor [weak self] in
                guard let self, self.phase == .preparing else { return }
                self.statusLine = line
            }
        }
        let report = try await Task.detached(priority: .userInitiated) {
            try VieNeuCoreMLPreparer.prepare(backend: backend, progress: onProgress)
        }.value
        prepareLines = report.lines
        coreMLPassed = report.passed
        // Không nhả session: đã nạp sẵn lúc màn còn sáng, giữ qua lượt 1 tới hết lượt Core ML (1.3.909 — nạp lúc
        // khoá màn làm app chết ở bản 1.3.907). Giữ một session chỉ tốn ~20 MB.
        preloadNote = report.preloadedSessions > 0 ? "giữ \(report.preloadedSessions) session Core ML từ lúc chuẩn bị" : ""
        refresh()
        saveReport()
        trail("chuẩn bị xong: \(report.passed ? "qua tự kiểm" : "không qua tự kiểm"), giữ tối đa \(report.sessionCap) session")
        var saved = VieNeuAutoRunProgress(startedAt: startedAt, voice: voice)
        saved.prepareDone = true
        saved.prepareLines = report.lines
        saved.coreMLPassed = report.passed
        saved.sessionCap = report.sessionCap
        saved.sessionEstimateMB = report.sessionEstimateMB
        self.progress = saved
        saveProgress()
        statusLine = "Đang nạp lại engine Nano (giọng \(voice))…"
        try await service.prepare(voice: voice)
        trail("đã nạp lại engine Nano")
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
