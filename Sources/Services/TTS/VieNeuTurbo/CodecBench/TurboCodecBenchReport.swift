import Foundation

/// **TẠM — màn đo "Codec Turbo: AMX vs Neural Engine"** (1.3.932): dựng báo cáo Markdown từ kết quả của
/// `TurboCodecBenchRunner`. Xoá cùng màn đo khi có kết luận.
enum TurboCodecBenchReport {
    static func make(
        started: Date,
        thermalStart: ProcessInfo.ThermalState,
        thermalEnd: ProcessInfo.ThermalState,
        voiceId: String,
        samples: [TurboCodecBenchRunner.Sample],
        results: [TurboCodecBenchRunner.ConfigResult]
    ) -> String {
        var lines: [String] = []
        lines.append("# Đo codec Turbo: AMX vs Neural Engine")
        lines.append("")
        lines.append("- Thời điểm: \(dateText(started)) · \(String(format: "%.0f", Date().timeIntervalSince(started))) s")
        lines.append("- Máy: \(machineName()) · \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("- App: \(AppVersionInfo.display)")
        lines.append("- Nhiệt: \(thermalName(thermalStart)) → \(thermalName(thermalEnd)) · giọng `\(voiceId)`")
        lines.append("- Mẫu: \(samples.count) (\(TurboCodecBenchRunner.texts.count) câu × \(TurboCodecBenchRunner.rounds) vòng), "
            + "khung: \(Set(samples.map(\.frames)).sorted().map(String.init).joined(separator: ", "))")
        lines.append("")

        let amx = samples.compactMap { sample in sample.amxCodecMs.map { $0 / max(0.001, sample.seconds) } }
        let amxMedian = median(amx)
        lines.append("## Tổng hợp (ms giải mã mỗi giây tiếng, trung vị 9 mẫu)")
        lines.append("")
        lines.append("| Cấu hình | ms/giây tiếng | So với AMX | SNR thấp nhất (dB) | Dựng session (ms) | Lượt đầu (ms) | Core ML nhận | Nhiệt lúc đo |")
        lines.append("|---|---|---|---|---|---|---|---|")
        lines.append("| audio.cpp AMX (đang dùng) | \(format(amxMedian)) | 1× | — | — | — | — | \(thermalName(thermalStart)) |")
        for result in results {
            let value = median(result.msPerSecond.compactMap { $0 })
            let ratio = (amxMedian ?? 0) > 0 && (value ?? 0) > 0 ? String(format: "%.2f×", amxMedian! / value!) : "—"
            let snrMin = result.snr.compactMap { $0 }.min()
            lines.append("| \(result.label) | \(format(value)) | \(ratio) | \(format(snrMin, decimals: 1)) | "
                + "\(keyed(result.createMs)) | \(keyed(result.firstRunMs)) | \(keyedText(result.coverage)) | \(thermalName(result.thermalStart)) |")
        }
        lines.append("")
        lines.append("\"So với AMX\" > 1 = nhanh hơn codec đang dùng. SNR so với tiếng audio.cpp (≥ 40 dB ≈ nghe như nhau; "
            + "GGUF lưu codec F16 nên bản ONNX fp32 lệch ~60 dB là bình thường; Neural Engine tính fp16 nên SNR thấp hơn — nghe file "
            + "`nghe-*.wav` kèm báo cáo để so). \"Dựng session\" của Core ML gồm biên dịch, rơi vào cấu hình Core ML chạy trước; "
            + "AMX đo lúc tổng hợp, trước mọi cấu hình ONNX (máy mát hơn).")
        lines.append("")

        lines.append("## Theo từng câu (ms/giây tiếng, trung vị 3 vòng)")
        lines.append("")
        let header = ["Câu (khung)", "AMX"] + results.map(\.label)
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("|" + String(repeating: "---|", count: header.count))
        for textIndex in TurboCodecBenchRunner.texts.indices {
            let indices = samples.indices.filter { samples[$0].textIndex == textIndex }
            let frames = indices.map { samples[$0].frames }
            var row = ["\(textIndex + 1) (\(frames.map(String.init).joined(separator: "/")))"]
            row.append(format(median(indices.compactMap { index in
                samples[index].amxCodecMs.map { $0 / max(0.001, samples[index].seconds) }
            })))
            for result in results {
                row.append(format(median(indices.compactMap { result.msPerSecond[$0] })))
            }
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        lines.append("")
        lines.append("Nhiệt từng mẫu: " + samples.map { thermalName($0.thermal) }.joined(separator: ", "))

        let errors = results.flatMap { result in result.errors.map { "- \(result.label): \($0)" } }
        if !errors.isEmpty {
            lines.append("")
            lines.append("## Lỗi")
            lines.append("")
            lines.append(contentsOf: errors)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    private static func format(_ value: Double?, decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", value)
    }

    private static func keyed(_ values: [Int: Double]) -> String {
        guard !values.isEmpty else { return "—" }
        return values.keys.sorted().map { key in
            (key == 0 ? "" : "T\(key): ") + String(format: "%.0f", values[key] ?? 0)
        }.joined(separator: " · ")
    }

    private static func keyedText(_ values: [Int: String]) -> String {
        guard !values.isEmpty else { return "—" }
        return values.keys.sorted().map { key in (key == 0 ? "" : "T\(key): ") + (values[key] ?? "—") }
            .joined(separator: " · ")
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "mát"
        case .fair: return "ấm"
        case .serious: return "nóng"
        case .critical: return "rất nóng"
        @unknown default: return "?"
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Mã máy (`iPhone12,1` = iPhone 11) — đọc từ `uname`.
    private static func machineName() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
