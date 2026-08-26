import SwiftUI
import Combine

struct TTSWidgetSnapshot: Equatable {
    var isPlaying = false
    var showFloatingWidget = false
    var playingBookId = ""
    var playingCoverUrl = ""
    var timerMode: TTSManager.SleepTimerMode = .off
    var sleepTimerBadgeText = ""
}

/// Projects only the state rendered by the floating widget. Paragraph/highlight,
/// voice-download and settings changes no longer invalidate the widget tree.
@MainActor
final class TTSWidgetStateReader: ObservableObject {
    @Published private(set) var snapshot = TTSWidgetSnapshot()
    private var cancellables = Set<AnyCancellable>()

    init(manager: TTSManager? = nil) {
        let manager = manager ?? TTSManager.shared
        snapshot = Self.makeSnapshot(from: manager)

        manager.$isPlaying.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$showFloatingWidget.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$playingBookId.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$playingCoverUrl.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$timerMode.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$sleepTimerRemainingSeconds.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$isTimerRunning.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
    }

    private func refresh(from manager: TTSManager?) {
        guard let manager else { return }
        let newSnapshot = Self.makeSnapshot(from: manager)
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
    }

    private static func makeSnapshot(from manager: TTSManager) -> TTSWidgetSnapshot {
        TTSWidgetSnapshot(
            isPlaying: manager.isPlaying,
            showFloatingWidget: manager.showFloatingWidget,
            playingBookId: manager.playingBookId,
            playingCoverUrl: manager.playingCoverUrl,
            timerMode: manager.timerMode,
            sleepTimerBadgeText: manager.sleepTimerBadgeText
        )
    }
}

struct TTSRootPresentationSnapshot: Equatable {
    var showFloatingWidget = false
    var showingSettingsSheet = false
}

/// Keeps the app root independent from paragraph, highlight and timer ticks.
@MainActor
final class TTSRootPresentationReader: ObservableObject {
    @Published private(set) var snapshot = TTSRootPresentationSnapshot()
    private var cancellables = Set<AnyCancellable>()

    init(manager: TTSManager? = nil) {
        let manager = manager ?? TTSManager.shared
        snapshot = Self.makeSnapshot(from: manager)

        manager.$showFloatingWidget.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$showingSettingsSheet.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
    }

    private func refresh(from manager: TTSManager?) {
        guard let manager else { return }
        let newSnapshot = Self.makeSnapshot(from: manager)
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
    }

    private static func makeSnapshot(from manager: TTSManager) -> TTSRootPresentationSnapshot {
        TTSRootPresentationSnapshot(
            showFloatingWidget: manager.showFloatingWidget,
            showingSettingsSheet: manager.showingSettingsSheet
        )
    }
}

struct ReaderTTSStateSnapshot: Equatable {
    var isPlaying = false
    var showFloatingWidget = false
    var playingBookId = ""
    var playingChapterIndex = -1
    var currentParentParagraphIndex = -1
    var highlightRange: NSRange?
    var preparingParentParagraphIndex: Int?
    var preparingHighlightRange: NSRange?
}

/// Projects TTS state needed by one Reader. Highlight movement from another
/// book is collapsed to an unchanged inactive snapshot, so it does not redraw
/// the unrelated Reader.
@MainActor
final class ReaderTTSStateReader: ObservableObject {
    @Published private(set) var snapshot = ReaderTTSStateSnapshot()
    private var scopedBookId: String?
    private var cancellables = Set<AnyCancellable>()
    private let manager: TTSManager

    init(manager: TTSManager? = nil) {
        let manager = manager ?? TTSManager.shared
        self.manager = manager
        let ps = manager.playbackSnapshot
        snapshot = ReaderTTSStateSnapshot(
            isPlaying: ps.isPlaying,
            showFloatingWidget: manager.showFloatingWidget,
            playingBookId: ps.playingBookId,
            playingChapterIndex: ps.playingChapterIndex,
            currentParentParagraphIndex: -1,
            highlightRange: nil,
            preparingParentParagraphIndex: nil,
            preparingHighlightRange: nil
        )

        manager.$playbackSnapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        manager.$showFloatingWidget.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func scope(to bookId: String) {
        guard scopedBookId != bookId else { return }
        scopedBookId = bookId
        refresh()
    }

    private func refresh() {
        let ps = manager.playbackSnapshot
        let ownsBook = scopedBookId == ps.playingBookId
        let newSnapshot = ReaderTTSStateSnapshot(
            isPlaying: ps.isPlaying,
            showFloatingWidget: manager.showFloatingWidget,
            playingBookId: ps.playingBookId,
            playingChapterIndex: ps.playingChapterIndex,
            currentParentParagraphIndex: ownsBook ? ps.currentParentParagraphIndex : -1,
            highlightRange: ownsBook ? ps.highlightRange : nil,
            preparingParentParagraphIndex: ownsBook ? ps.preparingParentParagraphIndex : nil,
            preparingHighlightRange: ownsBook ? ps.preparingHighlightRange : nil
        )
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
    }
}
