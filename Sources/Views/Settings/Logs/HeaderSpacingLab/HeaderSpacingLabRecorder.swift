import SwiftUI
import UIKit

/// **Tạm thời** (1.3.1026) — bộ chạy + ghi số của màn tự thử nhịp dọc header. "Chạy" ⇒ lần lượt đẩy từng
/// `HeaderSpacingLabVariant` (đặt `current`, màn gốc `navigationDestination(item:)`), chờ trang đứng yên, đọc số từ đầu dò
/// UIKit (`HeaderSpacingLabProbe`) + khung SwiftUI (`labMeasure`), ghi một dòng kết quả (màn + log `📐 [HeaderLab]`), quay
/// lại, sang biến thể kế. Khoảng cách đo **từ đáy thanh** (trang có ô tìm: từ đáy ô tìm) — mốc B anh Bửu chọn.
@MainActor @Observable
final class HeaderSpacingLabRecorder {
    struct Result: Identifiable {
        let id: String
        let text: String
    }

    private(set) var results: [Result] = []
    private(set) var isRunning = false
    private(set) var progress = ""
    /// Biến thể đang đẩy vào; `nil` ⇒ về màn gốc.
    var current: HeaderSpacingLabVariant?

    @ObservationIgnored private var frames: [String: CGRect] = [:]
    @ObservationIgnored private var snapshot: HeaderSpacingLabProbe.Snapshot?
    @ObservationIgnored private var barDumpLogged = false

    func record(_ key: String, _ frame: CGRect) {
        frames[key] = frame
    }

    func receive(_ snap: HeaderSpacingLabProbe.Snapshot) {
        snapshot = snap
    }

    func start() {
        guard !isRunning else { return }
        results = []
        barDumpLogged = false
        isRunning = true
        Task { await run() }
    }

    var reportText: String {
        let device = UIDevice.current
        var lines = ["Thử nhịp dọc header · \(device.model) · iOS \(device.systemVersion)"]
        lines += results.map(\.text)
        return lines.joined(separator: "\n")
    }

    private func run() async {
        let variants = HeaderSpacingLabVariant.all
        AppLogger.shared.log("📐 [HeaderLab] bắt đầu \(variants.count) biến thể")
        for (index, variant) in variants.enumerated() {
            frames = [:]
            snapshot = nil
            progress = "\(index + 1)/\(variants.count) · \(variant.label)"
            current = variant
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            let line = describe(variant)
            results.append(Result(id: variant.id, text: line))
            AppLogger.shared.log("📐 [HeaderLab] " + line)
            if let dump = snapshot?.barDump, !dump.isEmpty, !barDumpLogged {
                barDumpLogged = true
                for chunk in stride(from: 0, to: dump.count, by: 12) {
                    AppLogger.shared.log("📐 [HeaderLab] bar " + dump[chunk..<min(chunk + 12, dump.count)].joined(separator: " | "))
                }
            }
            current = nil
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        isRunning = false
        progress = "Xong \(results.count) biến thể — bấm chia sẻ để gửi báo cáo"
    }

    /// Một dòng kết quả: Δ = khoảng từ mốc (đáy thanh / đáy ô tìm) tới mép trên phần tử.
    private func describe(_ variant: HeaderSpacingLabVariant) -> String {
        var parts = [variant.label]
        guard let snap = snapshot else {
            return variant.label + ": không chụp được thanh"
        }
        let reference = variant.hasSearch ? snap.fieldBottom : snap.barBottom
        parts.append("w\(Self.f(snap.windowWidth))")
        if let reference {
            parts.append("mốc \(variant.hasSearch ? "ô tìm" : "thanh")=\(Self.f(reference))")
            if let top = snap.firstCellTop { parts.append("ô đầu Δ\(Self.f(top - reference))") }
            if let top = snap.firstHeaderTop {
                parts.append("khung tiêu đề nhóm Δ\(Self.f(top - reference)) h\(Self.f(snap.firstHeaderHeight ?? 0))")
            }
            if let text = frames["groupText"] { parts.append("chữ tiêu đề nhóm Δ\(Self.f(text.minY - reference))") }
            if let panel = frames["firstPanel"] { parts.append("panel đầu Δ\(Self.f(panel.minY - reference))") }
            if let row = frames["firstRowText"] { parts.append("chữ hàng đầu Δ\(Self.f(row.minY - reference))") }
        } else {
            parts.append("không có thanh")
        }
        if let back = snap.systemBack { parts.append("back hệ thống x\(Self.f(back.minX)) w\(Self.f(back.width))") }
        if let custom = frames["customBack"] {
            // `HeaderBackButton` lùi mũi `backChevronOutdent` ra ngoài khung bố cục ⇒ mũi ≈ minX − 8.
            parts.append("back tự dựng x≈\(Self.f(custom.minX - HeaderMetrics.backChevronOutdent))")
        }
        if let right = frames["toolbarRight"] {
            parts.append("icon phải (SwiftUI) x\(Self.f(right.minX))–\(Self.f(right.maxX)) lề phải \(Self.f(snap.windowWidth - right.maxX))")
        }
        if let right = frames["customRight"] {
            parts.append("icon phải tự dựng lề \(Self.f(snap.windowWidth - right.maxX))")
        }
        return parts.joined(separator: " · ")
    }

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

extension View {
    /// Ghi khung `.global` của view vào bộ chạy màn tự thử (tạm thời, 1.3.1026).
    func labMeasure(_ key: String, _ recorder: HeaderSpacingLabRecorder) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { recorder.record(key, proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in recorder.record(key, frame) }
            }
        )
    }
}
