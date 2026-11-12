import Foundation

/// Lời bài hát của bài đang phát: nguồn lời đi cùng `track` (`AudioPreparedTrack.lyricSources`), nạp **sau** khi bài sẵn
/// sàng (`loadLyricsIfNeeded` ở `readyToPlay`) để không chặn việc phát. Mặc định thử lần lượt từng nguồn, nguồn đầu tiên
/// có nội dung thắng; người dùng chọn nguồn khác bằng `selectLyricSource`. Mỗi lượt nạp gắn `lyricsGeneration` — đổi bài /
/// chọn nguồn khác thì kết quả cũ bị bỏ. Dòng đang hát (`currentLyricLineIndex`) cập nhật theo tick.
/// Lời có chữ Hán ⇒ chuyển phồn → giản (cả khi tắt dịch) rồi dịch để hiển thị sau khi parse (`translateLyrics`, task riêng
/// `lyricsTranslationTask`); nguồn lời và `AudioLyricLine.text` giữ nguyên văn, View vẽ `displayText` / `translation` theo
/// `MediaCaptionDisplayMode`. Bộ dịch của album là tiện ích dịch ⇒ cả bài một lượt gửi tiện ích (dòng lỗi lùi QT).
extension AudioPlaybackSession {
    /// Gán nguồn lời của bài mới (rỗng ⇒ không có lời) và huỷ lượt nạp lời đang chạy.
    func resetLyrics(sources: [AudioLyricSource], headers: [String: String]) {
        lyricsGeneration += 1
        lyricsTask?.cancel()
        lyricsTask = nil
        cancelLyricsTranslation()
        if lyricSources != sources { lyricSources = sources }
        lyricHeaders = headers
        if selectedLyricSourceId != nil { selectedLyricSourceId = nil }
        if lyrics != nil { lyrics = nil }
        if currentLyricLineIndex != nil { currentLyricLineIndex = nil }
        let status: LyricsStatus = sources.isEmpty ? .unavailable : .pending
        if lyricsStatus != status { lyricsStatus = status }
    }

    /// Bài vừa sẵn sàng: còn nguồn lời chưa nạp ⇒ nạp (thử lần lượt từng nguồn).
    func loadLyricsIfNeeded() {
        guard lyricsStatus == .pending else { return }
        loadLyrics(from: lyricSources)
    }

    /// Người dùng chọn nguồn lời khác (bộ chọn của màn nghe). Chọn lại nguồn đang hiện thì thôi.
    func selectLyricSource(_ source: AudioLyricSource) {
        guard lyricSources.contains(source) else { return }
        if source.id == selectedLyricSourceId, lyricsStatus == .loaded { return }
        AppLogger.shared.log("🎵 [AudioPlayer] Chọn nguồn lời «\(source.displayLabel)»")
        loadLyrics(from: [source])
    }

    private func loadLyrics(from candidates: [AudioLyricSource]) {
        guard !candidates.isEmpty else { return }
        lyricsGeneration += 1
        let generation = lyricsGeneration
        lyricsTask?.cancel()
        cancelLyricsTranslation()
        lyricsStatus = .loading
        let headers = lyricHeaders
        lyricsTask = Task { [weak self] in
            var lastError: Error?
            for source in candidates {
                do {
                    let loaded = try await AudioLyricLoader.load(source, headers: headers)
                    guard let self, self.lyricsGeneration == generation else { return }
                    self.applyLyrics(loaded, source: source)
                    return
                } catch {
                    if AudioPlaybackSession.isCancellation(error) { return }
                    lastError = error
                }
            }
            guard let self, self.lyricsGeneration == generation else { return }
            self.lyricsTask = nil
            self.lyrics = nil
            self.currentLyricLineIndex = nil
            self.lyricsStatus = .failed(lastError?.localizedDescription ?? "Không đọc được lời bài hát.")
        }
    }

