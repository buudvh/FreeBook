import Foundation

/// Các nhóm "rác chắc chắn" của trang Dọn rác — theo thứ tự hiện. Mỗi nhóm thuộc **một** owner dữ liệu: owner biết chính
/// xác file nào nó đang dùng, rác là file trong thư mục của owner mà không nằm trong danh sách đó (luật ở `JunkScanner`).
/// Không bao giờ đoán theo tên trên thư mục không rõ chủ.
enum JunkGroupKind: String, CaseIterable, Sendable, Identifiable {
    /// `VieNeu/CoreML`: `Cache-noopt/`, `Cache/` không qua tự kiểm (hoặc có file `.fbtrim`), file gói ngoài manifest.
    case coreMLStale
    /// `VieNeu/Static/` + báo cáo trong `CoreML/Results/` trừ dấu tự kiểm (màn thử VieNeu đã gỡ).
    case labData
    /// `*.partial` (+ `manifest.json.new` của gói Core ML) khi không có lượt tải nào.
    case partialDownloads
    /// Mục trong `tmp/` không đổi hơn 1 giờ, khi không có sao lưu / tải / xuất nào chạy.
    case staleTemporary
    /// `books/*.bin`, `comics/*/`, `videos/*/` của `bookId` không còn trong thư viện.
    case deletedBooks
    /// `extension_store/legacy/` sau khi đã chuyển xong dữ liệu tiện ích cũ.
    case legacyExtensionCopy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coreMLStale: return "Tăng tốc Core ML · bản biên dịch cũ"
        case .labData: return "Dữ liệu màn thử VieNeu"
        case .partialDownloads: return "File tải dở · không còn lượt tải"
        case .staleTemporary: return "File tạm của việc đã xong"
        case .deletedBooks: return "Dữ liệu của truyện đã xoá"
        case .legacyExtensionCopy: return "Bản chép thư viện tiện ích cũ"
        }
    }
}
