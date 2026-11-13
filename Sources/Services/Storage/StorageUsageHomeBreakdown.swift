import Foundation

/// Lượt duyệt **cả thư mục nhà** của màn Dung lượng: tổng dung lượng app (như trước) và cùng lúc chia phần "Khác" (= nhà
/// trừ mọi loại đã liệt kê) thành file tạm, bộ đệm hệ thống, dữ liệu web, không rõ chủ.
///
/// - Vẫn đếm **mọi** file (kể cả file của các loại) để tổng không phụ thuộc việc so đường dẫn: lỡ một gốc không khớp thì
///   phần đó chỉ rơi vào "không rõ chủ" (là phần còn lại), không làm sai tổng hay cộng trùng.
/// - Gốc tính tương đối với chính thư mục nhà (`StorageRelativePath` chịu cả hai dạng `/private/var` và `/var`).
/// - "Không rõ chủ" chỉ hiện, không bao giờ tự xoá; mỗi lần đo ghi một dòng log ~10 mục lớn nhất để sau này phân loại.
/// - Hai dòng có dòng cháu (`StorageUsageSubItem`, 4 mục lớn nhất + phần còn lại): "Bộ đệm hệ thống" theo nhóm tên dễ hiểu
///   của các mục ngay trong `Library/Caches` (`SystemCacheTally`), "Không rõ chủ" theo đường dẫn tương đối với thư mục nhà.
enum StorageUsageHomeBreakdown {
    struct Result {
        let homeBytes: Int64
        let temporaryBytes: Int64
        let cachesBytes: Int64
        let webBytes: Int64
        /// Phần bộ đệm hệ thống theo mục ngay trong `Library/Caches` (không gồm thư mục của các loại).
        let cachesTally: SystemCacheTally
        /// Mục không rõ chủ (đường dẫn tương đối với thư mục nhà) → byte — cho dòng log và dòng cháu.
        let unknownTally: [String: Int64]

        /// Dòng con của "Khác": cắt theo `otherBytes` để các dòng cộng lại đúng bằng số của "Khác"; "không rõ chủ" là phần
        /// còn lại. Dòng cháu cắt theo số của dòng con đã cắt.
        func details(otherBytes: Int64) -> [StorageUsageDetail] {
            let other = max(0, otherBytes)
            let temporary = min(max(0, temporaryBytes), other)
            let caches = min(max(0, cachesBytes), other - temporary)
            let web = min(max(0, webBytes), other - temporary - caches)
            let unknown = other - temporary - caches - web
            let cachesChildren = StorageUsageSubItem.top(
                cachesTally.groups(), total: caches, remainderTitle: SystemCacheTally.remainderTitle
            )
            let unknownChildren = StorageUsageSubItem.top(unknownTally, total: unknown, remainderTitle: "Còn lại")
            return [
                StorageUsageDetail(kind: .temporary, bytes: temporary, count: nil),
                StorageUsageDetail(kind: .systemCaches, bytes: caches, count: nil, children: cachesChildren),
                StorageUsageDetail(kind: .webData, bytes: web, count: nil),
                StorageUsageDetail(kind: .unknown, bytes: unknown, count: nil, children: unknownChildren)
            ].filter { $0.bytes > 0 }
        }

        /// Một dòng log: tối đa `limit` mục không rõ chủ lớn nhất.
        func logUnknown(limit: Int = 10) {
            guard !unknownTally.isEmpty else { return }
            let total = unknownTally.values.reduce(Int64(0), +)
            let top = unknownTally.sorted { $0.value > $1.value }.prefix(limit)
                .map { "\($0.key) \(StorageUsageSnapshot.format($0.value))" }
            AppLogger.shared.log(
                "📦 [StorageUsage] Khác không rõ chủ \(StorageUsageSnapshot.format(total)) (\(unknownTally.count) mục): "
                + top.joined(separator: " · ")
            )
        }
    }

    static func measure(home: URL) -> Result {
        let base = StorageRelativePath(root: home)
        var categoryRoots: [String] = []
        var prefixRules: [(directory: String, prefix: String)] = []
        for category in StorageUsageCategory.allCases where category != .other {
            for location in category.locations {
                switch location {
                case .directory(let url):
                    if let relative = base.relative(url), !relative.isEmpty { categoryRoots.append(relative) }
                case .filesWithPrefix(let directory, let prefix):
                    if let relative = base.relative(directory) {
                        prefixRules.append((directory: relative, prefix: prefix))
                    }
                }
            }
        }

        let fileManager = FileManager.default
        let temporary = nonEmpty(base.relative(fileManager.temporaryDirectory)) ?? "tmp"
        let caches = nonEmpty(base.relative(fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]))
            ?? "Library/Caches"
        let library = nonEmpty(base.relative(fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]))
            ?? "Library"
        // `HTTPStorages/` = kho cookie / HSTS của URLSession (đăng nhập nguồn qua `HTTPCookieStorage.shared`).
        let web = [library + "/WebKit", library + "/Cookies", library + "/HTTPStorages"]
        let knownRoots = categoryRoots + [temporary, caches] + web

        var total: Int64 = 0
        var temporaryBytes: Int64 = 0
        var cachesBytes: Int64 = 0
        var webBytes: Int64 = 0
        var cachesTally = SystemCacheTally()
        var tally: [String: Int64] = [:]

        if let enumerator = fileManager.enumerator(
            at: home,
            includingPropertiesForKeys: Array(StorageUsageScanner.sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let item as URL in enumerator {
                let size = StorageUsageScanner.fileSize(item)
                guard size > 0 else { continue }
                total += size
                guard let relative = base.relative(item) else {
                    tally["?", default: 0] += size
                    continue
                }
                if categoryRoots.contains(where: { StorageRelativePath.isSameOrInside(relative, $0) })
                    || matchesPrefixRule(relative, prefixRules) {
                    continue
                }
                if StorageRelativePath.isSameOrInside(relative, temporary) {
                    temporaryBytes += size
                } else if StorageRelativePath.isSameOrInside(relative, caches) {
                    cachesBytes += size
                    if relative.count > caches.count + 1 {
                        cachesTally.add(relative: String(relative.dropFirst(caches.count + 1)), bytes: size)
                    }
                } else if web.contains(where: { StorageRelativePath.isSameOrInside(relative, $0) }) {
                    webBytes += size
                } else {
                    tally[StorageRelativePath.groupingRoot(of: relative, knownRoots: knownRoots), default: 0] += size
                }
            }
        }
        return Result(
            homeBytes: total, temporaryBytes: temporaryBytes, cachesBytes: cachesBytes, webBytes: webBytes,
            cachesTally: cachesTally, unknownTally: tally
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// File của loại dạng "các file cùng tiền tố trong một thư mục" (`library.db*`, `app_logs*`).
    private static func matchesPrefixRule(_ relative: String, _ rules: [(directory: String, prefix: String)]) -> Bool {
        guard !rules.isEmpty else { return false }
        let directory: String
        let name: String
        if let slash = relative.lastIndex(of: "/") {
            directory = String(relative[..<slash])
            name = String(relative[relative.index(after: slash)...])
        } else {
            directory = ""
            name = relative
        }
        return rules.contains { $0.directory == directory && name.hasPrefix($0.prefix) }
    }
}