    private func applyLyrics(_ loaded: AudioLyrics, source: AudioLyricSource) {
        lyricsTask = nil
        lyrics = loaded
        selectedLyricSourceId = source.id
        lyricsStatus = .loaded
        currentLyricLineIndex = nil
        updateCurrentLyricLine(at: currentPlaybackTime)
        let kind = loaded.isSynced ? "có mốc giờ" : "chữ thường"
        AppLogger.shared.log("🎵 [AudioPlayer] Đã nạp lời «\(source.displayLabel)»: \(loaded.lines.count) dòng, \(kind)")
        translateLyrics()
    }

    // MARK: - Dịch lời

    /// Sheet "Dịch lời" đóng mà cấu hình đổi: bỏ chữ đã chuyển + bản dịch cũ (tắt cả chuyển lẫn dịch thì dừng ở đây) rồi
    /// xử lý lại lời đã nạp. Lời chưa nạp xong ⇒ không làm gì (không đụng `lyricsTask`): lượt nạp đọc cấu hình mới khi xong.
    func retranslateLyrics() {
        // Tên album / bài / nghệ sĩ cũng theo cấu hình mới — kể cả khi lời chưa nạp xong.
        refreshDisplayNames()
        guard lyricsStatus == .loaded, let current = lyrics else { return }
        cancelLyricsTranslation()
        if current.hasCaptionOverrides {
            lyrics = current.clearingCaptions()
        }
        AppLogger.shared.log("🎵 [AudioPlayer] Cấu hình dịch đổi ⇒ chuyển / dịch lại lời")
        translateLyrics()
    }

    func cancelLyricsTranslation() {
        lyricsTranslationTask?.cancel()
        lyricsTranslationTask = nil
    }

    /// Chuyển phồn → giản (cả khi tắt dịch) rồi dịch cả lời một lượt (lời ngắn) bằng `MediaCaptionTranslator`, ngoài main,
    /// trong task riêng; xong mới gán `lyrics` mới. Gác bằng `lyricsGeneration` + cờ huỷ + lời không đổi trong lúc xử lý.
    private func translateLyrics() {
        cancelLyricsTranslation()
        guard let current = lyrics, !bookId.isEmpty else { return }
        let texts = current.lines.map(\.text)
        guard texts.contains(where: { TranslateUtils.containsChinese($0) }) else { return }
        let generation = lyricsGeneration
        let targetBookId = bookId
        let targetPackageId = packageId
        lyricsTranslationTask = Task { [weak self] in
            // Bộ dịch là tiện ích ⇒ cả bài một lô gửi tiện ích (dòng lỗi lùi QT).
            guard let pass = await MediaCaptionTranslator.prepare(
                bookId: targetBookId, packageId: targetPackageId, extensionSource: .chapterContent
            ), let results = await MediaCaptionTranslator.translate(texts, pass: pass) else { return }
            guard let self, !Task.isCancelled, self.lyricsGeneration == generation,
                  let latest = self.lyrics, latest.lines.map(\.text) == texts else { return }
            self.lyricsTranslationTask = nil
            self.lyrics = latest.withCaptions(converted: results.map(\.converted), translations: results.map(\.translation))
            let converted = results.reduce(0) { $1.converted == nil ? $0 : $0 + 1 }
            let translated = results.reduce(0) { $1.translation == nil ? $0 : $0 + 1 }
            AppLogger.shared.log("🎵 [AudioPlayer] Lời: chuyển phồn → giản \(converted), dịch \(translated)/\(texts.count) dòng")
        }
    }

    /// Tick / tua: cập nhật dòng đang hát (chỉ ghi khi đổi).
    func updateCurrentLyricLine(at seconds: Double) {
        guard let lyrics, lyrics.isSynced else {
            if currentLyricLineIndex != nil { currentLyricLineIndex = nil }
            return
        }
        let index = lyrics.lineIndex(at: seconds)
        if index != currentLyricLineIndex { currentLyricLineIndex = index }
    }
}
