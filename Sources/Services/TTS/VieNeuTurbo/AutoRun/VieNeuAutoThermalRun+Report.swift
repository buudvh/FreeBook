import Foundation

/// File báo cáo của "Đo tự động": cấu hình, bước chuẩn bị Core ML, **bảng so 3 lượt**, rồi chi tiết từng lượt (điều kiện
/// máy mỗi phút + nguyên văn báo cáo "Đọc liên tục").
extension VieNeuAutoThermalRun {
    static func reportFileName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "vieneu-nano-do-tu-dong-\(formatter.string(from: date)).txt"
    }

    /// Một dòng mỗi lượt đã xong (bảng so) — màn thử hiện ngay dưới nút.
    var summaryLines: [String] { allLegs.map { Self.tableLine($0) } }

    /// Lượt đã xong + lượt đang chạy (nếu có).
    private var allLegs: [VieNeuAutoThermalLeg] { legs + (currentLeg.map { [$0] } ?? []) }

    func reportText() -> String {
        var lines = [VieNeuTurboReportFile.header(), ""]
        lines.append("Đo tự động P1b — Nano ORT ↔ Core ML CPU-only, \(Self.legPlan.count) lượt "
            + Self.legPlan.map { $0 == .ort ? "ORT" : "Core ML" }.joined(separator: " → "))
        lines.append("giọng \(voiceUsed.isEmpty ? Self.voiceName : voiceUsed)"
            + (voiceUsed.isEmpty || voiceUsed == Self.voiceName ? "" : " (máy không có \(Self.voiceName))")
            + " · tổng hợp \(Self.synthesisSpeed) · phát \(Self.playbackRate)× · chờ mát liền "
            + "\(VieNeuTurboSoakStats.clock(Self.settleHoldSeconds)) trước mỗi lượt · lượt tối đa "
            + "\(VieNeuTurboSoakStats.clock(Self.legMaxSeconds)), lên nóng thì đọc thêm \(Self.chunksAfterSerious) đoạn")
        lines.append("trạng thái   \(statusLine)")
        if !resumeNotes.isEmpty {
            lines.append("chạy tiếp    \(resumeNotes.joined(separator: " · "))")
        }
        if let errorMessage { lines.append("lỗi         \(errorMessage)") }
        lines.append("")

        if !allLegs.isEmpty {
            lines.append("== So 3 lượt")
            lines.append("(bận = thời gian tổng hợp / thời gian lượt — người nghe 1,5× thì bận ≈ RTF × 1,5; hụt = trình phát phải chờ)")
            lines += allLegs.map { Self.tableLine($0) }
            lines.append("")
        }
        if !prepareLines.isEmpty {
            lines.append("== Chuẩn bị Core ML")
            lines += prepareLines
            if !preloadNote.isEmpty { lines.append(preloadNote) }
            lines.append("")
        }
        for leg in allLegs {
            lines += Self.detail(leg)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func tableLine(_ leg: VieNeuAutoThermalLeg) -> String {
        let name = "Lượt \(leg.index + 1) \(leg.engine == .ort ? "ORT    " : "Core ML")\(leg.interrupted ? " (dở)" : "")"
        if let skipped = leg.skippedReason { return "\(name): bỏ qua — \(skipped)" }
        let toFair = leg.secondsToFair.map { VieNeuTurboSoakStats.clock($0) } ?? "không"
        let toSerious = leg.secondsToSerious.map { VieNeuTurboSoakStats.clock($0) } ?? "không"
        let busy = leg.durationSeconds > 0 ? leg.synthesisSeconds / leg.durationSeconds * 100 : 0
        var line = String(
            format: "%@: ấm sau %@ · nóng sau %@ · chạy %@ · tiếng %.0f s · RTF %@ · CPU/tiếng %@ · bận %.0f%% · hụt %ld (%.1f s)",
            name, toFair, toSerious, VieNeuTurboSoakStats.clock(leg.durationSeconds), leg.audioSeconds,
            VieNeuTurboSoakStats.ratio(leg.synthesisSeconds, leg.audioSeconds),
            VieNeuTurboSoakStats.ratio(leg.processCPUSeconds, leg.audioSeconds),
            busy, leg.underruns, leg.underrunWaitSeconds
        )
        if let stats = leg.coreML {
            line += " · " + fallbackSummary(stats)
        }
        return line
    }

    private static func fallbackSummary(_ stats: VieNeuCoreMLFlowBackend.Stats) -> String {
        let frames = stats.coreMLFrames + stats.fallbackFrames
        let share = frames > 0 ? Double(stats.fallbackFrames) / Double(frames) * 100 : 0
        return String(format: "lùi ORT %ld/%ld chunk (%.0f%% khung)", stats.fallbackChunks,
                      stats.coreMLChunks + stats.fallbackChunks, share)
    }

    private static func detail(_ leg: VieNeuAutoThermalLeg) -> [String] {
        var lines = ["== Lượt \(leg.index + 1): \(leg.engine.title)\(leg.interrupted ? " — DỞ (chạy lại ở lần chạy tiếp)" : "")"]
        if let skipped = leg.skippedReason {
            lines.append("bỏ qua — \(skipped)")
            return lines
        }
        lines.append("chờ mát     \(VieNeuTurboSoakStats.clock(leg.settleSeconds)) (\(leg.settleNote))")
        lines.append("lúc bắt đầu \(leg.startCondition) · \(leg.modeNote)")
        lines.append("kết thúc    \(leg.endReason)")
        if let stats = leg.coreML {
            let padding = stats.coreMLFrames > 0 ? (Double(stats.paddedVEFrames) / Double(stats.coreMLFrames) - 1) * 100 : 0
            let ve = stats.veBucketUse.sorted { $0.key < $1.key }.map { "T\($0.key)×\($0.value)" }.joined(separator: " ")
            let codec = stats.codecBucketUse.sorted { $0.key < $1.key }.map { "T\($0.key)×\($0.value)" }.joined(separator: " ")
            let reasons = stats.fallbackReasons.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            lines.append("Core ML     \(fallbackSummary(stats)) · VE \(ve) · codec \(codec)")
            lines.append(String(format: "            tính thừa do đệm VE %.0f%% · L lớn nhất %ld · nạp session %ld lần (%.1f s)",
                                padding, stats.maxContextLength, stats.sessionLoads, stats.sessionLoadMs / 1_000))
            if !reasons.isEmpty { lines.append("            lý do lùi ORT: \(reasons)") }
        }
        if !leg.conditionLines.isEmpty {
            lines.append("— Điều kiện máy mỗi phút —")
            lines += leg.conditionLines
        }
        if !leg.soakReport.isEmpty {
            lines.append("— Đọc liên tục —")
            lines.append(leg.soakReport)
        }
        return lines
    }
}
