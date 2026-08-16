import Foundation
import AVFoundation
import MediaPlayer
import Combine
import QuartzCore
import UIKit
import SwiftData

internal struct TTSPreparedChapterKey: Equatable, Sendable {
    let bookId: String
    let chapterIndex: Int
    let chapterTitle: String
    let content: String
    let chunkLength: Int
    let includeChapterTitle: Bool
    let removeDuplicatedTitle: Bool
    let isTranslationEnabled: Bool
    let translationToken: Int
}

internal struct TTSPreparedChapter: Sendable {
    let normalizedContent: String
    let paragraphs: [TTSParagraph]
}

public struct TTSPrefetchPerfSummary: Sendable {
    public var sessionID: UUID
    public var chapterIndex: Int
    public var engine: String
    public var immediateHit: Int
    public var waitedHit: Int
    public var miss: Int
    public var failure: Int
    public var retrySuccess: Int
    public var retryFailure: Int
    public var totalWaitMs: Double
    public var maxWaitMs: Double
    public var startTime: Date

    public init(
        sessionID: UUID,
        chapterIndex: Int,
        engine: String,
        immediateHit: Int = 0,
        waitedHit: Int = 0,
        miss: Int = 0,
        failure: Int = 0,
        retrySuccess: Int = 0,
        retryFailure: Int = 0,
        totalWaitMs: Double = 0,
        maxWaitMs: Double = 0,
        startTime: Date = Date()
    ) {
        self.sessionID = sessionID
        self.chapterIndex = chapterIndex
        self.engine = engine
        self.immediateHit = immediateHit
        self.waitedHit = waitedHit
        self.miss = miss
        self.failure = failure
        self.retrySuccess = retrySuccess
        self.retryFailure = retryFailure
        self.totalWaitMs = totalWaitMs
        self.maxWaitMs = maxWaitMs
        self.startTime = startTime
    }
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
    internal var remoteTraceSequenceCount = 0

