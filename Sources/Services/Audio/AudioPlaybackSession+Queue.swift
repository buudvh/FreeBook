import Foundation

/// Thứ tự phát, chuyển bài, lặp và xáo trộn.
///
/// - `playOrder`: thứ tự của vòng hiện tại — thường = mục lục; xáo trộn = hoán vị **bắt đầu bằng bài đang phát** (bật xáo
///   giữa chừng, chọn bài khi đang xáo). Tắt xáo ⇒ về thứ tự mục lục, bài đang phát giữ nguyên.
/// - Hết bài (`advanceAfterTrackEnded`): lặp một ⇒ phát lại bài; còn bài kế trong `playOrder` ⇒ sang; hết vòng: lặp album
///   ⇒ vòng kế (đang xáo thì xáo lại — `nextCycleOrder`), tắt ⇒ dừng ở cuối.
/// - `autoAdvanceTarget()` là nguồn **duy nhất** cho "bài kế khi hết bài" — lượt nạp sẵn (`+TrackLoading`) và lúc hết bài
///   dùng chung nên luôn chọn cùng một bài (vòng xáo kế dựng sẵn một lần ở `upcomingCycleOrder`).
/// - Bài sau / bài trước do người dùng (nút, màn khoá, tai nghe): lặp một không áp; hết thứ tự chỉ quay vòng khi lặp album.
/// - Hẹn giờ "Hết bài" (`MediaSleepTimer`): hết bài thì dừng ở cuối bài, không sang bài kế kể cả đang lặp.
extension AudioPlaybackSession {
    /// Chỉ số mục lục của các bài theo thứ tự mục lục.
    var naturalOrder: [Int] { tracks.map(\.index) }

    /// Có bài sau cho nút "bài sau" (màn khoá bật/tắt lệnh theo giá trị này).
    var hasNextTrack: Bool {
        guard let position = currentOrderPosition else { return !playOrder.isEmpty }
        return position + 1 < playOrder.count || (repeatMode == .album && playOrder.count > 1)
    }

    /// Có bài trước (không tính "về đầu bài").
    var hasPreviousTrack: Bool {
        guard let position = currentOrderPosition else { return false }
        return position > 0 || (repeatMode == .album && playOrder.count > 1)
    }

    private var currentOrderPosition: Int? {
        guard let currentTrackIndex else { return nil }
        return playOrder.firstIndex(of: currentTrackIndex)
    }

    // MARK: - Dựng thứ tự

    /// Dựng lại thứ tự phát của vòng hiện tại; xáo trộn ⇒ `index` đứng đầu, phần còn lại ngẫu nhiên.
    func resetPlayOrder(startingWith index: Int) {
        upcomingCycleOrder = nil
        guard isShuffled else {
            playOrder = naturalOrder
            return
        }
        let rest = naturalOrder.filter { $0 != index }.shuffled()
        playOrder = track(at: index) != nil ? [index] + rest : rest
    }

    /// Mục lục vừa làm mới (thêm bài ở cuối): bài mới nối vào cuối thứ tự (đang xáo ⇒ xáo phần mới), bỏ bài không còn.
    func syncPlayOrderWithTracks() {
        let valid = Set(naturalOrder)
        var order = playOrder.filter { valid.contains($0) }
        let known = Set(order)
        let added = naturalOrder.filter { !known.contains($0) }
        order += isShuffled ? added.shuffled() : added
        playOrder = order
        upcomingCycleOrder = nil
    }

    /// Thứ tự của vòng kế khi lặp album: thường = mục lục; xáo = hoán vị mới, dựng **một lần** (giữ ở `upcomingCycleOrder`)
    /// và bài đầu khác bài vừa hết khi album có từ 2 bài.
    func nextCycleOrder() -> [Int] {
        guard isShuffled else { return naturalOrder }
        if let upcomingCycleOrder { return upcomingCycleOrder }
        var order = naturalOrder.shuffled()
        if order.count > 1, order.first == currentTrackIndex {
            order.swapAt(0, Int.random(in: 1..<order.count))
        }
        upcomingCycleOrder = order
        return order
    }

    /// Bài sẽ phát khi bài hiện **hết tự nhiên** — không đổi thứ tự (ngoài việc dựng sẵn vòng xáo kế). Lặp một ⇒ chính bài
    /// hiện; `nil` ⇒ hết album, không lặp.
    func autoAdvanceTarget() -> Int? {
        guard let current = currentTrackIndex else { return nil }
        if repeatMode == .one { return current }
        guard let position = currentOrderPosition else { return playOrder.first }
        if position + 1 < playOrder.count { return playOrder[position + 1] }
        guard repeatMode == .album else { return nil }
        return nextCycleOrder().first
    }

    // MARK: - Chuyển bài

