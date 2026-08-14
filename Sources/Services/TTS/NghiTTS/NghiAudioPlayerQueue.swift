import AVFoundation
import Foundation

@MainActor
final class NghiAudioPlayerQueue: NSObject, AVAudioPlayerDelegate {
    struct Item: Equatable, Sendable {
        let paragraphIndex: Int
        let playbackId: String
    }

    enum QueueState: Equatable, Sendable {
        case idle
        case playing(current: Item)
        case prepared(current: Item, next: Item)
        case scheduled(current: Item, next: Item, atDeviceTime: TimeInterval)
        case paused(current: Item, next: Item?, wasScheduled: Bool)
        case waitingForSynthesis(currentParentIndex: Int)
    }

    enum QueueError: LocalizedError {
        case playbackFailed
        case preparationFailed

        var errorDescription: String? {
            switch self {
            case .playbackFailed:
                return "AVAudioPlayer could not start playback."
            case .preparationFailed:
                return "AVAudioPlayer could not prepare audio for playback."
            }
        }
    }

    var onTransition: ((Item) -> Void)?
    var onFinished: ((Item, Bool) -> Void)?
    var onScheduleHandoff: ((Item, TimeInterval) -> Void)?


    private(set) var currentItem: Item?
    private(set) var nextItem: Item?
    private(set) var state: QueueState = .idle

    private(set) var currentPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?
    private var nextData: Data?
    private var nextIsScheduled = false
    private var playbackRate: Float = 1.0

    struct ScheduledStatus: Equatable, Sendable {
        let isCurrentItem: Bool
        let isNextItem: Bool
        let isCurrentPlaying: Bool
        let isNextPlaying: Bool
        let currentDeviceTime: TimeInterval
        let scheduledStartTime: TimeInterval?
    }

    func getScheduledStatus(for item: Item) -> ScheduledStatus? {
        guard let current = currentPlayer else { return nil }
        if nextItem == item {
            guard case let .scheduled(_, _, atDeviceTime) = state else { return nil }
            return ScheduledStatus(
                isCurrentItem: false,
                isNextItem: true,
                isCurrentPlaying: current.isPlaying,
                isNextPlaying: nextPlayer?.isPlaying ?? false,
                currentDeviceTime: current.deviceCurrentTime,
                scheduledStartTime: atDeviceTime
            )
        } else if currentItem == item {
            return ScheduledStatus(
                isCurrentItem: true,
                isNextItem: false,
                isCurrentPlaying: current.isPlaying,
                isNextPlaying: false,
                currentDeviceTime: current.deviceCurrentTime,
                scheduledStartTime: nil
            )
        }
        return nil
    }

    var isPlaying: Bool {
        currentPlayer?.isPlaying == true
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var isWaitingForSynthesis: Bool {
        if case .waitingForSynthesis = state { return true }
        return false
    }

    var hasPreparedNext: Bool {
        nextPlayer != nil
    }

    var effectivePlaybackRate: Double {
        Double(currentPlayer?.rate ?? playbackRate)
    }

    var preparedNextDuration: Double? {
        guard let nextPlayer else { return nil }
        return nextPlayer.duration / max(0.01, Double(nextPlayer.rate))
    }

    func markWaitingForSynthesis(currentParentIndex: Int) {
        state = .waitingForSynthesis(currentParentIndex: currentParentIndex)
    }

    func start(
        data: Data,
        item: Item,
        rate: Double
    ) throws {
        stop()
        playbackRate = clampedRate(rate)

        let player = try makePlayer(data: data)
        currentPlayer = player
        currentItem = item
        state = .playing(current: item)

        guard player.play() else {
            stop()
            throw QueueError.playbackFailed
        }
    }

    func prepareNext(
        data: Data,
        item: Item
    ) throws {
        if nextItem == item, nextPlayer != nil {
            return
        }

        if nextIsScheduled || nextPlayer?.isPlaying == true {
            return
        }

        discardNext()

        let player = try makePlayer(data: data)
        nextPlayer = player
        nextData = data
        nextItem = item
        if let currentItem {
            state = .prepared(current: currentItem, next: item)
        }
        scheduleNextIfPossible()
    }

    func pause() {
        let wasScheduled = nextIsScheduled
        currentPlayer?.pause()
        if nextIsScheduled {
            nextPlayer?.stop()
            nextIsScheduled = false
            nextPlayer?.prepareToPlay()
        }
        if let currentItem {
            state = .paused(current: currentItem, next: nextItem, wasScheduled: wasScheduled)
        } else {
            state = .idle
        }
    }

    @discardableResult
    func resume() -> Bool {
        guard let currentPlayer else { return false }
        guard currentPlayer.play() else { return false }
        if let currentItem {
            if let nextItem {
                state = .prepared(current: currentItem, next: nextItem)
            } else {
                state = .playing(current: currentItem)
            }
        }
        scheduleNextIfPossible()
        return true
    }

    func updateRate(_ rate: Double) {
        playbackRate = clampedRate(rate)
        currentPlayer?.rate = playbackRate
        nextPlayer?.rate = playbackRate

        if nextIsScheduled {
            // Hủy schedule cũ trên hardware nhưng GIỮ NGUYÊN instance nextPlayer
            nextPlayer?.stop()
            nextIsScheduled = false
            nextPlayer?.prepareToPlay()
        }

        scheduleNextIfPossible()
    }

    func stop() {
        currentPlayer?.stop()
        currentPlayer?.delegate = nil
        currentPlayer = nil
        currentItem = nil
        state = .idle
        discardNext(force: true)
    }

    func clearPreparedNext() {
        discardNext(force: true)
    }

    private func makePlayer(data: Data) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.enableRate = true
        player.rate = playbackRate
        guard player.prepareToPlay() else {
            player.delegate = nil
            throw QueueError.preparationFailed
        }
        return player
    }

