import Foundation

/// Phép đo **"Đo nạp Core ML"** của màn thử VieNeu — chạy ngoài MainActor (`Task.detached`), không đụng đường đọc truyện.
///
/// - P2a (1.3.912): nạp chậm là của chính Core ML (18–20 s mỗi VE) vì trọng số Linear nằm **trong chữ** `model.mil`
///   (549 MB / VE) — cũng là 4,16 GB cache (báo cáo §13).
/// - P2b-0 (1.3.913): tắt tối ưu ORT lúc chạy vô ích — `Gemm(transB=0)` đã gộp sẵn trong ONNX lúc xuất trên PC (§14).
/// - **P2b-1 (lượt này)**: gói định dạng 3 (Gemm `transB=1`, xuất lại trên PC). Probe tải gói mới (`VieNeuCoreMLLoadProbe`)
///   rồi đo: dựng session lần đầu, dung lượng, `model.mil`, nạp lại (`VieNeuCoreMLGraphCheck`), chất lượng + tốc độ so với
///   số của bản định dạng 2 (`VieNeuCoreMLGoldenSpeedCheck`).
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

    /// Mốc bắt đầu đo (thời gian thực + CPU của cả tiến trình).
    struct Mark {
        let wall: TimeInterval
        let cpuMs: Double

        static func now() -> Mark {
            Mark(wall: ProcessInfo.processInfo.systemUptime, cpuMs: ProcessCPUClock.nowMs())
        }

        func measure() -> Measure {
            Measure(wallMs: (ProcessInfo.processInfo.systemUptime - wall) * 1_000, cpuMs: ProcessCPUClock.nowMs() - cpuMs)
        }
    }

    /// Một graph Core ML của gói (VE main hoặc codec) ở một bucket.
    struct Target: Sendable {
        let kind: String
        let bucket: Int
        let graphName: String
        let weightsName: String

        var label: String { "\(kind) T\(bucket)" }
    }

    /// `downloadNote`: một dòng về lần làm mới gói vừa rồi (bao nhiêu file tải lại, có xoá cache không).
    static func run(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        downloadNote: String,
        progress: @Sendable (String) -> Void
    ) throws -> Outcome {
        try FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
        VieNeuCoreMLCacheInventory.restoreTrimmed(package.cacheDirectory) // file đổi tên của bản 1.3.912 bị ngắt
        var lines = [
            "Đo nạp Core ML (P2b-1, gói định dạng \(manifest.format)) — gói \(bytes(package.packageBytes)) · cache \(bytes(package.cacheBytes))",
            "làm mới gói: \(downloadNote)",
            "nhiệt lúc bắt đầu \(thermal()) · \(ProcessMemoryProbe.snapshot().summary) · \(freeSpace(package))"
        ]
        var summary: [String] = []
        let graph = try VieNeuCoreMLGraphCheck.run(package: package, manifest: manifest, progress: progress)
        lines.append(contentsOf: graph.lines)
        summary.append(contentsOf: graph.summary)
        try Task.checkCancellation()
        let golden = try VieNeuCoreMLGoldenSpeedCheck.run(package: package, manifest: manifest, progress: progress)
        lines.append(contentsOf: golden.lines)
        summary.append(contentsOf: golden.summary)
        lines.append("nhiệt lúc xong \(thermal()) · \(ProcessMemoryProbe.snapshot().summary) · \(freeSpace(package))")
        return Outcome(report: lines.joined(separator: "\n"), summary: summary)
    }

    // MARK: - Dùng chung với VieNeuCoreMLGraphCheck / VieNeuCoreMLGoldenSpeedCheck

    static func targets(_ manifest: VieNeuCoreMLPackage.Manifest) -> [Target] {
        var result: [Target] = []
        if let ve = manifest.veBuckets.min() {
            result.append(Target(kind: "ve", bucket: ve, graphName: "ve_main_T\(ve).onnx", weightsName: manifest.veWeights))
        }
        if let codec = manifest.codecBuckets.min() {
            result.append(Target(kind: "codec", bucket: codec, graphName: "codec_T\(codec).onnx", weightsName: manifest.codecWeights))
        }
        return result
    }

    /// Session ORT của một graph: `options` rỗng ⇒ CPU EP, khác rỗng ⇒ Core ML EP với đúng các tuỳ chọn đó.
    static func ortSession(
        _ target: Target,
        package: VieNeuCoreMLPackage,
        options: [String: String],
        logPath: String
    ) throws -> VieNeuONNXProbeSession {
        try VieNeuONNXProbeSession(
            modelPath: package.url(target.graphName).path,
            provider: options.isEmpty ? "CPU" : "CoreML",
            options: options,
            threads: 2,
            logPath: logPath,
            weights: [.init(name: target.weightsName, path: package.url(target.weightsName).path)]
        )
    }

    /// Đo một lần làm: thời gian thực + CPU của cả tiến trình, **không** tính lúc nhả (đối tượng sống tới sau mốc đo).
    static func timed<T>(_ body: () throws -> T) throws -> Measure {
        try autoreleasepool {
            let start = Mark.now()
            let value = try body()
            let result = start.measure()
            withExtendedLifetime(value) {}
            return result
        }
    }

    static func inventoryLines(_ entries: [VieNeuCoreMLCacheInventory.Entry], title: String) -> [String] {
        var lines = [title]
        if entries.isEmpty { lines.append("chưa có mục nào") }
        for entry in entries {
            let state = entry.compiledURL == nil ? " · CHƯA biên dịch xong" : ""
            lines.append("\(entry.label)#\(entry.partition): gói \(bytes(entry.packageBytes)) · biên dịch \(bytes(entry.compiledBytes))\(state)")
            for file in entry.largeFiles.prefix(4) {
                lines.append("    \(file.path) \(bytes(file.bytes))")
            }
        }
        return lines
    }

    /// Số partition Core ML cuối cùng ORT ghi trong log (bridge đặt log INFO ⇒ in **mọi** lần dựng session, không phải
    /// dấu hiệu biên dịch lại — đính chính §13).
    static func partitionCount(_ logURL: URL) -> Int? {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return nil }
        return text.components(separatedBy: "number of partitions supported by CoreML: ").dropFirst()
            .compactMap { Int($0.prefix { $0.isNumber }) }.last
    }

    /// Ngày sửa của `model.mil` mọi mục — biên dịch lại thì đổi (file `weight.bin` rỗng ORT tạo lại mỗi lần dựng session
    /// nên không dùng được).
    static func milStamps(_ entries: [VieNeuCoreMLCacheInventory.Entry]) -> [String: Date] {
        var stamps: [String: Date] = [:]
        for compiled in entries.compactMap(\.compiledURL) {
            let mil = compiled.appendingPathComponent("model.mil")
            stamps[mil.path] = (try? mil.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return stamps
    }

    static func freeSpace(_ package: VieNeuCoreMLPackage) -> String {
        guard let free = VieNeuCoreMLCacheInventory.volumeAvailable(package.rootURL) else { return "ổ trống ?" }
        return "ổ trống \(bytes(free))"
    }

    static func thermal() -> String {
        VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
