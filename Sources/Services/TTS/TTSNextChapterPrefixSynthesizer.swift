import Foundation

/// Phần tổng hợp âm thanh của bộ đệm prefix chương kế tiếp, tách khỏi
/// [`TTSNextChapterPrefixCache`](TTSNextChapterPrefixCache.swift) để file đó không vượt trần 400 dòng.
///
/// Toàn bộ là `static` + `nonisolated`: nhận đủ tham số, không đọc trạng thái nào của cache, nên chạy
/// được ngoài `MainActor` và không có đường nào để hai bên lệch trạng thái.
enum TTSNextChapterPrefixSynthesizer {

    /// Một chunk, một lượt tổng hợp — đúng đường cũ cho cả ba engine.
    static func one(
        key: TTSPreparedNextChapterKey,
        textToSpeak: String,
        boundaryKind: TTSBoundaryKind,
        synthesisKey: String,
        offset: Int,
        prefetchDelayMs: Int,
        nghiService: PiperTTSService?,
        googleService: GoogleTTSService,
        extService: ExtTTSService,
        audioWorker: TTSAudioSynthesisWorker
    ) async throws -> Data {
        if key.tool == "nghitts" {
            guard let nghiService else { throw CancellationError() }
            return try await nghiService.synthesize(
                text: textToSpeak,
                voice: key.selectedVoice,
                speed: 1.0,
                boundaryKind: boundaryKind,
                priority: .optionalReserve,
                requestID: UUID(),
                synthesisKey: synthesisKey
            )
        }

        if key.tool == "google" {
            let pitchToUse = key.googlePitch ?? 1.0
            return try await audioWorker.synthesizeParagraph(
                synthesisKey: synthesisKey,
                engine: "google",
                textLength: textToSpeak.count,
                priority: .nextChapter,
                offset: offset,
                prefetchDelayMs: prefetchDelayMs
            ) {
                try await googleService.synthesize(
                    text: textToSpeak,
                    voice: key.selectedVoice,
                    speed: 1.0,
                    pitch: pitchToUse
                )
            }
        }

        return try await audioWorker.synthesizeParagraph(
            synthesisKey: synthesisKey,
            engine: key.tool,
            textLength: textToSpeak.count,
            priority: .nextChapter,
            offset: offset,
            prefetchDelayMs: prefetchDelayMs
        ) {
            try await extService.synthesizeData(
                text: textToSpeak,
                voice: key.selectedVoice,
                localPath: key.extensionLocalPath,
                configJson: key.extensionConfigJson
            )
        }
    }

    /// Nhiều chunk trong **một** request Google — cùng cơ chế với cửa sổ nạp trước trong chương
    /// (`TTSManager+RemoteBatchPrefetch`): đi qua coordinator như một job, payload đóng khung bằng
    /// `TTSBatchAudioPayload`, và số audio **bắt buộc** khớp số đoạn gửi đi.
    static func googleBatch(
        key: TTSPreparedNextChapterKey,
        texts: [String],
        batchKey: String,
        offset: Int,
        prefetchDelayMs: Int,
        googleService: GoogleTTSService,
        audioWorker: TTSAudioSynthesisWorker
    ) async throws -> [Data] {
        let pitchToUse = key.googlePitch ?? 1.0
        let totalCharacters = texts.reduce(0) { $0 + $1.count }

        let packed = try await audioWorker.synthesizeParagraph(
            synthesisKey: batchKey,
            engine: "google",
            textLength: totalCharacters,
            priority: .nextChapter,
            offset: offset,
            prefetchDelayMs: prefetchDelayMs
        ) {
            let audios = try await googleService.synthesizeBatch(
                parts: texts,
                voice: key.selectedVoice,
                speed: 1.0,
                pitch: pitchToUse
            )
            return TTSBatchAudioPayload.encode(audios)
        }

        guard let audios = TTSBatchAudioPayload.decode(packed), audios.count == texts.count else {
            throw NSError(
                domain: "TTSNextChapterPrefixSynthesizer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Khung payload gộp không hợp lệ"]
            )
        }
        return audios
    }
}
