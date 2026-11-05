import Foundation

/// Các loại dữ liệu của màn Dung lượng (Cài đặt › Thư Viện › Dung lượng), mỗi loại ứng với thư mục / file app thật sự
/// ghi (xem mục lưu trữ của `CLAUDE.md`). Thêm thư mục dữ liệu mới thì thêm vào đây, không thì nó rơi vào `other`.
///
/// `other` = tổng thư mục nhà của app trừ các loại đã liệt kê (WebKit, `tmp`, cache khác, trí nhớ AI…) ⇒ tổng trên màn
/// luôn khớp dung lượng thật. Chỉ ba loại xoá được (`isClearable`): tải lại được hoặc chỉ là bản sao để chia sẻ.
public enum StorageUsageCategory: String, CaseIterable, Sendable, Identifiable, Codable {
    case books
    case videos
    case comics
    case comicImageCache
    case chapterStore
    case translation
    case covers
    case extensions
    case tts
    case adBlock
    case backups
    case library
    case exports
    case logs
    case other

    public var id: String { rawValue }

    /// Một chỗ dữ liệu của loại: cả thư mục, hoặc các file cùng tiền tố trong một thư mục (`library.db*`, `app_logs*`).
    enum Location: Sendable {
        case directory(URL)
        case filesWithPrefix(directory: URL, prefix: String)
    }

    public var title: String {
        switch self {
        case .books: return "Truyện chữ đã tải"
        case .videos: return "Phim tải offline"
        case .comics: return "Truyện tranh offline"
        case .comicImageCache: return "Cache ảnh truyện tranh"
        case .chapterStore: return "Mục lục chương"
        case .translation: return "Từ điển & dịch"
        case .covers: return "Bìa truyện"
        case .extensions: return "Tiện ích"
        case .tts: return "Giọng đọc & từ điển TTS"
        case .adBlock: return "Bộ lọc quảng cáo"
        case .backups: return "Bản sao lưu"
        case .library: return "Thư viện (danh sách truyện)"
        case .exports: return "File xuất (TXT, EPUB…)"
        case .logs: return "Nhật ký (log)"
        case .other: return "Khác"
        }
    }

    /// Xoá được mà không mất dữ liệu người dùng: cache ảnh tải lại được, file xuất chỉ là bản để chia sẻ, log.
    public var isClearable: Bool {
        switch self {
        case .comicImageCache, .exports, .logs: return true
        default: return false
        }
    }

    /// Lời nhắc của hộp xác nhận xoá (chỉ loại xoá được).
    public var clearNote: String {
        switch self {
        case .comicImageCache: return "Ảnh sẽ tải lại khi đọc truyện tranh online. Truyện tranh đã tải offline không bị đụng."
        case .exports: return "Xoá bản xuất của các tác vụ xuất đã xong, kèm hàng của chúng trong Tải xuống. Bản đang xuất giữ nguyên."
        case .logs: return "Nhật ký dùng để tìm lỗi; xoá rồi không lấy lại được."
        default: return ""
        }
    }

    var locations: [Location] {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        func dir(_ name: String) -> Location { .directory(support.appendingPathComponent(name, isDirectory: true)) }
        switch self {
        case .books: return [dir("books")]
        case .videos: return [dir("videos")]
        case .comics: return [dir("comics")]
        case .comicImageCache: return [.directory(caches.appendingPathComponent("comic_images", isDirectory: true))]
        case .chapterStore: return [dir("chapters")]
        case .translation: return [dir("translate")]
        case .covers: return [dir("covers")]
        case .extensions: return [dir("extensions"), .directory(ExtensionStorePaths.rootURL)]
        case .tts: return [dir("FreeBook")]
        case .adBlock: return [dir("adblock")]
        case .backups: return [dir("backups")]
        case .library: return [.filesWithPrefix(directory: support, prefix: "library.db")]
        case .exports: return [.directory(ExportFileNaming.exportsDirectoryURL())]
        case .logs: return [.filesWithPrefix(directory: support, prefix: "app_logs")]
        case .other: return []
        }
    }
}
