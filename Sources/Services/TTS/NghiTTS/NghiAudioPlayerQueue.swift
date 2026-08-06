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
        case schedulingFailed

        var errorDescription: String? {
            switch self {
            case .playbackFailed:
                return "AVAudioPlayer could not start playback."
            case .schedulingFailed:
                return "AVAudioPlayer could not schedule the next item."
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

    private func makePlayer(data: Data) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.enableRate = true
        player.rate = playbackRate
        player.prepareToPlay()
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
        let startTime = currentPlayer.deviceCurrentTime + wallClockRemaining

        nextPlayer.rate = playbackRate
        nextIsScheduled = nextPlayer.play(atTime: startTime)

        if !nextIsScheduled {
            AppLogger.shared.log("⚠️ [TTSManager] Không thể schedule AVAudioPlayer tiếp theo bằng device clock")
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

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === currentPlayer {
            let finishedItem = currentItem
            let promotedItem = promoteNextAfterCurrentFinished()

            if let promotedItem {
                onTransition?(promotedItem)
            } else if let finishedItem {
                onFinished?(finishedItem, flag)
            }
            return
        }

        if player === nextPlayer, let nextItem {
            onFinished?(nextItem, flag)
            discardNext()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "Unknown AVAudioPlayer decode error"
        AppLogger.shared.log("❌ [TTSManager] AVAudioPlayer decode error: \(message)")

        if player === currentPlayer, let currentItem {
            onFinished?(currentItem, false)
            stop()
        } else if player === nextPlayer, let nextItem {
            onFinished?(nextItem, false)
            discardNext()
        }
    }
}
