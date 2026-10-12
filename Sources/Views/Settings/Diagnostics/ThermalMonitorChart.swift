import SwiftUI
import Charts

/// Hai biểu đồ của màn "Theo dõi nhiệt": `.level` (mức nhiệt dạng bậc thang) và `.usage` (CPU app + pin).
/// Cả hai tô nền các đoạn đang phát TTS. Chỉ vẽ khi màn đang mở; tối đa 1.440 điểm (12 giờ).
struct ThermalMonitorChart: View {
    enum Kind {
        case level
        case usage
    }

    let kind: Kind
    let samples: [DeviceThermalMonitor.Sample]

    var body: some View {
        if samples.count < 2 {
            Text("Đang thu thập — mẫu được ghi mỗi 30 giây.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            switch kind {
            case .level: levelChart
            case .usage: usageChart
            }
        }
    }

    private var levelChart: some View {
        Chart {
            ttsSpanMarks
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                LineMark(
                    x: .value("Giờ", sample.time),
                    y: .value("Mức nhiệt", Int(sample.thermalLevel))
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color.orange)
            }
        }
        .chartYScale(domain: 0...3)
        .chartYAxis {
            AxisMarks(values: [0, 1, 2, 3]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let level = value.as(Int.self) {
                        Text(ThermalMonitorView.levelName(level))
                    }
                }
            }
        }
        .frame(height: 140)
    }

    private var usageChart: some View {
        let maxCPU = Double(samples.map(\.cpuPercent).max() ?? 0)
        return Chart {
            ttsSpanMarks
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                LineMark(
                    x: .value("Giờ", sample.time),
                    y: .value("Phần trăm", Double(sample.cpuPercent)),
                    series: .value("Loại", "CPU app")
                )
                .foregroundStyle(by: .value("Loại", "CPU app"))
                if sample.batteryPercent >= 0 {
                    LineMark(
                        x: .value("Giờ", sample.time),
                        y: .value("Phần trăm", Double(sample.batteryPercent)),
                        series: .value("Loại", "Pin")
                    )
                    .foregroundStyle(by: .value("Loại", "Pin"))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartForegroundStyleScale(["CPU app": Color.blue, "Pin": Color.green])
        .chartYScale(domain: 0...max(100, maxCPU))
        .chartLegend(position: .bottom)
        .frame(height: 160)
    }

    /// Nền nhạt cho các đoạn liên tiếp có TTS đang phát.
    @ChartContentBuilder
    private var ttsSpanMarks: some ChartContent {
        ForEach(Array(ttsSpans.enumerated()), id: \.offset) { _, span in
            RectangleMark(
                xStart: .value("Bắt đầu", span.start),
                xEnd: .value("Kết thúc", span.end)
            )
            .foregroundStyle(Color.accentColor.opacity(0.12))
        }
    }

    private var ttsSpans: [(start: Date, end: Date)] {
        var spans: [(start: Date, end: Date)] = []
        var spanStart: Date?
        var previous: Date?
        for sample in samples {
            if sample.ttsEngine != nil {
                if spanStart == nil { spanStart = sample.time }
            } else if let start = spanStart {
                spans.append((start, previous ?? start))
                spanStart = nil
            }
            previous = sample.time
        }
        if let start = spanStart, let end = samples.last?.time {
            spans.append((start, end))
        }
        return spans
    }
}
