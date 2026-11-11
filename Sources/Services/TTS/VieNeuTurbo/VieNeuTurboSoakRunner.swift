import AVFoundation
import Foundation
import Observation

/// Chế độ **"Đọc liên tục (đo nhiệt)"** của màn thử VieNeu Turbo: lặp một văn bản dài, tổng hợp từng đoạn, phát nối
/// tiếp, và ghi số đo từng đoạn + tổng kết mỗi phút — để biết sau 10–20 phút máy nóng tới đâu.
///
/// - **Cắt đoạn** bằng `NghiUtteranceSegmenter.expand(…, maximumLength: 150)` — đúng bộ cắt Reader dùng cho engine
///   local, nên Turbo và Nano nhận **cùng** các đoạn khi so.
/// - **Tổng hợp trước tối đa 2 đoạn** (`maxReadyAhead`), từng lượt một (không chạy song song) ⇒ CPU đo quanh mỗi lượt
///   là của riêng lượt đó.
/// - **Hụt tiếng**: trình phát hết đoạn mà đoạn kế chưa xong. Trong lúc chờ phát một vòng lặng (`keepAlivePlayer`) để
///   iOS không treo app khi đang khoá màn (app có background audio, nhưng không phát gì là bị treo).
/// - Engine nào cũng đi qua `Synthesizer` do `VieNeuTurboLab` dựng ⇒ runner không biết Turbo hay Nano.
@MainActor
@Observable
final class VieNeuTurboSoakRunner {
    struct ChunkAudio: Sendable {
        let wav: Data
        let audioSeconds: Double
        /// Thời gian tường của lượt tổng hợp (Turbo: tiền xử lý + phiên âm + audio.cpp; Nano: số của engine).
        let synthesisMs: Double
        /// CPU-time cả tiến trình quanh lượt tổng hợp.
        let cpuMs: Double
        /// Số ký tự phiên âm (Turbo); `nil` với Nano.
        let phonemeCount: Int?
        /// Phân rã text / vòng Euler / codec (Nano, 1.3.849); `nil` với Turbo.
        var split: VieNeuTurboSoakStats.StageSplit? = nil
        /// QoS **đo được** (Nano): "tổng hợp X · session Y" — để biết lựa chọn QoS có tới nơi thật không.
        var qosNote: String? = nil
    }

    typealias Synthesizer = @Sendable (String, TTSBoundaryKind) async throws -> ChunkAudio

    static let maxReadyAhead = 2
    static let maxChunkLength = 150
    private static let maxChunkLines = 40
    /// Trần số dòng từng đoạn giữ cho **file chia sẻ** (~ vài giờ đọc) — màn hình chỉ hiện `maxChunkLines`.
    private static let maxReportChunkLines = 5_000

    private(set) var isRunning = false
    private(set) var engineDescription = ""
    private(set) var statusLine = ""
    private(set) var errorMessage: String?
    /// Tổng kết từng phút, **mới nhất ở đầu**.
    private(set) var minuteLines: [String] = []
    /// Số đo từng đoạn, mới nhất ở đầu, giữ tối đa `maxChunkLines` dòng.
    private(set) var chunkLines: [String] = []
    private(set) var summaryText = ""

