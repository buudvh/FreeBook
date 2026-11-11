import Foundation

/// Phụ đề của item đang phát (chỉ `track.subtitles.first`): nạp bằng `VideoSubtitleParser` rồi dịch để hiển thị bằng
/// `MediaCaptionTranslator` trong **cùng** `subtitleTask` — `prepareForNewLoad` / `stop()` huỷ task là huỷ luôn lượt dịch.
///
/// `cues[].text` luôn là nguyên văn; `translation` gán dần theo lô (`MediaCaptionTranslator.batchSize`), bắt đầu từ dòng
/// đang chiếu trở đi rồi quay về đầu, nên dòng đang xem đổi sang bản dịch gần như ngay. Dòng nào chưa có bản dịch thì View
/// hiện nguyên văn. Đổi cấu hình dịch (sheet "Dịch phụ đề") ⇒ `retranslateSubtitles()` dịch lại phụ đề đã nạp, không nạp
/// lại phim; sửa từ điển giữa chừng thì áp từ tập sau.
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

    /// Sheet "Dịch phụ đề" đóng mà cấu hình đổi: bỏ bản dịch cũ (tắt dịch thì dừng ở đây) rồi dịch lại phụ đề đã nạp.
    /// Phụ đề chưa nạp xong (`cues` rỗng) ⇒ không làm gì, **không** huỷ `subtitleTask`: lượt nạp đang chạy đọc cấu hình
    /// mới lúc bắt đầu dịch.
    func retranslateSubtitles() {
        guard !cues.isEmpty, launch != nil else { return }
        subtitleTask?.cancel()
        clearSubtitleTranslations()
        let generation = loadGeneration
        AppLogger.shared.log("💬 [VideoPlayer] Cấu hình dịch đổi ⇒ dịch lại phụ đề")
        subtitleTask = Task { [weak self] in
            await self?.translateLoadedCues(generation: generation)
        }
    }

    // MARK: - Nội bộ

    /// Dịch `cues` đã nạp theo lô. Sau mỗi `await` đều kiểm task chưa huỷ + lượt nạp còn hiện hành trước khi ghi — lượt
    /// dịch lại dùng chung `loadGeneration` với lượt trước nên chỉ có cờ huỷ phân biệt hai lượt.
    private func translateLoadedCues(generation: Int) async {
        guard let launch, isCurrent(generation) else { return }
        let texts = cues.map(\.text)
        guard texts.contains(where: { TranslateUtils.containsChinese($0) }) else { return }
        guard let pass = await MediaCaptionTranslator.prepare(bookId: launch.bookId, packageId: launch.extensionPackageId),
              isCurrent(generation), cues.count == texts.count else { return }
        let order = translationOrder(count: texts.count, from: currentPlaybackTime)
        var translatedCount = 0
        var start = 0
        while start < order.count {
            let batch = Array(order[start..<min(start + MediaCaptionTranslator.batchSize, order.count)])
            start += batch.count
            guard let results = await MediaCaptionTranslator.translate(batch.map { texts[$0] }, pass: pass),
                  isCurrent(generation), cues.count == texts.count else { return }
            for (offset, index) in batch.enumerated() {
                cues[index].translation = results[offset]
            }
            translatedCount += results.reduce(0) { $1 == nil ? $0 : $0 + 1 }
            if translatedCount > 0, !hasTranslatedSubtitles { hasTranslatedSubtitles = true }
            updateCue(at: currentPlaybackTime)
        }
        AppLogger.shared.log("💬 [VideoPlayer] Đã dịch phụ đề: \(translatedCount)/\(texts.count) dòng")
    }

    /// Chỉ số cue theo thứ tự dịch: từ dòng đang chiếu (hoặc dòng sắp tới) đến hết, rồi quay về đầu.
    private func translationOrder(count: Int, from seconds: Double) -> [Int] {
        let start = cues.firstIndex { $0.end > seconds } ?? 0
        return Array(start..<count) + Array(0..<start)
    }

    private func clearSubtitleTranslations() {
        for index in cues.indices where cues[index].translation != nil {
            cues[index].translation = nil
        }
        if hasTranslatedSubtitles { hasTranslatedSubtitles = false }
        updateCue(at: currentPlaybackTime)
    }
}
