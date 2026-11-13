import Foundation

/// Phép thử P2b-0 (báo cáo §13): dựng session Core ML khi **tắt tối ưu đồ thị ORT** (`ORT_DISABLE_ALL` qua khoá riêng
/// `fb.graph_optimization`, chỉ cho session Core ML) ⇒ không `MatMulAddFusion` ⇒ MatMul giữ nguyên ⇒ op `matmul` tham
/// chiếu initializer ⇒ trọng số vào `weight.bin` thay vì nằm trong chữ `model.mil`.
///
/// Làm trên VE + codec bucket nhỏ nhất, cache riêng `Cache-noopt/` (biên dịch mới mỗi lượt để đo thời gian biên dịch):
/// 3. biên dịch: thời gian, số partition (phải vẫn 1 / 2 như bản hiện tại), dung lượng `model.mil` / `weight.bin` /
///    `model.mlmodel`;
/// 4. nạp: Core ML gốc (kèm lượt đoán đầu) và ORT + Core ML EP, mỗi cách 2 lần xen kẽ;
/// 5. **chất lượng + tốc độ**: cùng đoạn golden chạy qua bản hiện tại và bản tắt tối ưu — dB so tham chiếu PC, dB giữa hai
///    bản, thời gian mỗi quỹ đạo VE / mỗi lượt VE / mỗi lần codec (2 vòng xen kẽ, sau một lượt khởi động).
enum VieNeuCoreMLNoOptTrial {
    static func run(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        progress: (String) -> Void
    ) throws -> (lines: [String], summary: [String]) {
        typealias Worker = VieNeuCoreMLLoadWorker
        let options = VieNeuCoreMLFlowBackend.coreMLOptions(package: package, disablesGraphOptimization: true)
        let targets = Worker.targets(manifest)
        var lines: [String] = []
        var summary: [String] = []

        // 3. Biên dịch mới vào Cache-noopt/.
        lines.append("== 3. Biên dịch bản TẮT tối ưu đồ thị ORT (ORT_DISABLE_ALL, Cache-noopt/)")
        try? FileManager.default.removeItem(at: package.noOptCacheDirectory)
        try FileManager.default.createDirectory(at: package.noOptCacheDirectory, withIntermediateDirectories: true)
        for target in targets {
            try Task.checkCancellation()
            progress("Biên dịch bản tắt tối ưu: \(target.label)…")
            let logURL = package.resultsURL.appendingPathComponent("noopt-compile-\(target.kind)\(target.bucket).log")
            do {
                let compile = try Worker.timed {
                    try Worker.ortSession(target, package: package, options: options, logPath: logURL.path)
                }
                let partitions = Worker.partitionCount(logURL).map { "\($0) partition Core ML" } ?? "không đọc được số partition"
                lines.append("\(target.label): biên dịch \(compile.text) · \(partitions) · \(Worker.thermal())")
                summary.append("tắt tối ưu \(target.label): biên dịch \(compile.seconds) s · \(partitions)")
            } catch {
                lines.append("❌ \(target.label): biên dịch lỗi — \(error.localizedDescription)")
                summary.append("tắt tối ưu \(target.label): biên dịch lỗi")
                return (lines, summary)
            }
        }
        let entries = VieNeuCoreMLCacheInventory.scan(package.noOptCacheDirectory)
        lines.append(contentsOf: Worker.inventoryLines(entries, title: "dung lượng bản tắt tối ưu:"))
        let compiledTotal = entries.reduce(Int64(0)) { $0 + $1.compiledBytes }
        let packageTotal = entries.reduce(Int64(0)) { $0 + $1.packageBytes }
        summary.append("dung lượng tắt tối ưu (VE + codec nhỏ nhất): gói \(Worker.bytes(packageTotal)) · biên dịch \(Worker.bytes(compiledTotal))")

        // 4. Nạp lại từ Cache-noopt/.
        lines.append("== 4. Nạp bản tắt tối ưu (mỗi cách 2 lần, xen kẽ)")
        for target in targets {
            let graphEntries = entries.filter { $0.kind == target.kind && $0.bucket == target.bucket }
            let compiledURLs = graphEntries.compactMap(\.compiledURL)
            guard !compiledURLs.isEmpty else {
                lines.append("\(target.label): chưa có bản biên dịch — bỏ qua")
                continue
            }
            var native: [String] = []
            var bridged: [String] = []
            for round in 1...2 {
                try Task.checkCancellation()
                progress("Nạp bản tắt tối ưu \(target.label): Core ML gốc lần \(round)…")
                let load = try VieNeuCoreMLNativeLoad.measure(compiledURLs)
                native.append(load.shortText)
                lines.append("\(target.label) · Core ML gốc lần \(round) (\(compiledURLs.count) model): \(load.text) · \(Worker.thermal())")

                try Task.checkCancellation()
                progress("Nạp bản tắt tối ưu \(target.label): ORT + Core ML EP lần \(round)…")
                let before = Worker.milStamps(graphEntries)
                let ort = try Worker.timed { try Worker.ortSession(target, package: package, options: options, logPath: "") }
                let rewrote = Worker.milStamps(graphEntries) != before
                bridged.append(ort.seconds)
                lines.append("\(target.label) · ORT + Core ML EP lần \(round): \(ort.text)"
                    + "\(rewrote ? " · model.mil BỊ GHI LẠI (biên dịch lại)" : "") · \(Worker.thermal())")
            }
            summary.append("tắt tối ưu \(target.label) nạp: Core ML gốc (nạp+đoán đầu) \(native.joined(separator: " / ")) s · "
                + "ORT+Core ML \(bridged.joined(separator: " / ")) s")
        }

        // 5. Chất lượng + tốc độ so với bản hiện tại.
        try Task.checkCancellation()
        let comparison = try VieNeuCoreMLNoOptComparison.run(package: package, manifest: manifest, progress: progress)
        lines.append(contentsOf: comparison.lines)
        summary.append(contentsOf: comparison.summary)
        return (lines, summary)
    }
}
