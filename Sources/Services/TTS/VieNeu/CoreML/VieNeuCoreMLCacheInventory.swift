import Foundation

/// Kiểm kê thư mục cache Core ML của Nano (`VieNeuCoreMLPackage.cacheDirectory`) cho phép đo P2a "Đo nạp Core ML":
/// mục nào thuộc graph nào, mỗi mục tốn bao nhiêu cho **gói MLProgram** ORT ghi ra và bao nhiêu cho **bản biên dịch**
/// (`compiled_model.mlmodelc`), file trọng số nào trùng byte.
///
/// Bố cục ORT 1.24.2 (đã đọc mã, báo cáo §11): `Cache/<COREML_CACHE_KEY>/<id>_static_mlprogram/model/` là gói, bản biên
/// dịch nằm **trong** gói (`…/model/compiled_model.mlmodelc`). Khoá cache do script xuất ghi: `vnve<T>x…` (VE main),
/// `vncodec<T>x…` (codec — 2 partition ⇒ 2 mục). Chỉ đọc, trừ `restoreTrimmed` (trả file trọng số bị phép thử đổi tên).
enum VieNeuCoreMLCacheInventory {
    /// Đuôi gắn vào file trọng số của gói khi thử bỏ bản thừa — lần chạy sau (hoặc lúc mở màn thử) tự trả về.
    static let trimSuffix = ".fbtrim"
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
        /// Dung lượng phần gói (mọi file ngoài bản biên dịch), bản biên dịch, tổng.
        let packageBytes: Int64
        let compiledBytes: Int64
        /// File ≥ 1 MB: đường dẫn tương đối với mục + dung lượng.
        let largeFiles: [(path: String, bytes: Int64)]
        /// File trọng số của gói (ngoài bản biên dịch) — ứng viên bỏ được.
        let packageWeightFiles: [URL]
        /// Mọi file `weight.bin` (gói + bản biên dịch) để băm.
        let weightFiles: [URL]

        var label: String {
            guard let kind, let bucket else { return key }
            return "\(kind) T\(bucket)"
        }

        /// Số partition ở đầu tên mục (`0_static_mlprogram` ⇒ "0"); codec có 2 partition.
        var partition: String { String(name.prefix { $0.isNumber }) }
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
                entries.append(describe(child, key: key.lastPathComponent, kind: kind, bucket: bucket))
            }
        }
        return entries.sorted {
            ($0.kind ?? "~", $0.bucket ?? .max, $0.name) < ($1.kind ?? "~", $1.bucket ?? .max, $1.name)
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

    private static func describe(_ entry: URL, key: String, kind: String?, bucket: Int?) -> Entry {
        let base = entry.resolvingSymlinksInPath().path
        var compiledURL: URL?
        var packageBytes: Int64 = 0
        var compiledBytes: Int64 = 0
        var largeFiles: [(path: String, bytes: Int64)] = []
        var packageWeights: [URL] = []
        var weights: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        if let enumerator = FileManager.default.enumerator(at: entry, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let relative = relativePath(url, base: base)
                if values?.isDirectory == true {
                    if url.lastPathComponent == compiledName, compiledURL == nil { compiledURL = url }
                    continue
                }
                let bytes = Int64(values?.fileSize ?? 0)
                let insideCompiled = url.pathComponents.contains(compiledName)
                if insideCompiled { compiledBytes += bytes } else { packageBytes += bytes }
                if bytes >= 1 << 20 { largeFiles.append((path: relative, bytes: bytes)) }
                if url.lastPathComponent == "weight.bin" {
                    weights.append(url)
                    if !insideCompiled { packageWeights.append(url) }
                }
            }
        }
        return Entry(
            kind: kind, bucket: bucket, key: key, name: entry.lastPathComponent, url: entry, compiledURL: compiledURL,
            packageBytes: packageBytes, compiledBytes: compiledBytes,
            largeFiles: largeFiles.sorted { $0.bytes > $1.bytes }, packageWeightFiles: packageWeights, weightFiles: weights
        )
    }

    private static func relativePath(_ url: URL, base: String) -> String {
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(base) else { return url.lastPathComponent }
        return String(path.dropFirst(base.count).drop { $0 == "/" })
    }

    // MARK: - Trọng số trùng byte

    struct WeightGroup: Sendable {
        let digest: String
        let bytes: Int64
        let members: [String]
    }

    /// Băm mọi `weight.bin` (gói + bản biên dịch) rồi gom theo sha256 — nhóm > 1 phần tử = gộp được bằng hard link.
    static func weightGroups(_ entries: [Entry], progress: (String) -> Void) throws -> [WeightGroup] {
        var byDigest: [String: (bytes: Int64, members: [String])] = [:]
        var order: [String] = []
        for entry in entries {
            for url in entry.weightFiles {
                try Task.checkCancellation()
                let inside = url.pathComponents.contains(compiledName) ? "biên dịch" : "gói"
                progress("Băm trọng số \(entry.label) (\(inside))…")
                let digest = try VieNeuNanoStaticPackage.sha256(of: url)
                if byDigest[digest] == nil { order.append(digest) }
                byDigest[digest, default: (VieNeuTurboModelStore.fileSize(at: url), [])].members
                    .append("\(entry.label)#\(entry.partition) \(inside)")
            }
        }
        return order.compactMap { digest in
            byDigest[digest].map { WeightGroup(digest: digest, bytes: $0.bytes, members: $0.members) }
        }
    }

    // MARK: - Trả file bị đổi tên

    /// Trả mọi file `*.fbtrim` về tên cũ (phép thử bỏ bản thừa bị ngắt giữa chừng). Tên cũ đã có file (ORT ghi lại gói) ⇒
    /// xoá bản đổi tên. Trả số file đã xử lý.
    @discardableResult
    static func restoreTrimmed(_ cacheDirectory: URL) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: nil) else { return 0 }
        var trimmed: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(trimSuffix) {
            trimmed.append(url)
        }
        for url in trimmed {
            restore(url)
        }
        return trimmed.count
    }

    /// Trả một file `<tên>.fbtrim` về `<tên>`.
    static func restore(_ trimmedURL: URL) {
        let fileManager = FileManager.default
        let originalPath = String(trimmedURL.path.dropLast(trimSuffix.count))
        if fileManager.fileExists(atPath: originalPath) {
            try? fileManager.removeItem(at: trimmedURL)
        } else {
            try? fileManager.moveItem(atPath: trimmedURL.path, toPath: originalPath)
        }
    }
}
