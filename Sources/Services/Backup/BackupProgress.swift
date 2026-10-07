import Foundation

/// Tiến độ một phiên sao lưu / khôi phục, đủ nhỏ để đi qua ranh giới actor.
public struct BackupProgress: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case idle
        case readingLibrary
        case writingChapters
        case copyingContent
        case copyingCovers
        case copyingExtensions
        case copyingDictionaries
        case compressing
        case extracting
        case restoringRepositories
        case restoringExtensions
        case restoringBooks
        case restoringChapters
        case restoringCovers
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
            case .copyingCovers: return "Đang gom ảnh bìa"
            case .copyingExtensions: return "Đang gom extension"
            case .copyingDictionaries: return "Đang gom từ điển"
            case .compressing: return "Đang nén"
            case .extracting: return "Đang giải nén"
            case .restoringRepositories: return "Đang khôi phục kho"
            case .restoringExtensions: return "Đang khôi phục extension"
            case .restoringBooks: return "Đang khôi phục truyện"
            case .restoringChapters: return "Đang khôi phục chương"
            case .restoringCovers: return "Đang khôi phục ảnh bìa"
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

    /// Mục tiến độ có nên hiện ở **màn Thông báo** hay không.
    ///
    /// Khác `isActive` đúng một điểm: `.finished`/`.failed` **vẫn hiện**, vì màn Thông báo giữ lại **dòng
    /// kết quả** kèm nút "Bỏ qua" (người dùng chốt 2026-10-07) — xong rồi mà dòng biến mất thì người dùng
    /// không có chỗ nào xác nhận lượt khôi phục đã thành công. `.idle` là trạng thái nghỉ duy nhất ⇒ ẩn.
    ///
    /// **Không** dùng cờ này cho section tiến độ ở màn Sao lưu / Google Drive: hai màn đó vẽ đúng theo
    /// `isActive` (đang chạy), đổi sang cờ này là để một dòng "Hoàn tất" nằm lại vĩnh viễn ở đầu danh sách.
    public var isInboxVisible: Bool {
        phase != .idle
    }

    /// Lượt này là **khôi phục** hay **sao lưu** — chỉ dùng để đặt nhãn ở màn Thông báo.
    ///
    /// Suy từ `phase`, không phải trường riêng: worker báo tiến độ bằng `BackupProgress` trần, thêm một
    /// trường "loại tác vụ" là phải sửa mọi call site trong `BackupExportWorker`/`BackupRestoreWorker`.
    /// `.extracting`/`.downloading` tính là khôi phục vì cả hai chỉ xuất hiện trên đường đi vào dữ liệu
    /// (giải nén để đọc manifest, tải archive từ Drive về) — còn `.extracting` của luồng nhập file cũng
    /// đúng nghĩa "đang xử lý bản sao lưu".
    public var isRestore: Bool {
        switch phase {
        case .extracting, .restoringRepositories, .restoringExtensions, .restoringBooks,
             .restoringChapters, .restoringCovers, .restoringDictionaries, .downloading:
            return true
        case .idle, .readingLibrary, .writingChapters, .copyingContent, .copyingCovers,
             .copyingExtensions, .copyingDictionaries, .compressing, .uploading, .finished, .failed:
            return false
        }
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
