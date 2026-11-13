import CoreML
import Foundation

/// Phép đo P2a **"Đo nạp Core ML"** (báo cáo §12): trả lời hai câu chặn việc đưa Core ML vào trình đọc.
///
/// 1. **Nạp chậm ở đâu?** Đo lần nạp ~20 s mỗi VE mà lượt đo tự động thấy là của ORT hay của Core ML:
///    - ORT CPU EP cùng graph — phần ORT dựng graph + chép trọng số, không có Core ML;
///    - **Core ML gốc** (`MLModel(contentsOf:)`, `.cpuOnly`) đọc thẳng `compiled_model.mlmodelc` mà ORT để trong cache;
///    - ORT + Core ML EP như lượt đọc (`VieNeuCoreMLFlowBackend.coreMLOptions`), kèm dấu hiệu ORT có ghi lại gói không.
///    Mỗi cách 2 lần, xen kẽ (Core ML gốc → ORT → Core ML gốc → ORT) để nhiệt không dồn về một phía.
/// 2. **4,16 GB nằm ở đâu?** Dung lượng từng mục (gói ORT ghi ra / bản biên dịch), băm mọi `weight.bin` tìm bản trùng
///    byte, và **thử bỏ bản trọng số của gói** ở VE bucket nhỏ nhất: đổi tên (không xoá) → nạp lại → ORT còn coi là có
///    bản lưu không, tự kiểm golden còn đúng không → trả file về.
///
/// Chạy ngoài MainActor (`Task.detached`), từng bước một; không đụng đường đọc truyện.
enum VieNeuCoreMLLoadWorker {
    struct Outcome: Sendable {
        let report: String
        let summary: [String]
    }

    struct Measure: Sendable {
        let wallMs: Double
        let cpuMs: Double

        var text: String { String(format: "%.2f s · CPU %.2f s", wallMs / 1_000, cpuMs / 1_000) }
        var seconds: String { String(format: "%.1f", wallMs / 1_000) }
    }

    private struct Target {
        let kind: String
        let bucket: Int
        let graphName: String
        let weightsName: String

        var label: String { "\(kind) T\(bucket)" }
    }

    /// ORT chỉ in bảng partition khi **dựng** gói Core ML (có bản lưu thì không) — `VieNeuCoreMLPreparer.partitionNote`.
    static let rebuildMarker = "number of partitions supported by CoreML: "

