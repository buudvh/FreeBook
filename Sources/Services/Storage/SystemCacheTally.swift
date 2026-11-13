import Foundation

/// Gom dung lượng của `Library/Caches` (phần không thuộc loại nào của màn Dung lượng) theo **nhóm tên dễ hiểu** — cho các
/// dòng cháu của "Bộ đệm hệ thống" (`StorageUsageHomeBreakdown`) và dòng log của `SystemCacheCleaner`.
///
/// - Đơn vị là thư mục / file **ngay trong** `Library/Caches`; các mục ra cùng tên nhóm thì gộp lại.
/// - Bộ đệm mạng (`URLCache`) nhận ra theo nội dung: thư mục có `Cache.db*` hoặc `fsCachedData` (thường mang tên bundle id).
/// - Bộ đệm WebKit có thể nằm ngay trong thư mục bundle id đó (`<bundle id>/WebKit/…`) ⇒ phần đó tính vào "Bộ đệm web".
struct SystemCacheTally: Sendable {
    static let coreMLTitle = "Core ML của hệ thống"
    static let networkTitle = "Bộ đệm mạng"
    static let webTitle = "Bộ đệm web"
    static let coverTitle = "Ảnh bìa tạm"
    static let snapshotTitle = "Ảnh đa nhiệm của hệ thống"
    /// Dòng phần còn lại sau 4 nhóm lớn nhất.
    static let remainderTitle = "Khác"

    private var childBytes: [String: Int64] = [:]
    private var nestedWebBytes: Int64 = 0
    private var urlCacheChildren: Set<String> = []

    /// `relative` = đường dẫn của một file, tương đối với `Library/Caches` (vd `com.apple.e5rt.e5bundlecache/…/x.bin`).
    mutating func add(relative: String, bytes: Int64) {
        guard bytes > 0 else { return }
        let components = relative.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true)
        guard let first = components.first else { return }
        let child = String(first)
        if components.count >= 2 {
            let second = String(components[1])
            if second.hasPrefix("Cache.db") || second == "fsCachedData" {
                urlCacheChildren.insert(child)
            }
            if Self.isWebKitName(second) {
                nestedWebBytes += bytes
                return
            }
        }
        childBytes[child, default: 0] += bytes
    }

    /// Tên nhóm → byte (đã gộp các mục cùng tên).
    func groups() -> [String: Int64] {
        var result: [String: Int64] = [:]
        for (child, bytes) in childBytes {
            result[Self.title(forChild: child, isURLCache: urlCacheChildren.contains(child)), default: 0] += bytes
        }
        if nestedWebBytes > 0 {
            result[Self.webTitle, default: 0] += nestedWebBytes
        }
        return result
    }

    /// Tên dễ hiểu của một mục ngay trong `Library/Caches`; không nhận ra ⇒ chính tên thư mục / file.
    static func title(forChild name: String, isURLCache: Bool) -> String {
        if name.hasPrefix("com.apple.e5rt") || name.hasPrefix("com.apple.CoreML") || name.hasPrefix("com.apple.mlcompiler") {
            return coreMLTitle
        }
        if isWebKitName(name) { return webTitle }
        // `CoverImageLoader` (cache đĩa ảnh bìa tải theo URL).
        if name == "cover_images" { return coverTitle }
        if name == "Snapshots" || name == "com.apple.SplashBoard" { return snapshotTitle }
        if isURLCache { return networkTitle }
        return name
    }

    private static func isWebKitName(_ name: String) -> Bool {
        name == "WebKit" || name.hasPrefix("com.apple.WebKit")
    }

    // MARK: - Đo riêng (cho `SystemCacheCleaner`)

    /// Tên các mục ngay trong `Library/Caches` thuộc một loại của màn Dung lượng (hiện là `comic_images`, `comic_ocr` của
    /// "Cache ảnh truyện tranh" — loại đó có nút "Xoá" riêng). Lấy từ `StorageUsageCategory.locations` nên thêm loại mới
    /// dưới `Library/Caches` là tự được chừa.
    static func ownedChildNames(cachesRoot: URL) -> Set<String> {
        let base = StorageRelativePath(root: cachesRoot)
        var names: Set<String> = []
        for category in StorageUsageCategory.allCases where category != .other {
            for location in category.locations {
                let url: URL
                switch location {
                case .directory(let directory): url = directory
                case .filesWithPrefix(let directory, _): url = directory
                }
                guard let relative = base.relative(url), let first = relative.split(separator: "/").first else { continue }
                names.insert(String(first))
            }
        }
        return names
    }

    /// Một lượt duyệt `cachesRoot` (bỏ các mục `skipping`), gom theo nhóm. Hàm thuần, gọi ngoài main.
    static func measure(cachesRoot: URL, skipping owned: Set<String>) -> SystemCacheTally {
        var tally = SystemCacheTally()
        let base = StorageRelativePath(root: cachesRoot)
        let fileManager = FileManager.default
        let children = (try? fileManager.contentsOfDirectory(at: cachesRoot, includingPropertiesForKeys: nil, options: [])) ?? []
        // Symlink không đếm (như lượt duyệt thư mục nhà: không đi theo symlink).
        for child in children where !owned.contains(child.lastPathComponent) && !JunkScanner.isSymbolicLink(child) {
            let name = child.lastPathComponent
            let own = StorageUsageScanner.fileSize(child)
            if own > 0 {
                tally.add(relative: name, bytes: own)
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: child,
                includingPropertiesForKeys: Array(StorageUsageScanner.sizeKeys),
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let item as URL in enumerator {
                let size = StorageUsageScanner.fileSize(item)
                guard size > 0, let relative = base.relative(item) else { continue }
                tally.add(relative: relative, bytes: size)
            }
        }
        return tally
    }
}
