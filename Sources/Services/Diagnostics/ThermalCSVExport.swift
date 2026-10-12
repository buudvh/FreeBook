import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Dữ liệu chia sẻ của màn "Theo dõi nhiệt": file CSV dựng **trong RAM, đúng lúc người dùng chia sẻ**, từ
/// bộ đệm của `DeviceThermalMonitor` — không có file nào nằm sẵn trên đĩa trong lúc thu.
///
/// Định dạng: 3 dòng `#` tóm tắt, rồi tiêu đề cột và mỗi mẫu một dòng.
struct ThermalCSVExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { _ in
            let samples = await MainActor.run { DeviceThermalMonitor.shared.samples() }
            return Data(Self.makeCSV(samples).utf8)
        }
        .suggestedFileName { _ in "thermal_\(Self.fileStamp.string(from: Date())).csv" }
    }

    static let levelCodes = ["nominal", "fair", "serious", "critical"]

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // giờ 24h + lịch Gregorian bất kể cài đặt máy
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // cột thời gian phải parse được bằng máy
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func makeCSV(_ samples: [DeviceThermalMonitor.Sample]) -> String {
        var lines: [String] = ["# FreeBook theo dõi nhiệt"]
        if let first = samples.first, let last = samples.last {
            let maxLevel = Int(samples.map(\.thermalLevel).max() ?? 0)
            let averageCPU = samples.map(\.cpuPercent).reduce(0, +) / Float(samples.count)
            lines.append("# Thu từ \(timeFormatter.string(from: first.time)) đến \(timeFormatter.string(from: last.time)) · \(samples.count) mẫu")
            lines.append(String(
                format: "# Nhiệt cao nhất: %@ · CPU app TB %.0f%% · Pin %@→%@",
                levelCode(maxLevel), averageCPU, batteryText(first), batteryText(last)
            ))
        } else {
            lines.append("# Chưa có mẫu nào")
        }
        lines.append("time,thermal,cpu_pct,battery_pct,charging,low_power,tts")
        for sample in samples {
            lines.append([
                timeFormatter.string(from: sample.time),
                levelCode(Int(sample.thermalLevel)),
                String(format: "%.0f", sample.cpuPercent),
                sample.batteryPercent < 0 ? "" : String(format: "%.0f", sample.batteryPercent),
                sample.isCharging ? "1" : "0",
                sample.isLowPowerMode ? "1" : "0",
                sample.ttsEngine ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func levelCode(_ level: Int) -> String {
        levelCodes.indices.contains(level) ? levelCodes[level] : "unknown"
    }

    private static func batteryText(_ sample: DeviceThermalMonitor.Sample) -> String {
        sample.batteryPercent < 0 ? "?" : String(format: "%.0f%%", sample.batteryPercent)
    }
}