    static func run(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        progress: @Sendable (String) -> Void
    ) throws -> Outcome {
        try FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
        let restored = VieNeuCoreMLCacheInventory.restoreTrimmed(package.cacheDirectory)
        var lines: [String] = []
        var summary: [String] = []

        // 1. Dung lượng.
        progress("Kiểm kê cache Core ML…")
        let entries = VieNeuCoreMLCacheInventory.scan(package.cacheDirectory)
        lines.append("Đo nạp Core ML (P2a) — gói \(bytes(package.packageBytes)) · cache \(bytes(package.cacheBytes)) · \(entries.count) mục biên dịch")
        lines.append("nhiệt lúc bắt đầu \(thermal()) · \(ProcessMemoryProbe.snapshot().summary)")
        if restored > 0 { lines.append("đã trả \(restored) file trọng số của lần thử trước bị ngắt") }
        lines.append(contentsOf: inventoryLines(entries))
        let packagePart = entries.reduce(Int64(0)) { $0 + $1.packageBytes }
        let compiledPart = entries.reduce(Int64(0)) { $0 + $1.compiledBytes }
        let packageWeights = entries.flatMap(\.packageWeightFiles).reduce(Int64(0)) {
            $0 + VieNeuTurboModelStore.fileSize(at: $1)
        }
        lines.append("tổng: gói \(bytes(packagePart)) (trọng số \(bytes(packageWeights))) · biên dịch \(bytes(compiledPart))")
        summary.append("cache: gói \(bytes(packagePart)) · biên dịch \(bytes(compiledPart)) · trọng số trong gói \(bytes(packageWeights))")

        // 2. Trọng số trùng byte.
        lines.append("== 2. File trọng số trùng byte (sha256)")
        let groups = try VieNeuCoreMLCacheInventory.weightGroups(entries, progress: progress)
        for group in groups {
            lines.append("\(group.digest.prefix(12)) · \(bytes(group.bytes)) × \(group.members.count): \(group.members.joined(separator: ", "))")
        }
        let duplicateBytes = groups.reduce(Int64(0)) { $0 + $1.bytes * Int64(max(0, $1.members.count - 1)) }
        let weightFileCount = groups.reduce(0) { $0 + $1.members.count }
        summary.append("trọng số: \(weightFileCount) file, \(groups.count) bản khác nhau ⇒ gộp bản trùng bớt \(bytes(duplicateBytes))")

        // 3. Thời gian nạp.
        lines.append("== 3. Thời gian nạp (mỗi cách 2 lần, xen kẽ; QoS userInitiated)")
        for target in targets(manifest) {
            try Task.checkCancellation()
            let graphEntries = entries.filter { $0.kind == target.kind && $0.bucket == target.bucket }
            let result = try measureLoads(target: target, entries: graphEntries, package: package, progress: progress)
            lines.append(contentsOf: result.lines)
            summary.append(result.summary)
        }

        // 4. Thử bỏ bản trọng số của gói.
        try Task.checkCancellation()
        let trim = try trimTest(entries: entries, package: package, manifest: manifest, progress: progress)
        lines.append(contentsOf: trim.lines)
        summary.append(trim.summary)
        lines.append("nhiệt lúc xong \(thermal()) · \(ProcessMemoryProbe.snapshot().summary)")
        return Outcome(report: lines.joined(separator: "\n"), summary: summary)
    }

    // MARK: - Thời gian nạp

    private static func targets(_ manifest: VieNeuCoreMLPackage.Manifest) -> [Target] {
        var result: [Target] = []
        if let ve = manifest.veBuckets.min() {
            result.append(Target(kind: "ve", bucket: ve, graphName: "ve_main_T\(ve).onnx", weightsName: manifest.veWeights))
        }
        if let codec = manifest.codecBuckets.min() {
            result.append(Target(kind: "codec", bucket: codec, graphName: "codec_T\(codec).onnx", weightsName: manifest.codecWeights))
        }
        return result
    }

    private static func measureLoads(
        target: Target,
        entries: [VieNeuCoreMLCacheInventory.Entry],
        package: VieNeuCoreMLPackage,
        progress: (String) -> Void
    ) throws -> (lines: [String], summary: String) {
        let compiledURLs = entries.compactMap(\.compiledURL)
        guard !compiledURLs.isEmpty else {
            return (["\(target.label): chưa có bản biên dịch — bỏ qua"], "\(target.label): chưa có bản biên dịch")
        }
        var lines: [String] = []
        progress("\(target.label): ORT CPU (không Core ML)…")
        let plain = try measure { try ortSession(target, package: package, provider: "CPU", logPath: "") }
        lines.append("\(target.label) · ORT CPU, không Core ML (dựng graph + chép trọng số): \(plain.text) · \(thermal())")
        var native: [Measure] = []
        var bridged: [Measure] = []
        var rebuilt = false
        for round in 1...2 {
            try Task.checkCancellation()
            progress("\(target.label): Core ML gốc lần \(round)…")
            let nativeLoad = try measure { try loadNative(compiledURLs) }
            native.append(nativeLoad)
            lines.append("\(target.label) · Core ML gốc lần \(round) (\(compiledURLs.count) model): \(nativeLoad.text) · \(thermal())")

            try Task.checkCancellation()
            progress("\(target.label): ORT + Core ML EP lần \(round)…")
            let before = modificationStamps(entries)
            let logURL = package.resultsURL.appendingPathComponent("load-\(target.kind)\(target.bucket)-\(round).log")
            let ortLoad = try measure { try ortSession(target, package: package, provider: "CoreML", logPath: logURL.path) }
            let wrote = logShowsRebuild(logURL) || modificationStamps(entries) != before
            rebuilt = rebuilt || wrote
            bridged.append(ortLoad)
            lines.append("\(target.label) · ORT + Core ML EP lần \(round): \(ortLoad.text) · "
                + "\(wrote ? "ORT GHI LẠI gói / biên dịch lại" : "trúng bản lưu") · \(thermal())")
        }
        let summary = "\(target.label) nạp: Core ML gốc \(native.map(\.seconds).joined(separator: " / ")) s · "
            + "ORT+Core ML \(bridged.map(\.seconds).joined(separator: " / ")) s · ORT CPU \(plain.seconds) s"
            + (rebuilt ? " · ORT ghi lại gói!" : "")
        return (lines, summary)
    }