    /// Mọi dòng từng đoạn theo thứ tự thời gian — chỉ để dựng file chia sẻ (`reportText`).
    @ObservationIgnored private var allChunkLines: [String] = []
    /// QoS đo được ở đoạn gần nhất (Nano) — in ở đầu file chia sẻ.
    @ObservationIgnored private var lastQoSNote: String?
    @ObservationIgnored private var stats = VieNeuTurboSoakStats()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var producerTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var ready: [ChunkAudio] = []
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var keepAlivePlayer: AVAudioPlayer?
    private let playerDelegate = PlayerDelegate()
    @ObservationIgnored private var underrunStartedAt: TimeInterval?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    /// Văn bản (đã qua thay thế ký tự) ⇒ các đoạn ≤ 150 ký tự theo câu, mỗi dòng một đoạn văn.
    static func chunks(from text: String) -> [TTSParagraph] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                TTSParagraph(text: line, range: NSRange(location: 0, length: line.utf16.count), paragraphIndex: index)
            }
        return NghiUtteranceSegmenter.expand(paragraphs, maximumLength: maxChunkLength)
    }

    // MARK: - Điều khiển

    /// `priority` = mức ưu tiên của task tổng hợp. Turbo giữ `.utility` (cùng hàng đợi của `VieNeuTurboRuntime`); lượt
    /// Nano dùng QoS chọn ở màn thử (1.3.849) — `PiperSynthesisCoordinator` thừa hưởng mức này từ task gọi nó.
    func start(
        chunks: [TTSParagraph],
        engineDescription: String,
        priority: TaskPriority = .utility,
        synthesize: @escaping Synthesizer
    ) {
        guard !chunks.isEmpty else { return }
        stop(reason: "bắt đầu lượt mới")
        generation += 1
        let runGeneration = generation
        isRunning = true
        self.engineDescription = engineDescription
        errorMessage = nil
        minuteLines = []
        chunkLines = []
        allChunkLines = []
        lastQoSNote = nil
        stats = VieNeuTurboSoakStats()
        summaryText = stats.summary()
        statusLine = "Đang chuẩn bị đoạn đầu…"
        playerDelegate.onFinish = { [weak self] finished in self?.playerDidFinish(finished) }
        // Cuộc gọi / Siri tạm dừng AVAudioPlayer mà không gọi `didFinish` ⇒ lượt đo đứng im trong khi đồng hồ vẫn chạy.
        // Dừng hẳn để tổng kết không bị kéo sai.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
            Task { @MainActor in self?.stop(reason: "bị ngắt âm thanh (cuộc gọi, Siri…)") }
        }
        startKeepAlive()

        producerTask = Task(priority: priority) { [weak self] in
            await self?.produce(chunks: chunks, generation: runGeneration, synthesize: synthesize)
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.closeMinute(generation: runGeneration)
            }
        }
        AppLogger.shared.log(
            "🎙️ [VieNeuTurbo] Bắt đầu đọc liên tục — \(engineDescription), \(chunks.count) đoạn mỗi vòng, nhiệt \(VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState))"
        )
    }

    func stop(reason: String = "bấm Dừng") {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        producerTask?.cancel()
        producerTask = nil
        clockTask?.cancel()
        clockTask = nil
        player?.stop()
        player = nil
        stopKeepAlive()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        ready.removeAll()
        if let started = underrunStartedAt {
            stats.recordUnderrunEnd(waitMs: (ProcessInfo.processInfo.systemUptime - started) * 1_000)
            underrunStartedAt = nil
        }
        summaryText = stats.summary()
        statusLine = "Đã dừng (\(reason))."
        let oneLine = summaryText
            .split(separator: "\n")
            .map { $0.split(whereSeparator: { $0 == " " }).joined(separator: " ") }
            .joined(separator: " | ")
        AppLogger.shared.log("🎙️ [VieNeuTurbo] Kết thúc đọc liên tục (\(reason)) — \(engineDescription): \(oneLine)")
    }

    // MARK: - Bộ sinh

    private func produce(chunks: [TTSParagraph], generation runGeneration: Int, synthesize: Synthesizer) async {
        var index = 0
        while isRunning, generation == runGeneration, !Task.isCancelled {
            if ready.count >= Self.maxReadyAhead {
                try? await Task.sleep(for: .milliseconds(150))
                continue
            }
            let chunk = chunks[index % chunks.count]
            if player == nil, underrunStartedAt == nil {
                statusLine = "Đang tổng hợp đoạn \(index + 1)…"
            }
            do {
                let audio = try await synthesize(chunk.text, chunk.boundaryKind)
                guard isRunning, generation == runGeneration else { return }
                stats.recordChunk(
                    characters: chunk.text.count,
                    audioSeconds: audio.audioSeconds,
                    synthesisMs: audio.synthesisMs,
                    cpuMs: audio.cpuMs,
                    split: audio.split
                )
                recordChunkLine(number: index + 1, round: index / chunks.count + 1, characters: chunk.text.count, audio: audio)
                ready.append(audio)
                if player == nil { playNext() }
                index += 1
            } catch is CancellationError {
                return
            } catch {
                guard isRunning, generation == runGeneration else { return }
                fail(error)
                return
            }
        }
    }

    private func recordChunkLine(number: Int, round: Int, characters: Int, audio: ChunkAudio) {
        let thermal = VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState)
        let phonemes = audio.phonemeCount.map { " · \($0) âm vị" } ?? ""
        // Nano: giây tường của vòng Euler / codec / text_encoder (CPU-s trong ngoặc).
        let split = audio.split.map {
            String(
                format: " · Euler %.2f (%.2f) · codec %.2f (%.2f) · text %.2f (%.2f) s",
                $0.vectorMs / 1_000, $0.vectorCPUMs / 1_000, $0.codecMs / 1_000, $0.codecCPUMs / 1_000,
                $0.textMs / 1_000, $0.textCPUMs / 1_000
            )
        } ?? ""
        if let note = audio.qosNote { lastQoSNote = note }
        let qos = audio.qosNote.map { " · QoS \($0)" } ?? ""
        let line = String(
            format: "#%d (vòng %d) · %d ký tự%@ · tổng hợp %.2f s%@ · tiếng %.2f s · RTF %@ · CPU/tiếng %@ · %@ · %@%@",
            number,
            round,
            characters,
            phonemes,
            audio.synthesisMs / 1_000,
            split,
            audio.audioSeconds,
            VieNeuTurboSoakStats.ratio(audio.synthesisMs / 1_000, audio.audioSeconds),
            VieNeuTurboSoakStats.ratio(audio.cpuMs / 1_000, audio.audioSeconds),
            thermal,
            // Bộ nhớ sau mỗi đoạn: thấy được nó có tăng dần theo thời gian không (lỗi cấp phát của 1.3.847).
            ProcessMemoryProbe.snapshot().summary,
            qos
        )
        chunkLines.insert(line, at: 0)
        if chunkLines.count > Self.maxChunkLines { chunkLines.removeLast(chunkLines.count - Self.maxChunkLines) }
        allChunkLines.append(line)
        if allChunkLines.count > Self.maxReportChunkLines {
            allChunkLines.removeFirst(allChunkLines.count - Self.maxReportChunkLines)
        }
        summaryText = stats.summary()
        AppLogger.shared.log("🎙️ [VieNeuTurbo] [\(engineDescription)] \(line)")
    }

    /// Nội dung file chia sẻ của lượt đọc liên tục: engine + trạng thái + tổng kết + **mọi** phút và **mọi** đoạn theo
    /// thứ tự thời gian (màn hình chỉ hiện 40 đoạn gần nhất). Dựng lúc bấm chia sẻ (`VieNeuTurboReportFile`).
    func reportText() -> String {
        // Đang chạy thì tính lại cho tới giây này; đã dừng thì giữ bản chốt lúc dừng (tính lại sẽ kéo dài "thời gian").
        var parts = [engineDescription]
        // Mô tả engine ghi QoS **đã chọn**; dòng này là QoS **đo được** trên luồng thật (Nano).
        if let lastQoSNote { parts.append("QoS đo được: \(lastQoSNote)") }
        parts += [statusLine, isRunning ? stats.summary() : summaryText]
        if let errorMessage { parts.append("Lỗi: \(errorMessage)") }
        if !minuteLines.isEmpty {
            parts.append("— Từng phút —")
            parts.append(contentsOf: minuteLines.reversed())
        }
        if !allChunkLines.isEmpty {
            parts.append("— Từng đoạn (\(allChunkLines.count)) —")
            parts.append(contentsOf: allChunkLines)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func closeMinute(generation runGeneration: Int) {
        guard isRunning, generation == runGeneration else { return }
        let line = stats.closeMinute()
        minuteLines.insert(line, at: 0)
        summaryText = stats.summary()
        AppLogger.shared.log("🎙️ [VieNeuTurbo] [\(engineDescription)] \(line)")
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        AppLogger.shared.log(
            "❌ [VieNeuTurbo] Đọc liên tục lỗi — \(engineDescription): \(error.localizedDescription) — \(ProcessMemoryProbe.snapshot().summary)"
        )
        stop(reason: "lỗi")
    }

    // MARK: - Trình phát

    private func playNext() {
        guard isRunning, !ready.isEmpty else { return }
        let next = ready.removeFirst()
        if let started = underrunStartedAt {
            let waitMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            stats.recordUnderrunEnd(waitMs: waitMs)
            underrunStartedAt = nil
            AppLogger.shared.log("🎙️ [VieNeuTurbo] Hết hụt tiếng sau \(String(format: "%.0f", waitMs)) ms")
        }
        stopKeepAlive()
        do {
            let newPlayer = try AVAudioPlayer(data: next.wav)
            newPlayer.delegate = playerDelegate
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                fail(NSError(domain: "VieNeuTurbo", code: 1, userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer không phát được"]))
                return
            }
            player = newPlayer
            statusLine = "Đang phát · \(stats.chunks) đoạn đã tổng hợp · chờ sẵn \(ready.count)"
        } catch {
            fail(error)
        }
    }

    private func playerDidFinish(_ finished: AVAudioPlayer) {
        guard isRunning, finished === player else { return }
        player = nil
        if ready.isEmpty {
            underrunStartedAt = ProcessInfo.processInfo.systemUptime
            stats.recordUnderrunStart()
            startKeepAlive()
            statusLine = "Hụt tiếng — đang chờ đoạn kế…"
            AppLogger.shared.log("🎙️ [VieNeuTurbo] Hụt tiếng: trình phát chờ đoạn kế (lần \(stats.underruns))")
        } else {
            playNext()
        }
    }

    /// Vòng lặng 1 s lặp vô hạn — giữ phiên âm thanh "đang phát" trong lúc chờ đoạn (khi khoá màn).
    private func startKeepAlive() {
        if keepAlivePlayer == nil {
            let silence = [Float](repeating: 0, count: 24_000)
            keepAlivePlayer = try? AVAudioPlayer(data: WAVEncoder.encodePCM16(samples: silence, sampleRate: 24_000))
            keepAlivePlayer?.numberOfLoops = -1
            keepAlivePlayer?.volume = 0
        }
        keepAlivePlayer?.play()
    }

    private func stopKeepAlive() {
        keepAlivePlayer?.stop()
    }

    /// Delegate tách riêng vì `@Observable` class không kế thừa `NSObject` được gọn. AVAudioPlayer gọi delegate trên
    /// main thread; vẫn nhảy qua `MainActor` cho chắc.
    private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (@MainActor (AVAudioPlayer) -> Void)?

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            let callback = onFinish
            Task { @MainActor in callback?(player) }
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            let callback = onFinish
            Task { @MainActor in callback?(player) }
        }
    }
}
