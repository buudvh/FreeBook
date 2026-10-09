import Foundation

/// Giãn nhịp tiến độ do **worker** báo về (tách khỏi `BackupCoordinator.swift` để file gốc dưới trần 400 dòng).
/// Ba biến trạng thái nằm ở file gốc vì extension không chứa stored property.
extension BackupCoordinator {
    /// Nhịp publish tối thiểu cho tiến độ do worker báo về (worker báo theo từng truyện/extension).
    static let reportedProgressInterval: TimeInterval = 0.25

    /// Tiến độ do **worker** báo về: chỉ publish tối đa mỗi `reportedProgressInterval` trong cùng một
    /// pha, nhưng luôn publish khi đổi pha hoặc tới đơn vị cuối. Mỗi lần publish `progress` là một lần
    /// vẽ lại mọi view observe coordinator. Các chỗ gán trạng thái trực tiếp (`setProgress`,
    /// `.failed`…) không đi qua đây nên không bao giờ bị nuốt.
    func publishReportedProgress(_ value: BackupProgress) {
        let now = ProcessInfo.processInfo.systemUptime
        let isFinalUnit = value.totalUnits > 0 && value.completedUnits >= value.totalUnits - 1
        let elapsed = now - lastReportedProgressTime
        guard value.phase != progress.phase
            || isFinalUnit
            || elapsed >= Self.reportedProgressInterval
        else {
            pendingReportedProgress = value
            scheduleReportedProgressFlush(after: Self.reportedProgressInterval - elapsed)
            return
        }
        pendingReportedProgress = nil
        lastReportedProgressTime = now
        setProgress(value)
    }

    private func scheduleReportedProgressFlush(after delay: TimeInterval) {
        guard !isReportedProgressFlushScheduled else { return }
        isReportedProgressFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard let self else { return }
            self.isReportedProgressFlushScheduled = false
            let pending = self.pendingReportedProgress
            self.pendingReportedProgress = nil
            // Chỉ bù khi lượt vẫn ở đúng pha đó — trạng thái gán trực tiếp (xong/lỗi/pha khác) luôn thắng.
            guard let pending, self.progress.isActive, pending.phase == self.progress.phase else { return }
            self.lastReportedProgressTime = ProcessInfo.processInfo.systemUptime
            self.setProgress(pending)
        }
    }
}
