import UIKit

@MainActor
final class ReaderEnergyDiagnostics {
    static let shared = ReaderEnergyDiagnostics()

    /// Class (không phải struct) để mutate in-place: struct chứa Set<ObjectIdentifier>
    /// bị copy-on-write toàn bộ Set mỗi lần ghi qua `var snapshot = window … window = snapshot`.
    private final class Window {
        let startedAt: TimeInterval
        var updateUIViewCount = 0
        var uniqueViews: Set<ObjectIdentifier> = []
        var highlightMutations = 0
        var geometryRebuilds = 0
        var themeRebuilds = 0
        var explicitSizeInvalidations = 0
        var contentSizeInvalidations = 0
        var ttsScrollTargets = 0
        var ttsScrollSkippedVisible = 0
        var ttsScrollExecuted = 0
        var frameUpdates = 0
        var frameUpdatesSkipped = 0
        var paragraphsRealized = 0

        init(startedAt: TimeInterval) {
            self.startedAt = startedAt
        }
    }

    private static let summaryInterval: TimeInterval = 60
    /// Số event giữa hai lần đọc systemUptime — đọc đồng hồ mỗi event là chi phí thật
    /// trên hot path cuộn, còn mốc tổng kết 60 s không cần chính xác tới từng event.
    private static let clockSampleStride = 64
    private var window: Window?
    /// Chốt một lần lúc mở Reader. Log tắt (mặc định mỗi lần khởi chạy app) ⇒ toàn bộ
    /// đo đếm rút về một phép so bool, không đụng UserDefaults hay đồng hồ hệ thống.
    private var isEnabled = false
    private var eventsSinceClockCheck = 0
    /// Đếm card `ParagraphCardView` mà `LazyVStack` phải realize kể từ lần commit
    /// navigation gần nhất. Đây là con số phân biệt "một lượt realize" với "hai lượt"
    /// (hạ cánh đầu chương rồi bị auto-scroll TTS kéo sâu vài giây sau).
    private var paragraphsRealizedSinceNavigation = 0
    private var lastNavigationIndex = -1

    private init() {}

    func beginReaderSession() {
        isEnabled = AppLogger.shared.isLoggingEnabled
        eventsSinceClockCheck = 0
        paragraphsRealizedSinceNavigation = 0
        lastNavigationIndex = -1
        guard isEnabled else {
            window = nil
            return
        }
        window = Window(startedAt: ProcessInfo.processInfo.systemUptime)
    }

    func recordParagraphRealized() {
        guard isEnabled else { return }
        paragraphsRealizedSinceNavigation += 1
        updateWindow { $0.paragraphsRealized += 1 }
    }

    func recordNavigationCommit(index: Int) {
        guard isEnabled else { return }
        emitNavigationRealizeCount(reason: "commit")
        lastNavigationIndex = index
    }

    /// Không đo ms quanh `proxy.scrollTo`: hàm đó chỉ ghi nhận neo, còn phần đắt (realize +
    /// đo các card trung gian của `LazyVStack`) xảy ra ở layout pass sau đó nên số ms sẽ
    /// gần 0 và gây hiểu sai. Neo đã chọn + `NavRealize cards=` mới là bằng chứng thật.
    func recordScrollAttempt(chapterIndex: Int, paragraphIndex: Int, reason: String, anchor: String) {
        guard isEnabled else { return }
        AppLogger.shared.log(String(
            format: "[ReaderPerf] Scroll chapter=%d paragraph=%d reason=%@ anchor=%@",
            chapterIndex,
            paragraphIndex,
            reason,
            anchor
        ))
    }

    private func emitNavigationRealizeCount(reason: String) {
        guard lastNavigationIndex >= 0 else { return }
        AppLogger.shared.log(String(
            format: "[ReaderPerf] NavRealize index=%d cards=%d reason=%@",
            lastNavigationIndex,
            paragraphsRealizedSinceNavigation,
            reason
        ))
        paragraphsRealizedSinceNavigation = 0
    }

