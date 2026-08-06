import AVFoundation
import Foundation

@MainActor
final class NghiAudioPlayerQueue: NSObject, AVAudioPlayerDelegate {
    struct Item: Equatable {
        let paragraphIndex: Int
        let playbackId: String
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

    private(set) var currentItem: Item?
    private(set) var nextItem: Item?

    private var currentPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?
    private var nextData: Data?
    private var nextIsScheduled = false
    private var playbackRate: Float = 1.0

    var isPlaying: Bool {
        currentPlayer?.isPlaying == true
    }

    var hasPreparedNext: Bool {
        nextPlayer != nil
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

        discardNext()

        let player = try makePlayer(data: data)
        nextPlayer = player
        nextData = data
        nextItem = item
        scheduleNextIfPossible()
    }

    func pause() {
        currentPlayer?.pause()
        unscheduleNextKeepingData()
    }

    @discardableResult
    func resume() -> Bool {
        guard let currentPlayer else { return false }
        guard currentPlayer.play() else { return false }
        scheduleNextIfPossible()
        return true
    }

    func updateRate(_ rate: Double) {
        playbackRate = clampedRate(rate)
        currentPlayer?.rate = playbackRate

        if nextIsScheduled {
            unscheduleNextKeepingData()
        } else {
            nextPlayer?.rate = playbackRate
        }

        scheduleNextIfPossible()
    }

    func stop() {
        currentPlayer?.stop()
        currentPlayer?.delegate = nil
        currentPlayer = nil
        currentItem = nil
        discardNext()
    }

    func clearPreparedNext() {
        discardNext()
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

        // If the current item is effectively over, let the delegate promotion
        // start the prepared player immediately instead of scheduling in the past.
        guard wallClockRemaining > 0.005 else { return }

        let startTime = currentPlayer.deviceCurrentTime + wallClockRemaining
        nextPlayer.rate = playbackRate
        nextIsScheduled = nextPlayer.play(atTime: startTime)

        if !nextIsScheduled {
            AppLogger.shared.log("⚠️ [TTSManager] Không thể schedule AVAudioPlayer tiếp theo bằng device clock; sẽ fallback khi đoạn hiện tại kết thúc")
        }
    }

    private func unscheduleNextKeepingData() {
        guard nextPlayer != nil else { return }

        nextPlayer?.stop()
        nextIsScheduled = false

        guard let nextData else {
            discardNext()
            return
        }

        do {
            let rebuilt = try makePlayer(data: nextData)
            nextPlayer = rebuilt
        } catch {
            AppLogger.shared.log("⚠️ [TTSManager] Không thể rebuild AVAudioPlayer đã prepare: \(error.localizedDescription)")
            discardNext()
        }
    }

    private func discardNext() {
        nextPlayer?.stop()
        nextPlayer?.delegate = nil
        nextPlayer = nil
        nextData = nil
        nextItem = nil
        nextIsScheduled = false
    }

    private func promoteNextAfterCurrentFinished() -> Item? {
        guard let nextPlayer, let nextItem else {
            currentPlayer = nil
            currentItem = nil
            return nil
        }

        currentPlayer?.delegate = nil
        currentPlayer = nextPlayer
        currentItem = nextItem
        self.nextPlayer = nil
        self.nextItem = nil
        nextData = nil
        nextIsScheduled = false

        if currentPlayer?.isPlaying != true {
            _ = currentPlayer?.play()
        }

        return currentItem
    }

    private func clampedRate(_ rate: Double) -> Float {
        Float(min(2.0, max(0.5, rate)))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
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
        Task { @MainActor in
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