    // REMOVE_AFTER_TTS_REMOTE_DIAGNOSIS
    internal func logRemoteTrace(_ event: String, details: String = "") {
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
            cancelChapterAdvanceTask()
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
            if !isInitializing && tool == "google" && oldValue != pitch {
                cancelClaimedSynthesisTask()
                remotePlaybackTask?.cancel()
                remotePlaybackTask = nil
                nextChapterPrefetcher.cancel()
                Task { await audioSynthesisWorker.cancelPrefetchTasks() }
                preloadedData.removeAll()
                preloadedDurations.removeAll()
            }
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
            let clampedCount = max(2, min(10, googlePrefetchCount))
            UserDefaults.standard.set(clampedCount, forKey: "googlePrefetchCount")
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

    @Published public private(set) var nghittsSafeCachedTimeThreshold: Double = NghiSynthesisPolicy.defaultSafeCachedTimeThreshold

    public func setNghiTTSSafeCachedTimeThreshold(_ newValue: Double) {
        let clamped = NghiSynthesisPolicy.clampSafeCachedTimeThreshold(newValue)
        guard clamped != nghittsSafeCachedTimeThreshold else { return }
        nghittsSafeCachedTimeThreshold = clamped
        UserDefaults.standard.set(clamped, forKey: "nghittsSafeCachedTimeThreshold")
        if tool == "nghitts" && isPlaying {
            cancelNghiWakeTask()
            updateNghiPrefetchWindow()
        }
    }

    @Published public var extPrefetchCount: Int {
        didSet {
            guard !isInitializing else { return }
            if tool != "system" && tool != "nghitts" && tool != "google" {
                let clampedCount = max(2, min(10, extPrefetchCount))
                UserDefaults.standard.set(clampedCount, forKey: "extPrefetchUser_\(tool)")
                clearPrefetchCache()
            }
        }
    }

    @Published public var prefetchDelayMs: Int {
        didSet {
            guard !isInitializing else { return }
            let isRemoteTTS = (tool != "system" && tool != "nghitts")
            let clampedValue = isRemoteTTS ? max(300, prefetchDelayMs) : prefetchDelayMs
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

    private func extractInt(from value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    public func parseExtensionConfigParams(jsonString: String, localPath: String? = nil) -> (preloadSize: Int?, maxLength: Int?) {
        let path = (localPath != nil && !localPath!.isEmpty) ? localPath! : extensionLocalPath
        let configs = ExtensionManager.shared.getCombinedConfigs(localPath: path, configJson: jsonString)
        let pSize = extractInt(from: configs["preload_size"])
        let mLen = extractInt(from: configs["max_length"])
        return (pSize, mLen)
    }

    // Trạng thái playback
    @Published public var isPlaying: Bool = false
    @Published public var currentParagraphIndex: Int = -1
    @Published public var currentParentParagraphIndex: Int = -1
    @Published public var highlightRange: NSRange? = nil
    @Published public private(set) var playbackSnapshot: TTSPlaybackSnapshot = TTSPlaybackSnapshot()
    internal var audibleHandoffGeneration: UInt64 = 0
    @Published public var showFloatingWidget: Bool = false
    @Published public var showingSettingsSheet: Bool = false


    internal struct TTSAutoAdvancePerfContext {
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

    internal var activeTTSAutoAdvancePerf: TTSAutoAdvancePerfContext? = nil
    internal var paragraph0SynthesisStartUptime: Double = 0
    internal var paragraph0AudioCacheHit: Bool = false

    internal func resetParagraph0Timing() {
        paragraph0SynthesisStartUptime = 0
        paragraph0AudioCacheHit = false
    }

    internal func currentParagraph0SynthesisMs(untilUptime: Double? = nil) -> Double {
        guard paragraph0SynthesisStartUptime > 0 && !paragraph0AudioCacheHit else { return 0.0 }
        let end = untilUptime ?? ProcessInfo.processInfo.systemUptime
        return max(0.0, (end - paragraph0SynthesisStartUptime) * 1000)
    }



    @MainActor
    internal func finishTTSPrefetchPerfSummary() {
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
    internal func recordPrefetchResult(sessionID: UUID, chapterIndex: Int, engine: String, index: Int, outcome: String, waitMs: Double = 0) {
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
    }

    @Published public var timerMode: SleepTimerMode = .off {
        didSet {
            guard !isInitializing else { return }
            persistSleepTimerMode()
        }
    }
    @Published public var sleepTimerRemainingSeconds: Int = 0
    @Published public var isTimerRunning: Bool = false
    private var sleepTimerObj: Timer? = nil

    public var sleepTimerBadgeText: String {
        switch timerMode {
        case .off:
            return ""
        case .minutes:
            if isTimerRunning && sleepTimerRemainingSeconds > 0 {
                let mins = sleepTimerRemainingSeconds / 60
                let secs = sleepTimerRemainingSeconds % 60
                return String(format: "%d:%02d", mins, secs)
            }
            return ""
        case .endOfChapter:
            return "Hết bài"
        }
    }

    public func startSleepTimer(minutes: Int) {
        if minutes <= 0 {
            cancelSleepTimer()
            return
        }
        timerMode = .minutes(minutes)
        if isPlaying {
            startTimerCountdown(minutes: minutes)
        } else {
            stopTimerCountdown(keepMode: true)
            sleepTimerRemainingSeconds = minutes * 60
        }
    }

    public func setStopAtEndOfChapter() {
        stopTimerCountdown(keepMode: false)
        timerMode = .endOfChapter
    }

    public func cancelSleepTimer() {
        stopTimerCountdown(keepMode: false)
        timerMode = .off
    }

    private func persistSleepTimerMode() {
        switch timerMode {
        case .off:
            UserDefaults.standard.set("off", forKey: "ttsSleepTimerMode")
            UserDefaults.standard.removeObject(forKey: "ttsSleepTimerMinutes")
        case .minutes(let mins):
            UserDefaults.standard.set("minutes", forKey: "ttsSleepTimerMode")
            UserDefaults.standard.set(mins, forKey: "ttsSleepTimerMinutes")
        case .endOfChapter:
            UserDefaults.standard.set("endOfChapter", forKey: "ttsSleepTimerMode")
            UserDefaults.standard.removeObject(forKey: "ttsSleepTimerMinutes")
        }
    }

    public func startTimerCountdown(minutes: Int) {
        stopTimerCountdown(keepMode: true)
        self.sleepTimerRemainingSeconds = minutes * 60
        self.isTimerRunning = true

        self.sleepTimerObj = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.sleepTimerRemainingSeconds > 1 {
                    self.sleepTimerRemainingSeconds -= 1
                } else {
                    self.sleepTimerRemainingSeconds = 0
                    self.stopTimerCountdown(keepMode: true)
                    self.onSleepTimerExpired()
                }
            }
        }
    }

    public func stopTimerCountdown(keepMode: Bool) {
        sleepTimerObj?.invalidate()
        sleepTimerObj = nil
        isTimerRunning = false
        if !keepMode {
            timerMode = .off
            sleepTimerRemainingSeconds = 0
        }
    }

    public func restartSleepTimerIfNeeded() {
        if case .minutes(let mins) = timerMode {
            if !isTimerRunning || sleepTimerRemainingSeconds <= 0 {
                startTimerCountdown(minutes: mins)
            }
        }
    }

    private func onSleepTimerExpired() {
        pause()
        let label: String
        if case .minutes(let m) = timerMode {
            label = " (\(m) phút)"
        } else {
            label = ""
        }
        TTSPresentationEventCenter.shared.send(.showToast(message: "⏱️ Hẹn giờ\(label): Đã tự động tạm dừng đọc.", type: .info))
    }


    // Thông tin phát nhạc độc lập toàn cục
    @Published public private(set) var playingBookId: String = ""
    @Published public private(set) var playingCoverUrl: String = ""
    @Published public private(set) var playingChapterUrl: String = ""
    @Published public private(set) var playingChapterIndex: Int = -1
    @Published public private(set) var playingBookDetailUrl: String = ""
    @Published public private(set) var playingBookSourceName: String = ""
    @Published public private(set) var extensionInfo: TTSExtensionInfo? = nil

    internal var chaptersQueue: [TTSChapterInfo] = []
    internal var currentPlaybackId: String? = nil
    internal var wasPlayingBeforeSettings = false
    internal var savedParagraphIdentityBeforeSettings: Int = -1
    internal var wasPlayingBeforeInterruption = false
    internal var lastPausedTime: Date? = nil
    internal var cancellables = Set<AnyCancellable>()
    internal var prepareSpeakingTask: Task<Void, Never>? = nil
    internal var startSpeakingTask: Task<Void, Never>? = nil
    internal var chapterQueueRefreshTask: Task<Void, Never>? = nil
    internal var chapterAdvanceTask: Task<Void, Never>? = nil
    internal var chapterAdvanceTaskGeneration: UInt64 = 0
    internal var nghiWarmUpTask: Task<Void, Never>? = nil
    internal let audioSynthesisWorker = TTSAudioSynthesisWorker()
    internal lazy var nextChapterPrefetcher = TTSChapterPrefetcher(audioWorker: audioSynthesisWorker)
    internal var claimedSynthesisTask: Task<Data, Error>? = nil
    internal var claimedSynthesisTaskKey: String? = nil
    internal var sessionID = UUID()
    internal var ttsProcessingGeneration = 0
    internal var preparationGeneration = 0
    internal var preparedChapterKey: TTSPreparedChapterKey? = nil
    internal var preparedChapter: TTSPreparedChapter? = nil
    internal var sessionTranslationEnabled: Bool = false
    internal var activePrefetchPerfSummary: TTSPrefetchPerfSummary? = nil
    internal var prefetchTaskGenerations: [Int: UInt64] = [:]
    internal var nextPrefetchTaskGeneration: UInt64 = 0

    public func clearPreparedChapterCache() {
        prepareSpeakingTask?.cancel()
        prepareSpeakingTask = nil
        preparationGeneration += 1
        preparedChapterKey = nil
        preparedChapter = nil
    }

    internal func cancelClaimedSynthesisTask() {
        claimedSynthesisTask?.cancel()
        claimedSynthesisTask = nil
        claimedSynthesisTaskKey = nil
    }

    private func cancelChapterAdvanceTask() {
        chapterAdvanceTaskGeneration &+= 1
        chapterAdvanceTask?.cancel()
        chapterAdvanceTask = nil
        cancelClaimedSynthesisTask()
    }

    private func clearChapterAdvanceTask(ifGenerationMatches generation: UInt64) {
        guard chapterAdvanceTaskGeneration == generation else { return }
        chapterAdvanceTask = nil
    }

    internal struct NowPlayingStaticMetadataKey: Equatable, Sendable {
        let bookId: String
        let bookTitle: String
        let chapterIndex: Int
        let chapterTitle: String
        let coverUrl: String
        let isTranslationEnabled: Bool
        let translationToken: Int
    }

    internal struct NowPlayingStaticMetadata {
        let key: NowPlayingStaticMetadataKey
        let displayBookTitle: String
        let displayChapterTitle: String
        let artwork: MPMediaItemArtwork?
    }

    // Static title/artwork work is coalesced by book/chapter/translation key.
    // Paragraph transitions update only the cheap timeline fields.
    internal var nowPlayingUpdateGeneration: UInt = 0
    internal var nowPlayingStaticMetadata: NowPlayingStaticMetadata?
    internal var nowPlayingMetadataTaskKey: NowPlayingStaticMetadataKey?
    internal var nowPlayingMetadataTask: Task<Void, Never>?
    internal var nowPlayingCoverDownloadKey: NowPlayingStaticMetadataKey?

    // Cache lưu trữ dữ liệu âm thanh đã được tổng hợp trước cho các đoạn văn
    internal var preloadedData: [Int: Data] = [:]
    internal var preloadedDurations: [Int: Double] = [:]
    internal var prefetchTasks: [Int: Task<Void, Never>] = [:]
    internal var remotePlaybackTask: Task<Void, Never>?
    internal var remotePlaybackTaskGeneration: UInt64 = 0
    internal var nghiPlaybackTask: Task<Void, Never>?
    internal var nghiPlaybackTaskGeneration: UInt64 = 0
    internal var nghiRefillTask: Task<Void, Never>? = nil
    internal var nghiRefillGeneration: UInt64 = 0
    internal var nghiRefillInFlightIndex: Int? = nil
    internal var nghiWakeTask: Task<Void, Never>? = nil

    private struct TTSSettingsSnapshot: Equatable {
        let tool: String
        let selectedVoice: String
        let pitch: Double
        let speed: Double
        let chunkLength: Int
        let prefetchDelayMs: Int
        let googlePrefetchCount: Int
        let extPrefetchCount: Int
        let extensionLocalPath: String
        let extensionConfigJson: String
        let newlinePause: Double
        let sentencePause: Double
        let phrasePause: Double
        let bracketPause: Double
        let paragraphPause: Double
        let numericNormalization: Bool
        let dictionaryReplacement: Bool
        let transliteration: Bool
    }
    private var savedSettingsSnapshot: TTSSettingsSnapshot? = nil

    private func captureTTSSettingsSnapshot() -> TTSSettingsSnapshot {
        TTSSettingsSnapshot(
            tool: tool,
            selectedVoice: selectedVoice,
            pitch: pitch,
            speed: speed,
            chunkLength: chunkLength,
            prefetchDelayMs: prefetchDelayMs,
            googlePrefetchCount: googlePrefetchCount,
            extPrefetchCount: extPrefetchCount,
            extensionLocalPath: extensionLocalPath,
            extensionConfigJson: extensionConfigJson,
            newlinePause: UserDefaults.standard.double(forKey: "newlinePauseDuration"),
            sentencePause: UserDefaults.standard.double(forKey: "sentencePauseDuration"),
            phrasePause: UserDefaults.standard.double(forKey: "phrasePauseDuration"),
            bracketPause: UserDefaults.standard.double(forKey: "bracketPauseDuration"),
            paragraphPause: UserDefaults.standard.double(forKey: "paragraphPauseDuration"),
            numericNormalization: UserDefaults.standard.object(forKey: PreprocessorSettingKey.numericNormalizationEnabled) as? Bool ?? true,
            dictionaryReplacement: UserDefaults.standard.object(forKey: PreprocessorSettingKey.dictionaryReplacementEnabled) as? Bool ?? true,
            transliteration: UserDefaults.standard.object(forKey: PreprocessorSettingKey.transliterationEnabled) as? Bool ?? true
        )
    }

    internal struct NghiEnergyAccumulator {
        var startedAt: TimeInterval?
        var synthesisCount = 0
        var essentialCount = 0
        var onDemandCount = 0
        var underrunCount = 0
        var reusedInFlightCount = 0
        var totalQueueWaitMs = 0.0
        var totalSynthesisMs = 0.0
        var totalPCMSeconds = 0.0
        var maxRTF = 0.0
    }

    internal var nghiEnergy = NghiEnergyAccumulator()
    internal var audioPlayer: AVAudioPlayer?
    internal let nghiAudioPlayerQueue = NghiAudioPlayerQueue()
    internal let callObserver = TTSCallObserver()
    internal var isAudioSessionConfigured = false

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
    internal let extService = ExtTTSService()
    internal let googleService = GoogleTTSService()
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
    internal var audioEngine: AVAudioEngine?
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
        let savedInitThreshold = UserDefaults.standard.object(forKey: "nghittsSafeCachedTimeThreshold") != nil
            ? UserDefaults.standard.double(forKey: "nghittsSafeCachedTimeThreshold")
            : NghiSynthesisPolicy.defaultSafeCachedTimeThreshold
        let clampedInitThreshold = NghiSynthesisPolicy.clampSafeCachedTimeThreshold(savedInitThreshold)
        self.nghittsSafeCachedTimeThreshold = clampedInitThreshold
        UserDefaults.standard.set(clampedInitThreshold, forKey: "nghittsSafeCachedTimeThreshold")
        self.extPrefetchCount = 3
        self.prefetchDelayMs = UserDefaults.standard.object(forKey: "ttsPrefetchDelayMs") != nil ? UserDefaults.standard.integer(forKey: "ttsPrefetchDelayMs") : 350
        self.extensionLocalPath = UserDefaults.standard.string(forKey: "ttsExtensionLocalPath") ?? ""
        self.extensionConfigJson = UserDefaults.standard.string(forKey: "ttsExtensionConfigJson") ?? "{}"

        switch UserDefaults.standard.string(forKey: "ttsSleepTimerMode") {
        case "minutes":
            let savedMins = UserDefaults.standard.integer(forKey: "ttsSleepTimerMinutes")
            self.timerMode = savedMins > 0 ? .minutes(savedMins) : .off
        case "endOfChapter":
            self.timerMode = .endOfChapter
        default:
            self.timerMode = .off
        }

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
            let savedThreshold = UserDefaults.standard.object(forKey: "nghittsSafeCachedTimeThreshold") != nil
                ? UserDefaults.standard.double(forKey: "nghittsSafeCachedTimeThreshold")
                : NghiSynthesisPolicy.defaultSafeCachedTimeThreshold
            let clampedThreshold = NghiSynthesisPolicy.clampSafeCachedTimeThreshold(savedThreshold)
            self.nghittsSafeCachedTimeThreshold = clampedThreshold
            UserDefaults.standard.set(clampedThreshold, forKey: "nghittsSafeCachedTimeThreshold")
            self.chunkLength = UserDefaults.standard.object(forKey: "nghittsChunk") != nil ? UserDefaults.standard.integer(forKey: "nghittsChunk") : 200
            let savedDelay = UserDefaults.standard.object(forKey: "nghittsPrefetchDelay") != nil ? UserDefaults.standard.integer(forKey: "nghittsPrefetchDelay") : 500
            self.prefetchDelayMs = savedDelay >= 300 ? savedDelay : 500
        } else if tool == "google" {
            self.speed = UserDefaults.standard.double(forKey: "googleRate") > 0 ? UserDefaults.standard.double(forKey: "googleRate") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "googlePitch") > 0 ? UserDefaults.standard.double(forKey: "googlePitch") : defaultPitch
            let savedVoice = UserDefaults.standard.string(forKey: "googleVoice") ?? "via"
            let validGoogleVoiceIds = Set(GoogleVoice.allVoices.map { $0.id })
            self.selectedVoice = validGoogleVoiceIds.contains(savedVoice) ? savedVoice : "via"
            let savedCount = UserDefaults.standard.object(forKey: "googlePrefetchCount") != nil ? UserDefaults.standard.integer(forKey: "googlePrefetchCount") : 3
            self.googlePrefetchCount = max(2, min(10, savedCount))
            self.chunkLength = UserDefaults.standard.object(forKey: "googleChunk") != nil ? UserDefaults.standard.integer(forKey: "googleChunk") : 200
            let savedDelay = UserDefaults.standard.object(forKey: "googlePrefetchDelay") != nil ? UserDefaults.standard.integer(forKey: "googlePrefetchDelay") : 500
            self.prefetchDelayMs = max(300, savedDelay)
        } else {
            self.speed = UserDefaults.standard.double(forKey: "extRate_\(tool)") > 0 ? UserDefaults.standard.double(forKey: "extRate_\(tool)") : defaultRate
            self.pitch = UserDefaults.standard.double(forKey: "extPitch_\(tool)") > 0 ? UserDefaults.standard.double(forKey: "extPitch_\(tool)") : defaultPitch
            self.selectedVoice = UserDefaults.standard.string(forKey: "extVoice_\(tool)") ?? ""
            
            let parsed = parseExtensionConfigParams(jsonString: extensionConfigJson, localPath: extensionLocalPath)
            let countToUse = parsed.preloadSize ?? 3
            self.extPrefetchCount = max(2, min(10, countToUse))
            self.chunkLength = parsed.maxLength ?? 200
            let saved = UserDefaults.standard.object(forKey: "extPrefetchDelay_\(tool)") != nil ? UserDefaults.standard.integer(forKey: "extPrefetchDelay_\(tool)") : 500
            self.prefetchDelayMs = max(300, saved)
        }
    }

    private func setupEngines() {
        nextChapterPrefetcher.onDTOReady = { [weak self] key in
            guard let self, self.isPlaying, key.tool == "nghitts" else { return }
            self.checkAndPromoteNextChapterAudioIfNeeded()
        }
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

    public let audioEngineController = TTSAudioEngineController()
    public let audioSessionController = TTSAudioSessionController()
    public let nowPlayingController = TTSNowPlayingController()

    internal func setupAudioEngine() {
        audioEngineController.configureEngine(speed: speed, pitch: pitch)
        self.audioEngine = audioEngineController.audioEngine
        self.playerNode = audioEngineController.playerNode
        self.timePitchNode = audioEngineController.pitchNode
        self.eqNode = audioEngineController.eqNode
    }

    private func readRemoveDuplicatedTitle(for bookId: String) -> Bool {
        let key = "removeDuplicatedTitle_\(bookId)"
        return UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
    }

    internal func configureAudioSession() {
        if isAudioSessionConfigured { return }
        audioSessionController.activate()
        if audioSessionController.configureAudioSession() {
            isAudioSessionConfigured = true
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
                cancelNghiWakeTask()
                updateNghiPrefetchWindow()
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
        let removeDuplicatedTitle = readRemoveDuplicatedTitle(for: bookId)
        let isTransEnabled = TranslateUtils.isTranslationEnabled

        let preparedKey = TTSPreparedChapterKey(
            bookId: bookId,
            chapterIndex: currentIndex,
            chapterTitle: currentChapter.title,
            content: chapterContent,
            chunkLength: chunkLength,
            includeChapterTitle: showTitle,
            removeDuplicatedTitle: removeDuplicatedTitle,
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
                    removeDuplicatedTitle: removeDuplicatedTitle,
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
        cancelChapterAdvanceTask()

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
        let removeDuplicatedTitle = readRemoveDuplicatedTitle(for: bookId)
        let expectedTitle = currentChapter.title

        let requestedKey = TTSPreparedChapterKey(
            bookId: bookId,
            chapterIndex: currentIndex,
            chapterTitle: expectedTitle,
            content: chapterContent,
            chunkLength: chunkLen,
            includeChapterTitle: showTitle,
            removeDuplicatedTitle: removeDuplicatedTitle,
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
                    removeDuplicatedTitle: removeDuplicatedTitle,
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
        cancelChapterAdvanceTask()
        finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "pause")
        checkpointProgressAndRelease()
        self.isPlaying = false
        self.lastPausedTime = Date()
        invalidateAudibleHandoffGeneration()
        publishLifecycleState(isPlaying: false)
        setSystemNowPlayingPlaybackState(.paused)

        if tool == "system" {
            siriService.pause()
        } else if tool == "nghitts" {
            flushNghiEnergySummary(reason: "pause", force: true)
            cancelNghiWakeTask()
            nghiAudioPlayerQueue.pause()
            Task { await PiperSynthesisCoordinator.shared.cancelPendingOptionalReserveRequests() }
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
        restartSleepTimerIfNeeded()
        if isPlaying {
            if tool == "system" {
                if siriService.isPaused {
                    if siriService.resume() {
                        publishLifecycleState(isPlaying: true)
                    } else {
                        speakCurrent()
                    }
                } else {
                    speakCurrent()
                }
            } else if tool == "nghitts" {
                if nghiAudioPlayerQueue.resume() {
                    publishLifecycleState(isPlaying: true)
                    updatePrefetchWindow()
                    prepareNextNghiAudioIfPossible()
                } else {
                    speakCurrent()
                }
            } else {
                if let player = audioPlayer, !player.isPlaying {
                    let ok = player.play()
                    if ok {
                        publishLifecycleState(isPlaying: true)
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

        if tool == "system" {
            if siriService.isPaused {
                if siriService.resume() {
                    publishLifecycleState(isPlaying: true)
                } else {
                    speakCurrent()
                }
            } else {
                speakCurrent()
            }
        } else if tool == "nghitts" {
            if nghiAudioPlayerQueue.resume() {
                publishLifecycleState(isPlaying: true)
                updatePrefetchWindow()
                prepareNextNghiAudioIfPossible()
            } else if nghiPlaybackTask != nil {
                updatePrefetchWindow()
            } else if let cachedData = preloadedData[currentParagraphIndex] {
                playNghiAudioData(cachedData, playbackId: currentPlaybackId ?? String(UUID().uuidString.prefix(4)))
                updatePrefetchWindow()
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
                        if player.play() {
                            publishLifecycleState(isPlaying: true)
                        } else {
                            speakCurrent()
                        }
                    }
                } else {
                    speakCurrent()
                }
            }
        }
        setSystemNowPlayingPlaybackState(.playing)
        syncRemoteCommandState()
        updateNowPlayingInfo()
    }

    private func stopPlayback(keepWidget: Bool = false) {
        finishTTSAutoAdvancePerf(outcome: "cancelled", endpoint: "stop")
        finishTTSPrefetchPerfSummary()
        flushNghiEnergySummary(reason: "stop", force: true)
        checkpointProgressAndRelease()
        sessionID = UUID()
        self.isPlaying = false
        self.wasPlayingBeforeSettings = false
        self.wasPlayingBeforeInterruption = false
        self.ttsProcessingGeneration += 1
        invalidateAudibleHandoffGeneration()
        startSpeakingTask?.cancel()
        startSpeakingTask = nil
        chapterQueueRefreshTask?.cancel()
        chapterQueueRefreshTask = nil
        cancelChapterAdvanceTask()
        nowPlayingUpdateGeneration &+= 1
        nowPlayingMetadataTask?.cancel()
        nowPlayingMetadataTask = nil
        nowPlayingMetadataTaskKey = nil
        nowPlayingStaticMetadata = nil
        nowPlayingCoverDownloadKey = nil

        if !keepWidget {
            self.playingBookId = ""
            self.currentParagraphIndex = -1
            self.currentParentParagraphIndex = -1
            self.savedParagraphIdentityBeforeSettings = -1
            self.highlightRange = nil
            self.showFloatingWidget = false
        }

        publishLifecycleState(isPlaying: false, isStopped: !keepWidget)
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
        savedSettingsSnapshot = captureTTSSettingsSnapshot()
        if isPlaying {
            pause()
        }
    }

    public func resumeAfterSettings() {
        guard !chapterContent.isEmpty else {
            stopPlayback(keepWidget: false)
            return
        }

        let currentSnapshot = captureTTSSettingsSnapshot()
        // Note: TTSSettingsSnapshot captures all text-processing and synthesis-affecting settings
        // (voice, pitch, speed, chunkLength, delay, preprocessor toggles, pause durations, extension config)
        // and explicitly excludes ONLY nghittsSafeCachedTimeThreshold.
        // Therefore, if isSynthesisIdentityUnchanged is true, no synthesis-affecting setting changed.
        let isSynthesisIdentityUnchanged = (savedSettingsSnapshot != nil && savedSettingsSnapshot == currentSnapshot)
        savedSettingsSnapshot = nil

        let savedParagraphIdentity = savedParagraphIdentityBeforeSettings
        savedParagraphIdentityBeforeSettings = -1
        let wasPlaying = wasPlayingBeforeSettings || isPlaying
        wasPlayingBeforeSettings = false

        if isSynthesisIdentityUnchanged {
            if wasPlaying {
                resume()
            }
            return
        }

        // Dừng engine cũ để áp dụng cài đặt mới (nhưng giữ widget nổi)
        stopPlayback(keepWidget: true)

        if normalizedChapterText.lines.isEmpty && !chapterContent.isEmpty {
            self.normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(chapterContent)
        }

        // Nạp lại phân đoạn
        var buildLines = normalizedChapterText.lines
        if readRemoveDuplicatedTitle(for: playingBookId), let first = buildLines.first {
            let compiledTOCRegexes = TranslateUtils.getCompiledActiveTOCRegexes()
            if TranslateUtils.isChapterHeaderLine(first.text, compiledTOCRegexes: compiledTOCRegexes) {
                buildLines.removeFirst()
            }
        }
        let rebuiltEntries = buildLines.map {
            TTSLineEntry(lineId: $0.id, originalText: $0.text, translatedText: $0.text, spans: [])
        }
        self.paragraphs = playbackParagraphs(from: TTSParagraphBuilder.buildFromEntries(rebuiltEntries, chunkLength: chunkLength))

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
                TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Hẹn giờ: Đã tự động tạm dừng khi đọc hết chương.", type: .info))
                return
            }
            stopCurrentPlayback()
            if let nextIdx = nextChapterIndex(after: playingChapterIndex) {
                advanceToNextChapter(nextIdx: nextIdx)
            } else {
                stopCurrentPlayback()
                pause()
                TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Đã phát hết nội dung bộ truyện.", type: .info))
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

    internal func stopCurrentPlayback() {
        invalidateAudibleHandoffGeneration()
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
                TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Hẹn giờ: Đã tự động tạm dừng khi đọc hết chương.", type: .info))
                return
            }
            if let nextIdx = nextChapterIndex(after: playingChapterIndex) {
                stopCurrentPlayback()
                advanceToNextChapter(nextIdx: nextIdx)
            } else {
                // Đã hết sách hoàn toàn
                stopCurrentPlayback()
                pause()
                TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Đã phát hết nội dung bộ truyện.", type: .info))
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
        let removeDuplicatedTitle = readRemoveDuplicatedTitle(for: playingBookId)
        let extFingerprint: String?
        if tool == "system" || tool == "nghitts" || tool == "google" {
            extFingerprint = nil
        } else {
            extFingerprint = ExtensionManager.shared.getTTSRuntimeFingerprint(
                localPath: extensionLocalPath,
                configJson: extensionConfigJson
            )
        }
        return TTSPreparedNextChapterKey(
            bookId: playingBookId,
            chapterIndex: chapter.index,
            chapterUrl: chapter.url,
            chapterHost: chapter.host,
            chapterTitle: chapter.title,
            tool: tool,
            selectedVoice: selectedVoice,
            googlePitch: tool == "google" ? pitch : nil,
            chunkLength: chunkLength,
            includeChapterTitle: showTitle,
            removeDuplicatedTitle: removeDuplicatedTitle,
            isTranslationEnabled: self.sessionTranslationEnabled,
            translationToken: TranslateUtils.translationGenerationToken(for: playingBookId),
            extensionLocalPath: extensionLocalPath,
            extensionConfigJson: extensionConfigJson,
            extensionFingerprint: extFingerprint
        )
    }

    private func advanceToNextChapter(nextIdx: Int) {
        guard let nextChapter = chaptersQueue.first(where: { $0.index == nextIdx }) else {
            if let followingIdx = nextChapterIndex(after: nextIdx) {
                advanceToNextChapter(nextIdx: followingIdx)
            } else {
                stopCurrentPlayback()
                pause()
                TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Đã phát hết nội dung bộ truyện.", type: .info))
                onChapterFinished?()
            }
            return
        }
        cancelChapterAdvanceTask()
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
        case .audioReady(_, _, let processed, let audioData, let loadMs, let processMs, _):
            updateTTSAutoAdvanceLoadPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                loadMs: loadMs,
                origin: "next_prefetch_audio"
            )
            updateTTSAutoAdvanceProcessPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                processMs: processMs
            )

            applyNextChapter(
                index: processed.chapterIndex,
                content: processed.normalizedContent,
                title: processed.chapterTitle,
                paragraphs: processed.paragraphs,
                chapter: nextChapter,
                firstAudioData: audioData
            )

        case .synthesizingAudio(_, _, let processed, let task, let synthesisKey, let loadMs, let processMs):
            updateTTSAutoAdvanceLoadPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                loadMs: loadMs,
                origin: "next_prefetch_dto"
            )
            updateTTSAutoAdvanceProcessPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                processMs: processMs
            )

            self.claimedSynthesisTask = task
            self.claimedSynthesisTaskKey = synthesisKey
            let currentGen = self.chapterAdvanceTaskGeneration

            let advanceTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.claimedSynthesisTaskKey == synthesisKey {
                        self.claimedSynthesisTask = nil
                        self.claimedSynthesisTaskKey = nil
                    }
                }

                if requestedKey.tool == "nghitts" {
                    await PiperSynthesisCoordinator.shared.promote(synthesisKey: synthesisKey, to: .demand)
                } else {
                    await RemoteTTSSynthesisCoordinator.shared.promote(key: synthesisKey, to: .current)
                }
                if AppLogger.shared.isLoggingEnabled {
                    AppLogger.shared.log("[TTSHandoff] Claimed in-flight synthesis task chapter=\(nextChapter.index) engine=\(requestedKey.tool)")
                }

                var firstAudioData: Data? = nil

                do {
                    let data = try await task.value
                    if !data.isEmpty {
                        firstAudioData = data
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if AppLogger.shared.isLoggingEnabled {
                        AppLogger.shared.log("⚠️ [TTSHandoff] In-flight synthesis task failed: \(error.localizedDescription). Falling back to current synthesis.")
                    }
                }

                @MainActor
                func isValidState() -> Bool {
                    if Task.isCancelled { return false }
                    if self.chapterAdvanceTaskGeneration != currentGen { return false }
                    if !self.isPlaying { return false }
                    if self.sessionID != expectedSessionID { return false }
                    if self.ttsProcessingGeneration != expectedGeneration { return false }
                    if self.playingBookId != expectedBookId { return false }
                    if self.chaptersQueue.first(where: { $0.index == nextChapter.index })?.url != expectedChapterURL { return false }
                    if self.playingChapterIndex >= nextChapter.index { return false }
                    if self.tool != requestedKey.tool { return false }
                    if self.selectedVoice != requestedKey.selectedVoice { return false }
                    if requestedKey.tool == "google" && self.pitch != requestedKey.googlePitch { return false }
                    if requestedKey.tool != "system" && requestedKey.tool != "nghitts" && requestedKey.tool != "google" {
                        if self.extensionLocalPath != requestedKey.extensionLocalPath { return false }
                        if self.extensionConfigJson != requestedKey.extensionConfigJson { return false }
                        let currentFingerprint = ExtensionManager.shared.getTTSRuntimeFingerprint(localPath: self.extensionLocalPath, configJson: self.extensionConfigJson)
                        if currentFingerprint != requestedKey.extensionFingerprint { return false }
                    }
                    return true
                }

                guard isValidState() else { return }

                self.applyNextChapter(
                    index: processed.chapterIndex,
                    content: processed.normalizedContent,
                    title: processed.chapterTitle,
                    paragraphs: processed.paragraphs,
                    chapter: nextChapter,
                    firstAudioData: firstAudioData
                )
            }
            self.chapterAdvanceTask = advanceTask

        case .processedReady(_, _, let processed, let loadMs, let processMs):
            updateTTSAutoAdvanceLoadPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                loadMs: loadMs,
                origin: "next_prefetch_dto"
            )
            updateTTSAutoAdvanceProcessPerf(
                sessionID: expectedSessionID,
                generation: expectedGeneration,
                chapterIndex: nextChapter.index,
                processMs: processMs
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
        let removeDuplicatedTitle = readRemoveDuplicatedTitle(for: expectedBookId)
        let rawTitle = nextChapter.title
        let processor = TTSBackgroundProcessor()

        let isPerfLogging = AppLogger.shared.isLoggingEnabled
        let perfStartUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0

        chapterAdvanceTaskGeneration &+= 1
        let taskGeneration = chapterAdvanceTaskGeneration
        chapterAdvanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.clearChapterAdvanceTask(ifGenerationMatches: taskGeneration)
            }

            let result: ChapterContentResult
            do {
                result = try await self.loadChapterForAutoAdvance(request)
            } catch is CancellationError {
                if isPerfLogging {
                    self.finishTTSAutoAdvancePerf(
                        outcome: "cancelled",
                        endpoint: "cancelled",
                        sessionID: expectedSessionID,
                        generation: expectedGeneration,
                        chapterIndex: nextChapter.index
                    )
                }
                return
            } catch {
                let loadEndUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
                let loadMs = isPerfLogging ? (loadEndUptime - perfStartUptime) * 1000 : 0
                if isPerfLogging {
                    self.updateTTSAutoAdvanceLoadPerf(
                        sessionID: expectedSessionID,
                        generation: expectedGeneration,
                        chapterIndex: nextChapter.index,
                        loadMs: loadMs,
                        origin: "unknown"
                    )
                    self.finishTTSAutoAdvancePerf(
                        outcome: "load_failed",
                        endpoint: "error",
                        sessionID: expectedSessionID,
                        generation: expectedGeneration,
                        chapterIndex: nextChapter.index
                    )
                }
                guard self.sessionID == expectedSessionID,
                      self.playingBookId == expectedBookId,
                      self.isPlaying else { return }
                AppLogger.shared.log("❌ [TTSManager] Không tải được chương \(nextChapter.index): \(error.localizedDescription)")
                TTSPresentationEventCenter.shared.send(.showToast(message: "⚠️ Lỗi tải chương \(nextChapter.index), đang chuyển sang chương tiếp theo...", type: .info))
                if let followingIdx = self.nextChapterIndex(after: nextChapter.index) {
                    self.advanceToNextChapter(nextIdx: followingIdx)
                } else {
                    self.stopCurrentPlayback()
                    self.pause()
                    TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Đã phát hết nội dung bộ truyện.", type: .info))
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
                self.updateTTSAutoAdvanceLoadPerf(
                    sessionID: expectedSessionID,
                    generation: expectedGeneration,
                    chapterIndex: nextChapter.index,
                    loadMs: loadMs,
                    origin: originStr
                )
            }

            guard self.isPlaying,
                  self.sessionID == expectedSessionID,
                  self.ttsProcessingGeneration == expectedGeneration,
                  self.playingBookId == expectedBookId,
                  self.chaptersQueue.first(where: { $0.index == nextChapter.index })?.url == expectedChapterURL,
                  self.playingChapterIndex < nextChapter.index else {
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
                    removeDuplicatedTitle: removeDuplicatedTitle,
                    sessionID: expectedSessionID,
                    generation: expectedGeneration
                )
            } catch is CancellationError {
                if isPerfLogging {
                    self.finishTTSAutoAdvancePerf(
                        outcome: "cancelled",
                        endpoint: "cancelled",
                        sessionID: expectedSessionID,
                        generation: expectedGeneration,
                        chapterIndex: nextChapter.index
                    )
                }
                return
            } catch {
                let processEndUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
                let processMs = isPerfLogging ? (processEndUptime - loadEndUptime) * 1000 : 0
                if isPerfLogging {
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
                guard self.sessionID == expectedSessionID,
                      self.playingBookId == expectedBookId,
                      self.isPlaying else { return }
                AppLogger.shared.log("❌ [TTSManager] Lỗi xử lý chương \(nextChapter.index): \(error.localizedDescription)")
                TTSPresentationEventCenter.shared.send(.showToast(message: "⚠️ Lỗi xử lý chương \(nextChapter.index), đang chuyển sang chương tiếp theo...", type: .info))
                if let followingIdx = self.nextChapterIndex(after: nextChapter.index) {
                    self.advanceToNextChapter(nextIdx: followingIdx)
                } else {
                    self.stopCurrentPlayback()
                    self.pause()
                    TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Đã phát hết nội dung bộ truyện.", type: .info))
                    self.onChapterFinished?()
                }
                return
            }

            let processEndUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
            let processMs = isPerfLogging ? (processEndUptime - loadEndUptime) * 1000 : 0

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

    private func loadChapterForAutoAdvance(
        _ request: ChapterContentRequest
    ) async throws -> ChapterContentResult {
        do {
            return try await ChapterContentRepository.shared.load(request)
        } catch is CancellationError {
            // A force-refresh consumer may supersede the shared repository load
            // without canceling this playback task. Reattach once to that fresh
            // load; a real stop/session cancellation still exits immediately.
            try Task.checkCancellation()
            return try await ChapterContentRepository.shared.load(request)
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
        let playbackParas = playbackParagraphs(from: paragraphs)
        guard !playbackParas.isEmpty else {
            AppLogger.shared.log("⚠️ [TTSManager] Chương \(index) không có nội dung đọc, tự động chuyển sang chương tiếp theo.")
            TTSPresentationEventCenter.shared.send(.showToast(message: "⚠️ Chương \(index) không có nội dung, đang chuyển tiếp...", type: .info))
            if let nextIdx = nextChapterIndex(after: index) {
                advanceToNextChapter(nextIdx: nextIdx)
            } else {
                stopCurrentPlayback()
                pause()
                TTSPresentationEventCenter.shared.send(.showToast(message: "📖 Đã phát hết nội dung bộ truyện.", type: .info))
                onChapterFinished?()
            }
            return
        }

        checkpointProgress()
        self.playingChapterIndex = index
        self.playingChapterUrl = chapter.url
        self.chapterTitle = title
        self.normalizedChapterText = ChapterTextNormalizer.normalizeProcessedContent(content)
        self.chapterContent = content
        self.paragraphs = playbackParas
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

        var remainingParents = Set<Int>()
        if currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count {
            for index in currentParagraphIndex..<paragraphs.count {
                remainingParents.insert(paragraphs[index].paragraphIndex)
            }
        }
        let remainingCount = remainingParents.isEmpty ? 99 : remainingParents.count

        let isPastHalfway = currentParagraphIndex >= paragraphs.count / 2
        let isNearEnd = remainingCount <= 3
        let shouldPrefetch = (tool == "nghitts" ? isPlaying : (isPastHalfway || isNearEnd))

        if shouldPrefetch {
            nextChapterPrefetcher.startPrefetch(
                key: key,
                sessionID: sessionID,
                generation: ttsProcessingGeneration,
                extensionInfo: extensionInfo,
                processor: TTSBackgroundProcessor()
            )
        }
    }

    private func checkAndPromoteNextChapterAudioIfNeeded() {
        guard isPlaying,
              tool != "system",
              currentParagraphIndex >= 0,
              currentParagraphIndex < paragraphs.count,
              !nextChapterPrefetcher.reservesNghiAudioSlot else { return }

        var remainingParents = Set<Int>()
        for index in currentParagraphIndex..<paragraphs.count {
            remainingParents.insert(paragraphs[index].paragraphIndex)
            if tool != "nghitts" && remainingParents.count > 2 { return }
        }

        nextChapterPrefetcher.promoteAudioIfNeeded(
            remainingParentCount: remainingParents.count,
            nghiService: nghiTTSService,
            googleService: googleService,
            extService: extService
        )
    }

    // speakCurrent: Bắt đầu phát âm thanh của đoạn văn bản hiện tại (index = currentParagraphIndex)
    internal func speakCurrent() {
        guard isPlaying, currentParagraphIndex >= 0 && currentParagraphIndex < paragraphs.count else { return }

        restartSleepTimerIfNeeded()

        let paragraph = paragraphs[currentParagraphIndex]

        // Áp dụng các quy tắc thay thế ký tự trước khi đọc
        let textToSpeak = TTSReplacementManager.shared.applyReplacements(to: paragraph.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

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
        let index = currentParagraphIndex
        let playbackId = currentPlaybackId ?? String(UUID().uuidString.prefix(4))
        let context = makePlaybackContext(paragraphIndex: index, playbackId: playbackId, engine: "system")

        siriService.speak(
            text: text,
            voiceName: selectedVoice,
            speed: speed,
            pitch: pitch,
            onStart: { [weak self] in
                guard let self else { return }
                self.commitAudibleParagraphState(index: index, playbackId: playbackId, context: context)
            },
            onFinish: { [weak self] in
                guard let self = self, self.isContextValid(context) else { return }
                self.nextParagraph()
            }
        )
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



    // updatePrefetchWindow: Cập nhật cửa sổ trượt (Sliding Window) tải trước dữ liệu âm thanh
    // Mục tiêu: Luôn có sẵn âm thanh PCMBuffer của đoạn tiếp theo (N+1) trong bộ đệm để phát ngay khi đoạn hiện tại (N) kết thúc, triệt tiêu hoàn toàn khoảng trễ tổng hợp âm thanh.
    internal func updatePrefetchWindow() {
        guard isPlaying, tool != "system" else { return }

        if tool == "nghitts" {
            updateNghiPrefetchWindow()
            return
        }

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



    private func recordNghiUnderrun(index: Int, reusedInFlight: Bool) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if nghiEnergy.startedAt == nil {
            nghiEnergy.startedAt = now
        }
        nghiEnergy.underrunCount += 1
        if reusedInFlight {
            nghiEnergy.reusedInFlightCount += 1
        }
        AppLogger.shared.log(
            "[NghiEnergy] Underrun chapter=\(playingChapterIndex) index=\(index) reusedInFlight=\(reusedInFlight) thermal=\(Self.nghiThermalStateName(currentThermalState))"
        )
        flushNghiEnergySummary(reason: "interval", force: false)
    }



    private func cancelNghiWakeTask() {
        nghiWakeTask?.cancel()
        nghiWakeTask = nil
    }

    internal func cancelNghiRefill() {
        nghiRefillGeneration &+= 1
        nghiRefillTask?.cancel()
        nghiRefillTask = nil
        nghiRefillInFlightIndex = nil
        clearNghiRefillFailureStates()
    }

    internal struct RefillFailureKey: Hashable {
        let sessionID: UUID
        let chapterIndex: Int
        let paragraphIndex: Int
    }

    internal struct RefillFailureState {
        var attempts: Int = 0
        var isBlocked: Bool = false
    }

    private var nghiRefillFailureStates: [RefillFailureKey: RefillFailureState] = [:]
    private var nghiRefillRetryTask: Task<Void, Never>?
    private var nghiRefillRetryGeneration: UInt64 = 0

    internal func cancelNghiRefillRetry() {
        nghiRefillRetryGeneration &+= 1
        nghiRefillRetryTask?.cancel()
        nghiRefillRetryTask = nil
    }

    internal func clearNghiRefillFailureStates() {
        nghiRefillFailureStates.removeAll()
        cancelNghiRefillRetry()
    }

    public var nghiWatermarks: (low: Double, high: Double) {
        (low: nghittsSafeCachedTimeThreshold, high: nghittsSafeCachedTimeThreshold)
    }

    public func calculateNghiCachedTime() -> Double {
        guard tool == "nghitts" else { return 0.0 }
        let effectiveRate = nghiAudioPlayerQueue.effectivePlaybackRate
        var total: Double = 0.0

        let N = currentParagraphIndex
        guard N >= 0 && N < paragraphs.count else { return 0.0 }

        if let player = nghiAudioPlayerQueue.currentPlayer, (player.isPlaying || nghiAudioPlayerQueue.isPaused) {
            let remainingMedia = max(0, player.duration - player.currentTime)
            total += remainingMedia / max(0.01, Double(player.rate))
        } else if let data = preloadedData[N] {
            let dur = preloadedDurations[N] ?? WAVEncoder.duration(of: data)
            total += dur / effectiveRate
        } else {
            return 0.0
        }

        var startIdx = N + 1
        if nghiAudioPlayerQueue.hasPreparedNext,
           let nextItem = nghiAudioPlayerQueue.nextItem,
           nextItem.paragraphIndex == N + 1 {
            total += nghiAudioPlayerQueue.preparedNextDuration ?? 0.0
            startIdx = N + 2
        }

        if startIdx < paragraphs.count {
            for idx in startIdx..<paragraphs.count {
                if let data = preloadedData[idx] {
                    let dur = preloadedDurations[idx] ?? WAVEncoder.duration(of: data)
                    total += dur / effectiveRate
                } else {
                    return total
                }
            }
        }

        if let nextIdx = nextChapterIndex(after: playingChapterIndex),
           case .audioReady(let key, _, _, let audioData, _, _, _) = nextChapterPrefetcher.currentState,
           key.tool == "nghitts",
           key.chapterIndex == nextIdx {
            let duration = WAVEncoder.duration(of: audioData)
            total += duration / effectiveRate
        }

        return total
    }

    public func updateNghiBufferedDuration() {
        let dur = calculateNghiCachedTime()
        if abs(nghiBufferedDuration - dur) > 0.05 {
            nghiBufferedDuration = dur
        }
    }

    private func updateNghiPrefetchWindow() {
        updateNghiBufferedDuration()
        guard isPlaying, tool == "nghitts" else {
            cancelNghiWakeTask()
            return
        }

        prepareNextNghiAudioIfPossible()
        triggerNextChapterPrefetch()

        let currentSessionID = sessionID
        let currentChapter = playingChapterIndex
        let blockedIndices = Set(
            nghiRefillFailureStates.compactMap { (key, state) -> Int? in
                guard key.sessionID == currentSessionID, key.chapterIndex == currentChapter, state.isBlocked else { return nil }
                return key.paragraphIndex
            }
        )

        let N = currentParagraphIndex
        let nextIndex = N + 1
        let isNextBlocked = blockedIndices.contains(nextIndex)
        let isNextPrepared = nghiAudioPlayerQueue.nextItem?.paragraphIndex == nextIndex
        if nextIndex < paragraphs.count && preloadedData[nextIndex] == nil && !isNextPrepared && !isNextBlocked {
            scheduleNghiRefill()
            return
        }

        nextChapterPrefetcher.promoteAudioIfNeeded(
            remainingParentCount: max(0, paragraphs.count - N),
            nghiService: nghiTTSService,
            googleService: googleService,
            extService: extService
        )

        let cachedTime = calculateNghiCachedTime()
        let threshold = nghittsSafeCachedTimeThreshold

        if cachedTime < threshold {
            cancelNghiWakeTask()
            let optionalCount = preloadedData.keys.filter { $0 >= N + 2 }.count
            if optionalCount < NghiSynthesisPolicy.maxOptionalReserveItems {
                scheduleNghiRefill()
            }
        } else {
            let sleepSeconds = max(0.5, cachedTime - threshold)
            cancelNghiWakeTask()
            nghiWakeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                guard let self, !Task.isCancelled, self.isPlaying, self.tool == "nghitts" else { return }
                self.updateNghiPrefetchWindow()
            }
        }
    }

    nonisolated internal static func selectNghiOptionalRefillCandidate(
        currentParagraphIndex N: Int,
        paragraphsCount: Int,
        preloadedIndices: Set<Int>,
        blockedIndices: Set<Int> = []
    ) -> Int? {
        let optionalStart = N + 2
        guard optionalStart < paragraphsCount else { return nil }
        for idx in optionalStart..<paragraphsCount {
            if !preloadedIndices.contains(idx) && !blockedIndices.contains(idx) {
                return idx
            }
        }
        return nil
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
        tool == "nghitts" &&
        sessionID == expectedSessionID &&
        playingBookId == expectedBookID &&
        playingChapterIndex == expectedChapterIndex &&
        playingChapterUrl == expectedChapterURL &&
        selectedVoice == expectedVoice &&
        ttsProcessingGeneration == expectedGeneration &&
        nghiRefillGeneration == expectedRefillGeneration
    }

    internal enum RefillTaskOutcome: Equatable {
        case success
        case blocked(reason: String, action: String)
        case retryScheduled(reason: String, attempt: Int)
        case cancelled
    }

    nonisolated internal static func classifyTTSError(_ error: Error) -> (reason: String, isNonRetryable: Bool) {
        if let ttsError = error as? TTSError {
            switch ttsError {
            case .badRequest:
                return ("badRequest", true)
            case .notFound:
                return ("notFound", true)
            case .modelNotCached:
                return ("modelNotCached", true)
            case .engineUnavailable:
                return ("engineUnavailable", true)
            case .internalError:
                return ("internalError", false)
            }
        }
        return ("unknownError", false)
    }

    nonisolated internal static func evaluateRefillError(
        _ error: Error,
        currentAttempts: Int,
        maxAttempts: Int = 2
    ) -> (newState: RefillFailureState, outcome: RefillTaskOutcome) {
        if error is CancellationError {
            return (RefillFailureState(attempts: currentAttempts, isBlocked: false), .cancelled)
        }

        let (reasonCode, isNonRetryable) = classifyTTSError(error)
        if isNonRetryable {
            return (RefillFailureState(attempts: currentAttempts, isBlocked: true), .blocked(reason: reasonCode, action: "blocked_non_retryable"))
        }

        let nextAttempt = currentAttempts + 1
        if nextAttempt >= maxAttempts {
            return (RefillFailureState(attempts: nextAttempt, isBlocked: true), .blocked(reason: reasonCode, action: "blocked_max_retries"))
        } else {
            return (RefillFailureState(attempts: nextAttempt, isBlocked: false), .retryScheduled(reason: reasonCode, attempt: nextAttempt))
        }
    }

    nonisolated internal static func canScheduleNghiRefill(
        hasRefillTask: Bool,
        hasRetryTask: Bool
    ) -> Bool {
        !hasRefillTask && !hasRetryTask
    }

    private static func logPrefetchFailure(chapter: Int, index: Int, attempt: Int, reason: String, action: String) {
        if AppLogger.shared.isLoggingEnabled {
            AppLogger.shared.log("[TTSPerf] PrefetchFailure chapter=\(chapter) index=\(index) engine=nghitts attempt=\(attempt) reason=\(reason) action=\(action)")
        }
    }

    private func scheduleNghiRefill() {
        guard isPlaying,
              tool == "nghitts",
              Self.canScheduleNghiRefill(hasRefillTask: nghiRefillTask != nil, hasRetryTask: nghiRefillRetryTask != nil),
              let service = nghiTTSService else { return }

        let currentSessionID = sessionID
        let currentChapter = playingChapterIndex
        let blockedIndices = Set(
            nghiRefillFailureStates.compactMap { (key, state) -> Int? in
                guard key.sessionID == currentSessionID, key.chapterIndex == currentChapter, state.isBlocked else { return nil }
                return key.paragraphIndex
            }
        )

        let N = currentParagraphIndex
        let nextIndex = N + 1
        let optionalCount = preloadedData.keys.filter { $0 >= N + 2 }.count
        let targetIndex: Int?

        let isNextBlocked = blockedIndices.contains(nextIndex)
        let isNextPrepared = nghiAudioPlayerQueue.nextItem?.paragraphIndex == nextIndex
        if nextIndex < paragraphs.count && preloadedData[nextIndex] == nil && !isNextPrepared && !isNextBlocked {
            targetIndex = nextIndex
        } else if calculateNghiCachedTime() < nghittsSafeCachedTimeThreshold && optionalCount < NghiSynthesisPolicy.maxOptionalReserveItems {
            targetIndex = Self.selectNghiOptionalRefillCandidate(
                currentParagraphIndex: N,
                paragraphsCount: paragraphs.count,
                preloadedIndices: Set(preloadedData.keys),
                blockedIndices: blockedIndices
            )
        } else {
            targetIndex = nil
        }

        guard let index = targetIndex else { return }
        let paragraph = paragraphs[index]
        let text = TTSReplacementManager.shared.applyReplacements(to: paragraph.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let isEssentialNext = index == nextIndex
        let synthesisPriority: SynthesisPriority = isEssentialNext ? .immediateSuccessor : .optionalReserve

        let expectedSessionID = sessionID
        let expectedBookID = playingBookId
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl
        let expectedVoice = selectedVoice
        let expectedGeneration = ttsProcessingGeneration
        nghiRefillGeneration &+= 1
        let refillGeneration = nghiRefillGeneration
        nghiRefillInFlightIndex = index

        let synthesisKey = TTSSynthesisIdentity.computeKey(
            chapterURL: expectedChapterURL,
            chapterIndex: expectedChapterIndex,
            paragraphIndex: index,
            finalText: text,
            engine: "nghitts",
            voice: expectedVoice,
            googlePitch: nil,
            extensionFingerprint: nil
        )

        nghiRefillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var taskOutcome: RefillTaskOutcome = .cancelled

            defer {
                if self.nghiRefillGeneration == refillGeneration {
                    self.nghiRefillInFlightIndex = nil
                    self.nghiRefillTask = nil
                    self.updateNghiBufferedDuration()

                    switch taskOutcome {
                    case .success:
                        let key = RefillFailureKey(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, paragraphIndex: index)
                        self.nghiRefillFailureStates.removeValue(forKey: key)
                        if self.isPlaying && self.tool == "nghitts" {
                            self.updateNghiPrefetchWindow()
                        }

                    case .blocked:
                        if self.isPlaying && self.tool == "nghitts" {
                            self.updateNghiPrefetchWindow()
                        }

                    case .retryScheduled, .cancelled:
                        break
                    }
                }
            }

            guard self.isValidNghiRefillContext(
                sessionID: expectedSessionID,
                bookID: expectedBookID,
                chapterIndex: expectedChapterIndex,
                chapterURL: expectedChapterURL,
                voice: expectedVoice,
                generation: expectedGeneration,
                refillGeneration: refillGeneration
            ) else { return }

            do {
                let synthesized = try await service.synthesizeWithDuration(
                    text: text,
                    voice: expectedVoice,
                    speed: 1.0,
                    boundaryKind: paragraph.boundaryKind,
                    priority: synthesisPriority,
                    synthesisKey: synthesisKey
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

                self.recordNghiSynthesis(
                    pcmDuration: synthesized.pcmDuration,
                    queueWaitMs: synthesized.queueWaitMs,
                    synthesisMs: synthesized.synthesisMs,
                    essential: isEssentialNext,
                    onDemand: false
                )

                self.preloadedData[index] = synthesized.data
                self.preloadedDurations[index] = synthesized.pcmDuration
                self.updateNghiBufferedDuration()
                self.prepareNextNghiAudioIfPossible()
                self.checkAndPromoteNextChapterAudioIfNeeded()
                taskOutcome = .success
            } catch is CancellationError {
                taskOutcome = .cancelled
                return
            } catch {
                guard self.isValidNghiRefillContext(
                    sessionID: expectedSessionID,
                    bookID: expectedBookID,
                    chapterIndex: expectedChapterIndex,
                    chapterURL: expectedChapterURL,
                    voice: expectedVoice,
                    generation: expectedGeneration,
                    refillGeneration: refillGeneration
                ) else { return }

                let key = RefillFailureKey(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, paragraphIndex: index)
                let currentState = self.nghiRefillFailureStates[key] ?? RefillFailureState()
                let (newState, outcome) = Self.evaluateRefillError(error, currentAttempts: currentState.attempts)

                self.nghiRefillFailureStates[key] = newState

                switch outcome {
                case .cancelled:
                    taskOutcome = .cancelled

                case .blocked(let reason, let action):
                    taskOutcome = outcome
                    Self.logPrefetchFailure(chapter: expectedChapterIndex, index: index, attempt: newState.attempts, reason: reason, action: action)

                case .retryScheduled(let reason, let attempt):
                    taskOutcome = outcome
                    Self.logPrefetchFailure(chapter: expectedChapterIndex, index: index, attempt: attempt, reason: reason, action: "retry_scheduled")

                    self.cancelNghiRefillRetry()
                    let retryGen = self.nghiRefillRetryGeneration
                    let retrySessionID = expectedSessionID
                    let retryChapterIndex = expectedChapterIndex
                    self.nghiRefillRetryTask = Task { @MainActor [weak self] in
                        defer {
                            if let self, self.nghiRefillRetryGeneration == retryGen {
                                self.nghiRefillRetryTask = nil
                            }
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard let self, !Task.isCancelled, self.nghiRefillRetryGeneration == retryGen else { return }
                        guard self.isPlaying,
                              self.tool == "nghitts",
                              self.sessionID == retrySessionID,
                              self.playingChapterIndex == retryChapterIndex else { return }
                        self.nghiRefillRetryTask = nil
                        self.updateNghiPrefetchWindow()
                    }

                case .success:
                    break
                }
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
        let pitchToUse = pitch
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
        let audioSynthesisWorkerRef = self.audioSynthesisWorker

        let extFingerprint: String?
        if toolBeforeStart == "google" {
            extFingerprint = nil
        } else {
            extFingerprint = ExtensionManager.shared.getTTSRuntimeFingerprint(localPath: localPath, configJson: configJson)
        }
        let synthesisKey = TTSSynthesisIdentity.computeKey(
            chapterURL: expectedChapterURL,
            chapterIndex: expectedChapterIndex,
            paragraphIndex: index,
            finalText: text,
            engine: toolBeforeStart,
            voice: voice,
            googlePitch: toolBeforeStart == "google" ? pitchToUse : nil,
            extensionFingerprint: extFingerprint
        )

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.removePrefetchTask(for: index, taskGen: taskGen)
            }

            let offset = max(0, index - self.currentParagraphIndex)

            @MainActor
            func isValidSession() -> Bool {
                if Task.isCancelled { return false }
                if !self.isPlaying { return false }
                if self.sessionID != expectedSessionID { return false }
                if self.playingBookId != expectedBookId { return false }
                if self.playingChapterIndex != expectedChapterIndex { return false }
                if self.playingChapterUrl != expectedChapterURL { return false }
                if self.selectedVoice != voice { return false }
                if self.tool != toolBeforeStart { return false }
                return true
            }

            guard isValidSession() else { return }

            do {
                let data = try await audioSynthesisWorkerRef.synthesizeParagraph(
                    synthesisKey: synthesisKey,
                    engine: toolBeforeStart,
                    textLength: text.count,
                    priority: .prefetch,
                    offset: offset,
                    prefetchDelayMs: self.prefetchDelayMs
                ) {
                    if toolBeforeStart == "google" {
                        return try await googleService.synthesize(text: text, voice: voice, speed: 1.0, pitch: pitchToUse)
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
        nghiAudioPlayerQueue.onScheduleHandoff = { [weak self] item, startTime in
            self?.handleNghiScheduledHandoff(item: item, startTime: startTime)
        }
    }

    private var nghiScheduledHandoffTask: Task<Void, Never>?

    internal func makePlaybackContext(paragraphIndex: Int, playbackId: String, engine: String) -> TTSPlaybackContext {
        TTSPlaybackContext(
            sessionID: sessionID,
            handoffGeneration: audibleHandoffGeneration,
            bookId: playingBookId,
            chapterIndex: playingChapterIndex,
            paragraphIndex: paragraphIndex,
            playbackId: playbackId,
            engine: engine
        )
    }

    internal func isContextValid(_ context: TTSPlaybackContext) -> Bool {
        guard isPlaying,
              sessionID == context.sessionID,
              audibleHandoffGeneration == context.handoffGeneration,
              playingBookId == context.bookId,
              playingChapterIndex == context.chapterIndex,
              tool == context.engine else {
            return false
        }

        if context.engine == "nghitts" {
            let isCurrentOrNext = (context.paragraphIndex == currentParagraphIndex || context.paragraphIndex == currentParagraphIndex + 1)
            guard isCurrentOrNext else { return false }
            let inQueue = nghiAudioPlayerQueue.currentItem?.paragraphIndex == context.paragraphIndex ||
                          nghiAudioPlayerQueue.nextItem?.paragraphIndex == context.paragraphIndex
            return inQueue
        } else {
            guard context.paragraphIndex == currentParagraphIndex else { return false }
            if let currentPlaybackId, !currentPlaybackId.isEmpty {
                return currentPlaybackId == context.playbackId
            }
            return true
        }
    }

    internal func publishLifecycleState(isPlaying: Bool, isStopped: Bool = false) {
        let newParentIndex = isStopped ? -1 : currentParentParagraphIndex
        let newRange = isStopped ? nil : highlightRange
        let newBookId = isStopped ? "" : playingBookId
        let newChapterIndex = isStopped ? -1 : playingChapterIndex

        let newSnapshot = TTSPlaybackSnapshot(
            isPlaying: isPlaying,
            playingBookId: newBookId,
            playingChapterIndex: newChapterIndex,
            currentParentParagraphIndex: newParentIndex,
            highlightRange: newRange,
            sessionID: sessionID,
            handoffGeneration: audibleHandoffGeneration
        )
        if self.playbackSnapshot != newSnapshot {
            self.playbackSnapshot = newSnapshot
        }
        if self.highlightRange != newRange {
            self.highlightRange = newRange
        }
        if self.currentParentParagraphIndex != newParentIndex {
            self.currentParentParagraphIndex = newParentIndex
        }
    }

    private func handleNghiScheduledHandoff(item: NghiAudioPlayerQueue.Item, startTime: TimeInterval) {
        guard isPlaying, tool == "nghitts" else { return }
        let context = makePlaybackContext(paragraphIndex: item.paragraphIndex, playbackId: item.playbackId, engine: "nghitts")
        nghiScheduledHandoffTask?.cancel()

        let initialClockLag = max(0.001, startTime - (nghiAudioPlayerQueue.currentPlayer?.deviceCurrentTime ?? startTime))

        nghiScheduledHandoffTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(initialClockLag * 1_000_000_000))
            } catch {
                return
            }
            guard let self, self.isContextValid(context) else { return }

            var recheckCount = 0
            while !Task.isCancelled {
                guard let status = self.nghiAudioPlayerQueue.getScheduledStatus(for: item) else { return }
                let currentTime = status.currentDeviceTime
                let targetStart = status.scheduledStartTime ?? startTime

                if currentTime < targetStart - 0.005 {
                    let remaining = max(0.001, targetStart - currentTime)
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    } catch {
                        return
                    }
                    guard self.isContextValid(context) else { return }
                } else {
                    if status.isCurrentItem {
                        if status.isCurrentPlaying {
                            self.commitAudibleParagraphState(index: item.paragraphIndex, playbackId: item.playbackId, context: context)
                        }
                        return
                    } else if status.isNextItem {
                        if status.isNextPlaying {
                            self.commitAudibleParagraphState(index: item.paragraphIndex, playbackId: item.playbackId, context: context)
                            return
                        } else if recheckCount < 5 {
                            recheckCount += 1
                            do {
                                try await Task.sleep(nanoseconds: 5_000_000)
                            } catch {
                                return
                            }
                            guard self.isContextValid(context) else { return }
                        } else {
                            return
                        }
                    } else {
                        return
                    }
                }
            }
        }
    }

    private func prepareNextNghiAudioIfPossible() {
        guard tool == "nghitts",
              isPlaying,
              nghiAudioPlayerQueue.isPlaying else { return }

        let nextIndex = currentParagraphIndex + 1
        guard nextIndex >= 0, nextIndex < paragraphs.count else {
            // Chỉ clear nextItem nếu nó không phải item của đoạn hiện tại đang phát.
            // Tránh hủy nhầm audio đoạn cuối chương khi nó đang là currentItem trong queue.
            if let nextItem = nghiAudioPlayerQueue.nextItem,
               nextItem.paragraphIndex != currentParagraphIndex {
                nghiAudioPlayerQueue.clearPreparedNext()
            }
            return
        }

        // Chỉ skip nếu nextItem đúng là đoạn tiếp theo cần prepare.
        // Không dùng || currentParagraphIndex vì nextItem có thể vẫn giữ index của
        // đoạn vừa được transition (chưa discard), khiến đoạn cuối chương không bao giờ được prepare.
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

    internal func invalidateAudibleHandoffGeneration() {
        audibleHandoffGeneration &+= 1
        nghiScheduledHandoffTask?.cancel()
        nghiScheduledHandoffTask = nil
    }

    internal func commitAudibleParagraphState(index: Int, playbackId: String, context: TTSPlaybackContext? = nil) {
        if let context, !isContextValid(context) { return }
        guard index >= 0 && index < paragraphs.count else { return }
        currentParagraphIndex = index
        currentPlaybackId = playbackId

        let paragraph = paragraphs[index]
        let newParentIndex = paragraph.paragraphIndex
        let newRange = paragraph.range

        let newSnapshot = TTSPlaybackSnapshot(
            isPlaying: isPlaying,
            playingBookId: playingBookId,
            playingChapterIndex: playingChapterIndex,
            currentParentParagraphIndex: newParentIndex,
            highlightRange: newRange,
            sessionID: sessionID,
            handoffGeneration: audibleHandoffGeneration
        )

        guard self.playbackSnapshot != newSnapshot else { return }

        self.playbackSnapshot = newSnapshot
        if self.highlightRange != newRange {
            self.highlightRange = newRange
        }
        if self.currentParentParagraphIndex != newParentIndex {
            self.currentParentParagraphIndex = newParentIndex
        }
        recordProgressInMemory()

        updatePrefetchWindow()
        updateNowPlayingInfo()
    }

    private func commitParagraphState(index: Int, playbackId: String) {
        commitAudibleParagraphState(index: index, playbackId: playbackId)
    }

    private func handleNghiAudioTransition(_ item: NghiAudioPlayerQueue.Item) {
        nghiScheduledHandoffTask?.cancel()
        nghiScheduledHandoffTask = nil
        guard isPlaying,
              tool == "nghitts",
              (item.paragraphIndex == currentParagraphIndex || item.paragraphIndex == currentParagraphIndex + 1),
              item.paragraphIndex < paragraphs.count else {
            nghiAudioPlayerQueue.stop()
            return
        }

        preloadedData.removeValue(forKey: item.paragraphIndex)
        preloadedDurations.removeValue(forKey: item.paragraphIndex)
        if item.paragraphIndex != currentParagraphIndex {
            let context = makePlaybackContext(paragraphIndex: item.paragraphIndex, playbackId: item.playbackId, engine: "nghitts")
            commitAudibleParagraphState(index: item.paragraphIndex, playbackId: item.playbackId, context: context)
        }

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
            invalidateAudibleHandoffGeneration()
            commitAudibleParagraphState(index: currentParagraphIndex, playbackId: playbackId)
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
            TTSPresentationEventCenter.shared.send(.showToast(message: "Lỗi trình phát âm thanh: \(error.localizedDescription). Tạm dừng đọc.", type: .error))
        }

        updateNowPlayingInfo()
    }

    internal func playAudioData(_ audioData: Data, withId customId: String? = nil, context: TTSPlaybackContext? = nil) {
        let playbackId = customId ?? context?.playbackId ?? String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId

        if let context, !isContextValid(context) { return }

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
                if let context {
                    guard isContextValid(context) else { return }
                }
                self.isPlaying = true
                commitAudibleParagraphState(index: context?.paragraphIndex ?? currentParagraphIndex, playbackId: playbackId, context: context)
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
                TTSPresentationEventCenter.shared.send(.showToast(message: "Lỗi trình phát âm thanh: Không thể phát dữ liệu audio.", type: .error))
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
            TTSPresentationEventCenter.shared.send(.showToast(message: "Lỗi trình phát âm thanh: \(error.localizedDescription). Tạm dừng đọc.", type: .error))
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
            pause()
            TTSPresentationEventCenter.shared.send(.showToast(message: "⚠️ NghiTTS engine chưa được khởi tạo. Tạm dừng đọc.", type: .error))
            return
        }

        cancelNghiPlaybackTask()
        let index = currentParagraphIndex
        let playbackId = String(UUID().uuidString.prefix(4))
        self.currentPlaybackId = playbackId
        let expectedSessionID = sessionID
        let expectedBookID = playingBookId
        let expectedChapterIndex = playingChapterIndex
        let expectedChapterURL = playingChapterUrl
        let expectedGeneration = ttsProcessingGeneration
        let expectedVoice = selectedVoice
        let playbackTaskGeneration = nghiPlaybackTaskGeneration

        if let cachedData = preloadedData[index] {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: "nghitts", index: index, outcome: "hit")
            let currentDuration = preloadedDurations[index] ?? WAVEncoder.duration(of: cachedData)
            preloadedDurations[index] = currentDuration
            self.playAudioData(cachedData, withId: playbackId)
            updatePrefetchWindow()
            return
        } else {
            recordPrefetchResult(sessionID: expectedSessionID, chapterIndex: expectedChapterIndex, engine: "nghitts", index: index, outcome: "miss")
        }

        let reusableRefillIndex = nghiRefillInFlightIndex
        let reusableRefillTask: Task<Void, Never>?
        if let reusableRefillIndex, reusableRefillIndex == index {
            reusableRefillTask = nghiRefillTask
        } else {
            reusableRefillTask = nil
        }
        let reusesCurrentSynthesis = reusableRefillIndex == index && reusableRefillTask != nil
        if index > 0 && preloadedData[index] == nil {
            recordNghiUnderrun(index: index, reusedInFlight: reusesCurrentSynthesis)
            nghiAudioPlayerQueue.markWaitingForSynthesis(currentParentIndex: index)
        }

        let synthesisKey = TTSSynthesisIdentity.computeKey(
            chapterURL: expectedChapterURL,
            chapterIndex: expectedChapterIndex,
            paragraphIndex: index,
            finalText: text,
            engine: "nghitts",
            voice: expectedVoice,
            googlePitch: nil,
            extensionFingerprint: nil
        )
        Task {
            await PiperSynthesisCoordinator.shared.promote(synthesisKey: synthesisKey, to: .demand)
        }

        nghiPlaybackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.nghiPlaybackTaskGeneration == playbackTaskGeneration {
                    self.nghiPlaybackTask = nil
                }
            }
            do {
                @MainActor func isIdentityValid() -> Bool {
                    !Task.isCancelled &&
                    self.currentPlaybackId == playbackId &&
                    self.sessionID == expectedSessionID &&
                    self.playingBookId == expectedBookID &&
                    self.playingChapterIndex == expectedChapterIndex &&
                    self.playingChapterUrl == expectedChapterURL &&
                    self.ttsProcessingGeneration == expectedGeneration &&
                    self.nghiPlaybackTaskGeneration == playbackTaskGeneration &&
                    self.selectedVoice == expectedVoice &&
                    self.tool == "nghitts"
                }

                if let reusableRefillTask {
                    await reusableRefillTask.value
                    guard isIdentityValid() else { return }
                }

                let currentData: Data
                if let cachedData = self.preloadedData[index] {
                    currentData = cachedData
                } else {
                    let boundaryKind = self.paragraphs.indices.contains(index) ? self.paragraphs[index].boundaryKind : .paragraphEnd
                    let synthesized = try await service.synthesizeWithDuration(
                        text: text,
                        voice: expectedVoice,
                        speed: 1.0,
                        boundaryKind: boundaryKind,
                        priority: .demand,
                        synthesisKey: synthesisKey
                    )
                    guard isIdentityValid() else { return }
                    currentData = synthesized.data
                    self.preloadedData[index] = synthesized.data
                    self.preloadedDurations[index] = synthesized.pcmDuration
                    self.recordNghiSynthesis(
                        pcmDuration: synthesized.pcmDuration,
                        queueWaitMs: synthesized.queueWaitMs,
                        synthesisMs: synthesized.synthesisMs,
                        essential: true,
                        onDemand: true
                    )
                }

                guard isIdentityValid(), self.isPlaying else { return }
                self.playAudioData(currentData, withId: playbackId)
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
                AppLogger.shared.log("NghiTTS synthesis failed: \(error.localizedDescription)")
                self.preloadedData.removeValue(forKey: index)
                self.preloadedDurations.removeValue(forKey: index)
                self.currentPlaybackId = nil
                self.pause()
                TTSPresentationEventCenter.shared.send(.showToast(message: "Lỗi NghiTTS: \(error.localizedDescription). Tạm dừng đọc.", type: .error))
            }
        }
    }





    private func cleanUpTempFile() {
        // File tạm được dọn dẹp trực tiếp trong ExtTTSService.synthesize
    }

    // MARK: - Text Segmentation (Phân đoạn văn bản)

    // MARK: - Lock Screen & Remote Control Sync



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
        nowPlayingController.onPlayCommand = { [weak self] in
            guard let self = self else { return }
            _ = self.dispatchRemoteTransportCommand(.play, entryUptime: DispatchTime.now().uptimeNanoseconds, isMain: true, eventId: "RPT")
        }
        nowPlayingController.onPauseCommand = { [weak self] in
            guard let self = self else { return }
            _ = self.dispatchRemoteTransportCommand(.pause, entryUptime: DispatchTime.now().uptimeNanoseconds, isMain: true, eventId: "RPT")
        }
        nowPlayingController.onNextCommand = { [weak self] in
            guard let self = self else { return }
            self.handleRemoteTransportCommandOnMain(.next)
        }
        nowPlayingController.onPreviousCommand = { [weak self] in
            guard let self = self else { return }
            self.handleRemoteTransportCommandOnMain(.previous)
        }
        nowPlayingController.setupRemoteCommandCenter()
        self.setRemoteCommandsEnabled(false)
        #if DEBUG
        logRemoteTrace("setupRemoteCommandCenter")
        #endif
    }

    internal func updateNowPlayingInfo() {
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
                    if self.tool != "system" && self.tool != "nghitts" {
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


    public func applyTOCReconciliation(_ result: LocalTOCRefreshResult, newChapters: [TTSChapterInfo]? = nil) {
        if let newChapters {
            self.chaptersQueue = newChapters
        }
        if let newIndex = result.ttsNewIndex {
            self.playingChapterIndex = newIndex
        }
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
