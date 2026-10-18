import Foundation
import AVFoundation

/// Chẩn đoán "có hình mà mất tiếng" và tự khắc phục bằng phương án dự phòng của `VideoSourceResolution` (1.3.535).
///
/// - Player sang `.playing` ⇒ hẹn `audioCheckDelayNanoseconds` rồi đếm track của **`AVPlayerItem.tracks`**
///   (`AVURLAsset.tracks` thường rỗng với HLS), bỏ track tiếng bị tắt (`isEnabled == false`); nhóm `.audible` của
///   media selection chỉ ghi vào log. Mỗi lượt nạp (`loadGeneration`, kể cả mỗi phương án dự phòng) kiểm một lần; tới
///   hẹn mà đang tạm dừng thì hoãn tới lần phát sau. Item chưa có track nào ⇒ không kết luận (chỉ ghi `⚠️`).
/// - Không có tiếng ⇒ luôn ghi một dòng `❌` (công tắc log tắt vẫn ghi): tiện ích, server, nguồn link, loại playlist do
///   `VideoHLSPlaylistProbe` ghi nhận, URL đã che (host + tên file cuối, không query).
/// - Chỉ link `VideoMediaSniffer` dò từ trang mới có dự phòng: sang phương án kế, giữ giây đang xem. Phương án dự phòng
///   phải có **cả** tiếng lẫn hình (playlist con chỉ có tiếng ⇒ màn đen); lỗi phát cũng sang phương án kế. Nhúng trang
///   là bước cuối; hết phương án thì giữ nguyên. Chỉ tự đổi khi màn trình phát đang hiện ở trước và không PiP — thay
///   item lúc PiP / chạy nền / thu nhỏ làm hỏng các ca đó.
/// - Playlist ghép luồng hình + `audios` (`VideoAudioRenditionComposer`): tiếng là rendition `#EXT-X-MEDIA` ⇒ có lựa
///   chọn `.audible` đang được chọn cũng tính là có tiếng. Mất tiếng thì chỉ ghi log, không đổi (dự phòng là luồng gốc
///   không tiếng); item **lỗi** thì sang dự phòng đó để vẫn xem được hình như trước.
extension VideoPlaybackSession {
    /// Đếm track của một item tại thời điểm kiểm.
    struct AudioInspection {
        var trackCount = 0
        var audioTracks = 0
        var disabledAudioTracks = 0
        var videoTracks = 0
        var hasPicture = false
        /// `nil` = asset không có nhóm `.audible`.
        var audibleOptions: Int?
        var selectedAudible: String?

        var hasAudio: Bool { audioTracks > 0 }
        var hasVideo: Bool { videoTracks > 0 || hasPicture }

        var summary: String {
            var text = "track: \(videoTracks) hình, \(audioTracks) tiếng"
            if disabledAudioTracks > 0 { text += " (+\(disabledAudioTracks) tiếng bị tắt)" }
            if let audibleOptions {
                text += ", nhóm audible: \(audibleOptions) lựa chọn, đang chọn " + (selectedAudible.map { "«\($0)»" } ?? "không")
            } else {
                text += ", không có nhóm audible"
            }
            return text
        }
    }

    /// Chờ sau khi bắt đầu phát rồi mới kiểm: track tiếng/hình cần một nhịp để xuất hiện trong `AVPlayerItem.tracks`.
    static let audioCheckDelayNanoseconds: UInt64 = 2_500_000_000
    static let playbackNoticeNanoseconds: UInt64 = 5_000_000_000

    // MARK: - Trạng thái theo lượt nạp

    /// Lượt nạp mới (tập / server / thử lại / phương án kế) và `stop()`: bỏ track, dự phòng, lượt kiểm và thông báo cũ.
    func resetPlaybackSource() {
        audioCheckTask?.cancel()
        audioCheckTask = nil
        audioCheckedGeneration = nil
        currentTrack = nil
        sourceResolution = nil
        embedProgressSeconds = 0
        noticeTask?.cancel()
        noticeTask = nil
        if playbackNotice != nil { playbackNotice = nil }
    }

