import Foundation
import AVFoundation
import MediaPlayer
import Combine
import QuartzCore
import UIKit
import SwiftData

private struct TTSPreparedChapterKey: Equatable, Sendable {
    let bookId: String
    let chapterIndex: Int
    let chapterTitle: String
    let content: String
    let chunkLength: Int
    let includeChapterTitle: Bool
}

private struct TTSPreparedChapter: Sendable {
    let normalizedContent: String
    let paragraphs: [TTSParagraph]
}

@available(iOS 17.0, *)
private actor TTSChapterQueueMetadataWorker {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchLocalQueue(bookId: String) async -> [TTSChapterInfo] {
        if let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId), !storeChaps.isEmpty {
            return storeChaps.map {
                TTSChapterInfo(title: $0.title, url: $0.url, index: $0.index, host: $0.host)
            }
        }
        return []
    }
}



@MainActor
public final class TTSManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = TTSManager()

    // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
    private var remoteTraceSequenceCount = 0

    // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
    private func logRemoteTrace(_ event: String, details: String = "") {
        remoteTraceSequenceCount += 1
        let thread = Thread.isMainThread ? "Main" : "Bg"
        let session = AVAudioSession.sharedInstance()
        let sessionCat = session.category.rawValue
        let sessionMode = session.mode.rawValue
        let sessionOpts = session.categoryOptions.rawValue
        let rate = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1.0
        let state = MPNowPlayingInfoCenter.default().playbackState.rawValue
        let pNode = playerNode?.isPlaying == true ? "playing" : "stopped"
        let aEngine = audioEngine?.isRunning == true ? "running" : "stopped"
        let siriP = siriService.isPaused
        let siriS = siriService.isSpeaking
        let cmdCenter = MPRemoteCommandCenter.shared()
        let playE = cmdCenter.playCommand.isEnabled
        let pauseE = cmdCenter.pauseCommand.isEnabled
        let toggleE = cmdCenter.togglePlayPauseCommand.isEnabled

        AppLogger.shared.log("🔍 [TTSTrace #\(remoteTraceSequenceCount)] \(event) | Thread:\(thread) | playing:\(isPlaying) | widget:\(showFloatingWidget) | bookId:\(playingBookId.isEmpty ? "empty" : "set") | tool:\(tool) | rate:\(rate) | state:\(state) | pNode:\(pNode) | aEngine:\(aEngine) | siriP:\(siriP) | siriS:\(siriS) | playE:\(playE) | pauseE:\(pauseE) | toggleE:\(toggleE) | session:\(sessionCat)/\(sessionMode)/\(sessionOpts) | \(details)")
    }

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
            } else if tool == "google" {
                UserDefaults.standard.set(speed, forKey: "googleRate")
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
            } else if tool == "google" {
                UserDefaults.standard.set(pitch, forKey: "googlePitch")
            } else {
                UserDefaults.standard.set(pitch, forKey: "extPitch_\(tool)")
            }
            updatePlaybackParams()
        }
    }
    @Published public var selectedVoice: String {
        didSet {
            if tool == "system" {
                UserDefaults.standard.set(selectedVoice, forKey: "systemVoice")
            } else if tool == "nghitts" {
                UserDefaults.standard.set(selectedVoice, forKey: "nghittsVoice")
            } else if tool == "google" {
                UserDefaults.standard.set(selectedVoice, forKey: "googleVoice")
            } else {
                UserDefaults.standard.set(selectedVoice, forKey: "extVoice_\(tool)")
            }
            clearPrefetchCache()
        }
    }
    private var isInitializing = true

    @Published public var chunkLength: Int {
        didSet {
            guard !isInitializing else { return }
            UserDefaults.standard.set(chunkLength, forKey: "ttsChunkLength")
            if tool == "system" {
                UserDefaults.standard.set(chunkLength, forKey: "systemChunk")
            } else if tool == "nghitts" {
                UserDefaults.standard.set(chunkLength, forKey: "nghittsChunk")
            } else if tool == "google" {
                UserDefaults.standard.set(chunkLength, forKey: "googleChunk")
            } else {
                UserDefaults.standard.set(chunkLength, forKey: "extChunkUser_\(tool)")
            }
        }
    }

    @Published public var extensionLocalPath: String {
        didSet { UserDefaults.standard.set(extensionLocalPath, forKey: "ttsExtensionLocalPath") }
    }
    @Published public var extensionConfigJson: String {
        didSet {
            UserDefaults.standard.set(extensionConfigJson, forKey: "ttsExtensionConfigJson")
            if tool != "system" && tool != "nghitts" && tool != "google" {
                loadParamsForCurrentTool()
            }
        }
    }

    @Published public var googlePrefetchCount: Int {
        didSet {
            guard !isInitializing else { return }
            UserDefaults.standard.set(googlePrefetchCount, forKey: "googlePrefetchCount")
            if tool == "google" { clearPrefetchCache() }
        }
    }

    @Published public var nghittsPrefetchCount: Int {
        didSet {
            guard !isInitializing else { return }
            UserDefaults.standard.set(nghittsPrefetchCount, forKey: "nghittsPrefetchCount")
            if tool == "nghitts" { clearPrefetchCache() }
        }
    }

    @Published public var extPrefetchCount: Int {
        didSet {
            guard !isInitializing else { return }
            if tool != "system" && tool != "nghitts" && tool != "google" {
                UserDefaults.standard.set(extPrefetchCount, forKey: "extPrefetchUser_\(tool)")
                clearPrefetchCache()
            }
        }
    }

    @Published public var prefetchDelayMs: Int {
        didSet {
            guard !isInitializing else { return }
            let clampedValue = (tool == "google" || (tool != "system" && tool != "nghitts")) ? max(500, prefetchDelayMs) : prefetchDelayMs
            UserDefaults.standard.set(clampedValue, forKey: "ttsPrefetchDelayMs")
            if tool == "nghitts" {
                UserDefaults.standard.set(clampedValue, forKey: "nghittsPrefetchDelay")
            } else if tool == "google" {
                UserDefaults.standard.set(clampedValue, forKey: "googlePrefetchDelay")
            } else if tool != "system" {
                UserDefaults.standard.set(clampedValue, forKey: "extPrefetchDelay_\(tool)")
            }
        }
    }

    public var currentPrefetchCount: Int {
        if tool == "google" {
            return googlePrefetchCount
        } else if tool == "nghitts" {
            return nghittsPrefetchCount
        } else if tool == "system" {
            return 1
        } else {
            return extPrefetchCount
        }
    }

    public func parseExtensionConfigParams(jsonString: String) -> (preloadSize: Int?, maxLength: Int?) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        
        var pSize: Int? = nil
        var mLen: Int? = nil
        
        if let config = json["config"] as? [String: Any] {
            pSize = config["preload_size"] as? Int ?? (config["preload_size"] as? String).flatMap { Int($0) }
            mLen = config["max_length"] as? Int ?? (config["max_length"] as? String).flatMap { Int($0) }
        } else {
            pSize = json["preload_size"] as? Int ?? (json["preload_size"] as? String).flatMap { Int($0) }
            mLen = json["max_length"] as? Int ?? (json["max_length"] as? String).flatMap { Int($0) }
        }
        
        return (pSize, mLen)
    }

    // Trạng thái playback
    @Published public var isPlaying: Bool = false
    @Published public var currentParagraphIndex: Int = -1
    @Published public var currentParentParagraphIndex: Int = -1
    @Published public var highlightRange: NSRange? = nil
    @Published public var showFloatingWidget: Bool = false
    @Published public var showingSettingsSheet: Bool = false

    // Sleep Timer (Hẹn giờ tạm dừng đọc)
    public enum SleepTimerMode: Equatable {
        case off
        case minutes(Int)
        case endOfChapter

        public var title: String {
            switch self {
            case .off: return "Tắt"
            case .minutes(let m): return "\(m) phút"
            case .endOfChapter: return "Hết chương"
            }
        }
    }

    @Published public var timerMode: SleepTimerMode = .off
    @Published public var sleepTimerRemainingSeconds: Int = 0
    @Published public var isTimerRunning: Bool = false
    private var sleepTimerObj: Timer? = nil

    public var sleepTimerBadgeText: String {
        switch timerMode {
        case .off:
            return ""
        case .endOfChapter:
            return "📖 Hết chương"
        case .minutes(let m):
            if isTimerRunning && sleepTimerRemainingSeconds > 0 {
                let mins = sleepTimerRemainingSeconds / 60
                let secs = sleepTimerRemainingSeconds % 60
                if mins >= 60 {
                    let hrs = mins / 60
                    let remMins = mins % 60
                    return String(format: "⏱️ %dh%02dm", hrs, remMins)
                } else if mins > 0 {
                    return String(format: "⏱️ %dm%02ds", mins, secs)
                } else {
                    return String(format: "⏱️ %ds", secs)
                }
            } else {
                return "⏱️ \(m)m"
            }
        }
    }

    public func startSleepTimer(minutes: Int) {
        let clamped = max(1, minutes)
        self.timerMode = .minutes(clamped)
        self.startTimerCountdown(minutes: clamped)
        let msg = "Đã hẹn giờ: Tạm dừng đọc sau \(clamped) phút."
        ToastManager.shared.show(message: msg, type: .info)
    }

    public func setStopAtEndOfChapter() {
        self.timerMode = .endOfChapter
        self.stopTimerCountdown(keepMode: true)
        ToastManager.shared.show(message: "Đã hẹn giờ: Tạm dừng khi đọc hết chương hiện tại.", type: .info)
    }

    public func cancelSleepTimer() {
        self.timerMode = .off
        self.stopTimerCountdown(keepMode: false)
        ToastManager.shared.show(message: "Đã tắt hẹn giờ tạm dừng.", type: .info)
    }

    public func startTimerCountdown(minutes: Int) {
        stopTimerCountdown(keepMode: true)
        self.sleepTimerRemainingSeconds = minutes * 60
        self.isTimerRunning = true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sleepTimerObj = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.sleepTimerRemainingSeconds > 1 {
                        self.sleepTimerRemainingSeconds -= 1
                    } else {
                        self.sleepTimerRemainingSeconds = 0
                        self.onSleepTimerExpired()
                    }
                }
            }
        }
    }

    public func stopTimerCountdown(keepMode: Bool) {
        sleepTimerObj?.invalidate()
        sleepTimerObj = nil
        self.isTimerRunning = false
        if !keepMode {
            self.timerMode = .off
            self.sleepTimerRemainingSeconds = 0
        }
    }

    public func restartSleepTimerIfNeeded() {
        guard isPlaying else { return }
        switch timerMode {
        case .minutes(let m):
            if !isTimerRunning || sleepTimerRemainingSeconds <= 0 {
                startTimerCountdown(minutes: m)
            }
        case .endOfChapter, .off:
            break
        }
    }

    private func onSleepTimerExpired() {
        stopTimerCountdown(keepMode: true)
        pause()
        let label: String
        if case .minutes(let m) = timerMode {
            label = " (\(m) phút)"
        } else {
            label = ""
        }
        ToastManager.shared.show(message: "⏱️ Hẹn giờ\(label): Đã tự động tạm dừng đọc.", type: .info)
    }

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
    private var savedParagraphIdentityBeforeSettings: Int = -1
    private var wasPlayingBeforeInterruption = false
    private var lastPausedTime: Date? = nil
    private var cancellables = Set<AnyCancellable>()
    private var prepareSpeakingTask: Task<Void, Never>? = nil
    private var startSpeakingTask: Task<Void, Never>? = nil
    private var nextChapterPrefetchTask: Task<Void, Never>? = nil
    private var chapterQueueRefreshTask: Task<Void, Never>? = nil
    private var sessionID = UUID()
    private var ttsProcessingGeneration = 0
    private var preparationGeneration = 0
    private var preparedChapterKey: TTSPreparedChapterKey? = nil
    private var preparedChapter: TTSPreparedChapter? = nil
    // Now Playing updates include detached translation/cover work. A newer
    // playback state must invalidate older tasks so Lock Screen cannot revert
    // a just-resumed session back to paused (or vice versa).
    private var nowPlayingUpdateGeneration: UInt = 0

    // Cache lưu trữ dữ liệu âm thanh đã được tổng hợp trước cho các đoạn văn
    private var preloadedData: [Int: Data] = [:]
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]
    private var audioPlayer: AVAudioPlayer?

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
    private var modelContainer: ModelContainer?

    public func initialize(container: ModelContainer) {
        self.modelContainer = container
        Task {
            await ReadingProgressStore.shared.configure(container: container)
            await ChapterContentRepository.shared.configure(container: container)
        }
    }

    public func updateChaptersQueue(_ chapters: [TTSChapterInfo], for bookId: String) {
        guard playingBookId == bookId, !chapters.isEmpty else { return }
        chaptersQueue = chapters
        triggerNextChapterPrefetch()
    }

    public func refreshChaptersQueueInBackground(
        bookId: String,
        onlineChapters: [TTSChapterInfo]? = nil
    ) {
        chapterQueueRefreshTask?.cancel()

        let expectedSessionID = sessionID
        let container = modelContainer
        chapterQueueRefreshTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled,
                  self.sessionID == expectedSessionID,
                  self.playingBookId == bookId else { return }

            let refreshedQueue: [TTSChapterInfo]
            if let onlineChapters {
                refreshedQueue = onlineChapters
            } else if let container {
                let worker = TTSChapterQueueMetadataWorker(container: container)
                refreshedQueue = await worker.fetchLocalQueue(bookId: bookId)
            } else {
                return
            }

            guard !Task.isCancelled,
                  self.sessionID == expectedSessionID,
                  self.playingBookId == bookId else { return }
            self.updateChaptersQueue(refreshedQueue, for: bookId)
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
    private var eqNode: AVAudioUnitEQ?

    private override init() {
        // Nạp cấu hình từ UserDefaults
        let toolVal = UserDefaults.standard.string(forKey: "ttsTool") ?? "system"
        self.tool = toolVal

        let defaultRate = UserDefaults.standard.object(forKey: "ttsRate") != nil ? UserDefaults.standard.double(forKey: "ttsRate") : 1.0
        let defaultPitch = UserDefaults.standard.object(forKey: "ttsPitch") != nil ? UserDefaults.standard.double(forKey: "ttsPitch") : 1.0

        if toolVal == "system" {
            self.speed = UserDefaults.standard.double(forKey: "systemRate") > 0 ? UserDefaults.standard.double(forKey: "systemRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "systemPitch") > 0 ? UserDefaults.standard.double(forKey: "systemPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "systemVoice") ?? ""
        } else if toolVal == "nghitts" {
            self.speed = UserDefaults.standard.double(forKey: "nghittsRate") > 0 ? UserDefaults.standard.double(forKey: "nghittsRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "nghittsPitch") > 0 ? UserDefaults.standard.double(forKey: "nghittsPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? "Ngọc Huyền (mới)"
        } else if toolVal == "google" {
            self.speed = UserDefaults.standard.double(forKey: "googleRate") > 0 ? UserDefaults.standard.double(forKey: "googleRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "googlePitch") > 0 ? UserDefaults.standard.double(forKey: "googlePitch") : defaultPitch
            let savedVoice = UserDefaults.standard.string(forKey: "googleVoice") ?? "via"
            let validGoogleVoiceIds = Set(GoogleVoice.allVoices.map { $0.id })
            self.selectedVoice = validGoogleVoiceIds.contains(savedVoice) ? savedVoice : "via"
        } else {
            self.speed = UserDefaults.standard.double(forKey: "extRate_\(toolVal)") > 0 ? UserDefaults.standard.double(forKey: "extRate_\(toolVal)") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "extPitch_\(toolVal)") > 0 ? UserDefaults.standard.double(forKey: "extPitch_\(toolVal)") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "extVoice_\(toolVal)") ?? ""
        }

        self.chunkLength = UserDefaults.standard.object(forKey: "ttsChunkLength") != nil ? UserDefaults.standard.integer(forKey: "ttsChunkLength") : 200
        self.googlePrefetchCount = UserDefaults.standard.object(forKey: "googlePrefetchCount") != nil ? UserDefaults.standard.integer(forKey: "googlePrefetchCount") : 3
        self.nghittsPrefetchCount = UserDefaults.standard.object(forKey: "nghittsPrefetchCount") != nil ? UserDefaults.standard.integer(forKey: "nghittsPrefetchCount") : 3
        self.extPrefetchCount = 3
        self.prefetchDelayMs = UserDefaults.standard.object(forKey: "ttsPrefetchDelayMs") != nil ? UserDefaults.standard.integer(forKey: "ttsPrefetchDelayMs") : 350
        self.extensionLocalPath = UserDefaults.standard.string(forKey: "ttsExtensionLocalPath") ?? ""
        self.extensionConfigJson = UserDefaults.standard.string(forKey: "ttsExtensionConfigJson") ?? "{}"

        super.init()

        isInitializing = false
        loadParamsForCurrentTool()

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
            self.chunkLength = UserDefaults.standard.object(forKey: "systemChunk") != nil ? UserDefaults.standard.integer(forKey: "systemChunk") : 200
            self.prefetchDelayMs = 0
        } else if tool == "nghitts" {
            self.speed = UserDefaults.standard.double(forKey: "nghittsRate") > 0 ? UserDefaults.standard.double(forKey: "nghittsRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "nghittsPitch") > 0 ? UserDefaults.standard.double(forKey: "nghittsPitch") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? "Ngọc Huyền (mới)"
            self.nghittsPrefetchCount = UserDefaults.standard.object(forKey: "nghittsPrefetchCount") != nil ? UserDefaults.standard.integer(forKey: "nghittsPrefetchCount") : 3
            self.chunkLength = UserDefaults.standard.object(forKey: "nghittsChunk") != nil ? UserDefaults.standard.integer(forKey: "nghittsChunk") : 200
            self.prefetchDelayMs = UserDefaults.standard.object(forKey: "nghittsPrefetchDelay") != nil ? UserDefaults.standard.integer(forKey: "nghittsPrefetchDelay") : 0
        } else if tool == "google" {
            self.speed = UserDefaults.standard.double(forKey: "googleRate") > 0 ? UserDefaults.standard.double(forKey: "googleRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "googlePitch") > 0 ? UserDefaults.standard.double(forKey: "googlePitch") : defaultPitch
            let savedVoice = UserDefaults.standard.string(forKey: "googleVoice") ?? "via"
            let validGoogleVoiceIds = Set(GoogleVoice.allVoices.map { $0.id })
            self.selectedVoice = validGoogleVoiceIds.contains(savedVoice) ? savedVoice : "via"
            self.googlePrefetchCount = UserDefaults.standard.object(forKey: "googlePrefetchCount") != nil ? UserDefaults.standard.integer(forKey: "googlePrefetchCount") : 3
            self.chunkLength = UserDefaults.standard.object(forKey: "googleChunk") != nil ? UserDefaults.standard.integer(forKey: "googleChunk") : 200
            self.prefetchDelayMs = UserDefaults.standard.object(forKey: "googlePrefetchDelay") != nil ? UserDefaults.standard.integer(forKey: "googlePrefetchDelay") : 500
        } else {
            self.speed = UserDefaults.standard.double(forKey: "extRate_\(tool)") > 0 ? UserDefaults.standard.double(forKey: "extRate_\(tool)") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "extPitch_\(tool)") > 0 ? UserDefaults.standard.double(forKey: "extPitch_\(tool)") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "extVoice_\(tool)") ?? ""
            
            let parsed = parseExtensionConfigParams(jsonString: extensionConfigJson)
            self.extPrefetchCount = parsed.preloadSize ?? 3
            self.chunkLength = parsed.maxLength ?? 200
            let saved = UserDefaults.standard.object(forKey: "extPrefetchDelay_\(tool)") != nil ? UserDefaults.standard.integer(forKey: "extPrefetchDelay_\(tool)") : 500
            self.prefetchDelayMs = max(500, saved)
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
        let eqNode = AVAudioUnitEQ(numberOfBands: 2)

        let band0 = eqNode.bands[0]
        band0.filterType = .lowPass
        band0.frequency = 6500.0
        band0.bandwidth = 1.0
        band0.bypass = false

        let band1 = eqNode.bands[1]
        band1.filterType = .highShelf
        band1.frequency = 7500.0
        band1.gain = -12.0
        band1.bypass = false

        eqNode.bypass = false

        engine.attach(player)
        engine.attach(eqNode)
        engine.attach(pitchNode)

        // Connect Player -> EQ -> TimePitch -> mainMixer
        engine.connect(player, to: eqNode, format: nil)
        engine.connect(eqNode, to: pitchNode, format: nil)
        engine.connect(pitchNode, to: engine.mainMixerNode, format: nil)

        self.audioEngine = engine
        self.playerNode = player
        self.timePitchNode = pitchNode
        self.eqNode = eqNode
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            AppLogger.shared.log("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
        logRemoteTrace("configureAudioSession") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
    }

    private func updatePlaybackParams() {
        if isPlaying {
            if tool == "system" {
                // AVSpeechSynthesizer
            } else if let player = audioPlayer {
                player.rate = Float(speed)
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
        guard let currentChapter = chapters.first(where: { $0.index == currentIndex }) else { return }
        let key = "showChapterTitle_\(bookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true

        let preparedKey = TTSPreparedChapterKey(
            bookId: bookId,
            chapterIndex: currentIndex,
            chapterTitle: currentChapter.title,
            content: chapterContent,
            chunkLength: chunkLength,
            includeChapterTitle: showTitle
        )
        guard preparedChapterKey != preparedKey else { return }

        prepareSpeakingTask?.cancel()
        preparationGeneration += 1
        let expectedPreparationGeneration = preparationGeneration
        let processor = TTSBackgroundProcessor()

        prepareSpeakingTask = Task(priority: .utility) {
            do {
                let processed = try await processor.processChapter(
                    bookId: bookId,
                    chapterIndex: currentIndex,
                    chapterTitle: currentChapter.title,
                    rawContent: chapterContent,
                    chunkLength: preparedKey.chunkLength,
                    shouldTranslateRawContent: false,
                    includeChapterTitle: showTitle,
                    sessionID: UUID(),
                    generation: expectedPreparationGeneration
                )
                guard !Task.isCancelled,
                      self.preparationGeneration == expectedPreparationGeneration else { return }

                self.preparedChapterKey = preparedKey
                self.preparedChapter = TTSPreparedChapter(
                    normalizedContent: processed.normalizedContent,
                    paragraphs: processed.paragraphs
                )
            } catch is CancellationError {
                return
            } catch {
                AppLogger.shared.log("[TTSManager] Không thể chuẩn bị trước chương TTS: \(error.localizedDescription)")
            }
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

    #if DEBUG
    func waitForPreparationForTesting() async {
        await prepareSpeakingTask?.value
    }
    #endif

    public func startSpeaking(
        bookId: String,
        chapters: [TTSChapterInfo],
        currentIndex: Int,
        chapterContent: String,
        startParagraphIndex: Int,
        startTextOffset: Int? = nil,
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
        startSpeakingTask?.cancel()
        startSpeakingTask = nil

        let newSessionID = UUID()
        self.sessionID = newSessionID
        self.ttsProcessingGeneration += 1
        let currentGen = self.ttsProcessingGeneration

        self.stopCurrentPlayback()
        self.wasPlayingBeforeInterruption = false

        self.configureAudioSession()
        self.setRemoteCommandsEnabled(true)
        self.playingBookId = bookId
        self.playingCoverUrl = coverUrl
        self.chaptersQueue = chapters
        self.playingChapterIndex = currentIndex
        self.bookTitle = bookTitle
        self.playingBookDetailUrl = bookDetailUrl
        self.playingBookSourceName = bookSourceName
        self.extensionInfo = extensionInfo
        self.showFloatingWidget = true

        Task { await ReadingProgressStore.shared.claim(bookId: bookId, owner: .tts) }
        self.clearPrefetchCache()

        guard let currentChapter = chapters.first(where: { $0.index == currentIndex }) else { return }
        self.playingChapterUrl = currentChapter.url
        self.chapterTitle = currentChapter.title

        let chunkLen = chunkLength

        let key = "showChapterTitle_\(bookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
        let expectedTitle = currentChapter.title

        let requestedKey = TTSPreparedChapterKey(
            bookId: bookId,
            chapterIndex: currentIndex,
            chapterTitle: expectedTitle,
            content: chapterContent,
            chunkLength: chunkLen,
            includeChapterTitle: showTitle
        )

        if preparedChapterKey == requestedKey, let preparedChapter {
            self.normalizedChapterText = ChapterTextNormalizer.normalize(preparedChapter.normalizedContent)
            self.chapterContent = preparedChapter.normalizedContent
            self.paragraphs = preparedChapter.paragraphs
            self.continueStartSpeaking(startParagraphIndex: startParagraphIndex, startTextOffset: startTextOffset)
            self.triggerNextChapterPrefetch()
            return
        }

        let processor = TTSBackgroundProcessor()
        startSpeakingTask = Task(priority: .userInitiated) {
            do {
                let processed = try await processor.processChapter(
                    bookId: bookId,
                    chapterIndex: currentIndex,
                    chapterTitle: expectedTitle,
                    rawContent: chapterContent,
                    chunkLength: chunkLen,
                    shouldTranslateRawContent: false,
                    includeChapterTitle: showTitle,
                    sessionID: newSessionID,
                    generation: currentGen
                )

                guard !Task.isCancelled,
                      self.sessionID == processed.sessionID,
                      self.ttsProcessingGeneration == processed.generation,
                      self.playingBookId == processed.bookId else { return }

                self.preparedChapterKey = requestedKey
                self.preparedChapter = TTSPreparedChapter(
                    normalizedContent: processed.normalizedContent,
                    paragraphs: processed.paragraphs
                )
                self.normalizedChapterText = ChapterTextNormalizer.normalize(processed.normalizedContent)
                self.chapterContent = processed.normalizedContent
                self.paragraphs = processed.paragraphs
                self.continueStartSpeaking(startParagraphIndex: startParagraphIndex, startTextOffset: startTextOffset)
                self.triggerNextChapterPrefetch()
            } catch is CancellationError {
                return
            } catch {
                AppLogger.shared.log("[TTSManager] Không thể bắt đầu TTS: \(error.localizedDescription)")
            }
        }
    }

    private func continueStartSpeaking(startParagraphIndex: Int, startTextOffset: Int? = nil) {
        var targetIdx = 0
        if startParagraphIndex == -1 {
            targetIdx = 0
        } else if let offset = startTextOffset {
            if let idx = paragraphs.firstIndex(where: {
                $0.paragraphIndex == startParagraphIndex &&
                $0.range.location <= offset && offset < ($0.range.location + $0.range.length)
            }) {
                targetIdx = idx
            } else if let idx = paragraphs.firstIndex(where: { $0.paragraphIndex == startParagraphIndex }) {
                targetIdx = idx
            } else {
                targetIdx = 0
            }
        } else {
            if let idx = paragraphs.firstIndex(where: { $0.paragraphIndex == startParagraphIndex }) {
                targetIdx = idx
            } else {
                targetIdx = 0
            }
        }

        self.currentParagraphIndex = targetIdx
        self.isPlaying = true
        setSystemNowPlayingPlaybackState(.playing)
        self.syncRemoteCommandState()

        speakCurrent()
    }



    public func pause() {
        logRemoteTrace("pause()") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        guard isPlaying else { return }
        checkpointProgressAndRelease()
        self.isPlaying = false
        self.lastPausedTime = Date()
        setSystemNowPlayingPlaybackState(.paused)

        if tool == "system" {
            siriService.pause()
        } else {
            audioPlayer?.pause()
        }
        syncRemoteCommandState()
        updateNowPlayingInfo()
    }

    public func resume() {
        logRemoteTrace("resume()", details: "isPlayingBefore:\(isPlaying)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        if isPlaying {
            if tool == "system" {
                siriService.resume()
            } else {
                if let player = audioPlayer, !player.isPlaying {
                    let ok = player.play()
                    if ok {
                        isPlaying = true
                    } else {
                        speakCurrent()
                    }
                } else {
                    speakCurrent()
                }
            }
            setSystemNowPlayingPlaybackState(.playing)
            syncRemoteCommandState()
            updateNowPlayingInfo()
            return
        }

        guard currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count else {
            return
        }

        self.configureAudioSession()
        self.setRemoteCommandsEnabled(true)
        self.isPlaying = true
        Task { await ReadingProgressStore.shared.claim(bookId: playingBookId, owner: .tts) }
        setSystemNowPlayingPlaybackState(.playing)

        if tool == "system" {
            if siriService.isPaused {
                if !siriService.resume() {
                    speakCurrent()
                }
            } else {
                speakCurrent()
            }
        } else {
            let timeSincePause = lastPausedTime.map { Date().timeIntervalSince($0) } ?? 0.0
            if timeSincePause > 5.0 || currentPlaybackId == nil {
                speakCurrent()
            } else {
                if let player = audioPlayer {
                    if !player.isPlaying {
                        player.play()
                    }
                } else {
                    speakCurrent()
                }
            }
        }
        syncRemoteCommandState()
        updateNowPlayingInfo()
    }

    private func stopPlayback(keepWidget: Bool = false) {
        checkpointProgressAndRelease()
        sessionID = UUID()
        self.isPlaying = false
        self.wasPlayingBeforeSettings = false
        self.wasPlayingBeforeInterruption = false
        self.ttsProcessingGeneration += 1
        startSpeakingTask?.cancel()
        startSpeakingTask = nil
        chapterQueueRefreshTask?.cancel()
        chapterQueueRefreshTask = nil
        nowPlayingUpdateGeneration &+= 1

        if !keepWidget {
            self.currentParagraphIndex = -1
            self.currentParentParagraphIndex = -1
            self.savedParagraphIdentityBeforeSettings = -1
            self.highlightRange = nil
            self.showFloatingWidget = false
        }

        clearPrefetchCache()

        siriService.stop()
        stopCurrentHardwarePlayer()
        siriService.stop()
        clearPrefetchCache()

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
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
            if currentParentParagraphIndex != -1 {
                savedParagraphIdentityBeforeSettings = currentParentParagraphIndex
            } else if currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count {
                savedParagraphIdentityBeforeSettings = paragraphs[currentParagraphIndex].paragraphIndex
            } else {
                savedParagraphIdentityBeforeSettings = -1
            }
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

        // Lưu paragraph identity (số thứ tự dòng gốc) đã ghi nhận khi mở settings
        let savedParagraphIdentity = savedParagraphIdentityBeforeSettings
        savedParagraphIdentityBeforeSettings = -1
        let wasPlaying = wasPlayingBeforeSettings
        wasPlayingBeforeSettings = false

        // Dừng engine cũ để áp dụng cài đặt mới (nhưng giữ widget nổi)
        stopPlayback(keepWidget: true)

        if normalizedChapterText.lines.isEmpty && !chapterContent.isEmpty {
            self.normalizedChapterText = ChapterTextNormalizer.normalize(chapterContent)
        }

        // Nạp lại phân đoạn
        self.paragraphs = TTSParagraphBuilder.build(from: normalizedChapterText, chunkLength: chunkLength)

        let key = "showChapterTitle_\(playingBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true

        if showTitle && !chapterTitle.isEmpty {
            let titleParagraph = TTSParagraph(
                text: chapterTitle,
                range: NSRange(location: 0, length: chapterTitle.utf16.count),
                paragraphIndex: -1
            )
            self.paragraphs.insert(titleParagraph, at: 0)
        }

        let targetIdx: Int
        if savedParagraphIdentity == -1 {
            targetIdx = 0
        } else if let idx = paragraphs.firstIndex(where: { $0.paragraphIndex == savedParagraphIdentity }) {
            targetIdx = idx
        } else {
            targetIdx = (showTitle && !chapterTitle.isEmpty && paragraphs.count > 1) ? 1 : 0
        }

        self.currentParagraphIndex = targetIdx
        if targetIdx >= 0 && targetIdx < paragraphs.count {
            self.currentParentParagraphIndex = paragraphs[targetIdx].paragraphIndex
        } else {
            self.currentParentParagraphIndex = -1
        }

        // Nếu trước đó đang phát, tiếp tục phát đoạn đó với cài đặt mới
        if wasPlaying {
            self.configureAudioSession()
            self.setRemoteCommandsEnabled(true)
            Task { await ReadingProgressStore.shared.claim(bookId: playingBookId, owner: .tts) }
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
            // Đã hết chương, kiểm tra hẹn giờ dừng khi hết chương
            if timerMode == .endOfChapter {
                stopCurrentPlayback()
                pause()
                ToastManager.shared.show(message: "📖 Hẹn giờ: Đã tự động tạm dừng khi đọc hết chương.", type: .info)
                return
            }
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
            stopCurrentHardwarePlayer()
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
            // Hết chương, kiểm tra hẹn giờ dừng khi hết chương
            if timerMode == .endOfChapter {
                stopCurrentPlayback()
                pause()
                ToastManager.shared.show(message: "📖 Hẹn giờ: Đã tự động tạm dừng khi đọc hết chương.", type: .info)
                return
            }
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
        self.ttsProcessingGeneration += 1
        let expectedGeneration = self.ttsProcessingGeneration
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

        let chunkLen = chunkLength
        let isTransEnabled = TranslateUtils.isTranslationEnabled
        let key = "showChapterTitle_\(expectedBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
        let expectedTitle = isTransEnabled && TranslateUtils.containsChinese(nextChapter.title)
            ? TranslateUtils.translateChapterTitle(nextChapter.title, bookId: expectedBookId)
            : nextChapter.title
        let processor = TTSBackgroundProcessor()

        Task { [weak self] in
            do {
                let result = try await ChapterContentRepository.shared.load(request)
                guard let self,
                      self.isPlaying,
                      self.sessionID == expectedSessionID,
                      self.ttsProcessingGeneration == expectedGeneration,
                      self.playingBookId == expectedBookId,
                      self.chaptersQueue.first(where: { $0.index == nextChapter.index })?.url == expectedChapterURL,
                      self.playingChapterIndex < nextChapter.index else { return }

                let rawContent = result.document.text.content

                let processed = try await processor.processChapter(
                    bookId: expectedBookId,
                    chapterIndex: nextChapter.index,
                    chapterTitle: expectedTitle,
                    rawContent: rawContent,
                    chunkLength: chunkLen,
                    shouldTranslateRawContent: isTransEnabled,
                    includeChapterTitle: showTitle,
                    sessionID: expectedSessionID,
                    generation: expectedGeneration
                )

                await MainActor.run {
                    guard self.isPlaying,
                          self.sessionID == processed.sessionID,
                          self.ttsProcessingGeneration == processed.generation,
                          self.playingBookId == processed.bookId else {
                        return
                    }
                    self.applyNextChapter(index: processed.chapterIndex, content: processed.normalizedContent, paragraphs: processed.paragraphs, chapter: nextChapter)
                }
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

    private func applyNextChapter(index: Int, content: String, paragraphs: [TTSParagraph], chapter: TTSChapterInfo) {
        checkpointProgress()
        self.playingChapterIndex = index
        self.playingChapterUrl = chapter.url
        self.chapterTitle = chapter.title
        self.normalizedChapterText = ChapterTextNormalizer.normalize(content)
        self.chapterContent = content
        self.paragraphs = paragraphs
        self.clearPrefetchCache()

        self.continueStartSpeaking(startParagraphIndex: -1)

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

        restartSleepTimerIfNeeded()

        let paragraph = paragraphs[currentParagraphIndex]
        self.highlightRange = paragraph.range // Cập nhật vùng bôi đen chữ đang đọc trên giao diện đọc truyện
        self.currentParentParagraphIndex = paragraph.paragraphIndex

        recordProgressInMemory()

        // Áp dụng các quy tắc thay thế ký tự trước khi đọc
        let textToSpeak = TTSReplacementManager.shared.applyReplacements(to: paragraph.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        AppLogger.shared.log("🔊 [TTSManager] Chunk [\(currentParagraphIndex + 1)/\(paragraphs.count)] (ParentID=\(paragraph.paragraphIndex)): Raw='\(paragraph.text)' | Processed='\(textToSpeak)' | highlightRange=\(paragraph.range)")

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
            playGoogleTTS(textToSpeak) // Phát bằng Google Cloud TTS ReadAloud REST API
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

    public func clearPrefetchCache() {
        nextChapterPrefetchTask?.cancel()
        nextChapterPrefetchTask = nil

        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
        preloadedData.removeAll()
    }

    // updatePrefetchWindow: Cập nhật cửa sổ trượt (Sliding Window) tải trước dữ liệu âm thanh
    // Mục tiêu: Luôn có sẵn âm thanh PCMBuffer của đoạn tiếp theo (N+1) trong bộ đệm để phát ngay khi đoạn hiện tại (N) kết thúc, triệt tiêu hoàn toàn khoảng trễ tổng hợp âm thanh.
    private func updatePrefetchWindow() {
        guard isPlaying, tool != "system" else { return }

        let N = currentParagraphIndex
        let count = max(1, min(10, currentPrefetchCount))
        let targetIndices = (1...count).compactMap { offset -> Int? in
            let idx = N + offset
            return idx < paragraphs.count ? idx : nil
        }

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

        let cacheKeepIndices = Set(Array(N...(N + count)))
        var cacheToClear: [Int] = []
        for idx in preloadedData.keys {
            if !cacheKeepIndices.contains(idx) {
                cacheToClear.append(idx)
            }
        }
        for idx in cacheToClear {
            preloadedData.removeValue(forKey: idx)
        }

        for idx in targetIndices {
            if preloadedData[idx] == nil && prefetchTasks[idx] == nil {
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
                guard let self = self else { return }

                let offset = max(0, index - self.currentParagraphIndex)
                if offset >= 1 {
                    let delayStepMs = max(500, self.prefetchDelayMs)
                    let delayMs = UInt64(offset) * UInt64(delayStepMs)
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                }

                do {
                    let mp3Data = try await self.googleService.synthesize(text: text, voice: voice, speed: 1.0, pitch: 1.0)

                    if !Task.isCancelled,
                       self.sessionID == expectedSessionID,
                       self.playingBookId == expectedBookId,
                       self.playingChapterIndex == expectedChapterIndex,
                       self.playingChapterUrl == expectedChapterURL,
                       self.selectedVoice == voice,
                       self.tool == toolBeforeStart {
                        self.preloadedData[index] = mp3Data
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
                guard let self = self else { return }

                let offset = max(0, index - self.currentParagraphIndex)
                if offset > 1 && self.prefetchDelayMs > 0 {
                    let delayMs = UInt64(offset - 1) * UInt64(self.prefetchDelayMs)
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                }

                do {
                    let wavData = try await service.synthesize(text: text, voice: voice, speed: 1.0)

                    if !Task.isCancelled,
                       self.sessionID == expectedSessionID,
                       self.playingBookId == expectedBookId,
                       self.playingChapterIndex == expectedChapterIndex,
                       self.playingChapterUrl == expectedChapterURL,
                       self.selectedVoice == voice,
                       self.tool == toolBeforeStart {
                        self.preloadedData[index] = wavData
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
        } else {
            let localPath = extensionLocalPath
            let configJson = extensionConfigJson

            let task = Task { [weak self] in
                guard let self = self else { return }

                let offset = max(0, index - self.currentParagraphIndex)
                if offset >= 1 {
                    let delayStepMs = max(500, self.prefetchDelayMs)
                    let delayMs = UInt64(offset) * UInt64(delayStepMs)
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                }

                do {
                    let audioData = try await self.extService.synthesizeData(text: text, voice: voice, localPath: localPath, configJson: configJson)

                    if !Task.isCancelled,
                       self.sessionID == expectedSessionID,
                       self.playingBookId == expectedBookId,
                       self.playingChapterIndex == expectedChapterIndex,
                       self.playingChapterUrl == expectedChapterURL,
                       self.selectedVoice == voice,
                       self.tool == toolBeforeStart {
                        self.preloadedData[index] = audioData
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
        }
    }

    private func playAudioData(_ audioData: Data, withId customId: String? = nil) {
        let playbackId = customId ?? String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        cleanUpTempFile()
        stopCurrentHardwarePlayer()

        do {
            configureAudioSession()
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.enableRate = true
            player.rate = Float(speed)

            self.audioPlayer = player

            let ok = player.play()
            if ok {
                self.isPlaying = true
            } else {
                AppLogger.shared.log("❌ [TTSManager] [ID=\(playbackId)] player.play() thất bại")
                self.preloadedData.removeValue(forKey: currentParagraphIndex)
                self.currentPlaybackId = nil
                self.pause()
                ToastManager.shared.show(message: "Lỗi trình phát âm thanh: Không thể phát dữ liệu audio.", type: .error)
            }
        } catch {
            AppLogger.shared.log("❌ [TTSManager] [ID=\(playbackId)] Khởi tạo AVAudioPlayer thất bại: \(error.localizedDescription)")
            self.preloadedData.removeValue(forKey: currentParagraphIndex)
            self.currentPlaybackId = nil
            self.pause()
            ToastManager.shared.show(message: "Lỗi trình phát âm thanh: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
        }

        updateNowPlayingInfo()
    }

    private func stopCurrentHardwarePlayer() {
        if let player = audioPlayer {
            player.stop()
            player.delegate = nil
            self.audioPlayer = nil
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

        updatePrefetchWindow()

        if let cachedData = preloadedData[index] {
            self.playAudioData(cachedData, withId: playbackId)
            return
        }

        Task {
            do {
                let wavData: Data
                if let activeTask = prefetchTasks[index] {
                    _ = await activeTask.value
                    if let cached = preloadedData[index] {
                        wavData = cached
                    } else {
                        wavData = try await service.synthesize(text: text, voice: selectedVoice, speed: 1.0)
                    }
                } else {
                    wavData = try await service.synthesize(text: text, voice: selectedVoice, speed: 1.0)
                }

                guard self.isPlaying && self.currentPlaybackId == playbackId else {
                    return
                }

                await MainActor.run {
                    self.playAudioData(wavData, withId: playbackId)
                }
            } catch {
                await MainActor.run {
                    guard self.currentPlaybackId == playbackId else { return }
                    AppLogger.shared.log("🔊 [TTSManager] Chơi trực tiếp thất bại cho đoạn \(index): \(error.localizedDescription)")
                    self.preloadedData.removeValue(forKey: index)
                    self.prefetchTasks[index]?.cancel()
                    self.prefetchTasks.removeValue(forKey: index)
                    self.currentPlaybackId = nil
                    self.pause()
                    ToastManager.shared.show(message: "Lỗi NghiTTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
                }
            }
        }
    }

    private func playGoogleTTS(_ text: String) {
        let index = currentParagraphIndex
        let voice = selectedVoice
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        updatePrefetchWindow()

        if let cachedData = preloadedData[index] {
            self.playAudioData(cachedData, withId: playbackId)
            return
        }

        Task {
            do {
                let mp3Data: Data
                if let activeTask = prefetchTasks[index] {
                    _ = await activeTask.value
                    if let cached = preloadedData[index] {
                        mp3Data = cached
                    } else {
                        mp3Data = try await googleService.synthesize(text: text, voice: voice, speed: 1.0, pitch: 1.0)
                    }
                } else {
                    mp3Data = try await googleService.synthesize(text: text, voice: voice, speed: 1.0, pitch: 1.0)
                }

                guard self.isPlaying && self.currentPlaybackId == playbackId else {
                    return
                }

                await MainActor.run {
                    self.playAudioData(mp3Data, withId: playbackId)
                }
            } catch {
                await MainActor.run {
                    guard self.currentPlaybackId == playbackId else { return }
                    AppLogger.shared.log("❌ Lỗi Google Cloud TTS: \(error.localizedDescription)")
                    self.preloadedData.removeValue(forKey: index)
                    self.prefetchTasks[index]?.cancel()
                    self.prefetchTasks.removeValue(forKey: index)
                    self.currentPlaybackId = nil
                    self.pause()
                    ToastManager.shared.show(message: "Lỗi Google TTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
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

        updatePrefetchWindow()

        if let cachedData = preloadedData[index] {
            self.playAudioData(cachedData, withId: playbackId)
            return
        }

        Task {
            do {
                let audioData: Data
                if let activeTask = prefetchTasks[index] {
                    _ = await activeTask.value
                    if let cached = preloadedData[index] {
                        audioData = cached
                    } else {
                        audioData = try await extService.synthesizeData(text: text, voice: voice, localPath: localPath, configJson: configJson)
                    }
                } else {
                    audioData = try await extService.synthesizeData(text: text, voice: voice, localPath: localPath, configJson: configJson)
                }

                guard self.isPlaying && self.currentPlaybackId == playbackId else {
                    return
                }

                await MainActor.run {
                    self.playAudioData(audioData, withId: playbackId)
                }
            } catch {
                await MainActor.run {
                    guard self.currentPlaybackId == playbackId else { return }
                    AppLogger.shared.log("❌ Lỗi Extension TTS: \(error.localizedDescription)")
                    self.preloadedData.removeValue(forKey: index)
                    self.prefetchTasks[index]?.cancel()
                    self.prefetchTasks.removeValue(forKey: index)
                    self.currentPlaybackId = nil
                    self.pause()
                    ToastManager.shared.show(message: "Lỗi Extension TTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
                }
            }
        }
    }

    private func cleanUpTempFile() {
        // File tạm được dọn dẹp trực tiếp trong ExtTTSService.synthesize
    }

    // MARK: - Text Segmentation (Phân đoạn văn bản)

    // MARK: - Lock Screen & Remote Control Sync

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        logRemoteTrace("setRemoteCommandsEnabled(\(enabled))") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = enabled
        commandCenter.pauseCommand.isEnabled = enabled
        commandCenter.togglePlayPauseCommand.isEnabled = enabled
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
        let playing = active && isPlaying
        let paused = active && !isPlaying
        commandCenter.playCommand.isEnabled = paused
        commandCenter.pauseCommand.isEnabled = playing
        commandCenter.togglePlayPauseCommand.isEnabled = active
        commandCenter.nextTrackCommand.isEnabled = active
        commandCenter.previousTrackCommand.isEnabled = active
        logRemoteTrace("syncRemoteCommandState", details: "active:\(active), playing:\(playing), paused:\(paused)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
    }

    /// Synchronously publishes relative current (1.0/0.0) and default (TTS speed) playback rates
    /// along with a complete finite paragraph timeline (elapsed, duration, progress) to iOS Now Playing
    /// metadata without waiting for the asynchronous metadata refresh.
    /// The playbackState assignment is retained for system compatibility and logging.
    @MainActor
    private func setSystemNowPlayingPlaybackState(_ state: MPNowPlayingPlaybackState) {
        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo ?? [:]
        let currentRate = (state == .playing) ? 1.0 : 0.0
        let pIndex = self.currentParagraphIndex
        let pCount = self.paragraphs.count
        let duration = Double(max(1, pCount))
        let elapsed = min(duration, Double(max(0, pIndex)))
        let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0.0

        info[MPNowPlayingInfoPropertyPlaybackRate] = currentRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = self.speed
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackProgress] = progress

        center.nowPlayingInfo = info
        center.playbackState = state

        // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        let thread = Thread.isMainThread ? "Main" : "Bg"
        AppLogger.shared.log("🔍 [TTSTrace] setSystemNowPlayingPlaybackState | Thread:\(thread) | state:\(state.rawValue) | currentRate:\(currentRate) | defaultRate:\(self.speed) | elapsed:\(elapsed) | duration:\(duration) | progress:\(String(format: "%.2f", progress))")
    }

    enum RemoteTransportAction {
        case play
        case pause
        case toggle
        case next
        case previous
    }

    func handleRemoteTransportCommandOnMain(_ action: RemoteTransportAction) {
        logRemoteTrace("handleRemoteTransportCommandOnMain", details: "action:\(action)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS

        switch action {
        case .toggle:
            if self.isPlaying {
                self.pause()
            } else {
                self.resume()
            }
        case .play:
            if !self.isPlaying {
                self.resume()
            } else {
                self.syncRemoteCommandState()
                self.updateNowPlayingInfo()
            }
        case .pause:
            if self.isPlaying {
                self.pause()
            } else {
                self.resume()
            }
        case .next:
            self.skipForward()
        case .previous:
            self.skipBackward()
        }
    }

    @MainActor
    func dispatchRemoteTransportCommand(
        _ action: RemoteTransportAction,
        entryUptime: UInt64,
        isMain: Bool,
        eventId: String
    ) -> MPRemoteCommandHandlerStatus {
        let latencyMs = Double(DispatchTime.now().uptimeNanoseconds - entryUptime) / 1_000_000.0
        self.logRemoteTrace("remoteCallbackDispatched", details: "id:\(eventId) | action:\(action) | entryThread:\(isMain ? "Main" : "Bg") | queueLatency:\(String(format: "%.2f", latencyMs))ms")

        let wasPlaying = self.isPlaying
        self.handleRemoteTransportCommandOnMain(action)

        let status: MPRemoteCommandHandlerStatus
        switch action {
        case .play:
            status = self.isPlaying ? .success : .commandFailed
        case .pause:
            status = !self.isPlaying ? .success : .commandFailed
        case .toggle:
            status = (self.isPlaying != wasPlaying) ? .success : .commandFailed
        case .next, .previous:
            status = .success
        }

        self.logRemoteTrace("remoteCallbackCompleted", details: "id:\(eventId) | action:\(action) | status:\(status == .success ? "success" : "commandFailed")(\(status.rawValue))")
        return status
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)

        // Toggle Play / Pause
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            let isMain = Thread.isMainThread
            let entryUptime = DispatchTime.now().uptimeNanoseconds
            let eventId = String(UUID().uuidString.prefix(8))

            if isMain {
                return MainActor.assumeIsolated {
                    guard let self = self else { return .commandFailed }
                    return self.dispatchRemoteTransportCommand(
                        .toggle,
                        entryUptime: entryUptime,
                        isMain: true,
                        eventId: eventId
                    )
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    _ = self.dispatchRemoteTransportCommand(
                        .toggle,
                        entryUptime: entryUptime,
                        isMain: false,
                        eventId: eventId
                    )
                }
                return .success
            }
        }

        // Play
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            let isMain = Thread.isMainThread
            let entryUptime = DispatchTime.now().uptimeNanoseconds
            let eventId = String(UUID().uuidString.prefix(8))

            if isMain {
                return MainActor.assumeIsolated {
                    guard let self = self else { return .commandFailed }
                    return self.dispatchRemoteTransportCommand(
                        .play,
                        entryUptime: entryUptime,
                        isMain: true,
                        eventId: eventId
                    )
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    _ = self.dispatchRemoteTransportCommand(
                        .play,
                        entryUptime: entryUptime,
                        isMain: false,
                        eventId: eventId
                    )
                }
                return .success
            }
        }

        // Pause
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            let isMain = Thread.isMainThread
            let entryUptime = DispatchTime.now().uptimeNanoseconds
            let eventId = String(UUID().uuidString.prefix(8))

            if isMain {
                return MainActor.assumeIsolated {
                    guard let self = self else { return .commandFailed }
                    return self.dispatchRemoteTransportCommand(
                        .pause,
                        entryUptime: entryUptime,
                        isMain: true,
                        eventId: eventId
                    )
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    _ = self.dispatchRemoteTransportCommand(
                        .pause,
                        entryUptime: entryUptime,
                        isMain: false,
                        eventId: eventId
                    )
                }
                return .success
            }
        }

        // Next Track (Đoạn sau)
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            DispatchQueue.main.async { [weak self] in
                self?.handleRemoteTransportCommandOnMain(.next)
            }
            return .success
        }

        // Prev Track (Đoạn trước)
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            DispatchQueue.main.async { [weak self] in
                self?.handleRemoteTransportCommandOnMain(.previous)
            }
            return .success
        }

        // Mặc định ban đầu vô hiệu hóa các remote commands cho đến khi bắt đầu phát thực sự
        self.setRemoteCommandsEnabled(false)
        logRemoteTrace("setupRemoteCommandCenter") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
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

            let liveIsPlaying = self.isPlaying
            let liveSpeed = self.speed

            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyTitle] = displayBookTitle

            let currentPart = pCount == 0 ? "" : " (Đoạn \(pIndex + 1)/\(pCount))"
            info[MPMediaItemPropertyArtist] = displayChapterTitle + currentPart

            info.removeValue(forKey: MPNowPlayingInfoPropertyIsLiveStream)
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            let currentRate = liveIsPlaying ? 1.0 : 0.0
            let duration = Double(max(1, pCount))
            let elapsed = min(duration, Double(max(0, pIndex)))
            let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0.0

            info[MPNowPlayingInfoPropertyPlaybackRate] = currentRate
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = liveSpeed
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyPlaybackProgress] = progress

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
            MPNowPlayingInfoCenter.default().playbackState = liveIsPlaying ? .playing : .paused
            self.logRemoteTrace("updateNowPlayingInfo", details: "liveIsPlaying:\(liveIsPlaying), liveSpeed:\(liveSpeed)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
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
        logRemoteTrace("handleInterruption", details: "userInfo:\(notification.userInfo ?? [:])") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
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
        logRemoteTrace("handleRouteChange", details: "userInfo:\(notification.userInfo ?? [:])") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
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
        logRemoteTrace("handleMediaServicesReset") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
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
        logRemoteTrace("handleEngineConfigChange") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
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

extension TTSManager {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audioPlayer == player else { return }
            self.stopCurrentHardwarePlayer()
            if flag {
                self.nextParagraph()
            } else {
                AppLogger.shared.log("⚠️ [TTSManager] AVAudioPlayer phát kết thúc không thành công")
                self.isPlaying = false
            }
        }
    }

    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            AppLogger.shared.log("❌ [TTSManager] AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
            self.isPlaying = false
        }
    }
}