    /// Người dùng chọn một bài (danh sách bài). Đang xáo ⇒ thứ tự mới bắt đầu bằng bài đó. Chọn lại bài đang mở ⇒ đang lỗi
    /// thì thử lại, đang dừng thì phát.
    func playTrack(at index: Int) {
        guard isActive, track(at: index) != nil else { return }
        if index == currentTrackIndex {
            if case .failed = phase {
                retry()
            } else if !isPlaying {
                play()
            }
            return
        }
        if isShuffled { resetPlayOrder(startingWith: index) }
        moveToTrack(index, reason: "chọn bài")
    }

    /// Bài sau (nút, màn khoá, tai nghe). Hết thứ tự: lặp album ⇒ sang vòng kế; còn lại không làm gì.
    func next() {
        guard isActive, let position = currentOrderPosition ?? (playOrder.isEmpty ? nil : -1) else { return }
        if position + 1 < playOrder.count {
            moveToTrack(playOrder[position + 1], reason: "bài sau")
            return
        }
        guard repeatMode == .album, playOrder.count > 1 else { return }
        playOrder = nextCycleOrder()
        upcomingCycleOrder = nil
        guard let first = playOrder.first else { return }
        moveToTrack(first, reason: "bài sau (quay về đầu album)")
    }

    /// Bài trước: bài đang phát quá `restartThresholdSeconds` ⇒ về đầu bài; còn lại bài trước trong thứ tự (đầu thứ tự: lặp
    /// album ⇒ bài cuối, không thì về đầu bài).
    func previous() {
        guard isActive else { return }
        if player.currentItem != nil, currentPlaybackTime > Self.restartThresholdSeconds {
            seek(to: 0)
            return
        }
        guard let position = currentOrderPosition else {
            seek(to: 0)
            return
        }
        if position > 0 {
            moveToTrack(playOrder[position - 1], reason: "bài trước")
        } else if repeatMode == .album, playOrder.count > 1, let last = playOrder.last {
            moveToTrack(last, reason: "bài trước (quay về cuối album)")
        } else {
            seek(to: 0)
        }
    }

    /// Chuyển bài do người dùng: lưu tiến độ bài cũ, dừng TTS / phim, phát bài mới từ đầu.
    private func moveToTrack(_ index: Int, reason: String) {
        saveProgress(reason: reason)
        beginUserRequestedPlayback()
        AppLogger.shared.log("⏭️ [AudioPlayer] \(reason): bài \(index)")
        beginTrackLoad(index, resumeSeconds: 0, autoplay: true)
    }

    /// Hết bài (`AVPlayerItem.didPlayToEndTime`). Hẹn giờ "Hết bài" xét **trước** cả lặp một bài: dừng ở cuối bài.
    func advanceAfterTrackEnded() {
        guard let current = currentTrackIndex else { return }
        if sleepTimer.stopsAfterItemEnded() {
            stopAtEndOfTrackForSleepTimer()
            return
        }
        if repeatMode == .one {
            AppLogger.shared.log("🔁 [AudioPlayer] Lặp một bài ⇒ phát lại bài \(current)")
            reachedEndOfItem = false
            seek(to: 0)
            player.play()
            return
        }
        guard let target = autoAdvanceTarget() else {
            AppLogger.shared.log("🏁 [AudioPlayer] Hết album (không lặp) ⇒ dừng ở cuối")
            saveProgress(reason: "hết album", seconds: 0)
            phase = .paused
            syncMiniPlayerState()
            publishNowPlaying()
            // Công tắc "Tự phát bài gợi ý" bật ⇒ phát mục gợi ý đầu tiên của nguồn.
            AudioAutoNextCoordinator.shared.albumDidEnd(in: self)
            return
        }
        if let position = currentOrderPosition, position + 1 >= playOrder.count {
            playOrder = nextCycleOrder()
            upcomingCycleOrder = nil
            AppLogger.shared.log("🔁 [AudioPlayer] Lặp album ⇒ quay về đầu\(isShuffled ? " (xáo lại)" : "")")
        }
        AppLogger.shared.log("⏭️ [AudioPlayer] Hết bài \(current) ⇒ sang bài \(target)")
        beginTrackLoad(target, resumeSeconds: 0, autoplay: true)
        saveProgress(reason: "sang bài kế", seconds: 0)
    }

    // MARK: - Lặp / xáo

    /// `off` → `album` → `one` → `off`, nhớ toàn app.
    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        AudioPlaybackPreferences.repeatMode = repeatMode
        upcomingCycleOrder = nil
        AppLogger.shared.log("🔁 [AudioPlayer] Chế độ lặp: \(repeatMode.title)")
        syncMiniPlayerState()
        publishNowPlaying()
    }

    /// Bật / tắt xáo trộn (nhớ toàn app). Bài đang phát giữ nguyên, thứ tự còn lại dựng lại.
    func toggleShuffle() {
        isShuffled.toggle()
        AudioPlaybackPreferences.isShuffled = isShuffled
        resetPlayOrder(startingWith: currentTrackIndex ?? tracks.first?.index ?? 0)
        AppLogger.shared.log("🔀 [AudioPlayer] Xáo trộn: \(isShuffled ? "bật" : "tắt")")
        syncMiniPlayerState()
        publishNowPlaying()
    }
}
