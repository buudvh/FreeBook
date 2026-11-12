import Foundation

/// **Chạy tiếp** của "Đo tự động" (1.3.910): nạp lại tiến độ đã lưu (`VieNeuAutoRunProgress`), bỏ bước tải + biên dịch,
/// chạy từ lượt đầu tiên chưa xong êm. Lượt dở (bấm Dừng / bị gián đoạn / app bị giết) chạy lại cả bước chờ mát.
extension VieNeuAutoThermalRun {
    /// Chỉ số các lượt đã xong êm (kể cả lượt bị bỏ qua) — vòng lượt bỏ qua chúng.
    var completedLegIndices: Set<Int> {
        Set(legs.filter { !$0.interrupted }.map(\.index))
    }

    func saveProgress() {
        guard let package, let progress else { return }
        progress.save(to: VieNeuAutoRunProgress.url(in: package))
    }

    /// Lượt sẽ chạy tiếp nếu lượt đo trước chưa xong mà đã qua bước chuẩn bị; `nil` = chỉ đo mới được.
    static func resumableLeg(package: VieNeuCoreMLPackage?) -> Int? {
        guard let package,
              let saved = VieNeuAutoRunProgress.load(from: VieNeuAutoRunProgress.url(in: package)),
              saved.prepareDone, !saved.finished else { return nil }
        return saved.nextLegIndex(planCount: legPlan.count)
    }

    /// Nạp lại trạng thái lượt đo trước; `false` = không có gì để chạy tiếp (chỗ gọi đo mới).
    func restoreForResume(package: VieNeuCoreMLPackage) -> Bool {
        guard var saved = VieNeuAutoRunProgress.load(from: VieNeuAutoRunProgress.url(in: package)),
              saved.prepareDone, !saved.finished,
              let next = saved.nextLegIndex(planCount: Self.legPlan.count) else { return false }
        // App bị giết giữa lượt ⇒ bản chụp phút cuối của lượt đó vào báo cáo như lượt dở.
        if var dangling = saved.inProgressLeg {
            dangling.interrupted = true
            dangling.endReason = "app bị tắt giữa lượt — số tới phút cuối ghi được"
            saved.legs.append(dangling)
            saved.inProgressLeg = nil
        }
        let note = "chạy tiếp \(Self.clockFormatter.string(from: Date())) từ lượt \(next + 1)"
        saved.resumeNotes.append(note)
        startedAt = saved.startedAt
        voiceUsed = saved.voice
        prepareLines = saved.prepareLines
        coreMLPassed = saved.coreMLPassed
        legs = saved.legs
        resumeNotes = saved.resumeNotes
        progress = saved
        saveProgress()
        trail("— \(note) —")
        return true
    }

    /// Chạy tiếp: không biên dịch / tự kiểm lại. Còn lượt Core ML thì nạp sẵn session **ngay bây giờ** (vừa bấm nút, màn
    /// còn sáng): iOS giết app chạy nền dùng CPU quá 80% trong 60 giây, mà nạp model Core ML là việc nặng (file
    /// `cpu_resource_fatal` của lần đo 1.3.907: "Non-Frontmost App", CoreML → Espresso → MIL, "Process killed").
    func prepareForResume(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        service: VieNeuTTSService,
        voice: String
    ) async throws {
        let remaining = Self.legPlan.indices.filter { !completedLegIndices.contains($0) }
        let needsCoreML = coreMLPassed && remaining.contains { Self.legPlan[$0] == .coreML }
        guard needsCoreML, let saved = progress else {
            statusLine = "Đang nạp engine Nano (giọng \(voice))…"
            try await service.prepare(voice: voice)
            trail("chạy tiếp: đã nạp engine Nano")
            return
        }
        setPhase(.preparing)
        statusLine = "Chạy tiếp: nạp sẵn session Core ML — giữ màn sáng tới khi xong…"
        _ = await Task.detached(priority: .utility) { service.releaseEngineRuntime() }.value
        let backend = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: saved.sessionCap)
        backend.sessionEstimateMB = saved.sessionEstimateMB
        self.backend = backend
        let removed = package.removeIncompleteCacheEntries()
        let trailURL = VieNeuAutoRunTrail.url(in: package)
        let result = try await Task.detached(priority: .userInitiated) {
            try backend.preload { step in VieNeuAutoRunTrail.append(trailURL, "\(step) (chạy tiếp)") }
        }.value
        var note = String(format: "chạy tiếp: nạp sẵn %ld/%ld session trong %.1f s", result.count,
                          backend.preloadOrder.count, result.ms / 1_000)
        if removed > 0 { note += " · dọn \(removed) bản biên dịch dở" }
        preloadNote = note
        trail(note)
        statusLine = "Đang nạp lại engine Nano (giọng \(voice))…"
        try await service.prepare(voice: voice)
        trail("chạy tiếp: đã nạp lại engine Nano")
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
