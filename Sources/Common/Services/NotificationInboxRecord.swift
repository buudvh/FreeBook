import Foundation

/// Một dòng nhật ký toast đã hiện, phục vụ Trung tâm thông báo.
///
/// Cố ý **không** nằm trong SwiftData (schema `@Model` của app không có `VersionedSchema`) — đây là
/// dữ liệu phái sinh, dựng lại được, nên có file JSON riêng do [`NotificationInboxStore`](NotificationInboxStore.swift)
/// sở hữu. Cùng lý do với [[new-chapter-record-json]] của phân hệ chương mới.
struct NotificationInboxRecord: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let message: String
    let type: ToastType
    let date: Date
    var isRead: Bool

    init(id: UUID = UUID(), message: String, type: ToastType, date: Date = Date(), isRead: Bool = false) {
        self.id = id
        self.message = message
        self.type = type
        self.date = date
        self.isRead = isRead
    }

    /// Decode chịu lỗi để file của bản app cũ vẫn đọc được sau khi thêm field mới.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        self.type = try container.decodeIfPresent(ToastType.self, forKey: .type) ?? .info
        self.date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    }
}

/// `ToastType` không tự Codable (chỉ `Sendable, Equatable`) nên khai bảng mã tối giản tại đây, tránh
/// đụng vào định nghĩa gốc ở [`ToastManager`](ToastManager.swift).
extension ToastType: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "success": self = .success
        case "error": self = .error
        default: self = .info
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .success: try container.encode("success")
        case .error: try container.encode("error")
        case .info: try container.encode("info")
        }
    }
}
