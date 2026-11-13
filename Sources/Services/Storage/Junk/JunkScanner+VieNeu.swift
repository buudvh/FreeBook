import Foundation

/// Ba nhóm rác nằm trong `Application Support/FreeBook` (loại TTS): bản biên dịch Core ML cũ, dữ liệu màn thử VieNeu,
/// file tải dở. Chỉ dùng phần **trình đọc** của Core ML (`VieNeuCoreMLPackage` init / `manifest` / hằng tên,
/// `VieNeuCoreMLAccelerator.isVerified(package:)`); hằng của màn thử chép ở `JunkPaths`.
extension JunkScanner {
    // MARK: - Tăng tốc Core ML · bản biên dịch cũ

    /// - `Cache-noopt/`: bản thử P2b-0, không còn ai đọc.
    /// - `Cache/`: cả thư mục khi dấu tự kiểm của trình đọc không khớp gói hiện tại (`isVerified` sai — gói thiếu / đổi,
    ///   dấu thiếu / khác commit, bản biên dịch thiếu) hoặc còn file `.fbtrim` (phép thử bỏ trọng số bị ngắt ⇒ bản biên
    ///   dịch thiếu file). Kèm dấu `reader-verified.json` như `VieNeuCoreMLPackage.deleteCache()`. Dấu khớp ⇒ **giữ cả**
    ///   `Cache/`: khoá cache của từng graph (`COREML_CACHE_KEY`) do script xuất ghi trong graph, app không tự tính được
    ///   mục nào thuộc bộ đang dùng — chắc chắn hơn tiết kiệm.
    /// - `Package/`: file không có trong `manifest.json` hiện tại (giữ manifest; `*.partial` và `manifest.json.new` thuộc
    ///   nhóm file tải dở). Manifest đọc không được / khác định dạng ⇒ không xét `Package/`.
    static func coreMLStaleCandidates() -> [Candidate] {
        let fileManager = FileManager.default
        let root = JunkPaths.freeBookRoot
        guard fileManager.fileExists(atPath: JunkPaths.coreMLRoot.path) else { return [] }
        var result: [Candidate] = []

        let noOpt = JunkPaths.coreMLLegacyNoOptCacheDirectory
        if fileManager.fileExists(atPath: noOpt.path) {
            result.append(Candidate(url: noOpt, root: root))
        }

        // `VieNeuCoreMLPackage()` gọi `VieNeuModelStore()` (tạo `Models/` + `Assets/`): thư mục VieNeu đã có vì `CoreML/` có.
        let package = try? VieNeuCoreMLPackage()
        let cache = JunkPaths.coreMLCacheDirectory
        if fileManager.fileExists(atPath: cache.path) {
            let verified = package.map { VieNeuCoreMLAccelerator.isVerified(package: $0) } ?? false
            if !verified || containsFile(withSuffix: JunkPaths.coreMLTrimSuffix, in: cache) {
                result.append(Candidate(url: cache, root: root))
                let marker = JunkPaths.coreMLReaderVerifiedMarker
                if fileManager.fileExists(atPath: marker.path) {
                    result.append(Candidate(url: marker, root: root))
                }
            }
        }

        if let manifest = package?.manifest {
            var keep: Set<String> = [VieNeuCoreMLPackage.manifestName]
            for file in manifest.files {
                if let first = file.name.split(separator: "/").first { keep.insert(String(first)) }
            }
            for child in children(of: JunkPaths.coreMLPackageDirectory) {
                let name = child.lastPathComponent
                guard !keep.contains(name), !name.hasSuffix(JunkPaths.partialSuffix),
                      name != JunkPaths.coreMLPendingManifestName else { continue }
                result.append(Candidate(url: child, root: root))
            }
        }
        return result
    }

    /// Lần đầu thấy file có đuôi `suffix` trong cây `directory` thì dừng.
    static func containsFile(withSuffix suffix: String, in directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return false }
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(suffix) {
            return true
        }
        return false
    }

    // MARK: - Dữ liệu màn thử VieNeu

    /// `VieNeu/Static/` (gói graph tĩnh của phép thử EP) cả thư mục, và mọi file trong `CoreML/Results/` trừ dấu tự kiểm
    /// của trình đọc (báo cáo đo tự động, nhật ký biên dịch…). Giữ thư mục `Results/`.
    static func labDataCandidates() -> [Candidate] {
        let root = JunkPaths.freeBookRoot
        var result: [Candidate] = []
        let staticDirectory = JunkPaths.labStaticDirectory
        if FileManager.default.fileExists(atPath: staticDirectory.path) {
            result.append(Candidate(url: staticDirectory, root: root))
        }
        for child in children(of: JunkPaths.coreMLResultsDirectory)
        where child.lastPathComponent != VieNeuCoreMLPackage.readerVerifiedMarkerName {
            result.append(Candidate(url: child, root: root))
        }
        return result
    }

    // MARK: - File tải dở

    /// `*.partial` trong `FreeBook/` và `translate/` (không vào `CustomVoices/`), cộng `manifest.json.new` của gói Core ML.
    /// Người gọi chỉ quét khi không có lượt tải nào: file `.partial` chỉ tồn tại giữa hai lần `moveItem` của một lượt tải,
    /// còn lại sau đó là lượt bị app tắt giữa chừng.
    static func partialDownloadCandidates() -> [Candidate] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        var result: [Candidate] = []
        for root in [JunkPaths.freeBookRoot, JunkPaths.translateRoot] {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    if JunkPaths.protectedComponents.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    continue
                }
                if values?.isRegularFile == true, url.lastPathComponent.hasSuffix(JunkPaths.partialSuffix) {
                    result.append(Candidate(url: url, root: root))
                }
            }
        }
        let pendingManifest = JunkPaths.coreMLPackageDirectory
            .appendingPathComponent(JunkPaths.coreMLPendingManifestName, isDirectory: false)
        if fileManager.fileExists(atPath: pendingManifest.path) {
            result.append(Candidate(url: pendingManifest, root: JunkPaths.freeBookRoot))
        }
        return result
    }
}
