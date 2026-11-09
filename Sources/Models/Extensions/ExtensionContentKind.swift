import Foundation

/// Loại **nội dung** mà một tiện ích cung cấp — quyết định sách mở bằng Reader chữ, màn đọc truyện tranh,
/// trình phát video hay màn nghe âm thanh (`BookContentDestination`).
///
/// Suy ra **lúc chạy** từ `metadata.type`, không lưu vào `@Model Book` (bất biến 4 của plan comic/video):
/// đổi shape `@Model` là nguy hiểm vì repo chỉ có lightweight migration ngầm.
///
/// Ánh xạ đi qua `ExtensionFilterGroups.typeGroup(for:)` để nhãn chip ở kho, Khám phá và Tìm kiếm không trôi
/// khỏi loại dùng để định tuyến: `novel`/lạ/rỗng → `text`, `comic` → `comic`, `video` → `video`,
/// `audio`/`music` → `audio`, còn lại (`tts`, `translate`, `ai`, `tool`) → `unsupported`.
public enum ExtensionContentKind: String, Sendable {
    case text
    case comic
    case video
    /// Tiện ích loại `audio` (album / bài nghe): màn nghe riêng (`AudioPlaybackSession`), chưa có tải / xuất.
    case audio
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
        case ExtensionFilterGroups.audioGroup:
            self = .audio
        default:
            self = .unsupported
        }
    }

    /// Loại của sách theo `extensionPackageId`. Thứ tự: `"local"`/rỗng → `text`; `local-comic`/`local-video`
    /// (`LocalMediaPackage`) → comic/video; tiện ích đã cài → catalog (mục registry chưa cài) → `text`.
    ///
    /// Đọc bảng chụp có lock của `ExtensionLibraryRepository` nên gọi được từ thread bất kỳ, không `await`.
    public static func resolve(packageId: String) -> ExtensionContentKind {
        resolveIfKnown(packageId: packageId) ?? .text
    }

    /// Như `resolve(packageId:)` nhưng trả `nil` khi không tra được cả bản cài lẫn catalog (tiện ích đã gỡ) —
    /// dùng cho chỗ **lọc/so loại** (đổi nguồn), nơi đoán `text` sẽ chặn nhầm sách tranh/video. `"local"`/rỗng → `text`.
    public static func resolveIfKnown(packageId: String) -> ExtensionContentKind? {
        let trimmed = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "local" else { return .text }
        if let local = LocalMediaPackage.contentKind(packageId: trimmed) { return local }
        if let installed = ExtensionLibraryRepository.snapshot(packageId: trimmed) {
            return ExtensionContentKind(typeString: installed.type)
        }
        if let catalog = ExtensionLibraryRepository.catalogSnapshot(packageId: trimmed) {
            return ExtensionContentKind(typeString: catalog.type)
        }
        return nil
    }

    /// Loại theo `metadata.type` trong `plugin.json` của gói (dự phòng `type` ở gốc file, giống luồng cài) — đọc qua
    /// `ExtensionPackageReader`. Không đọc được ⇒ `text`.
    nonisolated public static func resolve(localPath: String) -> ExtensionContentKind {
        guard !localPath.isEmpty,
              let meta = ExtensionPackageReader.metadata(localPath: localPath),
              let type = meta["type"] as? String else { return .text }
        return ExtensionContentKind(typeString: type)
    }

    /// `true` với truyện tranh/video/âm thanh: không đi qua pipeline text (chuẩn hoá, dịch nội dung, TTS, xuất ebook).
    /// Mục lục của chúng gắn cờ `isSection` cho dòng `type: "section"` (`ExtensionManager.toc`).
    public var isMedia: Bool {
        self == .comic || self == .video || self == .audio
    }

    /// `true` với phim/âm thanh: item danh sách mở **thẳng** màn phát (`ContentDetailRouter`), không bao giờ mở trang
    /// Chi tiết; trình duyệt ẩn của tiện ích được tự phát media tắt tiếng (`WebViewLoader`).
    public var isPlayable: Bool {
        self == .video || self == .audio
    }

    /// Nhãn trùng nhãn nhóm thể loại của kho (`ExtensionFilterGroups.typeGroupLabel`).
    public var label: String {
        switch self {
        case .text: return ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.novelGroup)
        case .comic: return ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.comicGroup)
        case .video: return ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.videoGroup)
        case .audio: return ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.audioGroup)
        case .unsupported: return "Không hỗ trợ"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: return "book"
        case .comic: return "photo.on.rectangle"
        case .video: return "play.rectangle"
        case .audio: return "music.note"
        case .unsupported: return "questionmark.square.dashed"
        }
    }
}
