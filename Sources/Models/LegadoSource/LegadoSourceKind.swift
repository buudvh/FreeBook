import Foundation

/// Loại nội dung của một nguồn Legado, suy từ `bookSourceType` (spec §1.6) — **không** suy từ tên/nhóm.
///
/// Ánh xạ sang `Extension.type` của bản ghi trong kho tiện ích: `legado` (chữ), `legado_comic`, `legado_video`.
/// `ExtensionFilterGroups.typeGroup(for:)` đưa ba giá trị này về đúng nhóm (`legado` → "other" → `.text`,
/// `legado_comic` → comic, `legado_video` → video), nên `ExtensionContentKind` / `BookContentDestination`
/// định tuyến đúng mà không cần sửa.
public enum LegadoSourceKind: String, Sendable, CaseIterable, Hashable {
    case text
    case comic
    case video
    /// Audio (1), tệp tải về (3) và giá trị lạ — bị bỏ qua khi nhập, không bao giờ có bản ghi.
    case unsupported

    public static let textExtensionType = "legado"
    public static let comicExtensionType = "legado_comic"
    public static let videoExtensionType = "legado_video"

    /// `bookSourceType` → loại: 0 chữ, 2 tranh, 4 video; còn lại → `unsupported`.
    public init(bookSourceType: Int) {
        switch bookSourceType {
        case 0: self = .text
        case 2: self = .comic
        case 4: self = .video
        default: self = .unsupported
        }
    }

    /// `Extension.type` của bản ghi → loại; `nil` khi không phải một trong ba giá trị Legado.
    public init?(extensionType: String) {
        switch extensionType {
        case Self.textExtensionType: self = .text
        case Self.comicExtensionType: self = .comic
        case Self.videoExtensionType: self = .video
        default: return nil
        }
    }

    /// Giá trị ghi vào `Extension.type` / `metadata.type` của `plugin.json`; `nil` với loại không lưu.
    public var extensionType: String? {
        switch self {
        case .text: return Self.textExtensionType
        case .comic: return Self.comicExtensionType
        case .video: return Self.videoExtensionType
        case .unsupported: return nil
        }
    }

    public var contentKind: ExtensionContentKind {
        switch self {
        case .text: return .text
        case .comic: return .comic
        case .video: return .video
        case .unsupported: return .unsupported
        }
    }

    /// Nhãn chip trên dòng nguồn ở tab "Nguồn Legado".
    public var label: String {
        switch self {
        case .text: return "Chữ"
        case .comic: return "Tranh"
        case .video: return "Video"
        case .unsupported: return "Không hỗ trợ"
        }
    }
}
