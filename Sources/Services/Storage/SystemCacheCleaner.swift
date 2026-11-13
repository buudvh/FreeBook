import Foundation
import WebKit

/// Nút "Xoá" của dòng **"Bộ đệm hệ thống"** (màn Dung lượng › Khác): xoá mọi mục ngay trong `Library/Caches` trừ thư mục
/// của các loại có nút riêng (`comic_images`, `comic_ocr` của "Cache ảnh truyện tranh" — `SystemCacheTally.ownedChildNames`).
///
/// `Library/Caches` là chỗ iOS được phép tự dọn khi máy thiếu chỗ ⇒ mọi owner phải tự tạo lại được; cookie, dữ liệu trang
/// web (local storage, đăng nhập) nằm ở `Library/WebKit`, `Library/Cookies`, `Library/HTTPStorages` — không đụng.
///
/// Thứ tự: chặn khi đang đọc truyện / đang chuẩn bị Tăng tốc Core ML → đo theo nhóm + nhả Core ML của trình đọc (session
/// map file từ bộ đệm Core ML của hệ thống) → xoá bằng API chính thức (`URLCache`, kho WebKit mặc định: chỉ các loại cache)
/// → xoá file ngoài main, kiểm từng mục còn nằm trong `Library/Caches` (giải symlink) → đo lại, ghi một dòng log theo nhóm
/// → gói Core ML đã qua tự kiểm thì nạp sẵn lại ở nền (không thì lần đọc đầu chạy ORT tới lần engine khởi động sau).
///
/// Không báo toast (Services không gọi `ToastManager`): trả lý do từ chối, màn đo lại rồi tự báo số đã giải phóng.
enum SystemCacheCleaner {
    /// Thư mục owner chỉ tạo một lần lúc khởi tạo (`CoverImageLoader.init`) ⇒ chỉ xoá bên trong, giữ thư mục, kẻo mọi lần
    /// ghi cache ảnh bìa báo lỗi tới lần mở app sau.
    static let keptFolderNames: Set<String> = ["cover_images"]

    /// Các loại dữ liệu cache của kho WebKit mặc định (không gồm cookie, local storage, IndexedDB…).
    private static let webCacheTypes: Set<String> = [
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeFetchCache,
        WKWebsiteDataTypeOfflineWebApplicationCache
    ]

    @MainActor private static var isRunning = false

    private struct Removal: Sendable {
        var removedCount = 0
        var failures: [String] = []
        var after: [String: Int64] = [:]
    }

    /// Xoá bộ đệm hệ thống. `nil` = đã xoá; chuỗi = lý do không xoá (màn hiện toast).
    @MainActor
    static func clear() async -> String? {
        if TTSManager.shared.isPlaying {
            return "Đang đọc truyện — dừng đọc rồi xoá bộ đệm."
        }
        if VieNeuCoreMLAccelerator.shared.isBusy {
            return "Đang chuẩn bị Tăng tốc Core ML — đợi xong rồi xoá."
        }
        guard !isRunning else { return "Đang xoá bộ đệm hệ thống." }
        guard let root = cachesRoot() else {
            AppLogger.shared.log("❌ [SystemCache] Không định vị được Library/Caches — không xoá gì")
            return "Không định vị được thư mục bộ đệm."
        }
        isRunning = true
        defer { isRunning = false }
        let package = VieNeuCoreMLAccelerator.shared.package
        let readerUsesVieNeu = TTSManager.shared.tool == "vieneu"

        // Đo trước các bước xoá bằng API (chúng làm thư mục nhỏ đi trước) + nhả Core ML — `release` chờ khoá của backend
        // nên chạy ngoài main.
        let before = await Task.detached(priority: .utility) { () -> [String: Int64] in
            VieNeuCoreMLReaderRoute.shared.release(reason: "xoá bộ đệm hệ thống")
            let owned = SystemCacheTally.ownedChildNames(cachesRoot: root)
            return SystemCacheTally.measure(cachesRoot: root, skipping: owned).groups()
        }.value

        URLCache.shared.removeAllCachedResponses()
        await WKWebsiteDataStore.default().removeData(ofTypes: webCacheTypes, modifiedSince: .distantPast)

        let removal = await Task.detached(priority: .utility) { () -> Removal in
            let owned = SystemCacheTally.ownedChildNames(cachesRoot: root)
            var result = SystemCacheCleaner.removeChildren(of: root, keeping: owned)
            result.after = SystemCacheTally.measure(cachesRoot: root, skipping: owned).groups()
            return result
        }.value

        log(before: before, removal: removal)

        // Gói đã qua tự kiểm ⇒ nạp sẵn + chạy nháp lại (dựng lại backend vừa nhả, biên dịch lại bản Core ML của hệ thống).
        // Kiểm trong task nền: `isVerified` đọc + băm file. Chưa qua tự kiểm thì thôi — `warmUpIfReady` sẽ tự tải + biên
        // dịch gói. Trình đọc không dùng VieNeu thì engine Nano tự nạp khi khởi động, khỏi giữ session trong RAM.
        if readerUsesVieNeu, let package {
            Task.detached(priority: .utility) {
                guard VieNeuCoreMLAccelerator.isVerified(package: package) else { return }
                VieNeuTTSService.shared?.warmUpCoreMLForReader()
            }
        }
        return nil
    }

