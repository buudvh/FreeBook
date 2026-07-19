import Foundation
import AVFoundation
import MediaPlayer
import Combine
import QuartzCore
import UIKit
import SwiftData

/// Updates the transport state without waiting for the asynchronous metadata
/// refresh. The Lock Screen uses both values to choose its Play/Pause icon.
private func setSystemNowPlayingPlaybackState(
    _ state: MPNowPlayingPlaybackState,
    playbackRate: Double
) {
    let center = MPNowPlayingInfoCenter.default()
    center.playbackState = state

    guard var info = center.nowPlayingInfo else { return }
    info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
    center.nowPlayingInfo = info
}

@MainActor
public final class TTSManager: NSObject, ObservableObject {
    public static let shared = TTSManager()

    // Cấu hình (lưu qua AppStorage/UserDefaults)
    @Published public var tool: String {
        didSet {
            UserDefaults.standard.set(tool, forKey: "ttsTool")
            loadParamsForCurrentTool()
            clearPrefetchCache()
        }
    }
    @Published public var speed: Double {
        didSet {
            UserDefaults.standard.set(speed, forKey: "ttsRate")
            if tool == "system" {
                UserDefaults.standard.set(speed, forKey: "systemRate")
            } else if tool == "nghitts" {
                UserDefaults.standard.set(speed, forKey: "nghittsRate")
            } else {
                UserDefaults.standard.set(speed, forKey: "extRate_\(tool)")
            }
            updatePlaybackParams()
        }
    }
    @Published public var pitch: Double {
        didSet {
            UserDefaults.standard.set(pitch, forKey: "ttsPitch")
            if tool == "system" {
                UserDefaults.standard.set(pitch, forKey: "systemPitch")
            } else if tool == "nghitts" {
                UserDefaults.standard.set(pitch, forKey: "nghittsPitch")
            } else {
                UserDefaults.standard.set(pitch, forKey: "extPitch_\(tool)")
            }
            updatePlaybackParams()
        }
    }
    @Published public var selectedVoice: String {
        didSet {
            UserDefaults.standard.set(selectedVoice, forKey: "ttsVoice")
            if tool == "system" {
                UserDefaults.standard.set(selectedVoice, forKey: "systemVoice")
            } else if tool == "nghitts" {
                UserDefaults.standard.set(selectedVoice, forKey: "nghittsVoice")
            } else {
                UserDefaults.standard.set(selectedVoice, forKey: "extVoice_\(tool)")
            }
            clearPrefetchCache()
        }
    }
    @Published public var chunkLength: Int {
        didSet { UserDefaults.standard.set(chunkLength, forKey: "ttsChunkLength") }
    }

    @Published public var extensionLocalPath: String {
        didSet { UserDefaults.standard.set(extensionLocalPath, forKey: "ttsExtensionLocalPath") }
    }
    @Published public var extensionConfigJson: String {
        didSet { UserDefaults.standard.set(extensionConfigJson, forKey: "ttsExtensionConfigJson") }
    }

    // Trạng thái playback
    @Published public var isPlaying: Bool = false
    @Published public var currentParagraphIndex: Int = -1
    @Published public var currentParentParagraphIndex: Int = -1
    @Published public var highlightRange: NSRange? = nil
    @Published public var showFloatingWidget: Bool = false
    @Published public var showingSettingsSheet: Bool = false

    // Thông tin phát nhạc độc lập toàn cục
    @Published public private(set) var playingBookId: String = ""
    @Published public private(set) var playingCoverUrl: String = ""
    @Published public private(set) var playingChapterUrl: String = ""
    @Published public private(set) var playingChapterIndex: Int = -1
    @Published public private(set) var playingBookDetailUrl: String = ""
    @Published public private(set) var playingBookSourceName: String = ""
    @Published public private(set) var extensionInfo: TTSExtensionInfo? = nil

    private var chaptersQueue: [TTSChapterInfo] = []
    private var currentPlaybackId: String? = nil
    private var wasPlayingBeforeSettings = false
    private var wasPlayingBeforeInterruption = false
    private var lastPausedTime: Date? = nil
    private var cancellables = Set<AnyCancellable>()
    private var prepareSpeakingTask: Task<Void, Never>? = nil
    private var nextChapterPrefetchTask: Task<Void, Never>? = nil
    private var sessionID = UUID()
    // Now Playing updates include detached translation/cover work. A newer
    // playback state must invalidate older tasks so Lock Screen cannot revert
    // a just-resumed session back to paused (or vice versa).
    private var nowPlayingUpdateGeneration: UInt = 0

