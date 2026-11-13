import Foundation

/// Kiểm kê thư mục cache Core ML của Nano (`VieNeuCoreMLPackage.cacheDirectory`): mục nào thuộc graph nào, đã có **bản
/// biên dịch** (`compiled_model.mlmodelc`) chưa — `VieNeuCoreMLAccelerator` đếm số bản biên dịch (dấu tự kiểm, trang
/// Cài đặt VieNeu). Chỉ đọc.
///
/// Bố cục ORT 1.24.2 (đã đọc mã, báo cáo §11): `Cache/<COREML_CACHE_KEY>/<id>_static_mlprogram/model/` là gói, bản biên
/// dịch nằm **trong** gói (`…/model/compiled_model.mlmodelc`). Khoá cache do script xuất ghi: `vnve<T>x…` (VE main),
/// `vncodec<T>x…` (codec — 2 partition ⇒ 2 mục).
enum VieNeuCoreMLCacheInventory {
    static let compiledName = "compiled_model.mlmodelc"

    struct Entry: Sendable {
        /// "ve" / "codec"; `nil` = khoá cache không theo mẫu của script xuất.
        let kind: String?
        let bucket: Int?
        let key: String
        let name: String
        let url: URL
        /// `nil` = chưa biên dịch xong.
        let compiledURL: URL?
    }

    /// Quét `Cache/`; sắp theo loại rồi bucket.
    static func scan(_ cacheDirectory: URL) -> [Entry] {
        let fileManager = FileManager.default
        let keys = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        var entries: [Entry] = []
        for key in keys {
            let (kind, bucket) = parseKey(key.lastPathComponent)
            let children = (try? fileManager.contentsOfDirectory(at: key, includingPropertiesForKeys: nil)) ?? []
            for child in children where child.lastPathComponent.hasSuffix("_mlprogram") {
                entries.append(Entry(
                    kind: kind, bucket: bucket, key: key.lastPathComponent, name: child.lastPathComponent, url: child,
                    compiledURL: compiledURL(in: child)
                ))
            }
        }
        return entries.sorted { lhs, rhs in
            let left: (String, Int, String) = (lhs.kind ?? "~", lhs.bucket ?? Int.max, lhs.name)
            let right: (String, Int, String) = (rhs.kind ?? "~", rhs.bucket ?? Int.max, rhs.name)
            return left < right
        }
    }

    /// `vnve64xab12…` ⇒ ("ve", 64); `vncodec128x…` ⇒ ("codec", 128).
    static func parseKey(_ key: String) -> (String?, Int?) {
        for kind in ["codec", "ve"] where key.hasPrefix("vn\(kind)") {
            let digits = key.dropFirst(2 + kind.count).prefix { $0.isNumber }
            return (kind, Int(digits))
        }
        return (nil, nil)
    }

    /// Thư mục `compiled_model.mlmodelc` đầu tiên trong mục (ở bất kỳ tầng nào — không phụ thuộc bố cục của ORT).
    private static func compiledURL(in entry: URL) -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: entry, includingPropertiesForKeys: keys) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == compiledName {
            if (try? url.resourceValues(forKeys: Set(keys)))?.isDirectory == true { return url }
        }
        return nil
    }
}