    func showPlaybackNotice(_ text: String) {
        playbackNotice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.playbackNoticeNanoseconds)
            guard !Task.isCancelled else { return }
            self?.playbackNotice = nil
        }
    }

    // MARK: - Kiểm tiếng

    /// Gọi mỗi lần player sang `.playing` (`handleTimeControlChange`).
    func scheduleAudioCheckIfNeeded() {
        let generation = loadGeneration
        guard launch != nil, embedContent == nil, player.currentItem != nil,
              audioCheckedGeneration != generation else { return }
        audioCheckedGeneration = generation
        audioCheckTask?.cancel()
        audioCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.audioCheckDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.runAudioCheck(generation: generation)
        }
    }

    private func runAudioCheck(generation: Int) async {
        guard isCurrent(generation), embedContent == nil, let item = player.currentItem else { return }
        guard player.timeControlStatus != .paused else {
            // Đổi link lúc đang dừng sẽ tự phát item mới ⇒ để lần phát sau kiểm.
            audioCheckedGeneration = nil
            return
        }
        let inspection = await inspectAudio(of: item)
        guard isCurrent(generation), player.currentItem === item else { return }
        let onFallback = sourceResolution?.isOnFallback ?? false
        let mergedAudio = sourceResolution?.isMergedAudio ?? false
        let details = sourceDiagnostics(item: item, inspection: inspection)
        let hasAudio = inspection.hasAudio || (mergedAudio && inspection.selectedAudible != nil)
        if hasAudio, inspection.hasVideo || !onFallback {
            if onFallback { AppLogger.shared.log("🔊 [VideoPlayer] Phương án dự phòng có tiếng: \(details)") }
            // Log dòng thường để xác nhận từ file log rằng playlist ghép ra tiếng (kể cả khi chỉ thấy lựa chọn `.audible`).
            if mergedAudio { AppLogger.shared.log("🔊 [VideoPlayer] Playlist ghép audios có tiếng: \(details)") }
            return
        }
        guard inspection.trackCount > 0 else {
            AppLogger.shared.log("⚠️ [VideoPlayer] Chưa kết luận được âm thanh (item chưa có track): \(details)")
            return
        }
        let problem = hasAudio ? "Phương án dự phòng không có hình" : "Không có âm thanh"
        // Playlist ghép: dự phòng là luồng gốc không tiếng ⇒ đổi sang đó không giúp được gì.
        let canSwitch = !mergedAudio && canSwitchSourceAutomatically && sourceResolution?.fallbacks.isEmpty == false
        let action = mergedAudio
            ? "⇒ giữ nguyên (dự phòng chỉ là luồng hình gốc, không có tiếng)"
            : fallbackAction(canSwitch: canSwitch)
        AppLogger.shared.log("❌ [VideoPlayer] \(problem): \(details) \(action)")
        guard canSwitch else { return }
        // Đang chạy trong `audioCheckTask`: gỡ tham chiếu trước để `prepareForNewLoad` không huỷ chính task này — task
        // bị huỷ thì `isCurrent` sai và `apply` bỏ qua phương án mới.
        audioCheckTask = nil
        switchToNextFallback()
    }

    private func inspectAudio(of item: AVPlayerItem) async -> AudioInspection {
        var inspection = AudioInspection()
        for track in item.tracks {
            guard let mediaType = track.assetTrack?.mediaType else { continue }
            inspection.trackCount += 1
            if mediaType == .audio {
                if track.isEnabled {
                    inspection.audioTracks += 1
                } else {
                    inspection.disabledAudioTracks += 1
                }
            } else if mediaType == .video {
                inspection.videoTracks += 1
            }
        }
        let size = item.presentationSize
        inspection.hasPicture = size.width > 0 && size.height > 0
        if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
            inspection.audibleOptions = group.options.count
            inspection.selectedAudible = item.currentMediaSelection.selectedMediaOption(in: group)?.displayName
        }
        return inspection
    }

    // MARK: - Đổi phương án

    /// Đổi item lúc PiP / chạy nền / màn đã thu nhỏ làm hỏng PiP và phát nền ⇒ chỉ tự đổi khi màn đang hiện ở trước.
    private var canSwitchSourceAutomatically: Bool {
        isScreenAttached && !isInBackground && pictureInPicture?.isActiveOrStarting != true
    }

    private func fallbackAction(canSwitch: Bool) -> String {
        guard let resolution = sourceResolution, let next = resolution.fallbacks.first else {
            return sourceResolution?.isOnFallback == true
                ? "⇒ đã hết phương án dự phòng, giữ nguyên"
                : "⇒ không có phương án dự phòng (chỉ link dò từ trang mới có)"
        }
        guard canSwitch else { return "⇒ chưa tự đổi link (đang PiP / chạy nền / thu nhỏ)" }
        let note = next.note.map { " [\($0)]" } ?? ""
        return "⇒ thử phương án \(resolution.attemptNumber + 1)/\(resolution.totalAttempts): \(next.origin.label)\(note)"
    }

    /// Sang phương án kế với **cùng** `VideoTrack` (nhúng trang giữ Referer/UA như nhánh nhúng sẵn có).
    private func switchToNextFallback() {
        guard var resolution = sourceResolution, let track = currentTrack else { return }
        let leavingMergedAudio = resolution.isMergedAudio
        guard let next = resolution.advance() else { return }
        let resume = resumePointForReload()
        let generation = prepareForNewLoad(resumeSeconds: resume)
        currentTrack = track
        sourceResolution = resolution
        if case .embed = next.plan {
            // Nhúng không tua được ⇒ Lịch sử giữ giây đang xem thay vì ghi đè bằng 0.
            embedProgressSeconds = resume
            showPlaybackNotice("Đã chuyển sang trình phát của trang để có tiếng")
        } else if leavingMergedAudio {
            showPlaybackNotice("Không ghép được luồng tiếng, đang phát luồng gốc…")
        } else {
            showPlaybackNotice("Không có tiếng, đang thử link khác…")
        }
        apply(plan: next.plan, track: track, generation: generation)
    }

    /// Log ❌ khi `AVPlayerItem` lỗi, kèm nguồn link, URL đã che, URL lỗi và sự kiện lỗi mạng gần nhất (404…).
    /// Đang ở phương án dự phòng (hoặc playlist ghép `audios`) mà lỗi ⇒ sang phương án kế và trả `true` (caller không
    /// báo lỗi).
    func logItemFailureAndTryFallback(message: String) -> Bool {
        let item = player.currentItem
        let switchable = sourceResolution?.isOnFallback == true || sourceResolution?.isMergedAudio == true
        let canSwitch = switchable
            && sourceResolution?.fallbacks.isEmpty == false
            && canSwitchSourceAutomatically
        let action = canSwitch ? " \(fallbackAction(canSwitch: true))" : ""
        let header = "AVPlayerItem lỗi (tập \(currentEpisodeIndex), server «\(selectedServerTitle)»): \(message)"
        AppLogger.shared.log("❌ [VideoPlayer] \(header) — \(failureDiagnostics(item: item))\(action)")
        guard canSwitch else { return false }
        switchToNextFallback()
        return true
    }

    // MARK: - Chẩn đoán

    private func sourceDiagnostics(item: AVPlayerItem, inspection: AudioInspection) -> String {
        var parts = ["tiện ích \(extensionLabel)", "tập \(currentEpisodeIndex)", "server «\(selectedServerTitle)»"]
        if let sourceResolution { parts.append(sourceResolution.diagnostics) }
        if let url = (item.asset as? AVURLAsset)?.url { parts.append("url: \(VideoSourceResolution.redact(url))") }
        parts.append(inspection.summary)
        return parts.joined(separator: ", ")
    }

    private func failureDiagnostics(item: AVPlayerItem?) -> String {
        var parts = ["tiện ích \(extensionLabel)"]
        if let sourceResolution { parts.append(sourceResolution.diagnostics) }
        if let url = (item?.asset as? AVURLAsset)?.url { parts.append("url: \(VideoSourceResolution.redact(url))") }
        if let error = (item?.error).map({ $0 as NSError }) {
            parts.append("mã lỗi: \(error.domain) \(error.code)")
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            if let underlying { parts.append("lỗi gốc: \(underlying.domain) \(underlying.code)") }
            let failing = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
                ?? (underlying?.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            if let failing { parts.append("URL lỗi: \(VideoSourceResolution.redact(failing))") }
        }
        if let event = item?.errorLog()?.events.last {
            let uri = event.uri.map { VideoSourceResolution.redact($0) } ?? "-"
            parts.append("lỗi mạng gần nhất: \(event.errorStatusCode) \(event.errorDomain) \(uri)")
        }
        return parts.joined(separator: ", ")
    }

    private var extensionLabel: String {
        guard let packageId = launch?.extensionPackageId else { return "?" }
        let name = ExtensionLibraryRepository.snapshot(packageId: packageId)?.name ?? "?"
        return "«\(name)» (\(packageId))"
    }
}
