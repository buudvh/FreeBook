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
    let isTranslationEnabled: Bool
    let translationToken: Int
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
        #if DEBUG
        guard AppLogger.shared.isLoggingEnabled else { return }
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
        #endif
    }

    // Cấu hình (lưu qua AppStorage/UserDefaults)
    @Published public var tool: String {
        didSet {
            UserDefaults.standard.set(tool, forKey: "ttsTool")
            loadParamsForCurrentTool()
            clearPrefetchCache()
            if tool == "nghitts" {
                scheduleNghiWarmUp()
            } else {
                nghiWarmUpTask?.cancel()
                nghiWarmUpTask = nil
            }
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
            clearPrefetchCache()
        }
    }

    @Published public var extensionLocalPath: String {
        didSet {
            UserDefaults.standard.set(extensionLocalPath, forKey: "ttsExtensionLocalPath")
            clearPrefetchCache()
        }
    }
    @Published public var extensionConfigJson: String {
        didSet {
            UserDefaults.standard.set(extensionConfigJson, forKey: "ttsExtensionConfigJson")
            if tool != "system" && tool != "nghitts" && tool != "google" {
                loadParamsForCurrentTool()
            }
            clearPrefetchCache()
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

    private struct TTSAutoAdvancePerfContext {
        let sessionID: UUID
        let generation: Int
        let chapterIndex: Int
        let engine: String
        let startUptime: Double
        var origin: String = "unknown"
        var loadMs: Double = 0
        var processMs: Double = 0
        var synthesisMs: Double = 0
        var playerSetupMs: Double = 0
        var audioCacheHit: Bool = false
        var isFinished: Bool = false
    }

    private var activeTTSAutoAdvancePerf: TTSAutoAdvancePerfContext? = nil
    private var paragraph0SynthesisStartUptime: Double = 0
    private var paragraph0AudioCacheHit: Bool = false

    private func resetParagraph0Timing() {
        paragraph0SynthesisStartUptime = 0
        paragraph0AudioCacheHit = false
    }

    private func currentParagraph0SynthesisMs(untilUptime: Double? = nil) -> Double {
        guard paragraph0SynthesisStartUptime > 0 && !paragraph0AudioCacheHit else { return 0.0 }
        let end = untilUptime ?? ProcessInfo.processInfo.systemUptime
        return max(0.0, (end - paragraph0SynthesisStartUptime) * 1000)
    }

    @MainActor
    private func createTTSAutoAdvancePerf(
        sessionID: UUID,
        generation: Int,
        chapterIndex: Int,
        engine: String
    ) {
        finishTTSAutoAdvancePerf(outcome: "superseded", endpoint: "superseded")
        ensurePrefetchPerfSummary(sessionID: sessionID, chapterIndex: chapterIndex, engine: engine)
        resetParagraph0Timing()
        guard AppLogger.shared.isLoggingEnabled else { return }
        activeTTSAutoAdvancePerf = TTSAutoAdvancePerfContext(
            sessionID: sessionID,
            generation: generation,
            chapterIndex: chapterIndex,
            engine: engine,
            startUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    @MainActor
    private func updateTTSAutoAdvanceLoadPerf(
        sessionID: UUID,
        generation: Int,
        chapterIndex: Int,
        loadMs: Double,
        origin: String
    ) {
        guard var ctx = activeTTSAutoAdvancePerf,
              !ctx.isFinished,
              ctx.sessionID == sessionID,
              ctx.generation == generation,
              ctx.chapterIndex == chapterIndex else { return }
        ctx.loadMs = loadMs
        ctx.origin = origin
        activeTTSAutoAdvancePerf = ctx
    }

    @MainActor
    private func updateTTSAutoAdvanceProcessPerf(
        sessionID: UUID,
        generation: Int,
        chapterIndex: Int,
        processMs: Double
    ) {
        guard var ctx = activeTTSAutoAdvancePerf,
              !ctx.isFinished,
              ctx.sessionID == sessionID,
              ctx.generation == generation,
              ctx.chapterIndex == chapterIndex else { return }
        ctx.processMs = processMs
        activeTTSAutoAdvancePerf = ctx
    }

    @MainActor
    private func finishTTSAutoAdvancePerf(
        outcome: String,
        endpoint: String,
        sessionID: UUID? = nil,
        generation: Int? = nil,
        chapterIndex: Int? = nil,
        synthesisMs: Double = 0,
        playerSetupMs: Double = 0,
        audioCacheHit: Bool? = nil
    ) {
        guard var ctx = activeTTSAutoAdvancePerf, !ctx.isFinished else { return }
        if let sID = sessionID, ctx.sessionID != sID { return }
        if let gen = generation, ctx.generation != gen { return }
        if let chIdx = chapterIndex, ctx.chapterIndex != chIdx { return }

        ctx.isFinished = true
        activeTTSAutoAdvancePerf = nil

        let endUptime = ProcessInfo.processInfo.systemUptime
        let totalMs = (endUptime - ctx.startUptime) * 1000

        let finalSynMs = synthesisMs > 0 ? synthesisMs : ctx.synthesisMs
        let finalSetupMs = playerSetupMs > 0 ? playerSetupMs : ctx.playerSetupMs
        let finalCacheHit = audioCacheHit ?? ctx.audioCacheHit

        resetParagraph0Timing()

        let logLine = String(
            format: "[TTSPerf] AutoAdvance chapter=%d engine=%@ origin=%@ loadMs=%.2f processMs=%.2f synthesisMs=%.2f playerSetupMs=%.2f totalMs=%.2f cacheHit=%@ outcome=%@ endpoint=%@",
            ctx.chapterIndex,
            ctx.engine,
            ctx.origin,
            ctx.loadMs,
            ctx.processMs,
            finalSynMs,
            finalSetupMs,
            totalMs,
            finalCacheHit ? "true" : "false",
            outcome,
            endpoint
        )
        AppLogger.shared.log(logLine)
    }

    private struct TTSPrefetchPerfSummary {
        let sessionID: UUID
        let chapterIndex: Int
        let engine: String
        var immediateHit: Int = 0
        var waitedHit: Int = 0
        var miss: Int = 0
        var failure: Int = 0
        var retrySuccess: Int = 0
        var retryFailure: Int = 0
        var totalWaitMs: Double = 0
        var maxWaitMs: Double = 0
    }

    private var activePrefetchPerfSummary: TTSPrefetchPerfSummary? = nil
    private var prefetchTaskGenerations: [Int: UInt64] = [:]
    private var nextPrefetchTaskGeneration: UInt64 = 0

    @MainActor
    private func ensurePrefetchPerfSummary(sessionID: UUID, chapterIndex: Int, engine: String) {
        guard AppLogger.shared.isLoggingEnabled else {
            if activePrefetchPerfSummary != nil {
                activePrefetchPerfSummary = nil
            }
            return
        }
        if let current = activePrefetchPerfSummary {
            if current.sessionID == sessionID && current.chapterIndex == chapterIndex && current.engine == engine {
                return
            }
            finishTTSPrefetchPerfSummary()
        }
        activePrefetchPerfSummary = TTSPrefetchPerfSummary(
            sessionID: sessionID,
            chapterIndex: chapterIndex,
            engine: engine
        )
    }

    @MainActor
    private func finishTTSPrefetchPerfSummary() {
        guard let summary = activePrefetchPerfSummary else { return }
        activePrefetchPerfSummary = nil
        let total = summary.immediateHit + summary.waitedHit + summary.miss + summary.failure
        guard total > 0, AppLogger.shared.isLoggingEnabled else { return }
        let logLine = String(
            format: "[TTSPerf] PrefetchSummary chapter=%d engine=%@ immediateHit=%d waitedHit=%d miss=%d failure=%d retrySuccess=%d retryFailure=%d totalWaitMs=%.2f maxWaitMs=%.2f",
            summary.chapterIndex,
            summary.engine,
            summary.immediateHit,
            summary.waitedHit,
            summary.miss,
            summary.failure,
            summary.retrySuccess,
            summary.retryFailure,
            summary.totalWaitMs,
            summary.maxWaitMs
        )
        AppLogger.shared.log(logLine)
    }

    @MainActor
    private func recordPrefetchResult(sessionID: UUID, chapterIndex: Int, engine: String, index: Int, outcome: String, waitMs: Double = 0) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        guard sessionID == self.sessionID, chapterIndex == self.playingChapterIndex else { return }
        ensurePrefetchPerfSummary(sessionID: sessionID, chapterIndex: chapterIndex, engine: engine)
        guard var summary = activePrefetchPerfSummary,
              summary.sessionID == sessionID,
              summary.chapterIndex == chapterIndex,
              summary.engine == engine else { return }

        switch outcome {
        case "hit":
            summary.immediateHit += 1
        case "hit_wait":
            summary.waitedHit += 1
            summary.totalWaitMs += waitMs
            summary.maxWaitMs = max(summary.maxWaitMs, waitMs)
            if waitMs >= 100.0 {
                AppLogger.shared.log(String(format: "[TTSPerf] SlowPrefetch chapter=%d index=%d engine=%@ waitMs=%.2f", summary.chapterIndex, index, summary.engine, waitMs))
            }
        case "miss":
            summary.miss += 1
        case "failure":
            summary.failure += 1
            summary.totalWaitMs += waitMs
            summary.maxWaitMs = max(summary.maxWaitMs, waitMs)
        default:
            break
        }
        activePrefetchPerfSummary = summary
    }

    @MainActor
    private func recordPrefetchRetry(sessionID: UUID, chapterIndex: Int, engine: String, success: Bool) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        guard sessionID == self.sessionID, chapterIndex == self.playingChapterIndex else { return }
        guard var summary = activePrefetchPerfSummary,
              summary.sessionID == sessionID,
              summary.chapterIndex == chapterIndex,
              summary.engine == engine else { return }
        if success {
            summary.retrySuccess += 1
        } else {
            summary.retryFailure += 1
        }
        activePrefetchPerfSummary = summary
    }

    private func isTransientTTSError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorResourceUnavailable,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorDataNotAllowed:
                return true
            default:
                break
            }
        }
        if nsError.domain == "GoogleTTSService" || nsError.domain == "ExtTTSService" || nsError.domain == "ExtensionManager" {
            if nsError.code == 429 || (500...599).contains(nsError.code) || nsError.code == -20 || nsError.code == -21 {
                return true
            }
        }
        let lower = error.localizedDescription.lowercased()
        if lower.contains("unexpected eof") ||
           lower.contains("timed out") ||
           lower.contains("connection reset") ||
           lower.contains("network connection") ||
           lower.contains("internal error") ||
           lower.contains("rate limit") ||
           lower.contains("resource_exhausted") ||
           lower.contains("service unavailable") ||
           lower.contains("extttsservice") ||
           lower.contains("extensionmanager") ||
           lower.contains("503") ||
           lower.contains("500") ||
           lower.contains("502") ||
           lower.contains("504") {
            return true
        }
        return false
    }

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
    private var chapterQueueRefreshTask: Task<Void, Never>? = nil
    private var nghiWarmUpTask: Task<Void, Never>? = nil
    private let nextChapterPrefetcher = TTSChapterPrefetcher()
    private var sessionID = UUID()
    private var ttsProcessingGeneration = 0
    private var preparationGeneration = 0
    private var preparedChapterKey: TTSPreparedChapterKey? = nil
    private var preparedChapter: TTSPreparedChapter? = nil
    private var sessionTranslationEnabled: Bool = false

    public func clearPreparedChapterCache() {
        prepareSpeakingTask?.cancel()
        prepareSpeakingTask = nil
        preparationGeneration += 1
        preparedChapterKey = nil
        preparedChapter = nil
    }

    private struct NowPlayingStaticMetadataKey: Equatable, Sendable {
        let bookId: String
        let bookTitle: String
        let chapterIndex: Int
        let chapterTitle: String
        let coverUrl: String
        let isTranslationEnabled: Bool
        let translationToken: Int
    }

    private struct NowPlayingStaticMetadata {
        let key: NowPlayingStaticMetadataKey
        let displayBookTitle: String
        let displayChapterTitle: String
        let artwork: MPMediaItemArtwork?
    }

    // Static title/artwork work is coalesced by book/chapter/translation key.
    // Paragraph transitions update only the cheap timeline fields.
    private var nowPlayingUpdateGeneration: UInt = 0
    private var nowPlayingStaticMetadata: NowPlayingStaticMetadata?
    private var nowPlayingMetadataTaskKey: NowPlayingStaticMetadataKey?
    private var nowPlayingMetadataTask: Task<Void, Never>?
    private var nowPlayingCoverDownloadKey: NowPlayingStaticMetadataKey?

    // Cache lưu trữ dữ liệu âm thanh đã được tổng hợp trước cho các đoạn văn
    private var preloadedData: [Int: Data] = [:]
    private var preloadedDurations: [Int: Double] = [:]
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]
    private var remotePlaybackTask: Task<Void, Never>?
    private var remotePlaybackTaskGeneration: UInt64 = 0
    private var nghiRefillTask: Task<Void, Never>? = nil
    private var nghiRefillGeneration: UInt64 = 0
    private var nghiRefillInFlightIndex: Int? = nil
    private var audioPlayer: AVAudioPlayer?
    private let nghiAudioPlayerQueue = NghiAudioPlayerQueue()
    private let callObserver = TTSCallObserver()
    private var isAudioSessionConfigured = false

    // Trạng thái đệm thời lượng âm thanh & nhiệt độ thiết bị (NghiTTS Optimization)
    @Published public var nghiBufferedDuration: Double = 0.0
    @Published public var currentThermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

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
    private var normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent("")

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
        if tool == "nghitts" {
            scheduleNghiWarmUp()
        }
    }

    private func scheduleNghiWarmUp() {
        nghiWarmUpTask?.cancel()
        guard tool == "nghitts" else {
            nghiWarmUpTask = nil
            return
        }
        guard let service = nghiTTSService else { return }
        let voice = selectedVoice
        nghiWarmUpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await Task.detached(priority: .utility) {
                    await TextPreprocessor.shared.warmUp()
                    try await service.prepare(voice: voice)
                }.value
            } catch is CancellationError {
                return
            } catch {
                AppLogger.shared.log("[TTSPerf] NghiTTS warm-up failed: \(error.localizedDescription)")
            }
            await MainActor.run {
                self?.nghiWarmUpTask = nil
            }
        }
    }

    private func playbackParagraphs(from baseParagraphs: [TTSParagraph]) -> [TTSParagraph] {
        guard tool == "nghitts" else { return baseParagraphs }
        return NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)
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

        configureNghiAudioPlayerQueueCallbacks()
        isInitializing = false
        loadParamsForCurrentTool()

        setupEngines()
        setupAudioEngine()
        setupRemoteCommandCenter()
        setupInterruptionObserver()

        NotificationCenter.default.publisher(for: NSNotification.Name("translationDictionariesDidUpdate"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let updatedBookId = notification.userInfo?["bookId"] as? String
                if updatedBookId == nil || updatedBookId == self.playingBookId {
                    self.nextChapterPrefetcher.cancel()
                    self.nowPlayingUpdateGeneration &+= 1
                    self.nowPlayingMetadataTask?.cancel()
                    self.nowPlayingMetadataTask = nil
                    self.nowPlayingMetadataTaskKey = nil
                    self.nowPlayingStaticMetadata = nil
                    if self.showFloatingWidget {
                        self.updateNowPlayingInfo()
                    }
                }
            }
            .store(in: &cancellables)
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
            let savedDelay = UserDefaults.standard.object(forKey: "nghittsPrefetchDelay") != nil ? UserDefaults.standard.integer(forKey: "nghittsPrefetchDelay") : 500
            self.prefetchDelayMs = savedDelay >= 300 ? savedDelay : 500
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
        if isAudioSessionConfigured,
           session.category == .playback,
           session.mode == .spokenAudio {
            return
        }
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            isAudioSessionConfigured = true
        } catch {
            isAudioSessionConfigured = false
            AppLogger.shared.log("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
        #if DEBUG
        logRemoteTrace("configureAudioSession") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
    }

    private func updatePlaybackParams() {
        if isPlaying {
            if tool == "system" {
                // AVSpeechSynthesizer
            } else if tool == "nghitts" {
                nghiAudioPlayerQueue.updateRate(speed)
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
        let isTransEnabled = TranslateUtils.isTranslationEnabled

        let preparedKey = TTSPreparedChapterKey(
            bookId: bookId,
            chapterIndex: currentIndex,
            chapterTitle: currentChapter.title,
            content: chapterContent,
            chunkLength: chunkLength,
            includeChapterTitle: showTitle,
            isTranslationEnabled: isTransEnabled,
            translationToken: TranslateUtils.translationGenerationToken(for: bookId)
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
                    shouldTranslateRawContent: isTransEnabled,
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
        resumeIdentity: TTSChunkResumeIdentity? = nil,
        bookTitle: String,
        coverUrl: String = "",
        bookDetailUrl: String = "",
        bookSourceName: String = "",
        extensionInfo: TTSExtensionInfo?,
        snapshot: TTSPretranslatedSnapshot? = nil
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
        let isTransEnabled = TranslateUtils.isTranslationEnabled
        self.sessionTranslationEnabled = isTransEnabled
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
            includeChapterTitle: showTitle,
            isTranslationEnabled: isTransEnabled,
            translationToken: TranslateUtils.translationGenerationToken(for: bookId)
        )

        if preparedChapterKey == requestedKey, let preparedChapter {
            self.chapterTitle = isTransEnabled && TranslateUtils.containsChinese(expectedTitle)
                ? TranslateUtils.translateChapterTitle(expectedTitle, bookId: bookId)
                : expectedTitle
            self.normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(preparedChapter.normalizedContent)
            self.chapterContent = preparedChapter.normalizedContent
            self.paragraphs = playbackParagraphs(from: preparedChapter.paragraphs)
            self.continueStartSpeaking(startParagraphIndex: startParagraphIndex, startTextOffset: startTextOffset, resumeIdentity: resumeIdentity)
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
                    shouldTranslateRawContent: isTransEnabled,
                    includeChapterTitle: showTitle,
                    sessionID: newSessionID,
                    generation: currentGen,
                    snapshot: snapshot
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
                self.chapterTitle = processed.chapterTitle
                self.normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(processed.normalizedContent)
                self.chapterContent = processed.normalizedContent
                self.paragraphs = self.playbackParagraphs(from: processed.paragraphs)
                self.continueStartSpeaking(startParagraphIndex: startParagraphIndex, startTextOffset: startTextOffset, resumeIdentity: resumeIdentity)
                self.triggerNextChapterPrefetch()
            } catch is CancellationError {
                return
            } catch {
                AppLogger.shared.log("[TTSManager] Không thể bắt đầu TTS: \(error.localizedDescription)")
            }
        }
    }

    public func findTargetChunkIndex(
        startParagraphIndex: Int,
        startTextOffset: Int? = nil,
        resumeIdentity: TTSChunkResumeIdentity? = nil
    ) -> Int {
        guard !paragraphs.isEmpty else { return 0 }

        if let identity = resumeIdentity {
            if identity.sourceLineId == -1 {
                return 0
            }
            let matching = paragraphs.enumerated().filter { $0.element.paragraphIndex == identity.sourceLineId }
            if !matching.isEmpty {
                if let found = matching.first(where: {
                    let range = $0.element.sourceRange
                    return range.location != NSNotFound && range.location <= identity.sourceOffset && identity.sourceOffset < NSMaxRange(range)
                }) {
                    return found.offset
                }
                if identity.chunkOrdinal >= 0 && identity.chunkOrdinal < matching.count {
                    return matching[identity.chunkOrdinal].offset
                }
                return matching.first!.offset
            }
        }

        if startParagraphIndex == -1 {
            return 0
        }
        let matchingChunks = paragraphs.enumerated().filter { $0.element.paragraphIndex == startParagraphIndex }
        if matchingChunks.isEmpty {
            return 0
        }

        if let offset = startTextOffset, offset != NSNotFound, offset >= 0 {
            if let exact = matchingChunks.first(where: {
                let r = $0.element.sourceRange.location != NSNotFound ? $0.element.sourceRange : $0.element.range
                return r.location <= offset && offset < NSMaxRange(r)
            }) {
                return exact.offset
            }
            if let exactRange = matchingChunks.first(where: {
                $0.element.range.location <= offset && offset < NSMaxRange($0.element.range)
            }) {
                return exactRange.offset
            }
        }
        return matchingChunks.first!.offset
    }

    private func continueStartSpeaking(startParagraphIndex: Int, startTextOffset: Int? = nil, resumeIdentity: TTSChunkResumeIdentity? = nil) {
        let targetIdx = findTargetChunkIndex(startParagraphIndex: startParagraphIndex, startTextOffset: startTextOffset, resumeIdentity: resumeIdentity)
        self.currentParagraphIndex = targetIdx
        if targetIdx >= 0 && targetIdx < paragraphs.count {
            self.currentParentParagraphIndex = paragraphs[targetIdx].paragraphIndex
        }
        self.isPlaying = true
        setSystemNowPlayingPlaybackState(.playing)
        self.syncRemoteCommandState()

        speakCurrent()
    }



    public func pause() {
        #if DEBUG
        logRemoteTrace("pause()") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
        guard isPlaying else { return }
        finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "pause")
        checkpointProgressAndRelease()
        self.isPlaying = false
        self.lastPausedTime = Date()
        setSystemNowPlayingPlaybackState(.paused)

        if tool == "system" {
            siriService.pause()
        } else if tool == "nghitts" {
            cancelNghiRefill()
            nghiAudioPlayerQueue.pause()
            nextChapterPrefetcher.cancel()
            Task { await PiperSynthesisCoordinator.shared.cancelAllPending() }
        } else {
            let hasPreparedPlayer = audioPlayer != nil
            remotePlaybackTask?.cancel()
            remotePlaybackTask = nil
            cancelRemotePrefetchTasks()
            nextChapterPrefetcher.cancel()
            if !hasPreparedPlayer {
                currentPlaybackId = nil
            }
            audioPlayer?.pause()
        }
        syncRemoteCommandState()
        updateNowPlayingInfo()
    }

    public func resume() {
        #if DEBUG
        logRemoteTrace("resume()", details: "isPlayingBefore:\(isPlaying)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
        if isPlaying {
            if tool == "system" {
                siriService.resume()
            } else if tool == "nghitts" {
                if nghiAudioPlayerQueue.resume() {
                    isPlaying = true
                    updatePrefetchWindow()
                    prepareNextNghiAudioIfPossible()
                } else {
                    speakCurrent()
                }
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
        } else if tool == "nghitts" {
            let timeSincePause = lastPausedTime.map { Date().timeIntervalSince($0) } ?? 0.0
            if timeSincePause > 5.0 || currentPlaybackId == nil {
                nghiAudioPlayerQueue.stop()
                speakCurrent()
            } else if nghiAudioPlayerQueue.resume() {
                updatePrefetchWindow()
                prepareNextNghiAudioIfPossible()
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
        finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "stop")
        finishTTSPrefetchPerfSummary()
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
        nowPlayingMetadataTask?.cancel()
        nowPlayingMetadataTask = nil
        nowPlayingMetadataTaskKey = nil
        nowPlayingStaticMetadata = nil
        nowPlayingCoverDownloadKey = nil

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
            isAudioSessionConfigured = false
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
            self.normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(chapterContent)
        }

        // Nạp lại phân đoạn
        self.paragraphs = playbackParagraphs(from: TTSParagraphBuilder.build(from: normalizedChapterText, chunkLength: chunkLength))

        // Memory leak fix: Clear prefetch cache AFTER paragraph rebuild to remove stale audio from old VietPhrase settings
        if tool != "system" {
            clearPrefetchCache()
        }

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
        if activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
            finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "skip")
        }
        let nextIndex: Int?
        if tool == "nghitts" {
            let currentParent = paragraphs[currentParagraphIndex].paragraphIndex
            nextIndex = paragraphs.indices.dropFirst(currentParagraphIndex + 1).first {
                paragraphs[$0].paragraphIndex != currentParent
            }
        } else {
            let candidate = currentParagraphIndex + 1
            nextIndex = candidate < paragraphs.count ? candidate : nil
        }

        if let nextIndex {
            stopCurrentPlayback()
            currentParagraphIndex = nextIndex
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
        guard isPlaying else { return }
        if activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
            finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "skip")
        }
        let previousIndex: Int?
        if tool == "nghitts", currentParagraphIndex > 0 {
            let currentParent = paragraphs[currentParagraphIndex].paragraphIndex
            if let previousParentIndex = (0..<currentParagraphIndex).reversed().first(where: {
                paragraphs[$0].paragraphIndex != currentParent
            }) {
                let previousParent = paragraphs[previousParentIndex].paragraphIndex
                previousIndex = paragraphs.indices.first(where: {
                    paragraphs[$0].paragraphIndex == previousParent
                })
            } else {
                previousIndex = nil
            }
        } else {
            previousIndex = currentParagraphIndex > 0 ? currentParagraphIndex - 1 : nil
        }

        if let previousIndex {
            stopCurrentPlayback()
            currentParagraphIndex = previousIndex
            currentParentParagraphIndex = paragraphs[currentParagraphIndex].paragraphIndex
            highlightRange = nil
            checkpointProgress()
            speakCurrent()
        }
    }

    private func stopCurrentPlayback() {
        self.currentPlaybackId = nil
        if tool == "system" {
            siriService.stop()
        } else {
            stopCurrentHardwarePlayer()
        }
        cleanUpTempFile()
    }

    private func nextParagraph() {
        guard isPlaying else { return }
        if activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
            finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "skip")
        }
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

    private func makeNextChapterKey(for chapter: TTSChapterInfo) -> TTSPreparedNextChapterKey {
        let key = "showChapterTitle_\(playingBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
        return TTSPreparedNextChapterKey(
            bookId: playingBookId,
            chapterIndex: chapter.index,
            chapterUrl: chapter.url,
            chapterHost: chapter.host,
            chapterTitle: chapter.title,
            tool: tool,
            selectedVoice: selectedVoice,
            chunkLength: chunkLength,
            includeChapterTitle: showTitle,
            isTranslationEnabled: self.sessionTranslationEnabled,
            translationToken: TranslateUtils.translationGenerationToken(for: playingBookId),
            extensionLocalPath: extensionLocalPath,
            extensionConfigJson: extensionConfigJson
        )
    }

    private func advanceToNextChapter(nextIdx: Int) {
        guard let nextChapter = chaptersQueue.first(where: { $0.index == nextIdx }) else { return }
        let expectedSessionID = sessionID
        self.ttsProcessingGeneration += 1
        let expectedGeneration = self.ttsProcessingGeneration
        let expectedBookId = playingBookId
        let expectedChapterURL = nextChapter.url

        createTTSAutoAdvancePerf(
            sessionID: expectedSessionID,
            generation: expectedGeneration,
            chapterIndex: nextChapter.index,
            engine: tool
        )

        let requestedKey = makeNextChapterKey(for: nextChapter)
        let consumedState = nextChapterPrefetcher.consumeCache(matching: requestedKey)

        switch consumedState {
        case .audioReady(_, _, let processed, let audioData, _, _, _):
            updateTTSAutoAdvanceLoadPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                loadMs: 0.0,
                origin: "next_prefetch_audio"
            )
            updateTTSAutoAdvanceProcessPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                processMs: 0.0
            )

            applyNextChapter(
                index: processed.chapterIndex,
                content: processed.normalizedContent,
                title: processed.chapterTitle,
                paragraphs: processed.paragraphs,
                chapter: nextChapter,
                firstAudioData: audioData
            )

        case .processedReady(_, _, let processed, _, _),
             .synthesizingAudio(_, _, let processed, _, _):
            updateTTSAutoAdvanceLoadPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                loadMs: 0.0,
                origin: "next_prefetch_dto"
            )
            updateTTSAutoAdvanceProcessPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                processMs: 0.0
            )

            applyNextChapter(
                index: processed.chapterIndex,
                content: processed.normalizedContent,
                title: processed.chapterTitle,
                paragraphs: processed.paragraphs,
                chapter: nextChapter,
                firstAudioData: nil
            )

        default:
            fallbackAdvanceToNextChapter(
                nextChapter: nextChapter,
                expectedSessionID: expectedSessionID,
                expectedGeneration: expectedGeneration,
                expectedBookId: expectedBookId,
                expectedChapterURL: expectedChapterURL
            )
        }
    }

    private func fallbackAdvanceToNextChapter(
        nextChapter: TTSChapterInfo,
        expectedSessionID: UUID,
        expectedGeneration: Int,
        expectedBookId: String,
        expectedChapterURL: String
    ) {
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
        let isTransEnabled = self.sessionTranslationEnabled
        let key = "showChapterTitle_\(expectedBookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
        let rawTitle = nextChapter.title
        let processor = TTSBackgroundProcessor()

        let isPerfLogging = AppLogger.shared.isLoggingEnabled
        let perfStartUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0

        Task { [weak self] in
            let result: ChapterContentResult
            do {
                result = try await ChapterContentRepository.shared.load(request)
            } catch {
                let loadEndUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
                let loadMs = isPerfLogging ? (loadEndUptime - perfStartUptime) * 1000 : 0
                if isPerfLogging {
                    await MainActor.run {
                        self?.updateTTSAutoAdvanceLoadPerf(
                            sessionID: expectedSessionID,
                            generation: expectedGeneration,
                            chapterIndex: nextChapter.index,
                            loadMs: loadMs,
                            origin: "unknown"
                        )
                        self?.finishTTSAutoAdvancePerf(
                            outcome: "load_failed",
                            endpoint: "error",
                            sessionID: expectedSessionID,
                            generation: expectedGeneration,
                            chapterIndex: nextChapter.index
                        )
                    }
                }
                guard let self,
                      self.sessionID == expectedSessionID,
                      self.playingBookId == expectedBookId else { return }
                AppLogger.shared.log("❌ [TTSManager] Không tải được chương \(nextChapter.index): \(error.localizedDescription)")
                await MainActor.run {
                    self.stop()
                    self.onChapterFinished?()
                }
                return
            }

            let loadEndUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
            let loadMs = isPerfLogging ? (loadEndUptime - perfStartUptime) * 1000 : 0
            let originStr: String
            switch result.origin {
            case .memory:
                originStr = "memory"
            case .persistentCache:
                originStr = "persistentCache"
            case .extensionFetch:
                originStr = "extensionFetch"
            }

            if isPerfLogging {
                await MainActor.run {
                    self?.updateTTSAutoAdvanceLoadPerf(
                        sessionID: expectedSessionID,
                        generation: expectedGeneration,
                        chapterIndex: nextChapter.index,
                        loadMs: loadMs,
                        origin: originStr
                    )
                }
            }

            guard let self,
                  self.isPlaying,
                  self.sessionID == expectedSessionID,
                  self.ttsProcessingGeneration == expectedGeneration,
                  self.playingBookId == expectedBookId,
                  self.chaptersQueue.first(where: { $0.index == nextChapter.index })?.url == expectedChapterURL,
                  self.playingChapterIndex < nextChapter.index else {
                if isPerfLogging {
                    await MainActor.run {
                        self?.finishTTSAutoAdvancePerf(
                            outcome: "superseded",
                            endpoint: "superseded",
                            sessionID: expectedSessionID,
                            generation: expectedGeneration,
                            chapterIndex: nextChapter.index
                        )
                    }
                }
                return
            }

            let rawContent = result.document.text.content

            let processed: ProcessedChapterDTO
            do {
                processed = try await processor.processChapter(
                    bookId: expectedBookId,
                    chapterIndex: nextChapter.index,
                    chapterTitle: rawTitle,
                    rawContent: rawContent,
                    chunkLength: chunkLen,
                    shouldTranslateRawContent: isTransEnabled,
                    includeChapterTitle: showTitle,
                    sessionID: expectedSessionID,
                    generation: expectedGeneration
                )
            } catch {
                let processEndUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
                let processMs = isPerfLogging ? (processEndUptime - loadEndUptime) * 1000 : 0
                if isPerfLogging {
                    await MainActor.run {
                        self.updateTTSAutoAdvanceProcessPerf(
                            sessionID: expectedSessionID,
                            generation: expectedGeneration,
                            chapterIndex: nextChapter.index,
                            processMs: processMs
                        )
                        self.finishTTSAutoAdvancePerf(
                            outcome: "process_failed",
                            endpoint: "error",
                            sessionID: expectedSessionID,
                            generation: expectedGeneration,
                            chapterIndex: nextChapter.index
                        )
                    }
                }
                await MainActor.run {
                    self.stop()
                    self.onChapterFinished?()
                }
                return
            }

            let processEndUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
            let processMs = isPerfLogging ? (processEndUptime - loadEndUptime) * 1000 : 0

            await MainActor.run {
                guard self.isPlaying,
                      self.sessionID == processed.sessionID,
                      self.ttsProcessingGeneration == processed.generation,
                      self.playingBookId == processed.bookId else {
                    if isPerfLogging {
                        self.finishTTSAutoAdvancePerf(
                            outcome: "superseded",
                            endpoint: "superseded",
                            sessionID: expectedSessionID,
                            generation: expectedGeneration,
                            chapterIndex: nextChapter.index
                        )
                    }
                    return
                }
                if isPerfLogging {
                    self.updateTTSAutoAdvanceProcessPerf(
                        sessionID: expectedSessionID,
                        generation: expectedGeneration,
                        chapterIndex: processed.chapterIndex,
                        processMs: processMs
                    )
                }
                self.applyNextChapter(index: processed.chapterIndex, content: processed.normalizedContent, title: processed.chapterTitle, paragraphs: processed.paragraphs, chapter: nextChapter)
            }
        }
    }

    private func applyNextChapter(
        index: Int,
        content: String,
        title: String,
        paragraphs: [TTSParagraph],
        chapter: TTSChapterInfo,
        firstAudioData: Data? = nil
    ) {
        checkpointProgress()
        self.playingChapterIndex = index
        self.playingChapterUrl = chapter.url
        self.chapterTitle = title
        self.normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(content)
        self.chapterContent = content
        self.paragraphs = playbackParagraphs(from: paragraphs)
        self.clearCurrentParagraphPrefetchCache()

        if let audioData = firstAudioData {
            self.preloadedData[0] = audioData
            self.preloadedDurations[0] = WAVEncoder.duration(of: audioData)
        }

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
              let nextChapter = chaptersQueue.first(where: { $0.index == nextIdx }) else {
            nextChapterPrefetcher.cancel()
            return
        }

        let key = makeNextChapterKey(for: nextChapter)
        nextChapterPrefetcher.startPrefetch(
            key: key,
            sessionID: sessionID,
            generation: ttsProcessingGeneration,
            extensionInfo: extensionInfo,
            processor: TTSBackgroundProcessor(),
            googleService: googleService,
            extService: extService
        )
    }

    private func checkAndPromoteNextChapterAudioIfNeeded() {
        guard isPlaying,
              tool != "system",
              currentParagraphIndex >= 0,
              currentParagraphIndex < paragraphs.count,
              !nextChapterPrefetcher.reservesNghiAudioSlot else { return }

        if tool == "nghitts" {
            guard NghiSynthesisPolicy.allowsNextChapterAudio(at: currentThermalState) else {
                return
            }
        } else if currentThermalState == .serious || currentThermalState == .critical {
            return
        }

        var remainingParents = Set<Int>()
        for index in currentParagraphIndex..<paragraphs.count {
            remainingParents.insert(paragraphs[index].paragraphIndex)
            if remainingParents.count > 2 { return }
        }

        nextChapterPrefetcher.promoteAudioIfNeeded(
            nghiService: nghiTTSService,
            googleService: googleService,
            extService: extService
        )
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

        // AppLogger.shared.logTTSVerbose("🔊 [TTSManager] Chunk [\(currentParagraphIndex + 1)/\(paragraphs.count)] (ParentID=\(paragraph.paragraphIndex)): Raw='\(paragraph.text.prefix(20))...' | Processed='\(textToSpeak.prefix(20))...' | highlightRange=\(paragraph.range)")

        guard !textToSpeak.isEmpty else {
            if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
                finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "empty_chunk")
            }
            nextParagraph()
            return
        }

        if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
            if preloadedData[0] != nil {
                paragraph0AudioCacheHit = true
            } else {
                paragraph0AudioCacheHit = false
                paragraph0SynthesisStartUptime = ProcessInfo.processInfo.systemUptime
            }
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
        if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
            finishTTSAutoAdvancePerf(
                outcome: "played",
                endpoint: "dispatch",
                sessionID: sessionID,
                generation: ttsProcessingGeneration,
                chapterIndex: playingChapterIndex,
                synthesisMs: 0.0,
                playerSetupMs: 0.0,
                audioCacheHit: false
            )
        }
        updateNowPlayingInfo()
    }

    public func clearCurrentParagraphPrefetchCache() {
        cancelNghiRefill()
        remotePlaybackTask?.cancel()
        remotePlaybackTask = nil
        cancelRemotePrefetchTasks()
        preloadedData.removeAll()
        preloadedDurations.removeAll()
        nghiAudioPlayerQueue.clearPreparedNext()
        
        if tool != "system" && tool != "nghitts" && tool != "google" {
            extService.cleanupAllTempFiles()
        }
    }

    public func clearAllTTSCaches() {
        clearCurrentParagraphPrefetchCache()
        nextChapterPrefetcher.cancel()
        Task { await extService.resetRuntime() }
    }

    public func clearPrefetchCache() {
        clearAllTTSCaches()
    }

    private func cancelRemotePrefetchTasks() {
        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()
        prefetchTaskGenerations.removeAll()
    }

    // updatePrefetchWindow: Cập nhật cửa sổ trượt (Sliding Window) tải trước dữ liệu âm thanh
    // Mục tiêu: Luôn có sẵn âm thanh PCMBuffer của đoạn tiếp theo (N+1) trong bộ đệm để phát ngay khi đoạn hiện tại (N) kết thúc, triệt tiêu hoàn toàn khoảng trễ tổng hợp âm thanh.
    private func updatePrefetchWindow() {
        guard isPlaying, tool != "system" else { return }

        if tool == "nghitts" {
            updateNghiPrefetchWindow()
            return
        }

        if currentThermalState == .critical {
            cancelRemotePrefetchTasks()
            nextChapterPrefetcher.cancel()
            return
        }

        let N = currentParagraphIndex
        if currentThermalState == .serious {
            nextChapterPrefetcher.cancel()
        }
        let configuredCount = max(1, min(10, currentPrefetchCount))
        let count = currentThermalState == .serious ? 1 : configuredCount
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
            prefetchTaskGenerations.removeValue(forKey: idx)
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
        checkAndPromoteNextChapterAudioIfNeeded()
    }

    private func cancelNghiRefill() {
        nghiRefillGeneration &+= 1
        nghiRefillTask?.cancel()
        nghiRefillTask = nil
        nghiRefillInFlightIndex = nil
        Task { await PiperSynthesisCoordinator.shared.cancelAllPending() }
    }

    public var nghiWatermarks: (low: Double, high: Double) {
        NghiSynthesisPolicy.watermarks(for: currentThermalState)
    }

    public func calculateNghiBufferedDuration() -> Double {
        guard tool == "nghitts" else { return 0.0 }
        let effectiveRate = max(0.5, speed)
        var total: Double = 0.0

        if let player = nghiAudioPlayerQueue.currentPlayer, player.isPlaying {
            let remainingMedia = max(0, player.duration - player.currentTime)
            total += remainingMedia / max(0.01, Double(player.rate))
        }

        for (idx, data) in preloadedData where idx > currentParagraphIndex {
            let dur = preloadedDurations[idx] ?? WAVEncoder.duration(of: data)
            total += dur / effectiveRate
        }

        return total
    }

    public func updateNghiBufferedDuration() {
        let dur = calculateNghiBufferedDuration()
        if abs(nghiBufferedDuration - dur) > 0.05 {
            nghiBufferedDuration = dur
        }
    }

    private func nghiFutureTargetIndices() -> [Int] {
        let N = currentParagraphIndex
        let watermarks = nghiWatermarks
        guard N + 1 < paragraphs.count else { return [] }

        var targetIndices: [Int] = []
        let nextIndex = N + 1
        targetIndices.append(nextIndex)

        var currentBuf = calculateNghiBufferedDuration()
        var idx = N + 2
        while idx < paragraphs.count && currentBuf < watermarks.high {
            targetIndices.append(idx)
            if let dur = preloadedDurations[idx] {
                currentBuf += dur / max(0.5, speed)
            } else {
                currentBuf += 3.0 / max(0.5, speed)
            }
            idx += 1
        }

        return targetIndices
    }

    private func updateNghiPrefetchWindow() {
        updateNghiBufferedDuration()

        guard NghiSynthesisPolicy.allowsSpeculativeRefill(at: currentThermalState) else {
            if nghiRefillTask != nil || nghiRefillInFlightIndex != nil {
                cancelNghiRefill()
            }
            prepareNextNghiAudioIfPossible()
            return
        }

        let targetIndices = nghiFutureTargetIndices()
        let keepIndices = Set([currentParagraphIndex] + targetIndices)

        if let inFlight = nghiRefillInFlightIndex, !targetIndices.contains(inFlight) {
            cancelNghiRefill()
        }

        for index in Array(preloadedData.keys) where !keepIndices.contains(index) {
            preloadedData.removeValue(forKey: index)
            preloadedDurations.removeValue(forKey: index)
        }

        updateNghiBufferedDuration()
        prepareNextNghiAudioIfPossible()
        scheduleNghiRefill()
        checkAndPromoteNextChapterAudioIfNeeded()
    }

    private func isValidNghiRefillContext(
        sessionID expectedSessionID: UUID,
        bookID expectedBookID: String,
        chapterIndex expectedChapterIndex: Int,
        chapterURL expectedChapterURL: String,
        voice expectedVoice: String,
        generation expectedGeneration: Int,
        refillGeneration expectedRefillGeneration: UInt64
    ) -> Bool {
        !Task.isCancelled &&
        isPlaying &&
        tool == "nghitts" &&
        sessionID == expectedSessionID &&
        playingBookId == expectedBookID &&
        playingChapterIndex == expectedChapterIndex &&
        playingChapterUrl == expectedChapterURL &&
        selectedVoice == expectedVoice &&
        ttsProcessingGeneration == expectedGeneration &&
        nghiRefillGeneration == expectedRefillGeneration
    }

    private func scheduleNghiRefill() {
        guard isPlaying,
              tool == "nghitts",
              NghiSynthesisPolicy.allowsSpeculativeRefill(at: currentThermalState),
              nghiRefillTask == nil,
              let service = nghiTTSService else { return }

        let expectedSessionID = sessionID
        let expectedBookID = playingBookId
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl
        let expectedVoice = selectedVoice
        let expectedGeneration = ttsProcessingGeneration
        nghiRefillGeneration &+= 1
        let refillGeneration = nghiRefillGeneration

        nghiRefillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.nghiRefillGeneration == refillGeneration {
                    self.nghiRefillInFlightIndex = nil
                    self.nghiRefillTask = nil
                    self.updateNghiBufferedDuration()
                }
            }

            while self.isValidNghiRefillContext(
                sessionID: expectedSessionID,
                bookID: expectedBookID,
                chapterIndex: expectedChapterIndex,
                chapterURL: expectedChapterURL,
                voice: expectedVoice,
                generation: expectedGeneration,
                refillGeneration: refillGeneration
            ) {
                let N = self.currentParagraphIndex
                let nextIndex = N + 1
                let watermarks = self.nghiWatermarks
                let currentBuf = self.calculateNghiBufferedDuration()

                let targetIndex: Int?
                if nextIndex < self.paragraphs.count && self.preloadedData[nextIndex] == nil {
                    targetIndex = nextIndex
                } else if currentBuf < watermarks.high {
                    let targets = self.nghiFutureTargetIndices()
                    targetIndex = targets.first(where: { self.preloadedData[$0] == nil })
                } else {
                    targetIndex = nil
                }

                guard let index = targetIndex else { break }

                let paragraph = self.paragraphs[index]
                let text = TTSReplacementManager.shared.applyReplacements(to: paragraph.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { break }

                // Give the SoC a real idle window between speculative ONNX
                // jobs, while preserving at least 1.2 seconds for gapless N+1.
                let configuredCooldown = NghiSynthesisPolicy.refillCooldownMilliseconds(
                    for: self.currentThermalState,
                    configuredDelay: self.prefetchDelayMs
                )
                let safeCooldown = min(
                    configuredCooldown,
                    max(0, Int((currentBuf - 1.2) * 1_000))
                )
                if safeCooldown > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(safeCooldown) * 1_000_000)
                    } catch {
                        return
                    }
                    guard self.isValidNghiRefillContext(
                        sessionID: expectedSessionID,
                        bookID: expectedBookID,
                        chapterIndex: expectedChapterIndex,
                        chapterURL: expectedChapterURL,
                        voice: expectedVoice,
                        generation: expectedGeneration,
                        refillGeneration: refillGeneration
                    ),
                    NghiSynthesisPolicy.allowsSpeculativeRefill(at: self.currentThermalState) else {
                        return
                    }
                }

                self.nghiRefillInFlightIndex = index
                do {
                    let synthesized = try await service.synthesizeWithDuration(
                        text: text,
                        voice: expectedVoice,
                        speed: 1.0,
                        boundaryKind: paragraph.boundaryKind,
                        priority: .normal
                    )
                    guard self.isValidNghiRefillContext(
                        sessionID: expectedSessionID,
                        bookID: expectedBookID,
                        chapterIndex: expectedChapterIndex,
                        chapterURL: expectedChapterURL,
                        voice: expectedVoice,
                        generation: expectedGeneration,
                        refillGeneration: refillGeneration
                    ) else { return }

                    self.nghiRefillInFlightIndex = nil
                    if self.nghiFutureTargetIndices().contains(index) || index == nextIndex {
                        self.preloadedData[index] = synthesized.data
                        self.preloadedDurations[index] = synthesized.pcmDuration
                        self.updateNghiBufferedDuration()
                        self.prepareNextNghiAudioIfPossible()
                        self.checkAndPromoteNextChapterAudioIfNeeded()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.nghiRefillInFlightIndex = nil
                    if AppLogger.shared.isLoggingEnabled {
                        AppLogger.shared.log("[TTSPerf] PrefetchFailure chapter=\(expectedChapterIndex) index=\(index) engine=nghitts")
                    }
                    break
                }

                let updatedBuf = self.calculateNghiBufferedDuration()
                let hasMissingNext = nextIndex < self.paragraphs.count && self.preloadedData[nextIndex] == nil
                guard hasMissingNext || updatedBuf < watermarks.low else { break }

                // The next iteration applies the policy cooldown before work.
            }
        }
    }

    @MainActor
    private func removePrefetchTask(for index: Int, taskGen: UInt64) {
        if prefetchTaskGenerations[index] == taskGen {
            prefetchTasks.removeValue(forKey: index)
            prefetchTaskGenerations.removeValue(forKey: index)
            checkAndPromoteNextChapterAudioIfNeeded()
        }
    }

    private func startPrefetchTask(for index: Int) {
        if tool == "nghitts" {
            scheduleNghiRefill()
            return
        }
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

        nextPrefetchTaskGeneration += 1
        let taskGen = nextPrefetchTaskGeneration
        prefetchTaskGenerations[index] = taskGen

        let localPath = extensionLocalPath
        let configJson = extensionConfigJson
        let googleService = self.googleService
        let extService = self.extService
        let synthesisKey = "paragraph|\(expectedSessionID.uuidString)|\(expectedChapterIndex)|\(index)|\(toolBeforeStart)|\(voice)"

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.removePrefetchTask(for: index, taskGen: taskGen)
            }

            let offset = max(0, index - self.currentParagraphIndex)
            if offset >= 1 {
                let thermalDelay = self.currentThermalState == .fair ? 500 : 0
                let delayStepMs = max(500, self.prefetchDelayMs + thermalDelay)
                do {
                    try await Task.sleep(nanoseconds: UInt64(offset * delayStepMs) * 1_000_000)
                } catch {
                    return
                }
            }

            @MainActor
            func isValidSession() -> Bool {
                // Avoid a chained `&&` expression here. In Swift 6 each RHS is
                // evaluated through a nonisolated autoclosure, which cannot read
                // these MainActor-isolated properties even though the task itself
                // runs on MainActor.
                if Task.isCancelled { return false }
                if !self.isPlaying { return false }
                if self.sessionID != expectedSessionID { return false }
                if self.playingBookId != expectedBookId { return false }
                if self.playingChapterIndex != expectedChapterIndex { return false }
                if self.playingChapterUrl != expectedChapterURL { return false }
                if self.selectedVoice != voice { return false }
                if self.tool != toolBeforeStart { return false }
                if self.currentThermalState == .critical { return false }
                if self.currentThermalState == .serious {
                    let currentIndex = self.currentParagraphIndex
                    if index != currentIndex && index != currentIndex + 1 { return false }
                }
                return true
            }

            guard isValidSession() else { return }

            do {
                let data = try await RemoteTTSSynthesisCoordinator.shared.synthesize(
                    key: synthesisKey,
                    engine: toolBeforeStart,
                    textLength: text.count,
                    priority: .prefetch
                ) {
                    if toolBeforeStart == "google" {
                        return try await googleService.synthesize(text: text, voice: voice, speed: 1.0, pitch: 1.0)
                    }
                    return try await extService.synthesizeData(
                        text: text,
                        voice: voice,
                        localPath: localPath,
                        configJson: configJson
                    )
                }

                guard isValidSession() else { return }
                self.preloadedData[index] = data
            } catch is CancellationError {
                return
            } catch {
                guard isValidSession() else { return }
                if AppLogger.shared.isLoggingEnabled {
                    AppLogger.shared.log("⚠️ [TTSPerf] PrefetchFailure chapter=\(expectedChapterIndex) index=\(index) engine=\(toolBeforeStart): \(error.localizedDescription)")
                }
            }
        }
        prefetchTasks[index] = task
    }

    private func configureNghiAudioPlayerQueueCallbacks() {
        nghiAudioPlayerQueue.onTransition = { [weak self] item in
            self?.handleNghiAudioTransition(item)
        }
        nghiAudioPlayerQueue.onFinished = { [weak self] item, success in
            self?.handleNghiAudioFinished(item, successfully: success)
        }
    }

    private func prepareNextNghiAudioIfPossible() {
        guard tool == "nghitts",
              isPlaying,
              nghiAudioPlayerQueue.isPlaying else { return }

        let nextIndex = currentParagraphIndex + 1
        guard nextIndex >= 0, nextIndex < paragraphs.count else {
            nghiAudioPlayerQueue.clearPreparedNext()
            return
        }

        if nghiAudioPlayerQueue.nextItem?.paragraphIndex == nextIndex {
            return
        }

        guard let data = preloadedData[nextIndex] else { return }

        let item = NghiAudioPlayerQueue.Item(
            paragraphIndex: nextIndex,
            playbackId: String(UUID().uuidString.prefix(4))
        )

        do {
            try nghiAudioPlayerQueue.prepareNext(data: data, item: item)
            if AppLogger.shared.isLoggingEnabled {
                AppLogger.shared.log("🔊 [TTSPerf] NghiPreparedHandoff index=\(nextIndex)")
            }
        } catch {
            AppLogger.shared.log("⚠️ [TTSPerf] NghiPreparedHandoff failed index=\(nextIndex): \(error.localizedDescription)")
            preloadedData.removeValue(forKey: nextIndex)
            preloadedDurations.removeValue(forKey: nextIndex)
        }
    }

    private func commitParagraphState(index: Int, playbackId: String) {
        guard index >= 0 && index < paragraphs.count else { return }
        currentParagraphIndex = index
        currentPlaybackId = playbackId

        let paragraph = paragraphs[index]
        highlightRange = paragraph.range
        currentParentParagraphIndex = paragraph.paragraphIndex
        recordProgressInMemory()

        updatePrefetchWindow()
        updateNowPlayingInfo()
    }

    private func handleNghiAudioTransition(_ item: NghiAudioPlayerQueue.Item) {
        guard isPlaying,
              tool == "nghitts",
              item.paragraphIndex == currentParagraphIndex + 1,
              item.paragraphIndex < paragraphs.count else {
            nghiAudioPlayerQueue.stop()
            return
        }

        preloadedData.removeValue(forKey: item.paragraphIndex)
        preloadedDurations.removeValue(forKey: item.paragraphIndex)
        commitParagraphState(index: item.paragraphIndex, playbackId: item.playbackId)

        if AppLogger.shared.isLoggingEnabled {
            AppLogger.shared.log("🔊 [TTSPerf] NghiScheduledHandoff index=\(item.paragraphIndex)")
        }
    }

    private func handleNghiAudioFinished(_ item: NghiAudioPlayerQueue.Item, successfully flag: Bool) {
        guard tool == "nghitts" else { return }

        if item.paragraphIndex != currentParagraphIndex {
            if !flag {
                preloadedData.removeValue(forKey: item.paragraphIndex)
                preloadedDurations.removeValue(forKey: item.paragraphIndex)
                if isPlaying,
                   item.paragraphIndex > currentParagraphIndex,
                   item.paragraphIndex < paragraphs.count {
                    scheduleNghiRefill()
                }
            }
            return
        }

        guard currentPlaybackId == item.playbackId else { return }
        if flag {
            nextParagraph()
        } else {
            AppLogger.shared.log("⚠️ [TTSManager] NghiTTS AVAudioPlayer phát kết thúc không thành công")
            currentPlaybackId = nil
            isPlaying = false
            syncRemoteCommandState()
            updateNowPlayingInfo()
        }
    }

    private func playNghiAudioData(_ audioData: Data, playbackId: String) {
        cleanUpTempFile()
        stopCurrentHardwarePlayer()

        let setupStart = ProcessInfo.processInfo.systemUptime
        do {
            configureAudioSession()
            let item = NghiAudioPlayerQueue.Item(
                paragraphIndex: currentParagraphIndex,
                playbackId: playbackId
            )
            try nghiAudioPlayerQueue.start(data: audioData, item: item, rate: speed)
            currentPlaybackId = playbackId
            isPlaying = true
            preloadedData.removeValue(forKey: currentParagraphIndex)
            preloadedDurations.removeValue(forKey: currentParagraphIndex)

            let setupEnd = ProcessInfo.processInfo.systemUptime
            if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
                let playerSetupMs = (setupEnd - setupStart) * 1000
                let synMs = currentParagraph0SynthesisMs(untilUptime: setupStart)
                finishTTSAutoAdvancePerf(
                    outcome: "played",
                    endpoint: "player_play",
                    sessionID: sessionID,
                    generation: ttsProcessingGeneration,
                    chapterIndex: playingChapterIndex,
                    synthesisMs: synMs,
                    playerSetupMs: playerSetupMs,
                    audioCacheHit: paragraph0AudioCacheHit
                )
            }

            prepareNextNghiAudioIfPossible()
        } catch {
            let setupEnd = ProcessInfo.processInfo.systemUptime
            if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
                let playerSetupMs = (setupEnd - setupStart) * 1000
                let synMs = currentParagraph0SynthesisMs(untilUptime: setupStart)
                finishTTSAutoAdvancePerf(
                    outcome: "player_failed",
                    endpoint: "error",
                    sessionID: sessionID,
                    generation: ttsProcessingGeneration,
                    chapterIndex: playingChapterIndex,
                    synthesisMs: synMs,
                    playerSetupMs: playerSetupMs,
                    audioCacheHit: paragraph0AudioCacheHit
                )
            }
            AppLogger.shared.log("❌ [TTSManager] [ID=\(playbackId)] Khởi tạo NghiTTS AVAudioPlayer queue thất bại: \(error.localizedDescription)")
            preloadedData.removeValue(forKey: currentParagraphIndex)
            preloadedDurations.removeValue(forKey: currentParagraphIndex)
            currentPlaybackId = nil
            pause()
            ToastManager.shared.show(message: "Lỗi trình phát âm thanh: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
        }

        updateNowPlayingInfo()
    }

    private func playAudioData(_ audioData: Data, withId customId: String? = nil) {
        let playbackId = customId ?? String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        if tool == "nghitts" {
            playNghiAudioData(audioData, playbackId: playbackId)
            return
        }

        cleanUpTempFile()
        stopCurrentHardwarePlayer()

        let setupStart = ProcessInfo.processInfo.systemUptime
        do {
            configureAudioSession()
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.enableRate = true
            player.rate = Float(speed)

            self.audioPlayer = player

            let ok = player.play()
            let setupEnd = ProcessInfo.processInfo.systemUptime
            if ok {
                self.isPlaying = true
                if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
                    let playerSetupMs = (setupEnd - setupStart) * 1000
                    let synMs = currentParagraph0SynthesisMs(untilUptime: setupStart)
                    finishTTSAutoAdvancePerf(
                        outcome: "played",
                        endpoint: "player_play",
                        sessionID: sessionID,
                        generation: ttsProcessingGeneration,
                        chapterIndex: playingChapterIndex,
                        synthesisMs: synMs,
                        playerSetupMs: playerSetupMs,
                        audioCacheHit: paragraph0AudioCacheHit
                    )
                }
            } else {
                if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
                    let playerSetupMs = (setupEnd - setupStart) * 1000
                    let synMs = currentParagraph0SynthesisMs(untilUptime: setupStart)
                    finishTTSAutoAdvancePerf(
                        outcome: "player_failed",
                        endpoint: "error",
                        sessionID: sessionID,
                        generation: ttsProcessingGeneration,
                        chapterIndex: playingChapterIndex,
                        synthesisMs: synMs,
                        playerSetupMs: playerSetupMs,
                        audioCacheHit: paragraph0AudioCacheHit
                    )
                }
                AppLogger.shared.log("❌ [TTSManager] [ID=\(playbackId)] player.play() thất bại")
                self.preloadedData.removeValue(forKey: currentParagraphIndex)
                self.currentPlaybackId = nil
                self.pause()
                ToastManager.shared.show(message: "Lỗi trình phát âm thanh: Không thể phát dữ liệu audio.", type: .error)
            }
        } catch {
            let setupEnd = ProcessInfo.processInfo.systemUptime
            if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
                let playerSetupMs = (setupEnd - setupStart) * 1000
                let synMs = currentParagraph0SynthesisMs(untilUptime: setupStart)
                finishTTSAutoAdvancePerf(
                    outcome: "player_failed",
                    endpoint: "error",
                    sessionID: sessionID,
                    generation: ttsProcessingGeneration,
                    chapterIndex: playingChapterIndex,
                    synthesisMs: synMs,
                    playerSetupMs: playerSetupMs,
                    audioCacheHit: paragraph0AudioCacheHit
                )
            }
            AppLogger.shared.log("❌ [TTSManager] [ID=\(playbackId)] Khởi tạo AVAudioPlayer thất bại: \(error.localizedDescription)")
            self.preloadedData.removeValue(forKey: currentParagraphIndex)
            self.currentPlaybackId = nil
            self.pause()
            ToastManager.shared.show(message: "Lỗi trình phát âm thanh: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
        }

        updateNowPlayingInfo()
    }

    private func stopCurrentHardwarePlayer() {
        nghiAudioPlayerQueue.stop()

        if let player = audioPlayer {
            player.stop()
            player.delegate = nil
            self.audioPlayer = nil
        }
    }

    private func playNghiTTS(_ text: String) {
        guard let service = nghiTTSService else {
            if currentParagraphIndex == 0 && activeTTSAutoAdvancePerf?.chapterIndex == playingChapterIndex {
                let synMs = currentParagraph0SynthesisMs()
                finishTTSAutoAdvancePerf(
                    outcome: "synthesis_failed",
                    endpoint: "error",
                    sessionID: sessionID,
                    generation: ttsProcessingGeneration,
                    chapterIndex: playingChapterIndex,
                    synthesisMs: synMs
                )
            }
            AppLogger.shared.log("NghiTTS engine not initialized.")
            stop()
            return
        }

        let index = currentParagraphIndex
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId
        let expectedSessionID = sessionID
        let expectedBookID = playingBookId
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl
        let expectedGeneration = ttsProcessingGeneration
        let expectedVoice = selectedVoice
        let startupBufferTarget = 1.2

        if let cachedData = preloadedData[index] {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: "nghitts", index: index, outcome: "hit")
            let currentDuration = preloadedDurations[index] ?? WAVEncoder.duration(of: cachedData)
            preloadedDurations[index] = currentDuration
            var bufferedDuration = currentDuration / max(0.5, speed)
            for futureIndex in nghiFutureTargetIndices() {
                guard let futureData = preloadedData[futureIndex] else { break }
                let duration = preloadedDurations[futureIndex] ?? WAVEncoder.duration(of: futureData)
                preloadedDurations[futureIndex] = duration
                bufferedDuration += duration / max(0.5, speed)
                if bufferedDuration >= startupBufferTarget { break }
            }
            if index != 0 || bufferedDuration >= startupBufferTarget {
                self.playAudioData(cachedData, withId: playbackId)
                updatePrefetchWindow()
                return
            }
        } else {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: "nghitts", index: index, outcome: "miss")
        }

        cancelNghiRefill()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                @MainActor func isValidPlaybackRequest() -> Bool {
                    !Task.isCancelled &&
                    self.isPlaying &&
                    self.currentPlaybackId == playbackId &&
                    self.sessionID == expectedSessionID &&
                    self.playingBookId == expectedBookID &&
                    self.playingChapterIndex == expectedChapterIndex &&
                    self.playingChapterUrl == expectedChapterURL &&
                    self.ttsProcessingGeneration == expectedGeneration &&
                    self.selectedVoice == expectedVoice &&
                    self.tool == "nghitts"
                }

                let currentData: Data
                if let cachedData = self.preloadedData[index] {
                    currentData = cachedData
                } else {
                    let boundaryKind = self.paragraphs.indices.contains(index) ? self.paragraphs[index].boundaryKind : .paragraphEnd
                    currentData = try await service.synthesize(
                        text: text,
                        voice: expectedVoice,
                        speed: 1.0,
                        boundaryKind: boundaryKind,
                        priority: .high
                    )
                    guard isValidPlaybackRequest() else { return }
                }

                var bufferedDuration = WAVEncoder.duration(of: currentData) / max(0.5, self.speed)
                for futureIndex in self.nghiFutureTargetIndices() where bufferedDuration < startupBufferTarget {
                    guard isValidPlaybackRequest() else { return }
                    if let cachedData = self.preloadedData[futureIndex] {
                        let duration = self.preloadedDurations[futureIndex] ?? WAVEncoder.duration(of: cachedData)
                        self.preloadedDurations[futureIndex] = duration
                        bufferedDuration += duration / max(0.5, self.speed)
                        continue
                    }

                    let paragraph = self.paragraphs[futureIndex]
                    let futureText = TTSReplacementManager.shared.applyReplacements(to: paragraph.text)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !futureText.isEmpty else { continue }

                    let wavData = try await service.synthesize(
                        text: futureText,
                        voice: expectedVoice,
                        speed: 1.0,
                        boundaryKind: paragraph.boundaryKind,
                        priority: .high
                    )
                    guard isValidPlaybackRequest() else { return }
                    let duration = WAVEncoder.duration(of: wavData)
                    self.preloadedData[futureIndex] = wavData
                    self.preloadedDurations[futureIndex] = duration
                    bufferedDuration += duration / max(0.5, self.speed)
                }

                guard isValidPlaybackRequest() else { return }
                self.playAudioData(currentData, withId: playbackId)
                self.updatePrefetchWindow()
            } catch {
                guard self.currentPlaybackId == playbackId else { return }
                if index == 0 && self.activeTTSAutoAdvancePerf?.chapterIndex == self.playingChapterIndex {
                    let synMs = self.currentParagraph0SynthesisMs()
                    self.finishTTSAutoAdvancePerf(
                        outcome: "synthesis_failed",
                        endpoint: "error",
                        sessionID: self.sessionID,
                        generation: self.ttsProcessingGeneration,
                        chapterIndex: self.playingChapterIndex,
                        synthesisMs: synMs
                    )
                }
                AppLogger.shared.log("NghiTTS synthesis failed: \(error.localizedDescription)")
                self.preloadedData.removeValue(forKey: index)
                self.preloadedDurations.removeValue(forKey: index)
                self.currentPlaybackId = nil
                self.pause()
                ToastManager.shared.show(message: "Lỗi NghiTTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
            }
        }
    }



    private func playGoogleTTS(_ text: String) {
        let index = currentParagraphIndex
        let voice = selectedVoice
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId
        let expectedSessionID = sessionID
        let expectedChapterIndex = playingChapterIndex
        let expectedBookID = playingBookId
        let expectedChapterURL = playingChapterUrl
        let service = googleService
        let synthesisKey = "paragraph|\(expectedSessionID.uuidString)|\(expectedChapterIndex)|\(index)|google|\(voice)"

        if let cachedData = preloadedData[index] {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: "google", index: index, outcome: "hit")
            self.playAudioData(cachedData, withId: playbackId)
            updatePrefetchWindow()
            return
        }

        let wasPrefetching = prefetchTasks[index] != nil
        remotePlaybackTask?.cancel()
        remotePlaybackTaskGeneration &+= 1
        let taskGeneration = remotePlaybackTaskGeneration
        let startWait = ProcessInfo.processInfo.systemUptime

        remotePlaybackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.remotePlaybackTaskGeneration == taskGeneration {
                    self.remotePlaybackTask = nil
                }
            }

            do {
                let mp3Data = try await RemoteTTSSynthesisCoordinator.shared.synthesize(
                    key: synthesisKey,
                    engine: "google",
                    textLength: text.count,
                    priority: .current
                ) {
                    try await service.synthesize(text: text, voice: voice, speed: 1.0, pitch: 1.0)
                }

                guard !Task.isCancelled,
                      self.isPlaying,
                      self.currentPlaybackId == playbackId,
                      self.sessionID == expectedSessionID,
                      self.playingBookId == expectedBookID,
                      self.playingChapterIndex == expectedChapterIndex,
                      self.playingChapterUrl == expectedChapterURL,
                      self.tool == "google",
                      self.selectedVoice == voice else { return }

                let waitMs = (ProcessInfo.processInfo.systemUptime - startWait) * 1000
                self.recordPrefetchResult(
                    sessionID: expectedSessionID,
                    chapterIndex: expectedChapterIndex,
                    engine: "google",
                    index: index,
                    outcome: wasPrefetching ? "hit_wait" : "miss",
                    waitMs: wasPrefetching ? waitMs : 0
                )
                self.playAudioData(mp3Data, withId: playbackId)
                self.updatePrefetchWindow()
            } catch is CancellationError {
                return
            } catch {
                guard self.currentPlaybackId == playbackId else { return }
                if index == 0 && self.activeTTSAutoAdvancePerf?.chapterIndex == self.playingChapterIndex {
                    let synMs = self.currentParagraph0SynthesisMs()
                    self.finishTTSAutoAdvancePerf(
                        outcome: "synthesis_failed",
                        endpoint: "error",
                        sessionID: self.sessionID,
                        generation: self.ttsProcessingGeneration,
                        chapterIndex: self.playingChapterIndex,
                        synthesisMs: synMs
                    )
                }
                AppLogger.shared.log("❌ Lỗi Google Cloud TTS: \(error.localizedDescription)")
                self.preloadedData.removeValue(forKey: index)
                self.currentPlaybackId = nil
                self.pause()
                ToastManager.shared.show(message: "Lỗi Google TTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
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
        let expectedSessionID = sessionID
        let expectedChapterIndex = playingChapterIndex
        let expectedBookID = playingBookId
        let expectedChapterURL = playingChapterUrl
        let engineName = tool
        let service = extService
        let synthesisKey = "paragraph|\(expectedSessionID.uuidString)|\(expectedChapterIndex)|\(index)|\(engineName)|\(voice)"

        if let cachedData = preloadedData[index] {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: engineName, index: index, outcome: "hit")
            self.playAudioData(cachedData, withId: playbackId)
            updatePrefetchWindow()
            return
        }

        let wasPrefetching = prefetchTasks[index] != nil
        remotePlaybackTask?.cancel()
        remotePlaybackTaskGeneration &+= 1
        let taskGeneration = remotePlaybackTaskGeneration
        let startWait = ProcessInfo.processInfo.systemUptime

        remotePlaybackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.remotePlaybackTaskGeneration == taskGeneration {
                    self.remotePlaybackTask = nil
                }
            }

            do {
                let audioData = try await RemoteTTSSynthesisCoordinator.shared.synthesize(
                    key: synthesisKey,
                    engine: engineName,
                    textLength: text.count,
                    priority: .current
                ) {
                    try await service.synthesizeData(
                        text: text,
                        voice: voice,
                        localPath: localPath,
                        configJson: configJson
                    )
                }

                guard !Task.isCancelled,
                      self.isPlaying,
                      self.currentPlaybackId == playbackId,
                      self.sessionID == expectedSessionID,
                      self.playingBookId == expectedBookID,
                      self.playingChapterIndex == expectedChapterIndex,
                      self.playingChapterUrl == expectedChapterURL,
                      self.tool == engineName,
                      self.selectedVoice == voice else { return }

                let waitMs = (ProcessInfo.processInfo.systemUptime - startWait) * 1000
                self.recordPrefetchResult(
                    sessionID: expectedSessionID,
                    chapterIndex: expectedChapterIndex,
                    engine: engineName,
                    index: index,
                    outcome: wasPrefetching ? "hit_wait" : "miss",
                    waitMs: wasPrefetching ? waitMs : 0
                )
                self.playAudioData(audioData, withId: playbackId)
                self.updatePrefetchWindow()
            } catch is CancellationError {
                return
            } catch {
                guard self.currentPlaybackId == playbackId else { return }
                if index == 0 && self.activeTTSAutoAdvancePerf?.chapterIndex == self.playingChapterIndex {
                    let synMs = self.currentParagraph0SynthesisMs()
                    self.finishTTSAutoAdvancePerf(
                        outcome: "synthesis_failed",
                        endpoint: "error",
                        sessionID: self.sessionID,
                        generation: self.ttsProcessingGeneration,
                        chapterIndex: self.playingChapterIndex,
                        synthesisMs: synMs
                    )
                }
                AppLogger.shared.log("❌ Lỗi Extension TTS: \(error.localizedDescription)")
                self.preloadedData.removeValue(forKey: index)
                self.currentPlaybackId = nil
                self.pause()
                ToastManager.shared.show(message: "Lỗi Extension TTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error)
            }
        }
    }

    private func cleanUpTempFile() {
        // File tạm được dọn dẹp trực tiếp trong ExtTTSService.synthesize
    }

    // MARK: - Text Segmentation (Phân đoạn văn bản)

    // MARK: - Lock Screen & Remote Control Sync

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        #if DEBUG
        logRemoteTrace("setRemoteCommandsEnabled(\(enabled))") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
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
        #if DEBUG
        logRemoteTrace("syncRemoteCommandState", details: "active:\(active), playing:\(playing), paused:\(paused)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
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
        #if DEBUG
        let thread = Thread.isMainThread ? "Main" : "Bg"
        AppLogger.shared.log("🔍 [TTSTrace] setSystemNowPlayingPlaybackState | Thread:\(thread) | state:\(state.rawValue) | currentRate:\(currentRate) | defaultRate:\(self.speed) | elapsed:\(elapsed) | duration:\(duration) | progress:\(String(format: "%.2f", progress))")
        #endif
    }

    enum RemoteTransportAction {
        case play
        case pause
        case toggle
        case next
        case previous
    }

    func handleRemoteTransportCommandOnMain(_ action: RemoteTransportAction) {
        #if DEBUG
        logRemoteTrace("handleRemoteTransportCommandOnMain", details: "action:\(action)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif

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
        #if DEBUG
        let latencyMs = Double(DispatchTime.now().uptimeNanoseconds - entryUptime) / 1_000_000.0
        self.logRemoteTrace("remoteCallbackDispatched", details: "id:\(eventId) | action:\(action) | entryThread:\(isMain ? "Main" : "Bg") | queueLatency:\(String(format: "%.2f", latencyMs))ms")
        #endif

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

        #if DEBUG
        self.logRemoteTrace("remoteCallbackCompleted", details: "id:\(eventId) | action:\(action) | status:\(status == .success ? "success" : "commandFailed")(\(status.rawValue))")
        #endif
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
        #if DEBUG
        logRemoteTrace("setupRemoteCommandCenter") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
    }

    private func updateNowPlayingInfo() {
        let key = NowPlayingStaticMetadataKey(
            bookId: playingBookId,
            bookTitle: bookTitle,
            chapterIndex: playingChapterIndex,
            chapterTitle: chapterTitle,
            coverUrl: playingCoverUrl,
            isTranslationEnabled: TranslateUtils.isTranslationEnabled,
            translationToken: TranslateUtils.translationGenerationToken(for: playingBookId)
        )

        if let metadata = nowPlayingStaticMetadata, metadata.key == key {
            publishNowPlayingInfo(using: metadata)
            return
        }

        // A static load for this exact chapter is already active. Its completion
        // republishes using the latest paragraph/playback state.
        guard nowPlayingMetadataTaskKey != key else { return }

        nowPlayingUpdateGeneration &+= 1
        let updateGeneration = nowPlayingUpdateGeneration
        nowPlayingMetadataTask?.cancel()
        nowPlayingMetadataTaskKey = key

        nowPlayingMetadataTask = Task { [weak self] in
            let prepared = await Task.detached(priority: .background) {
                let rawChapterTitle = key.chapterTitle.isEmpty ? "Chương hiện tại" : key.chapterTitle
                let displayBookTitle: String
                let displayChapterTitle: String

                if key.isTranslationEnabled {
                    displayBookTitle = TranslateUtils.containsChinese(key.bookTitle)
                        ? TranslateUtils.translateMeta(key.bookTitle, bookId: key.bookId)
                        : key.bookTitle
                    displayChapterTitle = TranslateUtils.containsChinese(rawChapterTitle)
                        ? TranslateUtils.translateChapterTitle(rawChapterTitle, bookId: key.bookId)
                        : rawChapterTitle
                } else {
                    displayBookTitle = key.bookTitle
                    displayChapterTitle = rawChapterTitle
                }

                let image = ImageCacheManager.shared.loadLocalCover(for: key.bookId)
                return (displayBookTitle, displayChapterTitle, image)
            }.value

            guard !Task.isCancelled, let self,
                  updateGeneration == self.nowPlayingUpdateGeneration,
                  self.nowPlayingMetadataTaskKey == key,
                  self.playingBookId == key.bookId else { return }

            let artwork = prepared.2.map { image in
                MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
            self.nowPlayingStaticMetadata = NowPlayingStaticMetadata(
                key: key,
                displayBookTitle: prepared.0,
                displayChapterTitle: prepared.1,
                artwork: artwork
            )
            self.nowPlayingMetadataTask = nil
            self.nowPlayingMetadataTaskKey = nil

            if prepared.2 == nil {
                self.downloadNowPlayingCoverIfNeeded(for: key)
            }
            self.updateNowPlayingInfo()
        }
    }

    private func publishNowPlayingInfo(using metadata: NowPlayingStaticMetadata) {
        let paragraphIndex = currentParagraphIndex
        let paragraphCount = paragraphs.count
        let liveIsPlaying = isPlaying
        let liveSpeed = speed

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = metadata.displayBookTitle

        let currentPart = paragraphCount == 0 ? "" : " (Đoạn \(paragraphIndex + 1)/\(paragraphCount))"
        info[MPMediaItemPropertyArtist] = metadata.displayChapterTitle + currentPart
        info.removeValue(forKey: MPNowPlayingInfoPropertyIsLiveStream)
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        let currentRate = liveIsPlaying ? 1.0 : 0.0
        let duration = Double(max(1, paragraphCount))
        let elapsed = min(duration, Double(max(0, paragraphIndex)))
        let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = currentRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = liveSpeed
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackProgress] = progress

        if let artwork = metadata.artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = liveIsPlaying ? .playing : .paused
        #if DEBUG
        logRemoteTrace("updateNowPlayingInfo", details: "liveIsPlaying:\(liveIsPlaying), liveSpeed:\(liveSpeed)") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
    }

    private func downloadNowPlayingCoverIfNeeded(for key: NowPlayingStaticMetadataKey) {
        guard !key.coverUrl.isEmpty, nowPlayingCoverDownloadKey != key else { return }
        nowPlayingCoverDownloadKey = key

        ImageCacheManager.shared.downloadAndSaveCover(urlStr: key.coverUrl, bookId: key.bookId) { [weak self] image in
            guard image != nil else { return }
            DispatchQueue.main.async {
                guard let self,
                      self.playingBookId == key.bookId,
                      self.showFloatingWidget else { return }
                self.nowPlayingCoverDownloadKey = nil
                if self.nowPlayingStaticMetadata?.key == key {
                    self.nowPlayingStaticMetadata = nil
                }
                self.updateNowPlayingInfo()
            }
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
        // 0. System Call Observer (CallKit: Cuộc gọi cellular, FaceTime, Zalo, Messenger, VoIP)
        callObserver.onCallBegan = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isPlaying {
                    AppLogger.shared.log("📞 [TTSManager] Call began. Pausing TTS playback.")
                    self.wasPlayingBeforeInterruption = true
                    self.pause()
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    self.isAudioSessionConfigured = false
                }
            }
        }

        callObserver.onCallEnded = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                if self.wasPlayingBeforeInterruption {
                    self.wasPlayingBeforeInterruption = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        guard let self = self else { return }
                        if !self.isPlaying {
                            AppLogger.shared.log("📞 [TTSManager] Call ended. Resuming TTS playback.")
                            self.configureAudioSession()
                            self.resume()
                        }
                    }
                }
            }
        }

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

        // 5. Thermal State Change (thiết bị nóng/mát)
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.currentThermalState = ProcessInfo.processInfo.thermalState
                let engine = self.tool
                let isPlaying = self.isPlaying
                Task {
                    await RemoteTTSSynthesisCoordinator.shared.recordThermalStateChange(
                        engine: engine,
                        isPlaying: isPlaying
                    )
                }
                if self.isPlaying {
                    if self.tool == "nghitts",
                       !NghiSynthesisPolicy.allowsSpeculativeRefill(at: self.currentThermalState) {
                        self.cancelNghiRefill()
                        self.nextChapterPrefetcher.cancel()
                    }
                    if self.tool != "system" && self.tool != "nghitts" &&
                        self.currentThermalState != .serious &&
                        self.currentThermalState != .critical {
                        self.triggerNextChapterPrefetch()
                    }
                    self.updatePrefetchWindow()
                }
            }
            .store(in: &cancellables)

        // 6. App lifecycle, dùng để tách riêng tải remote khi màn hình bật và khi khóa máy.
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let engine = self.tool
                let isPlaying = self.isPlaying
                Task {
                    await RemoteTTSSynthesisCoordinator.shared.setApplicationState(
                        "background",
                        engine: engine,
                        isPlaying: isPlaying
                    )
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let engine = self.tool
                let isPlaying = self.isPlaying
                Task {
                    await RemoteTTSSynthesisCoordinator.shared.setApplicationState(
                        "foreground",
                        engine: engine,
                        isPlaying: isPlaying
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func handleInterruption(notification: Notification) {
        #if DEBUG
        logRemoteTrace("handleInterruption", details: "userInfo:\(notification.userInfo ?? [:])") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
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
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                self.isAudioSessionConfigured = false
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
                        self.configureAudioSession()
                        self.resume()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(notification: Notification) {
        #if DEBUG
        logRemoteTrace("handleRouteChange", details: "userInfo:\(notification.userInfo ?? [:])") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
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
        #if DEBUG
        logRemoteTrace("handleMediaServicesReset") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
        // Media services bị reset: tất cả AVAudioEngine/PlayerNode đều trở thành invalid
        AppLogger.shared.log("🔊 [TTSManager] Media services were reset. Rebuilding audio engine.")
        let wasPlaying = isPlaying
        let currentIdx = currentParagraphIndex
        isAudioSessionConfigured = false

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
        #if DEBUG
        logRemoteTrace("handleEngineConfigChange") // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
        #endif
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
            guard self.audioPlayer === player else { return }
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