    func recordUIViewUpdate(for coordinator: AnyObject) {
        guard isEnabled else { return }
        updateWindow { stats in
            stats.updateUIViewCount += 1
            stats.uniqueViews.insert(ObjectIdentifier(coordinator))
        }
    }

    func recordHighlightMutation() {
        guard isEnabled else { return }
        updateWindow { $0.highlightMutations += 1 }
    }

    func recordGeometryRebuild() {
        guard isEnabled else { return }
        updateWindow { $0.geometryRebuilds += 1 }
    }

    func recordThemeRebuild() {
        guard isEnabled else { return }
        updateWindow { $0.themeRebuilds += 1 }
    }

    func recordExplicitSizeInvalidation() {
        guard isEnabled else { return }
        updateWindow { $0.explicitSizeInvalidations += 1 }
    }

    func recordContentSizeInvalidation() {
        guard isEnabled else { return }
        updateWindow { $0.contentSizeInvalidations += 1 }
    }

    func recordTTSScrollTarget() {
        guard isEnabled else { return }
        updateWindow { $0.ttsScrollTargets += 1 }
    }

    func recordTTSScrollSkippedVisible() {
        guard isEnabled else { return }
        updateWindow { $0.ttsScrollSkippedVisible += 1 }
    }

    func recordTTSScrollExecuted() {
        guard isEnabled else { return }
        updateWindow { $0.ttsScrollExecuted += 1 }
    }

    func recordParagraphFrameUpdate(accepted: Bool) {
        guard isEnabled else { return }
        updateWindow { stats in
            if accepted {
                stats.frameUpdates += 1
            } else {
                stats.frameUpdatesSkipped += 1
            }
        }
    }

    func flush(reason: String) {
        guard isEnabled else { return }
        emitNavigationRealizeCount(reason: reason)
        lastNavigationIndex = -1
        emitSummary(reason: reason, resetWindow: false)
        window = nil
    }

    private func updateWindow(_ mutation: (Window) -> Void) {
        let current = window ?? Window(startedAt: ProcessInfo.processInfo.systemUptime)
        window = current
        mutation(current)

        eventsSinceClockCheck += 1
        guard eventsSinceClockCheck >= Self.clockSampleStride else { return }
        eventsSinceClockCheck = 0
        if ProcessInfo.processInfo.systemUptime - current.startedAt >= Self.summaryInterval {
            emitSummary(reason: "interval", resetWindow: true)
        }
    }

