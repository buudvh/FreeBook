import Foundation

/// Phụ đề của item đang phát (chỉ `track.subtitles.first`): nạp bằng `VideoSubtitleParser` rồi chuyển phồn → giản / dịch để
/// hiển thị bằng `MediaCaptionTranslator` trong **cùng** `subtitleTask` — `prepareForNewLoad` / `stop()` huỷ task là huỷ
/// luôn lượt.
///
/// `cues[].text` luôn là nguyên văn. Phồn → giản (chạy cả khi tắt dịch) gán `converted` cho **mọi** dòng trước — rẻ, nên
/// kiểu Gốc đổi ngay; rồi khi bật dịch, `translation` gán dần theo lô (`MediaCaptionTranslator.batchSize`), bắt đầu từ dòng
/// đang chiếu trở đi rồi quay về đầu, nên dòng đang xem đổi sang bản dịch gần như ngay. Dòng nào chưa có bản dịch thì View
/// hiện `displayText` (chữ đã chuyển, hoặc nguyên văn). Đổi cấu hình dịch (sheet "Dịch phụ đề") ⇒ `retranslateSubtitles()`
/// xử lý lại phụ đề đã nạp, không nạp lại phim; sửa từ điển giữa chừng thì áp từ tập sau. Bộ dịch của phim là tiện ích
/// dịch ⇒ mỗi lô 50 dòng là một lượt gửi tiện ích (dòng lỗi lùi QT, chỉ ghi log); đổi bộ dịch ở sheet cũng dịch lại.
extension VideoPlaybackSession {
    func toggleSubtitles() {
        setSubtitlesEnabled(!subtitlesEnabled)
    }

    /// Nút / menu phụ đề của thanh trên: chọn một kiểu hiển thị (Gốc · Bản dịch · Song ngữ) cũng là bật lại phụ đề.
    func setSubtitlesEnabled(_ enabled: Bool) {
        guard enabled != subtitlesEnabled else { return }
        subtitlesEnabled = enabled
        updateCue(at: currentPlaybackTime)
    }

    func loadSubtitles(for track: VideoTrack, generation: Int) {
        guard let subtitle = track.subtitles.first else { return }
        let headers = track.headers
        subtitleTask = Task { [weak self] in
            do {
                let loaded = try await VideoSubtitleParser.load(subtitle, headers: headers)
                guard let self, self.isCurrent(generation) else { return }
                self.cues = loaded
                self.hasSubtitles = !loaded.isEmpty
                AppLogger.shared.log("💬 [VideoPlayer] Đã nạp phụ đề: \(loaded.count) dòng")
                await self.translateLoadedCues(generation: generation)
            } catch {
                guard !(error is CancellationError) else { return }
                // Lỗi phụ đề không chặn việc phát.
                AppLogger.shared.log("❌ [VideoPlayer] Không nạp được phụ đề: \(error.localizedDescription)")
            }
        }
    }

    /// Sheet "Dịch phụ đề" đóng mà cấu hình đổi: bỏ chữ đã chuyển + bản dịch cũ (tắt cả chuyển lẫn dịch thì dừng ở đây) rồi
    /// xử lý lại phụ đề đã nạp. Phụ đề chưa nạp xong (`cues` rỗng) ⇒ không làm gì, **không** huỷ `subtitleTask`: lượt nạp
    /// đang chạy đọc cấu hình mới lúc bắt đầu xử lý.
    func retranslateSubtitles() {
        // Tên phim / tập cũng theo cấu hình mới — kể cả phim không có phụ đề mềm.
        refreshDisplayNames()
        guard !cues.isEmpty, launch != nil else { return }
        subtitleTask?.cancel()
        clearSubtitleTranslations()
        let generation = loadGeneration
        AppLogger.shared.log("💬 [VideoPlayer] Cấu hình dịch đổi ⇒ chuyển / dịch lại phụ đề")
        subtitleTask = Task { [weak self] in
            await self?.translateLoadedCues(generation: generation)
        }
    }

