import Foundation

/// Tiến độ của "Đo tự động" lưu xuống máy sau mỗi bước (1.3.910) — để **Chạy tiếp** khi lượt đo bị dừng, bị gián đoạn
/// (TTS / nhạc / cuộc gọi) hay app bị giết, thay vì đo lại cả 1–2 tiếng từ đầu (anh Bửu: *"lỡ trường hợp có việc thoát ra
/// khỏi chạy từ đầu"*).
///
/// Ghi: chuẩn bị Core ML xong (kết quả tự kiểm, trần session), mỗi lượt xong / dở, mỗi phút của lượt đang chạy (bản chụp
/// để app bị giết vẫn còn số), lúc kết thúc. Chạy tiếp = bỏ bước tải + biên dịch, chạy từ lượt đầu tiên chưa xong êm
/// (lượt dở chạy lại cả bước chờ mát).
struct VieNeuAutoRunProgress: Codable, Sendable {
    static let fileName = "do-tu-dong-tien-do.json"
    static let currentVersion = 1

    var version = VieNeuAutoRunProgress.currentVersion
    var startedAt: Date
    var voice: String
    var prepareDone = false
    var prepareLines: [String] = []
    var coreMLPassed = false
    var sessionCap = 2
    var sessionEstimateMB = 300.0
    /// Mọi lượt đã chạy, kể cả lượt dở (`interrupted`).
    var legs: [VieNeuAutoThermalLeg] = []
    /// Bản chụp mỗi phút của lượt đang chạy — app bị giết thì lần chạy tiếp ghi nó vào báo cáo như lượt dở.
    var inProgressLeg: VieNeuAutoThermalLeg?
    /// "chạy tiếp 15:40 từ lượt 2" — mỗi lần chạy tiếp một dòng.
    var resumeNotes: [String] = []
    var finished = false

    init(startedAt: Date, voice: String) {
        self.startedAt = startedAt
        self.voice = voice
    }

    /// Lượt kế tiếp phải chạy: bỏ lượt đã xong êm và lượt bị bỏ qua; `nil` = đã đủ.
    func nextLegIndex(planCount: Int) -> Int? {
        let done = Set(legs.filter { !$0.interrupted }.map(\.index))
        return (0..<planCount).first { !done.contains($0) }
    }

    static func url(in package: VieNeuCoreMLPackage) -> URL {
        package.resultsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    static func load(from url: URL) -> VieNeuAutoRunProgress? {
        guard let data = try? Data(contentsOf: url),
              let progress = try? JSONDecoder().decode(VieNeuAutoRunProgress.self, from: data),
              progress.version == currentVersion else { return nil }
        return progress
    }

    func save(to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [VieNeuAutoRun] Không ghi được tiến độ: \(error.localizedDescription)")
        }
    }

    static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