    private func emitSummary(reason: String, resetWindow: Bool) {
        guard isEnabled, let snapshot = window else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsedSeconds = max(0.1, now - snapshot.startedAt)
        let totalEvents = snapshot.updateUIViewCount + snapshot.ttsScrollTargets + snapshot.frameUpdates
        guard totalEvents > 0 else {
            if resetWindow {
                window = Window(startedAt: now)
            }
            return
        }

        let updateRPM = Double(snapshot.updateUIViewCount) * 60 / elapsedSeconds
        let repeatedUpdates = max(0, snapshot.updateUIViewCount - snapshot.uniqueViews.count)
        let repeatedUpdateRPM = Double(repeatedUpdates) * 60 / elapsedSeconds
        let highlightRPM = Double(snapshot.highlightMutations) * 60 / elapsedSeconds
        let sizeInvalidations = snapshot.explicitSizeInvalidations + snapshot.contentSizeInvalidations
        let sizeInvalidationRPM = Double(sizeInvalidations) * 60 / elapsedSeconds
        let scrollRPM = Double(snapshot.ttsScrollTargets) * 60 / elapsedSeconds
        let executedScrollRPM = Double(snapshot.ttsScrollExecuted) * 60 / elapsedSeconds
        let frameUpdateRPM = Double(snapshot.frameUpdates) * 60 / elapsedSeconds
        let repeatedGeometryRebuilds = max(0, snapshot.geometryRebuilds - snapshot.uniqueViews.count)
        let thermal = ProcessInfo.processInfo.thermalState
        let prediction = Self.prediction(
            elapsedSeconds: elapsedSeconds,
            thermalState: thermal,
            repeatedUpdateRPM: repeatedUpdateRPM,
            highlightRPM: highlightRPM,
            repeatedGeometryRebuilds: repeatedGeometryRebuilds,
            executedScrollRPM: executedScrollRPM,
            frameUpdateRPM: frameUpdateRPM
        )

        let message = String(
            format: "[ReaderEnergy] Summary reason=%@ state=%@ elapsedSec=%.1f updateUIView=%d updateRPM=%.1f repeatUpdateRPM=%.1f uniqueViews=%d highlight=%d highlightRPM=%.1f geometry=%d repeatGeometry=%d theme=%d explicitSizeInvalidation=%d contentSizeInvalidation=%d sizeInvalidationRPM=%.1f ttsScrollTarget=%d scrollRPM=%.1f scrollSkippedVisible=%d scrollExecuted=%d executedScrollRPM=%.1f frameUpdate=%d frameUpdateRPM=%.1f frameUpdateSkipped=%d paragraphRealized=%d thermal=%@ prediction=%@",
            reason,
            Self.applicationStateName(),
            elapsedSeconds,
            snapshot.updateUIViewCount,
            updateRPM,
            repeatedUpdateRPM,
            snapshot.uniqueViews.count,
            snapshot.highlightMutations,
            highlightRPM,
            snapshot.geometryRebuilds,
            repeatedGeometryRebuilds,
            snapshot.themeRebuilds,
            snapshot.explicitSizeInvalidations,
            snapshot.contentSizeInvalidations,
            sizeInvalidationRPM,
            snapshot.ttsScrollTargets,
            scrollRPM,
            snapshot.ttsScrollSkippedVisible,
            snapshot.ttsScrollExecuted,
            executedScrollRPM,
            snapshot.frameUpdates,
            frameUpdateRPM,
            snapshot.frameUpdatesSkipped,
            snapshot.paragraphsRealized,
            Self.thermalStateName(thermal),
            prediction
        )
        AppLogger.shared.log(message)

        if resetWindow {
            window = Window(startedAt: now)
        }
    }

    private static func prediction(
        elapsedSeconds: TimeInterval,
        thermalState: ProcessInfo.ThermalState,
        repeatedUpdateRPM: Double,
        highlightRPM: Double,
        repeatedGeometryRebuilds: Int,
        executedScrollRPM: Double,
        frameUpdateRPM: Double
    ) -> String {
        if elapsedSeconds < 20 {
            return "insufficient_sample"
        }

        let hasThermalPressure = thermalState == .serious || thermalState == .critical
        let hasRepeatedGeometryChurn = repeatedGeometryRebuilds >= 5
        let hasElevatedScrollActivity = executedScrollRPM >= 10 || frameUpdateRPM >= 120
        let hasElevatedHighlightActivity = highlightRPM >= 30

        if hasThermalPressure && hasRepeatedGeometryChurn {
            return "reader_layout_thermal_pressure_likely"
        }
        if hasThermalPressure && hasElevatedScrollActivity {
            return "reader_scroll_thermal_pressure_likely"
        }
        if hasThermalPressure && hasElevatedHighlightActivity {
            return "reader_updates_with_thermal_pressure"
        }
        if hasThermalPressure {
            return "thermal_pressure_not_explained_by_reader_updates"
        }
        if hasRepeatedGeometryChurn {
            return "reader_layout_churn_likely"
        }
        if hasElevatedScrollActivity {
            return "reader_scroll_activity_elevated"
        }
        if hasElevatedHighlightActivity || repeatedUpdateRPM >= 60 {
            return "reader_update_rate_elevated"
        }
        return "reader_render_load_low"
    }

    private static func applicationStateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "foreground"
        case .background: return "background"
        case .inactive: return "inactive"
        @unknown default: return "unknown"
        }
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