    private static func loadNative(_ urls: [URL]) throws -> [MLModel] {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return try urls.map { try MLModel(contentsOf: $0, configuration: configuration) }
    }

    private static func ortSession(
        _ target: Target,
        package: VieNeuCoreMLPackage,
        provider: String,
        logPath: String
    ) throws -> VieNeuONNXProbeSession {
        try VieNeuONNXProbeSession(
            modelPath: package.url(target.graphName).path,
            provider: provider,
            options: provider == "CoreML" ? VieNeuCoreMLFlowBackend.coreMLOptions(package: package) : [:],
            threads: 2,
            logPath: logPath,
            weights: [.init(name: target.weightsName, path: package.url(target.weightsName).path)]
        )
    }

    /// Đo một lần dựng: thời gian thực + CPU của cả tiến trình, **không** tính lúc nhả (đối tượng sống tới sau mốc đo).
    private static func measure<T>(_ body: () throws -> T) throws -> Measure {
        try autoreleasepool {
            let wall = ProcessInfo.processInfo.systemUptime
            let cpu = ProcessCPUClock.nowMs()
            let value = try body()
            let result = Measure(wallMs: (ProcessInfo.processInfo.systemUptime - wall) * 1_000, cpuMs: ProcessCPUClock.nowMs() - cpu)
            withExtendedLifetime(value) {}
            return result
        }
    }

    // MARK: - Thử bỏ bản trọng số của gói

    private static func trimTest(
        entries: [VieNeuCoreMLCacheInventory.Entry],
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        progress: (String) -> Void
    ) throws -> (lines: [String], summary: String) {
        guard let bucket = manifest.veBuckets.min(),
              let entry = entries.first(where: { $0.kind == "ve" && $0.bucket == bucket && $0.compiledURL != nil }) else {
            return (["== 4. Bỏ bản trọng số: không có mục VE đã biên dịch — bỏ qua"], "bỏ bản trọng số: chưa thử được")
        }
        var lines = ["== 4. Thử bỏ bản trọng số trong gói (\(entry.label), đổi tên rồi trả về)"]
        guard !entry.packageWeightFiles.isEmpty else {
            lines.append("gói không có file weight.bin ngoài bản biên dịch — không có gì để bỏ")
            return (lines, "bỏ bản trọng số: gói không có bản thừa")
        }
        let fileManager = FileManager.default
        var moved: [URL] = []
        // Trả file về **sau** khi nhả session (defer chạy ngược thứ tự khai báo: backend khai sau ⇒ nhả trước).
        defer { moved.forEach { VieNeuCoreMLCacheInventory.restore($0) } }
        var movedBytes: Int64 = 0
        for url in entry.packageWeightFiles {
            let trimmed = URL(fileURLWithPath: url.path + VieNeuCoreMLCacheInventory.trimSuffix)
            movedBytes += VieNeuTurboModelStore.fileSize(at: url)
            try fileManager.moveItem(at: url, to: trimmed)
            moved.append(trimmed)
        }
        lines.append("đổi tên \(moved.count) file (\(bytes(movedBytes)))")

        let backend = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: 2)
        defer { backend.releaseSessions() }
        progress("Thử bỏ trọng số: nạp lại \(entry.label)…")
        let logURL = package.resultsURL.appendingPathComponent("load-trim-ve\(bucket).log")
        let load = try measure { try backend.loadSession(kind: "ve", bucket: bucket, logPath: logURL.path) }
        let reappeared = entry.packageWeightFiles.contains { fileManager.fileExists(atPath: $0.path) }
        let rebuilt = logShowsRebuild(logURL) || reappeared
        lines.append("nạp ORT + Core ML EP khi thiếu bản trong gói: \(load.text) · "
            + "\(rebuilt ? "ORT DỰNG LẠI gói (không coi là có bản lưu)" : "trúng bản lưu") · \(thermal())")

