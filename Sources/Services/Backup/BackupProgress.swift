import Foundation

/// Tiến độ một phiên sao lưu / khôi phục, đủ nhỏ để đi qua ranh giới actor.
public struct BackupProgress: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case idle
        case readingLibrary
        case writingChapters
        case copyingContent
        case copyingExtensions
        case copyingDictionaries
        case compressing
        case extracting
        case restoringRepositories
        case restoringExtensions
        case restoringBooks
        case restoringChapters
        case restoringDictionaries
        case uploading
        case downloading
        case finished
        case failed

        public var label: String {
            switch self {
            case .idle: return "Chưa bắt đầu"
            case .readingLibrary: return "Đang đọc thư viện"
            case .writingChapters: return "Đang ghi mục lục"
            case .copyingContent: return "Đang gom nội dung chương"
            case .copyingExtensions: return "Đang gom extension"
            case .copyingDictionaries: return "Đang gom từ điển"
            case .compressing: return "Đang nén"
            case .extracting: return "Đang giải nén"
            case .restoringRepositories: return "Đang khôi phục kho"
            case .restoringExtensions: return "Đang khôi phục extension"
            case .restoringBooks: return "Đang khôi phục truyện"
            case .restoringChapters: return "Đang khôi phục chương"
            case .restoringDictionaries: return "Đang khôi phục từ điển"
            case .uploading: return "Đang tải lên"
            case .downloading: return "Đang tải xuống"
            case .finished: return "Hoàn tất"
            case .failed: return "Thất bại"
            }
        }
    }

    public var phase: Phase
    public var completedUnits: Int
    public var totalUnits: Int
    public var detail: String

    public init(phase: Phase = .idle, completedUnits: Int = 0, totalUnits: Int = 0, detail: String = "") {
        self.phase = phase
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.detail = detail
    }

    public var isActive: Bool {
        phase != .idle && phase != .finished && phase != .failed
    }

    /// `nil` khi chưa biết tổng số đơn vị — UI hiện `ProgressView()` không xác định.
    public var fraction: Double? {
        guard totalUnits > 0 else { return nil }
        return min(1.0, max(0.0, Double(completedUnits) / Double(totalUnits)))
    }

    public var message: String {
        if detail.isEmpty {
            guard totalUnits > 0 else { return phase.label }
            return "\(phase.label) (\(completedUnits)/\(totalUnits))"
        }
        guard totalUnits > 0 else { return "\(phase.label) — \(detail)" }
        return "\(phase.label) (\(completedUnits)/\(totalUnits)) — \(detail)"
    }

    public static let idle = BackupProgress()
}