    private func scheduleNextIfPossible() {
        guard !nextIsScheduled,
              let currentPlayer,
              currentPlayer.isPlaying,
              let nextPlayer else {
            return
        }

        let mediaRemaining = max(0, currentPlayer.duration - currentPlayer.currentTime)
        let effectiveRate = max(0.01, Double(currentPlayer.rate))
        let wallClockRemaining = mediaRemaining / effectiveRate

        // Safe scheduling window: nếu thời gian còn lại giữa 5ms và 50ms, KHÔNG ép schedule bằng atTime.
        // Giữ nextPlayer ở trạng thái prepared, để khi currentPlayer finish, promoteNextAfterCurrentFinished sẽ play() ngay lập tức.
        guard wallClockRemaining > 0.050 else {
            if wallClockRemaining <= 0.005 {
                AppLogger.shared.log("ℹ️ [NghiAudioPlayerQueue] Audio effectively over (wallClockRemaining <= 5ms); skipping atTime schedule for immediate delegate handoff")
            } else {
                AppLogger.shared.log("ℹ️ [NghiAudioPlayerQueue] Remaining time (\(String(format: "%.3f", wallClockRemaining))s) <= 50ms safe window; keeping nextPlayer prepared for immediate finish handoff")
            }
            return
        }

        let startTime = currentPlayer.deviceCurrentTime + wallClockRemaining
        nextPlayer.rate = playbackRate
        nextIsScheduled = nextPlayer.play(atTime: startTime)

        if nextIsScheduled {
            if let currentItem, let nextItem {
                state = .scheduled(current: currentItem, next: nextItem, atDeviceTime: startTime)
                onScheduleHandoff?(nextItem, startTime)
            }
        } else {
            AppLogger.shared.log("⚠️ [NghiAudioPlayerQueue] Không thể schedule AVAudioPlayer tiếp theo bằng device clock; sẽ fallback khi đoạn hiện tại kết thúc")
        }
    }

    private func discardNext(force: Bool = false) {
        if !force && (nextIsScheduled || nextPlayer?.isPlaying == true) {
            return
        }
        nextPlayer?.stop()
        nextPlayer?.delegate = nil
        nextPlayer = nil
        nextData = nil
        nextItem = nil
        nextIsScheduled = false
        if let currentItem {
            state = .playing(current: currentItem)
        } else {
            state = .idle
        }
    }

    private func promoteNextAfterCurrentFinished() -> Item? {
        guard let nextPlayer, let nextItem else {
            currentPlayer = nil
            currentItem = nil
            state = .idle
            return nil
        }

        currentPlayer?.delegate = nil
        currentPlayer = nextPlayer
        currentItem = nextItem
        self.nextPlayer = nil
        self.nextItem = nil
        nextData = nil
        nextIsScheduled = false
        state = .playing(current: nextItem)

        if currentPlayer?.isPlaying != true {
            _ = currentPlayer?.play()
        }

        return currentItem
    }

    private func clampedRate(_ rate: Double) -> Float {
        Float(min(2.0, max(0.5, rate)))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if player === self.currentPlayer {
                let finishedItem = self.currentItem
                let promotedItem = self.promoteNextAfterCurrentFinished()

                if let promotedItem {
                    self.onTransition?(promotedItem)
                } else if let finishedItem {
                    self.onFinished?(finishedItem, flag)
                }
                return
            }

            if player === self.nextPlayer, let nextItem = self.nextItem {
                self.onFinished?(nextItem, flag)
                self.discardNext()
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let message = error?.localizedDescription ?? "Unknown AVAudioPlayer decode error"
            AppLogger.shared.log("❌ [TTSManager] AVAudioPlayer decode error: \(message)")

            if player === self.currentPlayer, let currentItem = self.currentItem {
                self.onFinished?(currentItem, false)
                self.stop()
            } else if player === self.nextPlayer, let nextItem = self.nextItem {
                self.onFinished?(nextItem, false)
                self.discardNext()
            }
        }
    }
}