        let golden = try VieNeuNanoGolden(url: package.url("golden.npz"), chunkCount: manifest.goldenChunks)
        var passed = !rebuilt
        var checked = 0
        for (index, chunk) in golden.chunks.enumerated() where chunk.frames <= bucket {
            try Task.checkCancellation()
            progress("Thử bỏ trọng số: tự kiểm đoạn \(index + 1)…")
            let request = VieNeuCoreMLPreparer.goldenRequest(chunk, golden: golden, manifest: manifest)
            let latent = try backend.trajectory(request, veBucket: bucket)
            let db = VieNeuNanoEPWorker.snr(chunk.latent, latent)
            let nan = latent.contains(where: \.isNaN)
            passed = passed && !nan && db >= VieNeuCoreMLPreparer.minimumLatentDB
            checked += 1
            lines.append("đoạn \(index + 1) (T=\(chunk.frames)) latent \(VieNeuNanoEPWorker.format(db)) dB\(nan ? " · NaN!" : "")")
        }
        if checked == 0 {
            passed = false
            lines.append("không có đoạn golden nào vừa T\(bucket) — chưa kiểm được kết quả")
        }
        let verdict: String
        if rebuilt {
            verdict = "không bỏ được: thiếu trọng số trong gói thì ORT dựng lại"
        } else if passed {
            verdict = "BỎ ĐƯỢC: ORT nạp từ bản biên dịch, kết quả vẫn đúng (bớt \(bytes(movedBytes)) mỗi mục)"
        } else {
            verdict = "không bỏ được: kết quả sai / chưa kiểm được"
        }
        lines.append("⇒ \(verdict) · đã trả file về")
        return (lines, "bỏ bản trọng số (\(entry.label)): \(verdict)")
    }

    // MARK: - Tiện ích

    private static func inventoryLines(_ entries: [VieNeuCoreMLCacheInventory.Entry]) -> [String] {
        var lines = ["== 1. Dung lượng từng mục (gói ORT ghi ra / bản biên dịch)"]
        if entries.isEmpty { lines.append("chưa có mục nào — chạy Đo tự động để biên dịch trước") }
        for entry in entries {
            let state = entry.compiledURL == nil ? " · CHƯA biên dịch xong" : ""
            lines.append("\(entry.label)#\(entry.partition) (\(entry.key)): gói \(bytes(entry.packageBytes)) · biên dịch \(bytes(entry.compiledBytes))\(state)")
            for file in entry.largeFiles.prefix(4) {
                lines.append("    \(file.path) \(bytes(file.bytes))")
            }
        }
        return lines
    }

    /// Ngày sửa của mọi `weight.bin` thuộc graph — ORT ghi lại gói / biên dịch lại thì đổi.
    private static func modificationStamps(_ entries: [VieNeuCoreMLCacheInventory.Entry]) -> [String: Date] {
        var stamps: [String: Date] = [:]
        for url in entries.flatMap(\.weightFiles) {
            stamps[url.path] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return stamps
    }

    private static func logShowsRebuild(_ url: URL) -> Bool {
        (try? String(contentsOf: url, encoding: .utf8))?.contains(rebuildMarker) ?? false
    }

    private static func thermal() -> String {
        VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState)
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
