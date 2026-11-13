import Foundation

/// Đường dẫn + luật an toàn của trang **Dọn rác**.
///
/// Đường dẫn của từng owner được **chép lại** ở đây (kèm chỗ gốc) thay vì gọi init của owner: `ModelStore()` /
/// `VieNeuModelStore()` / `VieNeuTurboModelStore()` tạo thư mục khi khởi tạo — một lượt quét không được để lại thư mục mới
/// — và vài hằng chỉ thuộc màn thử VieNeu (`Cache-noopt`, `Static`, `.fbtrim`) sẽ bị gỡ khỏi code TTS. Đổi bố cục ở owner
/// thì sửa cả ở đây.
enum JunkPaths {
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// `Application Support/FreeBook` — cả loại "Giọng đọc & từ điển TTS" (`StorageUsageCategory.tts`).
    static var freeBookRoot: URL { applicationSupport.appendingPathComponent("FreeBook", isDirectory: true) }
    /// `FreeBook/TTS` — `ModelStore.rootURL` (NghiTTS): từ điển phiên âm ở gốc, model Piper ở `Models/`.
    static var ttsRoot: URL { freeBookRoot.appendingPathComponent("TTS", isDirectory: true) }
    /// `FreeBook/TTS/VieNeu` — `VieNeuModelStore.rootURL`.
    static var vieNeuRoot: URL { ttsRoot.appendingPathComponent("VieNeu", isDirectory: true) }
    /// `FreeBook/TTS/VieNeuTurbo` — `VieNeuTurboModelStore.rootURL`.
    static var vieNeuTurboRoot: URL { ttsRoot.appendingPathComponent("VieNeuTurbo", isDirectory: true) }

    // MARK: Tăng tốc Core ML của Nano (`VieNeuCoreMLPackage`)

    /// `VieNeuCoreMLPackage.rootURL`.
    static var coreMLRoot: URL { vieNeuRoot.appendingPathComponent("CoreML", isDirectory: true) }
    /// `VieNeuCoreMLPackage.directory`.
    static var coreMLPackageDirectory: URL { coreMLRoot.appendingPathComponent("Package", isDirectory: true) }
    /// `VieNeuCoreMLPackage.cacheDirectory` (`ModelCacheDirectory` của Core ML EP).
    static var coreMLCacheDirectory: URL { coreMLRoot.appendingPathComponent("Cache", isDirectory: true) }
    /// `VieNeuCoreMLPackage.legacyNoOptCacheDirectory` — bản thử P2b-0 (1.3.913), không còn dùng.
    static var coreMLLegacyNoOptCacheDirectory: URL { coreMLRoot.appendingPathComponent("Cache-noopt", isDirectory: true) }
    /// `VieNeuCoreMLPackage.resultsURL`.
    static var coreMLResultsDirectory: URL { coreMLRoot.appendingPathComponent("Results", isDirectory: true) }
    static var coreMLReaderVerifiedMarker: URL {
        coreMLResultsDirectory.appendingPathComponent(VieNeuCoreMLPackage.readerVerifiedMarkerName, isDirectory: false)
    }
    /// Manifest tải dở của `VieNeuCoreMLPackage.download` (`manifest.json.new`).
    static var coreMLPendingManifestName: String { VieNeuCoreMLPackage.manifestName + ".new" }
    /// Đuôi file trọng số bị phép thử "bỏ bản thừa" của màn thử đổi tên (`VieNeuCoreMLCacheInventory.trimSuffix`).
    static let coreMLTrimSuffix = ".fbtrim"
    /// Gói graph tĩnh của phép thử EP (`VieNeuNanoStaticPackage.directory`, màn thử đang gỡ).
    static var labStaticDirectory: URL { vieNeuRoot.appendingPathComponent("Static", isDirectory: true) }

    // MARK: Tải về dở

    /// Đuôi file đang chuyển của `VieNeuTurboModelClient.transfer` / `VieNeuModelClient` (`<đích>.partial`).
    static let partialSuffix = ".partial"
    /// `TranslationManager.translateDirectory` (không gọi thẳng: getter đó tạo thư mục).
    static var translateRoot: URL { applicationSupport.appendingPathComponent("translate", isDirectory: true) }

    // MARK: Dữ liệu theo truyện

    /// `BookBinManager.booksDirectory` — `<sha256(bookId)>.bin`.
    static var booksRoot: URL { applicationSupport.appendingPathComponent("books", isDirectory: true) }
    /// `ComicOfflineStore.rootDirectoryURL()` — `<sha256(bookId)>/`.
    static var comicsRoot: URL { applicationSupport.appendingPathComponent("comics", isDirectory: true) }
    /// `VideoOfflineStore.rootDirectoryURL()` — `<sha256(bookId)>/`.
    static var videosRoot: URL { applicationSupport.appendingPathComponent("videos", isDirectory: true) }
    /// `BookSourceChangeJournal.fileURL` (private ở owner) — còn file ⇒ đang có lượt đổi nguồn dở.
    static var sourceChangeJournal: URL {
        applicationSupport
            .appendingPathComponent("source_change", isDirectory: true)
            .appendingPathComponent("journal.json", isDirectory: false)
    }

    // MARK: Tiện ích

    static var extensionLegacyDirectory: URL { ExtensionStorePaths.legacyDirectory }
    static var extensionInstalledIndex: URL { ExtensionStorePaths.installedURL }

    static var temporaryRoot: URL { FileManager.default.temporaryDirectory }

    // MARK: - Không bao giờ đụng

    /// Thành phần đường dẫn không bao giờ xoá dù luật nào nói là rác: giọng nhân bản, dữ liệu AI, đăng nhập, sao lưu,
    /// file xuất, dữ liệu web, nháp tiện ích.
    static let protectedComponents: Set<String> = [
        "CustomVoices", "ai_memory", "ai_chats", "backups", "Exports", "WebKit", "Cookies",
        ".legado_login", ".telegram_backup_token", ".google_drive_token", "extension-drafts"
    ]
    /// Bản cứu tay (`*.corrupt-*`, `*.broken-*`, `*.bak-*`).
    static let protectedNameMarkers = [".corrupt-", ".broken-", ".bak-"]

    static func isProtected(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        if components.contains(where: { protectedComponents.contains($0) }) { return true }
        let name = url.lastPathComponent
        return protectedNameMarkers.contains { name.contains($0) }
    }

    /// `url` nằm **trong** `root` (không phải chính `root`) sau khi chuẩn hoá `.`/`..` và giải symlink — cùng cách
    /// `validatePathSafety(for:)` của các owner (`BookBinManager`, `ComicOfflineStore`…). Symlink trỏ ra ngoài ⇒ `false`.
    static func isSafelyInside(_ url: URL, root: URL) -> Bool {
        let canonicalRoot = root.standardized.resolvingSymlinksInPath().pathComponents
        let canonicalTarget = url.standardized.resolvingSymlinksInPath().pathComponents
        return canonicalTarget.count > canonicalRoot.count && canonicalTarget.starts(with: canonicalRoot)
    }

    /// Các gốc mà một mục rác được phép nằm trong — mục mang gốc khác bị từ chối lúc xoá.
    static var allowedRoots: [URL] {
        [freeBookRoot, translateRoot, temporaryRoot, booksRoot, comicsRoot, videosRoot, extensionLegacyDirectory]
    }
}