    // MARK: - Xoá file (ngoài main)

    /// `FileManager` trả về đúng `…/Library/Caches` mới dùng — lỡ trả chỗ khác thì không xoá gì.
    private static func cachesRoot() -> URL? {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              url.standardizedFileURL.path.hasSuffix("/Library/Caches") else { return nil }
        return url
    }

    /// Xoá từng mục ngay trong `root` (kể cả file ẩn) trừ `owned`; thư mục giữ lại (`keptFolderNames`) thì chỉ xoá bên trong.
    /// Lỗi từng mục chỉ ghi lại, không dừng lượt.
    private static func removeChildren(of root: URL, keeping owned: Set<String>) -> Removal {
        let fileManager = FileManager.default
        var removal = Removal()
        let children = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? []
        for child in children where !owned.contains(child.lastPathComponent) {
            if keptFolderNames.contains(child.lastPathComponent),
               JunkScanner.isDirectory(child), !JunkScanner.isSymbolicLink(child) {
                let inner = (try? fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [])) ?? []
                for item in inner {
                    remove(item, root: root, into: &removal)
                }
            } else {
                remove(child, root: root, into: &removal)
            }
        }
        return removal
    }

    /// Xoá một mục sau khi kiểm nó còn nằm **trong** `root` (chuẩn hoá `.`/`..`, giải symlink — `JunkPaths.isSafelyInside`).
    /// Symlink thì chỉ xoá chính link (`removeItem` không đi theo link); link trỏ ra ngoài bị từ chối.
    private static func remove(_ item: URL, root: URL, into removal: inout Removal) {
        let name = item.lastPathComponent
        guard JunkPaths.isSafelyInside(item, root: root) else {
            removal.failures.append("\(name): ngoài Library/Caches")
            return
        }
        do {
            try FileManager.default.removeItem(at: item)
            removal.removedCount += 1
        } catch {
            if FileManager.default.fileExists(atPath: item.path) {
                removal.failures.append("\(name): \(error.localizedDescription)")
            } else {
                removal.removedCount += 1
            }
        }
    }

    // MARK: - Log

    private static func log(before: [String: Int64], removal: Removal) {
        let freed = before
            .map { (title: $0.key, bytes: $0.value - (removal.after[$0.key] ?? 0)) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
        let total = freed.reduce(Int64(0)) { $0 + $1.bytes }
        let groups = freed.map { "\($0.title) \(StorageUsageSnapshot.format($0.bytes))" }
        AppLogger.shared.log(
            "🧹 [SystemCache] Đã xoá \(removal.removedCount) mục, giải phóng \(StorageUsageSnapshot.format(total))"
            + (groups.isEmpty ? "" : ": " + groups.joined(separator: " · "))
        )
        if !removal.failures.isEmpty {
            AppLogger.shared.log(
                "❌ [SystemCache] \(removal.failures.count) mục không xoá được: "
                + removal.failures.prefix(5).joined(separator: " · ")
            )
        }
    }
}
