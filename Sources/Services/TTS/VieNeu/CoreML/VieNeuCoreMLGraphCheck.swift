import Foundation

/// Phần "graph" của phép đo P2b-1 (gói định dạng 3, Gemm `transB=1` — báo cáo §14): với VE + codec bucket nhỏ nhất,
/// 1. dựng session ORT + Core ML EP lần đầu (biên dịch nếu `Cache/` chưa có bản của gói mới), ghi số partition;
/// 2. dung lượng bản biên dịch (`model.mil` phải còn vài MB, trọng số nằm ở `weight.bin`);
/// 3. dòng dài nhất của `model.mil` (không còn hằng `linear_…_t` cỡ MB nếu đúng);
/// 4. nạp lại: Core ML gốc (kèm lượt đoán đầu) và ORT + Core ML EP, mỗi cách 2 lần xen kẽ.
enum VieNeuCoreMLGraphCheck {
    static func run(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        progress: (String) -> Void
    ) throws -> (lines: [String], summary: [String]) {
        typealias Worker = VieNeuCoreMLLoadWorker
        let options = VieNeuCoreMLFlowBackend.coreMLOptions(package: package)
        let targets = Worker.targets(manifest)
        var lines = ["== 1. Dựng session lần đầu (Cache/)"]
        var summary: [String] = []
        try FileManager.default.createDirectory(at: package.cacheDirectory, withIntermediateDirectories: true)
        let existing = VieNeuCoreMLCacheInventory.scan(package.cacheDirectory)
        for target in targets {
            try Task.checkCancellation()
            let had = existing.contains { $0.kind == target.kind && $0.bucket == target.bucket && $0.compiledURL != nil }
            progress("\(had ? "Nạp" : "Biên dịch") \(target.label)…")
            let logURL = package.resultsURL.appendingPathComponent("p2b1-first-\(target.kind)\(target.bucket).log")
            let first = try Worker.timed {
                try Worker.ortSession(target, package: package, options: options, logPath: logURL.path)
            }
            let partitions = Worker.partitionCount(logURL).map { "\($0) partition Core ML" } ?? "không đọc được số partition"
            let action = had ? "nạp (đã có bản biên dịch)" : "biên dịch"
            lines.append("\(target.label): \(action) \(first.text) · \(partitions) · \(Worker.thermal())")
            summary.append("\(target.label): \(action) \(first.seconds) s · \(partitions)")
        }

        let entries = VieNeuCoreMLCacheInventory.scan(package.cacheDirectory)
        lines.append(contentsOf: Worker.inventoryLines(entries, title: "== 2. Dung lượng bản biên dịch (gói định dạng \(manifest.format))"))
        for target in targets {
            let graphEntries = entries.filter { $0.kind == target.kind && $0.bucket == target.bucket }
            let packagePart = graphEntries.reduce(Int64(0)) { $0 + $1.packageBytes }
            let compiledPart = graphEntries.reduce(Int64(0)) { $0 + $1.compiledBytes }
            summary.append("\(target.label) dung lượng: gói \(Worker.bytes(packagePart)) · biên dịch \(Worker.bytes(compiledPart))")
        }

        lines.append("== 3. Dòng dài nhất của model.mil")
        for target in targets {
            try Task.checkCancellation()
            guard let entry = entries.first(where: { $0.kind == target.kind && $0.bucket == target.bucket && $0.partition == "0" }),
                  let compiled = entry.compiledURL else {
                lines.append("\(target.label): chưa có bản biên dịch")
                continue
            }
            progress("Đọc lướt model.mil \(target.label)…")
            let scan = try VieNeuCoreMLMilScan.longestLines(compiled.appendingPathComponent("model.mil"))
            lines.append("\(target.label): \(Worker.bytes(Int64(scan.totalBytes))) · \(scan.lineCount) dòng · \(scan.lines.count) dòng dài nhất:")
            for line in scan.lines {
                lines.append("    \(Worker.bytes(Int64(line.length))) · \(line.prefix)")
            }
            summary.append("\(target.label) model.mil \(Worker.bytes(Int64(scan.totalBytes))), dòng dài nhất "
                + Worker.bytes(Int64(scan.lines.first?.length ?? 0)))
        }

        lines.append("== 4. Nạp lại (mỗi cách 2 lần, xen kẽ)")
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
                progress("Nạp \(target.label): Core ML gốc lần \(round)…")
                let load = try VieNeuCoreMLNativeLoad.measure(compiledURLs)
                native.append(load.shortText)
                lines.append("\(target.label) · Core ML gốc lần \(round) (\(compiledURLs.count) model): \(load.text) · \(Worker.thermal())")

                try Task.checkCancellation()
                progress("Nạp \(target.label): ORT + Core ML EP lần \(round)…")
                let before = Worker.milStamps(graphEntries)
                let ort = try Worker.timed { try Worker.ortSession(target, package: package, options: options, logPath: "") }
                let rewrote = Worker.milStamps(graphEntries) != before
                bridged.append(ort.seconds)
                lines.append("\(target.label) · ORT + Core ML EP lần \(round): \(ort.text)"
                    + "\(rewrote ? " · model.mil BỊ GHI LẠI (biên dịch lại)" : "") · \(Worker.thermal())")
            }
            summary.append("\(target.label) nạp: Core ML gốc (nạp+đoán đầu) \(native.joined(separator: " / ")) s · "
                + "ORT+Core ML \(bridged.joined(separator: " / ")) s")
        }
        return (lines, summary)
    }
}
