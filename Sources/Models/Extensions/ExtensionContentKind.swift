import Foundation

/// Loại **nội dung** mà một tiện ích VBook cung cấp — quyết định sách mở bằng Reader chữ, màn đọc truyện tranh
/// hay trình phát video (`BookContentDestination`).
///
/// Suy ra **lúc chạy** từ `metadata.type`, không lưu vào `@Model Book` (bất biến 4 của plan comic/video):
/// đổi shape `@Model` là nguy hiểm vì repo chỉ có lightweight migration ngầm.
///
/// Ánh xạ đi qua `ExtensionFilterGroups.typeGroup(for:)` để nhãn chip ở kho, Khám phá và Tìm kiếm không trôi
/// khỏi loại dùng để định tuyến: `novel`/lạ/rỗng → `text`, `comic` → `comic`, `video` → `video`, còn lại
/// (`tts`, `translate`, `ai`, `audio`, `tool`) → `unsupported`.
public enum ExtensionContentKind: String, Sendable {
    case text
    case comic
    case video
    case unsupported

    /// Chuẩn hoá giá trị `type` thô (`novel`, `chinese_novel`, `"novel,comic"`, `comic`, `video`, `tts`…).
    public init(typeString: String) {
        switch ExtensionFilterGroups.typeGroup(for: typeString) {
        case ExtensionFilterGroups.novelGroup, ExtensionFilterGroups.otherGroup:
            self = .text
        case ExtensionFilterGroups.comicGroup:
            self = .comic
        case ExtensionFilterGroups.videoGroup:
            self = .video
        default:
            self = .unsupported
        }
    }

    /// Loại của sách theo `extensionPackageId`. Thứ tự: `"local"`/rỗng → `text`; tiện ích đã cài → catalog
    /// (mục registry chưa cài) → `text`.
    ///
    /// Đọc bảng chụp có lock của `ExtensionLibraryRepository` nên gọi được từ thread bất kỳ, không `await`.
    public static func resolve(packageId: String) -> ExtensionContentKind {
        let trimmed = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "local" else { return .text }
        if let installed = ExtensionLibraryRepository.snapshot(packageId: trimmed) {
            return ExtensionContentKind(typeString: installed.type)
        }
        if let catalog = ExtensionLibraryRepository.catalogSnapshot(packageId: trimmed) {
            return ExtensionContentKind(typeString: catalog.type)
        }
        return .text
    }

    /// Loại theo `metadata.type` trong `<localPath>/plugin.json` (dự phòng `type` ở gốc file, giống luồng cài).
    /// Không đọc được file ⇒ `text`.
    nonisolated public static func resolve(localPath: String) -> ExtensionContentKind {
        guard !localPath.isEmpty else { return .text }
        let pluginUrl = URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: pluginUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .text }
        let meta = json["metadata"] as? [String: Any] ?? json
        guard let type = meta["type"] as? String else { return .text }
        return ExtensionContentKind(typeString: type)
    }

    /// `true` với truyện tranh/video: không đi qua pipeline text (chuẩn hoá, dịch nội dung, TTS, xuất ebook).
    public var isMedia: Bool {
        self == .comic || self == .video
    }

    /// Nhãn trùng nhãn nhóm thể loại của kho (`ExtensionFilterGroups.typeGroupLabel`).
    public var label: String {
        switch self {
        case .text: return ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.novelGroup)
        case .comic: return ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.comicGroup)
        case .video: return ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.videoGroup)
        case .unsupported: return "Không hỗ trợ"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: return "book"
        case .comic: return "photo.on.rectangle"
        case .video: return "play.rectangle"
        case .unsupported: return "questionmark.square.dashed"
        }
    }
}
