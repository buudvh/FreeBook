import Combine
import Foundation

/// Trạng thái góc quay của bìa đĩa xoay (đĩa nghe TTS / nhạc, sheet điều khiển nhanh) — vòng đời dài hạn do
/// `TTSWidgetCoverRotation` / `AudioCoverRotation` giữ, không mất góc khi view dựng lại. Dời nguyên văn khỏi file widget
/// "Đĩa nổi" khi kiểu đó bị bỏ (1.3.859; sót ở commit đó, dời ở 1.3.865).
@MainActor
public final class CoverRotationState: ObservableObject {
    private struct RotationData: Sendable, Equatable {
        let accumulatedAngle: Double
        let playStartDate: Date?

        init(accumulatedAngle: Double = 0.0, playStartDate: Date? = nil) {
            self.accumulatedAngle = accumulatedAngle
            self.playStartDate = playStartDate
        }
    }

    static let rotationSpeed: Double = 24.0 // 24 độ/giây = 15 giây / 1 vòng quay 360°
    // Không @Published: góc được Core Animation nội suy (TTSRotatingCoverView), view chỉ đọc lúc gắn animation.
    private var data: RotationData = RotationData()
    /// Tăng mỗi lần `resetAngle` (đổi sách) để TTSRotatingCoverView chạy lại animation từ góc 0.
    @Published public private(set) var resetGeneration: Int = 0

    public func syncPlaybackState(isPlaying: Bool, at date: Date = Date()) {
        if isPlaying {
            if data.playStartDate == nil {
                data = RotationData(accumulatedAngle: data.accumulatedAngle, playStartDate: date)
            }
        } else {
            if let start = data.playStartDate {
                let elapsed = max(0, date.timeIntervalSince(start))
                let newAccumulated = (data.accumulatedAngle + elapsed * Self.rotationSpeed).truncatingRemainder(dividingBy: 360.0)
                data = RotationData(accumulatedAngle: newAccumulated, playStartDate: nil)
            }
        }
    }

    /// Góc hiện tại (độ) theo trạng thái phát mà model đang giữ (`playStartDate` chỉ khác nil khi đang phát).
    public func currentAngle(at date: Date = Date()) -> Double {
        guard let start = data.playStartDate else {
            return data.accumulatedAngle
        }
        let elapsed = max(0, date.timeIntervalSince(start))
        return (data.accumulatedAngle + elapsed * Self.rotationSpeed).truncatingRemainder(dividingBy: 360.0)
    }

    public func resetAngle(isPlaying: Bool, at date: Date = Date()) {
        data = RotationData(accumulatedAngle: 0.0, playStartDate: isPlaying ? date : nil)
        resetGeneration &+= 1
    }
}