    // Cache lưu trữ dữ liệu âm thanh đã được tổng hợp trước cho các đoạn văn
    private var preloadedWavs: [Int: AVAudioPCMBuffer] = [:]
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]

    // Theo dõi format buffer cuối cùng để tránh rebuild node graph không cần thiết
    private var lastBufferFormat: AVAudioFormat? = nil

    // Tiến trình tải model NghiTTS
    @Published public var downloadingVoices: [String: Double] = [:] // voiceName -> progress (0.0 ... 1.0)
    @Published public var downloadingMessages: [String: String] = [:] // voiceName -> message

    // Thông tin sách & chương hiện tại
    public var bookTitle: String = ""
    public var chapterTitle: String = ""

    // Callbacks chuyển chương
    public var onChapterFinished: (() -> Void)?

    // Dữ liệu phân đoạn
    public private(set) var paragraphs: [TTSParagraph] = []
    private var chapterContent: String = ""
    private var normalizedChapterText = ChapterTextNormalizer.normalize("")

    // Trình phát & Engine
    private let siriService = SiriTTSService()
    private let extService = ExtTTSService()
    private let googleService = GoogleTTSService()
    private var nghiTTSService: PiperTTSService?
    public private(set) var nghiTTSClient: NghiTTSClient?
    private var modelStore: ModelStore?

    public func initialize(container: ModelContainer) {
        Task {
            await ReadingProgressStore.shared.configure(container: container)
            await ChapterContentRepository.shared.configure(container: container)
        }
    }

    private func progressSnapshot() -> ReadingProgressSnapshot? {
        guard !playingBookId.isEmpty, playingChapterIndex >= 0 else { return nil }
        return ReadingProgressSnapshot(
            bookId: playingBookId,
            chapterIndex: playingChapterIndex,
            paragraphIndex: currentParentParagraphIndex,
            chapterTitle: chaptersQueue.first(where: { $0.index == playingChapterIndex })?.title,
            owner: .tts,
            recordedAt: Date()
        )
    }

    private func recordProgressInMemory() {
        guard let snapshot = progressSnapshot() else { return }
        Task { await ReadingProgressStore.shared.record(snapshot) }
    }

    private func checkpointProgressAndRelease() {
        guard let snapshot = progressSnapshot() else { return }
        Task(priority: .high) {
            do {
                try await ReadingProgressStore.shared.checkpointAndRelease(snapshot, owner: .tts)
            } catch {
                AppLogger.shared.log("❌ Lỗi lưu checkpoint TTS: \(error.localizedDescription)")
            }
        }
    }

    private func checkpointProgress() {
        guard let snapshot = progressSnapshot() else { return }
        Task(priority: .high) {
            try? await ReadingProgressStore.shared.checkpoint(snapshot)
        }
    }

    public func checkpointForBackground() {
        guard let snapshot = progressSnapshot() else { return }
        Task(priority: .high) {
            await ReadingProgressStore.shared.record(snapshot)
            try? await ReadingProgressStore.shared.flush(bookId: snapshot.bookId)
        }
    }

    // AVAudioEngine cho NghiTTS
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?

    private override init() {
        // Nạp cấu hình từ UserDefaults
        let toolVal = UserDefaults.standard.string(forKey: "ttsTool") ?? "system"
        self.tool = toolVal

        let defaultRate = UserDefaults.standard.object(forKey: "ttsRate") != nil ? UserDefaults.standard.double(forKey: "ttsRate") : 1.0
        let defaultPitch = UserDefaults.standard.object(forKey: "ttsPitch") != nil ? UserDefaults.standard.double(forKey: "ttsPitch") : 1.0

        if toolVal == "system" {
            self.speed = UserDefaults.standard.double(forKey: "systemRate") > 0 ? UserDefaults.standard.double(forKey: "systemRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "systemPitch") > 0 ? UserDefaults.standard.double(forKey: "systemPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "systemVoice") ?? (UserDefaults.standard.string(forKey: "ttsVoice") ?? "")
        } else if toolVal == "nghitts" {
            self.speed = UserDefaults.standard.double(forKey: "nghittsRate") > 0 ? UserDefaults.standard.double(forKey: "nghittsRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "nghittsPitch") > 0 ? UserDefaults.standard.double(forKey: "nghittsPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? (UserDefaults.standard.string(forKey: "ttsVoice") ?? "Ngọc Huyền (mới)")
        } else {
            self.speed = UserDefaults.standard.double(forKey: "extRate_\(toolVal)") > 0 ? UserDefaults.standard.double(forKey: "extRate_\(toolVal)") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "extPitch_\(toolVal)") > 0 ? UserDefaults.standard.double(forKey: "extPitch_\(toolVal)") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "extVoice_\(toolVal)") ?? ""
        }

        self.chunkLength = UserDefaults.standard.object(forKey: "ttsChunkLength") != nil ? UserDefaults.standard.integer(forKey: "ttsChunkLength") : 200
        self.extensionLocalPath = UserDefaults.standard.string(forKey: "ttsExtensionLocalPath") ?? ""
        self.extensionConfigJson = UserDefaults.standard.string(forKey: "ttsExtensionConfigJson") ?? "{}"

        super.init()

        setupEngines()
        setupAudioEngine()
        setupRemoteCommandCenter()
        setupInterruptionObserver()
    }

    private func loadParamsForCurrentTool() {
        let defaultRate = UserDefaults.standard.object(forKey: "ttsRate") != nil ? UserDefaults.standard.double(forKey: "ttsRate") : 1.0
        let defaultPitch = UserDefaults.standard.object(forKey: "ttsPitch") != nil ? UserDefaults.standard.double(forKey: "ttsPitch") : 1.0

        if tool == "system" {
            self.speed = UserDefaults.standard.double(forKey: "systemRate") > 0 ? UserDefaults.standard.double(forKey: "systemRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "systemPitch") > 0 ? UserDefaults.standard.double(forKey: "systemPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "systemVoice") ?? ""
        } else if tool == "nghitts" {
            self.speed = UserDefaults.standard.double(forKey: "nghittsRate") > 0 ? UserDefaults.standard.double(forKey: "nghittsRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "nghittsPitch") > 0 ? UserDefaults.standard.double(forKey: "nghittsPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? "Ngọc Huyền (mới)"
        } else {
            self.speed = UserDefaults.standard.double(forKey: "extRate_\(tool)") > 0 ? UserDefaults.standard.double(forKey: "extRate_\(tool)") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "extPitch_\(tool)") > 0 ? UserDefaults.standard.double(forKey: "extPitch_\(tool)") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "extVoice_\(tool)") ?? ""
        }
    }

    private func setupEngines() {
        do {
            let store = try ModelStore()
            self.modelStore = store
            self.nghiTTSClient = NghiTTSClient(modelStore: store)
            self.nghiTTSService = PiperTTSService(modelStore: store, engine: ONNXPiperEngine())

            // Đặt giọng NghiTTS mặc định nếu chưa chọn
            if self.selectedVoice.isEmpty {
                self.selectedVoice = NghiTTSClient.defaultVietnameseVoice.name
            }
        } catch {
            AppLogger.shared.log("Error initializing TTS model store: \(error.localizedDescription)")
        }
    }

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitchNode = AVAudioUnitTimePitch()

        engine.attach(player)
        engine.attach(pitchNode)

        // Connect Player -> TimePitch -> mainMixer
        engine.connect(player, to: pitchNode, format: nil)
        engine.connect(pitchNode, to: engine.mainMixerNode, format: nil)

        self.audioEngine = engine
        self.playerNode = player
        self.timePitchNode = pitchNode
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            AppLogger.shared.log("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func updatePlaybackParams() {
        if isPlaying {
            if tool == "system" {
                // AVSpeechSynthesizer không hỗ trợ thay đổi tốc độ thời gian thực của câu đang nói,
                // nhưng cấu hình sẽ được áp dụng cho phân đoạn tiếp theo.
            } else if let pitchNode = timePitchNode {
                pitchNode.rate = Float(speed)
                let cents = 1200.0 * log2(pitch)
                pitchNode.pitch = Float(cents)
            }
            updateNowPlayingInfo()
        }
    }

    public func prepareSpeaking(
        bookId: String,
        chapters: [TTSChapterInfo],
        currentIndex: Int,
        chapterContent: String,
        startParagraphIndex: Int,
        bookTitle: String,
        coverUrl: String = "",
        bookDetailUrl: String = "",
        bookSourceName: String = "",
        extensionInfo: TTSExtensionInfo?
    ) {
        guard !isPlaying else { return }
        guard chapters.contains(where: { $0.index == currentIndex }) else { return }
        sessionID = UUID()
        let preparationSessionID = sessionID

        self.playingBookId = bookId
        self.playingCoverUrl = coverUrl
        self.chaptersQueue = chapters
        self.playingChapterIndex = currentIndex
        self.bookTitle = bookTitle
        self.playingBookDetailUrl = bookDetailUrl
        self.playingBookSourceName = bookSourceName
        self.extensionInfo = extensionInfo
        let normalizedText = ChapterTextNormalizer.normalize(chapterContent)
        self.normalizedChapterText = normalizedText
        self.chapterContent = normalizedText.content

        self.clearPrefetchCache()

        guard let currentChapter = chapters.first(where: { $0.index == currentIndex }) else { return }
        self.playingChapterUrl = currentChapter.url
        self.chapterTitle = currentChapter.title
        let preparationChapterURL = currentChapter.url

        let currentChunkLen = self.chunkLength
        self.prepareSpeakingTask?.cancel()
        self.prepareSpeakingTask = Task {
            let parsed = await Task.detached(priority: .userInitiated) { () -> [TTSParagraph] in
                return TTSParagraphBuilder.build(from: normalizedText, chunkLength: currentChunkLen)
            }.value

            guard !Task.isCancelled else { return }
            guard preparationSessionID == self.sessionID,
                  bookId == self.playingBookId,
                  currentIndex == self.playingChapterIndex,
                  preparationChapterURL == self.playingChapterUrl else { return }

            self.paragraphs = parsed

            let key = "showChapterTitle_\(playingBookId)"
            let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true

            var titleInserted = false
            if showTitle && !chapterTitle.isEmpty {
                let titleParagraph = TTSParagraph(
                    text: chapterTitle,
                    range: NSRange(location: 0, length: chapterTitle.utf16.count),
                    paragraphIndex: -1
                )
                self.paragraphs.insert(titleParagraph, at: 0)
                titleInserted = true
            }

            var targetIdx = 0
            if startParagraphIndex == -1 {
                targetIdx = 0
            } else {
                if let idx = paragraphs.firstIndex(where: { $0.paragraphIndex == startParagraphIndex }) {
                    targetIdx = idx
                } else {
                    targetIdx = titleInserted ? 1 : 0
                }
            }

            if targetIdx >= 0 && targetIdx < paragraphs.count {
                self.currentParagraphIndex = targetIdx
                let paragraph = paragraphs[targetIdx]
                self.highlightRange = paragraph.range
                self.currentParentParagraphIndex = paragraph.paragraphIndex
            }

            self.updateNowPlayingInfo()
        }
    }

    public func updateParagraphPositionWithoutPlaying(paragraphIndex: Int) {
        guard !isPlaying else { return }

        let titleInserted = paragraphs.first?.paragraphIndex == -1
        var targetIdx = -1
        if paragraphIndex == -1 {
            targetIdx = 0
        } else if let idx = paragraphs.firstIndex(where: { $0.paragraphIndex == paragraphIndex }) {
            targetIdx = idx
        } else {
            targetIdx = titleInserted ? 1 : 0
        }

        if targetIdx >= 0 && targetIdx < paragraphs.count {
            self.currentParagraphIndex = targetIdx
            let paragraph = paragraphs[targetIdx]
            self.highlightRange = paragraph.range
            self.currentParentParagraphIndex = paragraph.paragraphIndex
            updateNowPlayingInfo()
        }
    }

    public func startSpeaking(
        bookId: String,
        chapters: [TTSChapterInfo],
        currentIndex: Int,
        chapterContent: String,
        startParagraphIndex: Int,
        bookTitle: String,
        coverUrl: String = "",
        bookDetailUrl: String = "",
        bookSourceName: String = "",
        extensionInfo: TTSExtensionInfo?
    ) {
        guard chapters.contains(where: { $0.index == currentIndex }) else { return }
        checkpointProgressAndRelease()
        prepareSpeakingTask?.cancel()
        prepareSpeakingTask = nil
        sessionID = UUID()
        // Dọn dẹp trình phát cũ trước tiên để tránh xung đột luồng và callback lặp
        self.stopCurrentPlayback()
        self.wasPlayingBeforeInterruption = false

        self.configureAudioSession()
        self.setRemoteCommandsEnabled(true) // Kích hoạt Media Remote
        self.playingBookId = bookId
        self.playingCoverUrl = coverUrl
        self.chaptersQueue = chapters
        self.playingChapterIndex = currentIndex
        self.bookTitle = bookTitle
        self.playingBookDetailUrl = bookDetailUrl
        self.playingBookSourceName = bookSourceName
        self.extensionInfo = extensionInfo
        self.normalizedChapterText = ChapterTextNormalizer.normalize(chapterContent)
        self.chapterContent = normalizedChapterText.content
        self.showFloatingWidget = true
        Task { await ReadingProgressStore.shared.claim(bookId: bookId, owner: .tts) }

        // Huy du lieu tai truoc cu

        // Xóa bộ đệm tải trước của đoạn văn cũ
        self.clearPrefetchCache()

        guard let currentChapter = chapters.first(where: { $0.index == currentIndex }) else { return }
        self.playingChapterUrl = currentChapter.url
        self.chapterTitle = currentChapter.title

        self.continueStartSpeaking(startParagraphIndex: startParagraphIndex)
        self.triggerNextChapterPrefetch()
    }

    private func continueStartSpeaking(startParagraphIndex: Int) {
        // Phân đoạn văn bản sạch
        self.paragraphs = TTSParagraphBuilder.build(from: normalizedChapterText, chunkLength: chunkLength)

        // Kiểm tra cấu hình hiện tên chương trong nội dung của truyện hiện tại (mặc định bật)
        let key = "showChapterTitle_\(playingBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true

        var titleInserted = false
        if showTitle && !chapterTitle.isEmpty {
            let titleParagraph = TTSParagraph(
                text: chapterTitle,
                range: NSRange(location: 0, length: chapterTitle.utf16.count),
                paragraphIndex: -1
            )
            self.paragraphs.insert(titleParagraph, at: 0)
            titleInserted = true
        }

        // Tìm chunk đầu tiên có paragraphIndex khớp với chỉ số đoạn văn yêu cầu
        var targetIdx = 0
        if startParagraphIndex == -1 {
            targetIdx = 0
        } else {
            if let idx = paragraphs.firstIndex(where: { $0.paragraphIndex == startParagraphIndex }) {
                targetIdx = idx
            } else {
                targetIdx = titleInserted ? 1 : 0
            }
        }

        self.currentParagraphIndex = targetIdx
        self.isPlaying = true
        setSystemNowPlayingPlaybackState(.playing, playbackRate: speed)
        self.syncRemoteCommandState()

        speakCurrent()
    }



    public func pause() {
        // let pid = currentPlaybackId ?? "NONE"
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] pause() được gọi.")
        guard isPlaying else { return }
        checkpointProgressAndRelease()
        self.isPlaying = false
        self.lastPausedTime = Date()
        setSystemNowPlayingPlaybackState(.paused, playbackRate: 0)

        if tool == "system" {
            siriService.pause()
        } else {
            playerNode?.pause()
        }
        syncRemoteCommandState()
        updateNowPlayingInfo()
    }

    public func resume() {
        // let pid = currentPlaybackId ?? "NONE"
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] resume() được gọi.")
        if isPlaying {
            // Remote controls can deliver a duplicate play event while the
            // Lock Screen is catching up. Keep it idempotent and make sure the
            // underlying engine/synthesizer is actually running.
            if tool == "system" {
                if siriService.isPaused {
                    if !siriService.resume() {
                        speakCurrent()
                    }
                }
            } else if let playerNode, !playerNode.isPlaying {
                playerNode.play()
            }
            setSystemNowPlayingPlaybackState(.playing, playbackRate: speed)
            syncRemoteCommandState()
            updateNowPlayingInfo()
            return
        }

        // Đảm bảo có dữ liệu hợp lệ để tiếp tục phát
        guard currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count else {
            return
        }

        self.configureAudioSession()
        self.setRemoteCommandsEnabled(true) // Bật lại remote commands
        self.isPlaying = true
        Task { await ReadingProgressStore.shared.claim(bookId: playingBookId, owner: .tts) }
        setSystemNowPlayingPlaybackState(.playing, playbackRate: speed)

        if tool == "system" {
            if siriService.isPaused {
                if !siriService.resume() {
                    speakCurrent()
                }
            } else {
                speakCurrent()
            }
        } else {
            if let engine = audioEngine, !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    AppLogger.shared.log("🔊 [TTSManager] resume: Engine start failed: \(error.localizedDescription). Restarting paragraph.")
                    speakCurrent()
                    updateNowPlayingInfo()
                    return
                }
            }

            // Tính toán thời gian đã tạm dừng
            let timeSincePause = lastPausedTime.map { Date().timeIntervalSince($0) } ?? 0.0

            // Nếu đã tạm dừng quá 5 giây hoặc chưa có playback hoạt động, phát lại từ đầu câu.
            // Ngược lại, tiếp tục phát tiếp tục (resume) để có trải nghiệm mượt mà.
            if timeSincePause > 5.0 || currentPlaybackId == nil {
                speakCurrent()
            } else {
                playerNode?.play()
            }
        }
        syncRemoteCommandState()
        updateNowPlayingInfo()
    }

    private func stopPlayback(keepWidget: Bool = false) {
        // let pid = currentPlaybackId ?? "NONE"
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] stopPlayback(keepWidget=\(keepWidget)) được gọi.")
        checkpointProgressAndRelease()
        sessionID = UUID()
        self.isPlaying = false
        self.wasPlayingBeforeSettings = false
        self.wasPlayingBeforeInterruption = false
        nowPlayingUpdateGeneration &+= 1

        if !keepWidget {
            self.currentParagraphIndex = -1
            self.currentParentParagraphIndex = -1
            self.highlightRange = nil
            self.showFloatingWidget = false
        }

        clearPrefetchCache()

        siriService.stop()
        playerNode?.stop()
        audioEngine?.stop()
        cleanUpTempFile()

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        self.setRemoteCommandsEnabled(false) // Vô hiệu hóa remote commands khi dừng hẳn

        // Giải phóng Audio Session khi dừng hoàn toàn để ứng dụng khác có thể phát âm thanh
        if !keepWidget {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public func stop() {
        stopPlayback(keepWidget: false)
    }

    public func prepareForSettings() {
        if !wasPlayingBeforeSettings {
            wasPlayingBeforeSettings = isPlaying
        }
        if isPlaying {
            pause()
        }
    }

    public func resumeAfterSettings() {
        guard !chapterContent.isEmpty else {
            stopPlayback(keepWidget: false)
            return
        }

        // Lưu paragraph identity (số thứ tự dòng gốc) thay vì array index
        let savedParagraphIdentity: Int
        if currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count {
            savedParagraphIdentity = paragraphs[currentParagraphIndex].paragraphIndex
        } else {
            savedParagraphIdentity = -1
        }
        let wasPlaying = wasPlayingBeforeSettings
        wasPlayingBeforeSettings = false

        // Dừng engine cũ để áp dụng cài đặt mới (nhưng giữ widget nổi)
        stopPlayback(keepWidget: true)

        // Nạp lại phân đoạn
        self.paragraphs = TTSParagraphBuilder.build(from: normalizedChapterText, chunkLength: chunkLength)

        var targetIdx = paragraphs.firstIndex(where: {
            $0.paragraphIndex == savedParagraphIdentity
        }) ?? 0

        let key = "showChapterTitle_\(playingBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true

        if savedParagraphIdentity == -1 && showTitle && !chapterTitle.isEmpty {
            let titleParagraph = TTSParagraph(
                text: chapterTitle,
                range: NSRange(location: 0, length: chapterTitle.utf16.count),
                paragraphIndex: -1
            )
            self.paragraphs.insert(titleParagraph, at: 0)
            targetIdx = 0
        } else if showTitle && !chapterTitle.isEmpty {
            let titleParagraph = TTSParagraph(
                text: chapterTitle,
                range: NSRange(location: 0, length: chapterTitle.utf16.count),
                paragraphIndex: -1
            )
            self.paragraphs.insert(titleParagraph, at: 0)
            targetIdx = (paragraphs.firstIndex(where: { $0.paragraphIndex == savedParagraphIdentity }) ?? 1)
        }

        self.currentParagraphIndex = targetIdx

        // Nếu trước đó đang phát, tiếp tục phát đoạn đó với cài đặt mới
        if wasPlaying {
            self.isPlaying = true
            speakCurrent()
        }
    }

    public func restartCurrentParagraph() {
        guard isPlaying else { return }
        stopCurrentPlayback()
        clearPrefetchCache()
        speakCurrent()
    }

    public func skipForward() {
        guard currentParagraphIndex >= 0, currentParagraphIndex < paragraphs.count else { return }
        if currentParagraphIndex + 1 < paragraphs.count {
            stopCurrentPlayback()
            currentParagraphIndex += 1
            currentParentParagraphIndex = paragraphs[currentParagraphIndex].paragraphIndex
            highlightRange = nil
            checkpointProgress()
            if isPlaying {
                speakCurrent()
            } else {
                updateNowPlayingInfo()
            }
        } else {
            guard isPlaying else { return }
            // Đã hết chương, chuyển chương mới
            stopCurrentPlayback()
            if let nextIdx = nextChapterIndex(after: playingChapterIndex) {
                advanceToNextChapter(nextIdx: nextIdx)
            } else {
                stop()
                onChapterFinished?()
            }
        }
    }

    public func skipBackward() {
        // let pid = currentPlaybackId ?? "NONE"
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] skipBackward() được gọi.")
        guard isPlaying else { return }
        if currentParagraphIndex > 0 {
            stopCurrentPlayback()
            currentParagraphIndex -= 1
            speakCurrent()
        }
    }

    private func stopCurrentPlayback() {
        // let pid = currentPlaybackId ?? "NONE"
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] stopCurrentPlayback() được gọi.")
        self.currentPlaybackId = nil
        if tool == "system" {
            siriService.stop()
        } else {
            playerNode?.stop()
            playerNode?.reset() // Xóa toàn bộ buffer pending để tránh completion handler cũ gây nhiễu
        }
        cleanUpTempFile()
    }

    private func nextParagraph() {
        // let pid = currentPlaybackId ?? "NONE"
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] nextParagraph() được gọi.")
        guard isPlaying else { return }
        if currentParagraphIndex + 1 < paragraphs.count {
            currentParagraphIndex += 1
            speakCurrent()
        } else {
            // Hết chương → tự advance sang chương tiếp theo, không phụ thuộc ReaderView
            if let nextIdx = nextChapterIndex(after: playingChapterIndex) {
                stopCurrentPlayback()
                advanceToNextChapter(nextIdx: nextIdx)
            } else {
                // Đã hết sách hoàn toàn
                stop()
                onChapterFinished?()
            }
        }
    }

    /// Tự tải và phát chương tiếp theo mà không cần ReaderView làm trung gian.
    /// Nội dung chương kế tiếp luôn đi qua ChapterContentRepository local-first.
    /// Sau khi bắt đầu phát, post notification để ReaderView sync UI nếu đang visible.
    private func nextChapterIndex(after index: Int) -> Int? {
        chaptersQueue
            .map(\.index)
            .filter { $0 > index }
            .min()
    }

    private func advanceToNextChapter(nextIdx: Int) {
        guard let nextChapter = chaptersQueue.first(where: { $0.index == nextIdx }) else { return }
        let expectedSessionID = sessionID
        let expectedBookId = playingBookId
        let expectedChapterURL = nextChapter.url
        let request = ChapterContentRequest(
            bookId: expectedBookId,
            chapterIndex: nextChapter.index,
            title: nextChapter.title,
            url: nextChapter.url,
            host: nextChapter.host,
            bookMetadata: nil,
            extensionInfo: extensionInfo,
            forceRefresh: false
        )

        Task { [weak self] in
            do {
                let result = try await ChapterContentRepository.shared.load(request)
                guard let self,
                      self.isPlaying,
                      self.sessionID == expectedSessionID,
                      self.playingBookId == expectedBookId,
                      self.chaptersQueue.first(where: { $0.index == nextChapter.index })?.url == expectedChapterURL,
                      self.playingChapterIndex < nextChapter.index else { return }
                let normalized = result.document.text.content
                let content = TranslateUtils.isTranslationEnabled
                    ? TranslateUtils.translateContent(normalized, bookId: expectedBookId)
                    : normalized
                self.applyNextChapter(index: nextChapter.index, content: content, chapter: nextChapter)
            } catch {
                guard let self,
                      self.sessionID == expectedSessionID,
                      self.playingBookId == expectedBookId else { return }
                AppLogger.shared.log("❌ [TTSManager] Không tải được chương \(nextIdx): \(error.localizedDescription)")
                self.stop()
                self.onChapterFinished?()
            }
        }
    }

    /// Apply nội dung chương mới đã tải xong, bắt đầu phát và notify ReaderView.
    private func applyNextChapter(index: Int, content: String, chapter: TTSChapterInfo) {
        checkpointProgress()
        self.playingChapterIndex = index
        self.playingChapterUrl = chapter.url
        self.chapterTitle = chapter.title
        self.normalizedChapterText = ChapterTextNormalizer.normalize(content)
        self.chapterContent = normalizedChapterText.content
        self.clearPrefetchCache()

        // Parse va phat tu dau chuong
        self.continueStartSpeaking(startParagraphIndex: -1)

        // Notify ReaderView để sync UI (chuyển tab, scroll) nếu đang visible
        NotificationCenter.default.post(
            name: NSNotification.Name("ttsDidAdvanceToNextChapter"),
            object: nil,
            userInfo: ["bookId": self.playingBookId, "chapterIndex": index]
        )
        self.triggerNextChapterPrefetch()
    }

    private func triggerNextChapterPrefetch() {
        guard let nextIdx = nextChapterIndex(after: playingChapterIndex),
              let nextChapter = chaptersQueue.first(where: { $0.index == nextIdx }) else { return }
        nextChapterPrefetchTask?.cancel()

        let expectedSessionID = sessionID
        let expectedBookId = playingBookId
        let expectedChapterURL = nextChapter.url
        let request = ChapterContentRequest(
            bookId: expectedBookId,
            chapterIndex: nextChapter.index,
            title: nextChapter.title,
            url: nextChapter.url,
            host: nextChapter.host,
            bookMetadata: nil,
            extensionInfo: extensionInfo,
            forceRefresh: false
        )

        nextChapterPrefetchTask = Task {
            do {
                _ = try await ChapterContentRepository.shared.load(request)
                guard !Task.isCancelled,
                      sessionID == expectedSessionID,
                      playingBookId == expectedBookId,
                      chaptersQueue.first(where: { $0.index == nextChapter.index })?.url == expectedChapterURL else { return }
            } catch {
                #if DEBUG
                AppLogger.shared.log("[TTSManager] Prefetch next online chapter \(nextIdx) failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // speakCurrent: Bắt đầu phát âm thanh của đoạn văn bản hiện tại (index = currentParagraphIndex)
    private func speakCurrent() {
        // let pid = currentPlaybackId ?? "NONE"
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(pid)] speakCurrent() được gọi. index=\(currentParagraphIndex)")

        // Đảm bảo trạng thái đang phát hợp lệ và index nằm trong phạm vi của mảng paragraphs
        guard isPlaying, currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count else { return }

        let paragraph = paragraphs[currentParagraphIndex]
        self.highlightRange = paragraph.range // Cập nhật vùng bôi đen chữ đang đọc trên giao diện đọc truyện
        self.currentParentParagraphIndex = paragraph.paragraphIndex

        recordProgressInMemory()

        // Áp dụng các quy tắc thay thế ký tự trước khi đọc
        let textToSpeak = TTSReplacementManager.shared.applyReplacements(to: paragraph.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSpeak.isEmpty else {
            nextParagraph()
            return
        }

        // Điều hướng luồng phát âm thanh sang Engine tương ứng:
        if tool == "system" {
            playSystemTTS(textToSpeak) // Phát bằng Siri mặc định của iOS (không tốn dung lượng bộ nhớ)
        } else if tool == "nghitts" {
            playNghiTTS(textToSpeak) // Phát bằng Piper TTS offline (giọng đọc chất lượng cao tự nhiên hơn)
        } else if tool == "google" {
            playGoogleTTS(textToSpeak) // Phát bằng giọng đọc của Chị Google trực tuyến
        } else {
            playExtensionTTS(textToSpeak) // Phát thông qua Extension JavaScript tự định nghĩa
        }
    }

    private func playSystemTTS(_ text: String) {
        siriService.speak(text: text, voiceName: selectedVoice, speed: speed, pitch: pitch) { [weak self] in
            guard let self = self, self.isPlaying else { return }
            self.nextParagraph()
        }
        updateNowPlayingInfo()
    }

    private func clearPrefetchCache() {
        nextChapterPrefetchTask?.cancel()
        nextChapterPrefetchTask = nil

        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
        preloadedWavs.removeAll()
        // AppLogger.shared.log("🔊 [TTSManager] Đã làm sạch bộ đệm prefetch và hủy các task đang chạy nền.")
    }

    // updatePrefetchWindow: Cập nhật cửa sổ trượt (Sliding Window) tải trước dữ liệu âm thanh
    // Mục tiêu: Luôn có sẵn âm thanh PCMBuffer của đoạn tiếp theo (N+1) trong bộ đệm để phát ngay khi đoạn hiện tại (N) kết thúc, triệt tiêu hoàn toàn khoảng trễ tổng hợp âm thanh.
    private func updatePrefetchWindow() {
        // Chỉ hỗ trợ tải trước đối với NghiTTS hoặc Extension TTS (Siri hệ thống không hỗ trợ cache PCMBuffer)
        guard isPlaying, tool != "system" else { return }

        let N = currentParagraphIndex
        let targetIndices = [N + 1].filter { $0 >= 0 && $0 < paragraphs.count } // Cửa sổ đích cần tải trước là đoạn N+1

        // Bước 1: Hủy các tiến trình tải trước cũ không còn nằm trong cửa sổ mục tiêu (tránh lãng phí CPU/mạng khi người dùng bấm Skip liên tục)
        var tasksToCancel: [Int] = []
        for idx in prefetchTasks.keys {
            if !targetIndices.contains(idx) {
                tasksToCancel.append(idx)
            }
        }
        for idx in tasksToCancel {
            prefetchTasks[idx]?.cancel()
            prefetchTasks.removeValue(forKey: idx)
        }

        // Bước 2: Giải phóng bộ nhớ đệm (cache) của các đoạn cũ đã đọc xong. 
        // Chỉ giữ lại PCMBuffer của đoạn hiện tại (N) và đoạn kế tiếp (N+1).
        let cacheKeepIndices = [N, N + 1]
        var cacheToClear: [Int] = []
        for idx in preloadedWavs.keys {
            if !cacheKeepIndices.contains(idx) {
                cacheToClear.append(idx)
            }
        }
        for idx in cacheToClear {
            preloadedWavs.removeValue(forKey: idx)
        }

        // Bước 3: Kích hoạt tiến trình tải trước cho đoạn tiếp theo (N+1) nếu chưa có sẵn trong bộ nhớ đệm và chưa chạy task tải
        for idx in targetIndices {
            if preloadedWavs[idx] == nil && prefetchTasks[idx] == nil {
                startPrefetchTask(for: idx)
            }
        }
    }


    private func startPrefetchTask(for index: Int) {
        guard index >= 0 && index < paragraphs.count else { return }
        let rawText = paragraphs[index].text
        let text = TTSReplacementManager.shared.applyReplacements(to: rawText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let voice = selectedVoice
        let toolBeforeStart = tool
        let expectedSessionID = sessionID
        let expectedBookId = playingBookId
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl

        if tool == "google" {
            let task = Task { [weak self] in
                guard let self = self, let player = self.playerNode else { return }
                let targetFormat = player.outputFormat(forBus: 0)

                do {
                    let mp3Data = try await self.googleService.synthesize(text: text)

                    if !Task.isCancelled,
                       self.sessionID == expectedSessionID,
                       self.playingBookId == expectedBookId,
                       self.playingChapterIndex == expectedChapterIndex,
                       self.playingChapterUrl == expectedChapterURL,
                       self.tool == toolBeforeStart {
                        if let buffer = self.makePCMBuffer(fromMp3Data: mp3Data, targetFormat: targetFormat) {
                            self.preloadedWavs[index] = buffer
                        }
                    }
                    if self.sessionID == expectedSessionID {
                        self.prefetchTasks.removeValue(forKey: index)
                    }
                } catch {
                    if self.sessionID == expectedSessionID {
                        self.prefetchTasks.removeValue(forKey: index)
                    }
                }
            }
            prefetchTasks[index] = task
        } else if tool == "nghitts" {
            guard let service = nghiTTSService else { return }

            let task = Task { [weak self] in
                guard let self = self, let player = self.playerNode else { return }
                let targetFormat = player.outputFormat(forBus: 0)

                do {
                    // AppLogger.shared.log("🔊 [TTSManager] Bắt đầu tải trước cho đoạn \(index)...")
                    let wavData = try await service.synthesize(text: text, voice: voice, speed: 1.0)

                    if !Task.isCancelled,
                       self.sessionID == expectedSessionID,
                       self.playingBookId == expectedBookId,
                       self.playingChapterIndex == expectedChapterIndex,
                       self.playingChapterUrl == expectedChapterURL,
                       self.selectedVoice == voice,
                       self.tool == toolBeforeStart {
                        if let buffer = self.makePCMBuffer(fromWavData: wavData, targetFormat: targetFormat) {
                            self.preloadedWavs[index] = buffer
                            // AppLogger.shared.log("🔊 [TTSManager] Đã tải trước và lưu cache PCMBuffer thành công cho đoạn \(index).")
                        } else {
                            AppLogger.shared.log("❌ [TTSManager] Lỗi chuyển đổi WAV sang PCMBuffer cho đoạn \(index).")
                        }
                    }
                    if self.sessionID == expectedSessionID {
                        self.prefetchTasks.removeValue(forKey: index)
                    }
                } catch {
                    if self.sessionID == expectedSessionID {
                        self.prefetchTasks.removeValue(forKey: index)
                    }
                    // AppLogger.shared.log("🔊 [TTSManager] Tải trước thất bại cho đoạn \(index): \(error.localizedDescription)")
                }
            }
            prefetchTasks[index] = task
        } else {
            // Extension TTS
            let localPath = extensionLocalPath
            let configJson = extensionConfigJson

            let task = Task { [weak self] in
                guard let self = self, let player = self.playerNode else { return }
                let targetFormat = player.outputFormat(forBus: 0)

                do {
                    // AppLogger.shared.log("🔊 [TTSManager] Bắt đầu tải trước (extension tts) cho đoạn \(index)...")
                    let buffer = try await self.extService.synthesize(text: text, voice: voice, localPath: localPath, configJson: configJson, targetFormat: targetFormat)

                    if !Task.isCancelled,
                       self.sessionID == expectedSessionID,
                       self.playingBookId == expectedBookId,
                       self.playingChapterIndex == expectedChapterIndex,
                       self.playingChapterUrl == expectedChapterURL,
                       self.selectedVoice == voice,
                       self.tool == toolBeforeStart {
                        self.preloadedWavs[index] = buffer
                        // AppLogger.shared.log("🔊 [TTSManager] Đã tải trước và lưu cache PCMBuffer thành công (extension tts) cho đoạn \(index).")
                    }
                    if self.sessionID == expectedSessionID {
                        self.prefetchTasks.removeValue(forKey: index)
                    }
                } catch {
                    if self.sessionID == expectedSessionID {
                        self.prefetchTasks.removeValue(forKey: index)
                    }
                    // AppLogger.shared.log("🔊 [TTSManager] Tải trước thất bại (extension tts) cho đoạn \(index): \(error.localizedDescription)")
                }
            }
            prefetchTasks[index] = task
        }
    }

    private func playGoogleTTS(_ text: String) {
        let index = currentParagraphIndex
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        updatePrefetchWindow()

        if let cachedBuffer = preloadedWavs[index] {
            self.playAudioBuffer(cachedBuffer, withId: playbackId)
            return
        }

        Task {
            do {
                let buffer: AVAudioPCMBuffer
                guard let player = self.playerNode else { return }
                let targetFormat = player.outputFormat(forBus: 0)

                if let activeTask = prefetchTasks[index] {
                    _ = await activeTask.value
                    if let cached = preloadedWavs[index] {
                        buffer = cached
                    } else {
                        let mp3Data = try await googleService.synthesize(text: text)
                        guard let b = self.makePCMBuffer(fromMp3Data: mp3Data, targetFormat: targetFormat) else {
                            throw NSError(domain: "TTSManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "MP3 conversion failed"])
                        }
                        buffer = b
                    }
                } else {
                    let mp3Data = try await googleService.synthesize(text: text)
                    guard let b = self.makePCMBuffer(fromMp3Data: mp3Data, targetFormat: targetFormat) else {
                        throw NSError(domain: "TTSManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "MP3 conversion failed"])
                    }
                    buffer = b
                }

                guard self.isPlaying && self.currentPlaybackId == playbackId else {
                    return
                }

                await MainActor.run {
                    self.playAudioBuffer(buffer, withId: playbackId)
                }
            } catch {
                await MainActor.run {
                    AppLogger.shared.log("❌ Lỗi Google TTS: \(error.localizedDescription)")
                    self.nextParagraph()
                }
            }
        }
    }

    private func playNghiTTS(_ text: String) {
        guard let service = nghiTTSService else {
            AppLogger.shared.log("NghiTTS engine not initialized.")
            stop()
            return
        }

        let index = currentParagraphIndex
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        // Cập nhật cửa sổ prefetch gối đầu ngay khi bắt đầu phát đoạn mới
        updatePrefetchWindow()

        // Kiểm tra xem dữ liệu của đoạn index hiện tại đã có sẵn trong cache chưa
        if let cachedBuffer = preloadedWavs[index] {
            // AppLogger.shared.log("🔊 [TTSManager] Phát hiện cache PCMBuffer cho đoạn \(index), phát lập tức.")
            self.playAudioBuffer(cachedBuffer, withId: playbackId)
            return
        }

        Task {
            do {
                let buffer: AVAudioPCMBuffer
                guard let player = self.playerNode else { return }
                let targetFormat = player.outputFormat(forBus: 0)

                if let activeTask = prefetchTasks[index] {
                    // Chờ task đang chạy hoàn thành
                    _ = await activeTask.value
                    if let cached = preloadedWavs[index] {
                        buffer = cached
                    } else {
                        // Nếu chờ task prefetch bị hủy hoặc lỗi, ta chạy tự tổng hợp lại
                        let wavData = try await service.synthesize(text: text, voice: selectedVoice, speed: 1.0)
                        guard let b = self.makePCMBuffer(fromWavData: wavData, targetFormat: targetFormat) else {
                            throw NSError(domain: "TTSManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "WAV conversion failed"])
                        }
                        buffer = b
                    }
                } else {
                    let wavData = try await service.synthesize(text: text, voice: selectedVoice, speed: 1.0)
                    guard let b = self.makePCMBuffer(fromWavData: wavData, targetFormat: targetFormat) else {
                        throw NSError(domain: "TTSManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "WAV conversion failed"])
                    }
                    buffer = b
                }

                guard self.isPlaying && self.currentPlaybackId == playbackId else {
                    return
                }

                await MainActor.run {
                    self.playAudioBuffer(buffer, withId: playbackId)
                }
            } catch {
                await MainActor.run {
                    guard self.currentPlaybackId == playbackId else { return }
                    AppLogger.shared.log("🔊 [TTSManager] Chơi trực tiếp thất bại cho đoạn \(index): \(error.localizedDescription)")
                    self.stop()
                }
            }
        }
    }

    private func playExtensionTTS(_ text: String) {
        let index = currentParagraphIndex
        let voice = selectedVoice
        let localPath = extensionLocalPath
        let configJson = extensionConfigJson
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        // Cập nhật cửa sổ prefetch gối đầu ngay khi bắt đầu phát đoạn mới
        updatePrefetchWindow()

        // Kiểm tra xem dữ liệu của đoạn index hiện tại đã có sẵn trong cache chưa
        if let cachedBuffer = preloadedWavs[index] {
            // AppLogger.shared.log("🔊 [TTSManager] Phát hiện cache PCMBuffer cho đoạn \(index) từ extension tts, phát lập tức.")
            self.playAudioBuffer(cachedBuffer, withId: playbackId)
            return
        }

        Task {
            do {
                let buffer: AVAudioPCMBuffer
                guard let player = self.playerNode else { return }
                let targetFormat = player.outputFormat(forBus: 0)

                if let activeTask = prefetchTasks[index] {
                    // Chờ task đang chạy hoàn thành
                    _ = await activeTask.value
                    if let cached = preloadedWavs[index] {
                        buffer = cached
                    } else {
                        buffer = try await extService.synthesize(text: text, voice: voice, localPath: localPath, configJson: configJson, targetFormat: targetFormat)
                    }
                } else {
                    buffer = try await extService.synthesize(text: text, voice: voice, localPath: localPath, configJson: configJson, targetFormat: targetFormat)
                }

                guard self.isPlaying && self.currentPlaybackId == playbackId else {
                    return
                }

                await MainActor.run {
                    self.playAudioBuffer(buffer, withId: playbackId)
                }
            } catch {
                await MainActor.run {
                    guard self.currentPlaybackId == playbackId else { return }
                    AppLogger.shared.log("🔊 [TTSManager] Chơi trực tiếp extension tts thất bại cho đoạn \(index): \(error.localizedDescription)")
                    self.pause()
                }
            }
        }
    }

    private func playAudioBuffer(_ buffer: AVAudioPCMBuffer, withId customId: String? = nil) {
        let playbackId = customId ?? String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bắt đầu playAudioBuffer, paragraphIndex: \(paragraphIndex)")
        guard let engine = audioEngine, let player = playerNode, let pitchNode = timePitchNode else {
            AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] LỖI: Các thành phần AVAudioEngine chưa được khởi tạo.")
            return
        }

        cleanUpTempFile()

        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.stop()...")
        player.stop()
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.stop() xong.")

        // Chỉ ngắt và kết nối lại nếu format thay đổi để tránh tiếng nổ/rè (pop/click) do re-sync codec
        if lastBufferFormat == nil || lastBufferFormat != buffer.format {
            AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Định dạng buffer thay đổi (\(lastBufferFormat?.description ?? "nil") -> \(buffer.format.description)). Rebuilding node graph connections...")

            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(pitchNode)

            engine.connect(player, to: pitchNode, format: buffer.format)
            engine.connect(pitchNode, to: engine.mainMixerNode, format: buffer.format)

            lastBufferFormat = buffer.format
        }

        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bắt đầu chạy Audio Engine nếu chưa chạy...")
        if !engine.isRunning {
            do {
                try engine.start()
                // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Audio Engine đã khởi động thành công.")
            } catch {
                AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] LỖI: Không thể khởi động Audio Engine: \(error.localizedDescription)")
                return
            }
        }

        pitchNode.rate = Float(speed)
        let cents = 1200.0 * log2(pitch)
        pitchNode.pitch = Float(cents)

        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Đang lập lịch phát buffer âm thanh (scheduleBuffer)... t=\(startTime)")
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
            // let completionTime = CACurrentMediaTime()
            // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] scheduleBuffer completion callback: paragraph=\(paragraphIndex) t=\(completionTime)")

            DispatchQueue.main.async {
                guard let self = self, self.isPlaying else { return }
                guard self.currentPlaybackId == playbackId else {
                    // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Bỏ qua callback kết thúc vì currentPlaybackId (\(self.currentPlaybackId ?? "nil")) đã thay đổi.")
                    return
                }
                self.cleanUpTempFile()
                self.nextParagraph()
            }
        })

        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Gọi player.play()... t=\(CACurrentMediaTime())")
        player.play()
        updateNowPlayingInfo()
        // AppLogger.shared.log("🔊 [TTSManager] [ID=\(playbackId)] Phát buffer hoàn tất thiết lập.")
    }

    private func makePCMBuffer(fromWavData wavData: Data, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard wavData.count >= 44 else { return nil }

        let srcChannels = Int(wavData[22]) | (Int(wavData[23]) << 8)
        let srcSampleRate = Double(Int(wavData[24]) | (Int(wavData[25]) << 8) | (Int(wavData[26]) << 16) | (Int(wavData[27]) << 24))
        let payloadSize = Int(wavData[40]) | (Int(wavData[41]) << 8) | (Int(wavData[42]) << 16) | (Int(wavData[43]) << 24)

        guard wavData.count >= 44 + payloadSize else { return nil }

        let srcSampleCount = payloadSize / 2

        // 1. Tạo định dạng nguồn Float32 standard non-interleaved
        guard let srcFormat = AVAudioFormat(standardFormatWithSampleRate: srcSampleRate, channels: AVAudioChannelCount(srcChannels)) else {
            return nil
        }

        let srcFrameCount = AVAudioFrameCount(srcSampleCount / srcChannels)
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: srcFrameCount) else {
            return nil
        }
        srcBuffer.frameLength = srcFrameCount

        // 2. Chuyển đổi Int16 sang Float32 nạp vào srcBuffer
        wavData.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                let srcPointer = baseAddress.advanced(by: 44).assumingMemoryBound(to: Int16.self)
                if let floatChannelData = srcBuffer.floatChannelData {
                    for channel in 0..<srcChannels {
                        let destPointer = floatChannelData[channel]
                        for frame in 0..<Int(srcFrameCount) {
                            let srcIndex = frame * srcChannels + channel
                            if srcIndex < srcSampleCount {
                                let intVal = srcPointer[srcIndex]
                                destPointer[frame] = Float(intVal) / (intVal < 0 ? 32768.0 : 32767.0)
                            } else {
                                destPointer[frame] = 0.0
                            }
                        }
                    }
                }
            }
        }

        // Nếu trùng định dạng, trả về luôn srcBuffer
        if srcFormat == targetFormat {
            return srcBuffer
        }

        // 3. Sử dụng AVAudioConverter chuyển đổi chất lượng cao (resampling + channel mapping)
        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
            AppLogger.shared.log("❌ [TTSManager] Không thể tạo AVAudioConverter từ \(srcFormat) sang \(targetFormat)")
            return nil
        }

        let ratio = targetFormat.sampleRate / srcSampleRate
        let targetFrameCapacity = AVAudioFrameCount(Double(srcFrameCount) * ratio) + 16

        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCapacity) else {
            return nil
        }

        var error: NSError? = nil
        var isDataProvided = false
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if isDataProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            isDataProvided = true
            outStatus.pointee = .haveData
            return srcBuffer
        }

        let status = converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)
        if status == .error {
            if let error = error {
                AppLogger.shared.log("❌ [TTSManager] Lỗi convert định dạng buffer: \(error.localizedDescription)")
            }
            return nil
        }

        return targetBuffer
    }

    private func makePCMBuffer(fromMp3Data mp3Data: Data, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("google_tts_temp.mp3")
        do {
            try mp3Data.write(to: tempURL, options: .atomic)
            let audioFile = try AVAudioFile(forReading: tempURL)
            let srcFormat = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
                return nil
            }
            try audioFile.read(into: srcBuffer)
            
            try? FileManager.default.removeItem(at: tempURL)
            
            if srcFormat == targetFormat {
                return srcBuffer
            }
            
            guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
                return nil
            }
            
            let ratio = targetFormat.sampleRate / srcFormat.sampleRate
            let destFrameCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio) + 100
            guard let destBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: destFrameCapacity) else {
                return nil
            }
            
            var error: NSError? = nil
            var isDataProvided = false
            let status = converter.convert(to: destBuffer, error: &error) { inNumPackets, outStatus in
                if isDataProvided {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                isDataProvided = true
                outStatus.pointee = .haveData
                return srcBuffer
            }
            
            if status == .error || error != nil {
                AppLogger.shared.log("❌ Resampling MP3 failed: \(error?.localizedDescription ?? "unknown error")")
                return nil
            }
            
            return destBuffer
        } catch {
            AppLogger.shared.log("❌ Failed to convert MP3 to PCMBuffer: \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanUpTempFile() {
        // File tạm được dọn dẹp trực tiếp trong ExtTTSService.synthesize
    }

    // MARK: - Text Segmentation (Phân đoạn văn bản)

    // MARK: - Lock Screen & Remote Control Sync

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = enabled
        commandCenter.pauseCommand.isEnabled = enabled
        // iOS maps the headset play/pause button to one of the explicit
        // commands from playbackState. Enabling toggle as well can dispatch a
        // second event for the same press on some Bluetooth devices.
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = enabled
        commandCenter.previousTrackCommand.isEnabled = enabled

        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false

        if enabled {
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } else {
            UIApplication.shared.endReceivingRemoteControlEvents()
        }
    }

    private func syncRemoteCommandState() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let active = !playingBookId.isEmpty && showFloatingWidget
        commandCenter.playCommand.isEnabled = active && !isPlaying
        commandCenter.pauseCommand.isEnabled = active && isPlaying
        commandCenter.togglePlayPauseCommand.isEnabled = false
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            DispatchQueue.main.async { [weak self] in
                self?.resume()
            }
            return .success
        }

        // Pause
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            DispatchQueue.main.async { [weak self] in
                self?.pause()
            }
            return .success
        }

        // Next Track (Đoạn sau)
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.skipForward()
            }
            return .success
        }

        // Prev Track (Đoạn trước)
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.skipBackward()
            }
            return .success
        }

        // Mặc định ban đầu vô hiệu hóa các remote commands cho đến khi bắt đầu phát thực sự
        self.setRemoteCommandsEnabled(false)
    }

    private func updateNowPlayingInfo() {
        nowPlayingUpdateGeneration &+= 1
        let updateGeneration = nowPlayingUpdateGeneration
        let bid = playingBookId
        let bTitle = bookTitle
        let cTitle = chapterTitle
        let isTransEnabled = TranslateUtils.isTranslationEnabled
        let pIndex = currentParagraphIndex
        let pCount = paragraphs.count
        let isPlayingVal = isPlaying
        let speedVal = speed
        let coverUrlVal = playingCoverUrl

        Task {
            let (displayBookTitle, displayChapterTitle, image) = await Task.detached(priority: .background) {
                let displayBookTitle: String
                let displayChapterTitle: String

                if isTransEnabled {
                    displayBookTitle = TranslateUtils.containsChinese(bTitle)
                        ? TranslateUtils.translateMeta(bTitle, bookId: bid)
                        : bTitle

                    let rawChapterTitle = cTitle.isEmpty ? "Chương hiện tại" : cTitle
                    displayChapterTitle = TranslateUtils.containsChinese(rawChapterTitle)
                        ? TranslateUtils.translateChapterTitle(rawChapterTitle, bookId: bid)
                        : rawChapterTitle
                } else {
                    displayBookTitle = bTitle
                    displayChapterTitle = cTitle.isEmpty ? "Chương hiện tại" : cTitle
                }

                let img = ImageCacheManager.shared.loadLocalCover(for: bid)
                return (displayBookTitle, displayChapterTitle, img)
            }.value

            guard updateGeneration == self.nowPlayingUpdateGeneration,
                  self.playingBookId == bid else { return }

            var info: [String: Any] = [:]
            info[MPMediaItemPropertyTitle] = displayBookTitle

            let currentPart = pCount == 0 ? "" : " (Đoạn \(pIndex + 1)/\(pCount))"
            info[MPMediaItemPropertyArtist] = displayChapterTitle + currentPart

            info[MPNowPlayingInfoPropertyIsLiveStream] = true
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlayingVal ? speedVal : 0.0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(max(0, pIndex))

            if let img = image {
                let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in
                    return img
                }
                info[MPMediaItemPropertyArtwork] = artwork
            } else if !coverUrlVal.isEmpty {
                ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverUrlVal, bookId: bid) { [weak self] image in
                    guard image != nil else { return }
                    DispatchQueue.main.async {
                        guard let self = self,
                              self.playingBookId == bid,
                              self.showFloatingWidget else { return }
                        self.updateNowPlayingInfo()
                    }
                }
            }

            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = isPlayingVal ? .playing : .paused
        }
    }

    // MARK: - NghiTTS Downloader Wrapper

    public func downloadNghiTTSModel(voice: Voice) async {
        guard let client = nghiTTSClient else { return }
        downloadingVoices[voice.name] = 0.0
        downloadingMessages[voice.name] = "Bắt đầu tải..."

        do {
            _ = try await client.prefetchModels(voices: [voice.name]) { [weak self] msg, progress in
                DispatchQueue.main.async {
                    self?.downloadingVoices[voice.name] = progress
                    self?.downloadingMessages[voice.name] = msg
                }
            }
            DispatchQueue.main.async {
                self.downloadingVoices.removeValue(forKey: voice.name)
                self.downloadingMessages.removeValue(forKey: voice.name)
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadingVoices.removeValue(forKey: voice.name)
                self.downloadingMessages.removeValue(forKey: voice.name)
                AppLogger.shared.log("Lỗi tải model NghiTTS \(voice.name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Audio Session & Engine Notification Handling

    private func setupInterruptionObserver() {
        // 1. Audio Session Interruption (cuộc gọi, Siri, ứng dụng khác chiếm audio)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleInterruption(notification: notification)
            }
            .store(in: &cancellables)

        // 2. Route Change (rút/cắm tai nghe, bật/tắt Bluetooth, đổi thiết bị phát)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleRouteChange(notification: notification)
            }
            .store(in: &cancellables)

        // 3. Media Services Reset (media daemon crash, thiết bị hết bộ nhớ)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.handleMediaServicesReset()
            }
            .store(in: &cancellables)

        // 4. Engine Configuration Change (hardware sample rate/channel thay đổi)
        if let engine = audioEngine {
            NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.handleEngineConfigChange()
                }
                .store(in: &cancellables)
        }
    }

    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            AppLogger.shared.log("🔊 [TTSManager] Audio session interruption began. isPlaying = \(self.isPlaying)")
            if isPlaying {
                self.wasPlayingBeforeInterruption = true
                self.pause()
            }
        case .ended:
            AppLogger.shared.log("🔊 [TTSManager] Audio session interruption ended. wasPlayingBeforeInterruption = \(self.wasPlayingBeforeInterruption)")

            // Đối với ứng dụng đọc truyện, luôn khôi phục nếu trước đó đang đọc
            if self.wasPlayingBeforeInterruption {
                self.wasPlayingBeforeInterruption = false

                // Trì hoãn một chút để hệ thống nhả hoàn toàn Audio Session
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    if !self.isPlaying {
                        AppLogger.shared.log("🔊 [TTSManager] Resuming TTS playback after interruption.")
                        self.resume()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        AppLogger.shared.log("🔊 [TTSManager] Route change: reason=\(reason.rawValue)")

        switch reason {
        case .oldDeviceUnavailable:
            // Thiết bị phát cũ bị ngắt (rút tai nghe, tắt Bluetooth)
            // AVAudioEngine tự dừng khi route thay đổi, cần restart
            if isPlaying {
                AppLogger.shared.log("🔊 [TTSManager] Old device unavailable. Reconfiguring and restarting current paragraph.")
                let currentIdx = currentParagraphIndex

                // Dừng playback hiện tại
                stopCurrentPlayback()

                // Reconfigure audio session cho thiết bị mới
                configureAudioSession()

                // Phát lại đoạn hiện tại
                currentParagraphIndex = currentIdx
                speakCurrent()
            }

        case .newDeviceAvailable:
            // Thiết bị phát mới được kết nối (cắm tai nghe, bật Bluetooth)
            // AVAudioEngine sẽ tự động chuyển đổi, chỉ cần đảm bảo session đúng
            if isPlaying {
                configureAudioSession()
            }

        default:
            break
        }
    }

    private func handleMediaServicesReset() {
        // Media services bị reset: tất cả AVAudioEngine/PlayerNode đều trở thành invalid
        AppLogger.shared.log("🔊 [TTSManager] Media services were reset. Rebuilding audio engine.")
        let wasPlaying = isPlaying
        let currentIdx = currentParagraphIndex

        // Tạo mới hoàn toàn engine, player, pitchNode
        setupAudioEngine()

        // Đăng ký lại engine configuration change observer cho engine mới
        if let engine = audioEngine {
            NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.handleEngineConfigChange()
                }
                .store(in: &cancellables)
        }

        // Khôi phục playback nếu trước đó đang phát
        if wasPlaying && currentIdx >= 0 && currentIdx < paragraphs.count {
            configureAudioSession()
            self.isPlaying = true
            speakCurrent()
        }
    }

    private func handleEngineConfigChange() {
        // Hardware configuration thay đổi (sample rate, channel count)
        // Engine tự dừng, cần restart
        AppLogger.shared.log("🔊 [TTSManager] Engine configuration changed.")

        guard isPlaying else { return }
        let currentIdx = currentParagraphIndex

        stopCurrentPlayback()
        configureAudioSession()

        // Phát lại đoạn hiện tại
        currentParagraphIndex = currentIdx
        speakCurrent()
    }
}