    // MARK: - Nội bộ

    /// Chuyển phồn → giản rồi dịch `cues` đã nạp. Sau mỗi `await` đều kiểm task chưa huỷ + lượt nạp còn hiện hành trước khi
    /// ghi — lượt dịch lại dùng chung `loadGeneration` với lượt trước nên chỉ có cờ huỷ phân biệt hai lượt.
    private func translateLoadedCues(generation: Int) async {
        guard let launch, isCurrent(generation) else { return }
        let texts = cues.map(\.text)
        guard texts.contains(where: { TranslateUtils.containsChinese($0) }) else { return }
        // Bộ dịch là tiện ích ⇒ mỗi lô gửi tiện ích (dòng lỗi lùi QT); phụ đề cứng không xin nên luôn QT.
        guard let pass = await MediaCaptionTranslator.prepare(
            bookId: launch.bookId, packageId: launch.extensionPackageId, extensionSource: .chapterContent
        ), isCurrent(generation), cues.count == texts.count else { return }
        if pass.options.converts {
            guard await applyConversion(texts: texts, pass: pass, generation: generation) else { return }
        }
        guard pass.translates else { return }
        let order = translationOrder(count: texts.count, from: currentPlaybackTime)
        var translatedCount = 0
        var start = 0
        while start < order.count {
            let batch = Array(order[start..<min(start + MediaCaptionTranslator.batchSize, order.count)])
            start += batch.count
            guard let results = await MediaCaptionTranslator.translate(batch.map { texts[$0] }, pass: pass),
                  isCurrent(generation), cues.count == texts.count else { return }
            for (offset, index) in batch.enumerated() {
                cues[index].translation = results[offset].translation
            }
            translatedCount += results.reduce(0) { $1.translation == nil ? $0 : $0 + 1 }
            if translatedCount > 0, !hasTranslatedSubtitles { hasTranslatedSubtitles = true }
            updateCue(at: currentPlaybackTime)
        }
        AppLogger.shared.log("💬 [VideoPlayer] Đã dịch phụ đề: \(translatedCount)/\(texts.count) dòng")
    }

    /// Bước 1 cho cả phụ đề một lần (`pass.convertOnly` — chỉ chuyển, không dịch): gán `converted` cho mọi dòng (một lần gán
    /// mảng) rồi vẽ lại dòng đang chiếu. `false` = task bị huỷ / lượt nạp đã đổi ⇒ dừng cả lượt.
    private func applyConversion(texts: [String], pass: MediaCaptionTranslator.Pass, generation: Int) async -> Bool {
        guard let results = await MediaCaptionTranslator.translate(texts, pass: pass.convertOnly),
              isCurrent(generation), cues.count == texts.count else { return false }
        var updated = cues
        var convertedCount = 0
        for (index, result) in results.enumerated() where result.converted != nil {
            updated[index].converted = result.converted
            convertedCount += 1
        }
        if convertedCount > 0 {
            cues = updated
            updateCue(at: currentPlaybackTime)
            AppLogger.shared.log("💬 [VideoPlayer] Đã chuyển phồn → giản phụ đề: \(convertedCount)/\(texts.count) dòng")
        }
        return true
    }

    /// Chỉ số cue theo thứ tự dịch: từ dòng đang chiếu (hoặc dòng sắp tới) đến hết, rồi quay về đầu.
    private func translationOrder(count: Int, from seconds: Double) -> [Int] {
        let start = cues.firstIndex { $0.end > seconds } ?? 0
        return Array(start..<count) + Array(0..<start)
    }

    private func clearSubtitleTranslations() {
        if cues.contains(where: { $0.translation != nil || $0.converted != nil }) {
            cues = cues.map { VideoSubtitleCue(start: $0.start, end: $0.end, text: $0.text) }
        }
        if hasTranslatedSubtitles { hasTranslatedSubtitles = false }
        updateCue(at: currentPlaybackTime)
    }
}
