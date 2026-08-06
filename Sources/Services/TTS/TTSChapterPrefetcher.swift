import Foundation

internal struct TTSPreparedNextChapterKey: Equatable, Sendable {
    internal let bookId: String
    internal let chapterIndex: Int
    internal let chapterUrl: String
    internal let chapterHost: String?
    internal let chapterTitle: String
    internal let tool: String
    internal let selectedVoice: String
    internal let chunkLength: Int
    internal let includeChapterTitle: Bool
    internal let isTranslationEnabled: Bool
    internal let translationToken: Int
    internal let extensionLocalPath: String
    internal let extensionConfigJson: String
}

internal enum TTSNextChapterState: Sendable {
    case idle
    case loadingContent(key: TTSPreparedNextChapterKey, generation: UInt64)
    case processedReady(key: TTSPreparedNextChapterKey, generation: UInt64, processed: ProcessedChapterDTO, loadMs: Double, processMs: Double)
    case synthesizingAudio(key: TTSPreparedNextChapterKey, generation: UInt64, processed: ProcessedChapterDTO, loadMs: Double, processMs: Double)
    case audioReady(key: TTSPreparedNextChapterKey, generation: UInt64, processed: ProcessedChapterDTO, audioData: Data, loadMs: Double, processMs: Double, synthMs: Double)
    case failed(key: TTSPreparedNextChapterKey, generation: UInt64, stage: String, reason: String)
}

@MainActor
internal final class TTSChapterPrefetcher {
    internal private(set) var currentState: TTSNextChapterState = .idle
    private var activeGeneration: UInt64 = 0
    private var prefetchTask: Task<Void, Never>? = nil
    private var audioTask: Task<Void, Never>? = nil

    internal init() {}

    internal var reservesNghiAudioSlot: Bool {
        switch currentState {
        case .synthesizingAudio(let key, _, _, _, _),
             .audioReady(let key, _, _, _, _, _, _):
            return key.tool == "nghitts"
        default:
            return false
        }
    }

    internal func isPrefetchingOrCompleted(for key: TTSPreparedNextChapterKey) -> Bool {
        switch currentState {
        case .loadingContent(let k, _),
             .processedReady(let k, _, _, _, _),
             .synthesizingAudio(let k, _, _, _, _),
             .audioReady(let k, _, _, _, _, _, _):
            return k == key
        case .idle, .failed:
            return false
        }
    }

    internal func startPrefetch(
        key: TTSPreparedNextChapterKey,
        sessionID: UUID,
        generation: Int,
        extensionInfo: TTSExtensionInfo?,
        processor: TTSBackgroundProcessor,
        googleService: GoogleTTSService,
        extService: ExtTTSService
    ) {
        if isPrefetchingOrCompleted(for: key) { return }

        cancel()
        activeGeneration += 1
        let currentGen = activeGeneration
        currentState = .loadingContent(key: key, generation: currentGen)

        let startTime = ProcessInfo.processInfo.systemUptime

        prefetchTask = Task(priority: .utility) { [weak self] in
            let request = ChapterContentRequest(
                bookId: key.bookId,
                chapterIndex: key.chapterIndex,
                title: key.chapterTitle,
                url: key.chapterUrl,
                host: key.chapterHost,
                bookMetadata: nil,
                extensionInfo: extensionInfo,
                forceRefresh: false
            )

            guard let result = try? await ChapterContentRepository.shared.load(request), !Task.isCancelled else {
                self?.updateStateIfGenerationMatches(
                    .failed(key: key, generation: currentGen, stage: "load", reason: "load_failed"),
                    expectedGen: currentGen
                )
                return
            }
            let loadTime = ProcessInfo.processInfo.systemUptime
            let loadMs = (loadTime - startTime) * 1000

            guard let processed = try? await processor.processChapter(
                bookId: key.bookId,
                chapterIndex: key.chapterIndex,
                chapterTitle: key.chapterTitle,
                rawContent: result.document.text.content,
                chunkLength: key.chunkLength,
                shouldTranslateRawContent: key.isTranslationEnabled,
                includeChapterTitle: key.includeChapterTitle,
                sessionID: sessionID,
                generation: generation
            ), !Task.isCancelled else {
                self?.updateStateIfGenerationMatches(
                    .failed(key: key, generation: currentGen, stage: "process", reason: "process_failed"),
                    expectedGen: currentGen
                )
                return
            }
            let processTime = ProcessInfo.processInfo.systemUptime
            let processMs = (processTime - loadTime) * 1000

            self?.updateStateIfGenerationMatches(
                .processedReady(key: key, generation: currentGen, processed: processed, loadMs: loadMs, processMs: processMs),
                expectedGen: currentGen
            )

            if key.tool == "google" || (key.tool != "system" && key.tool != "nghitts") {
                self?.startAudioSynthesis(key: key, gen: currentGen, processed: processed, loadMs: loadMs, processMs: processMs, nghiService: nil, googleService: googleService, extService: extService)
            }
        }
    }

    internal func promoteAudioIfNeeded(
        nghiService: PiperTTSService?,
        googleService: GoogleTTSService,
        extService: ExtTTSService
    ) {
        guard case .processedReady(let key, let gen, let processed, let loadMs, let processMs) = currentState,
              gen == activeGeneration, key.tool == "nghitts" else { return }

        startAudioSynthesis(key: key, gen: gen, processed: processed, loadMs: loadMs, processMs: processMs, nghiService: nghiService, googleService: googleService, extService: extService)
    }

    private func startAudioSynthesis(
        key: TTSPreparedNextChapterKey,
        gen: UInt64,
        processed: ProcessedChapterDTO,
        loadMs: Double,
        processMs: Double,
        nghiService: PiperTTSService?,
        googleService: GoogleTTSService,
        extService: ExtTTSService
    ) {
        guard !Task.isCancelled,
              activeGeneration == gen,
              case .processedReady(let currentKey, let currentGen, _, _, _) = currentState,
              currentGen == gen,
              currentKey == key else { return }

        let playbackParagraphs: [TTSParagraph]
        if key.tool == "nghitts" {
            playbackParagraphs = NghiUtteranceSegmenter.expand(
                processed.paragraphs,
                maximumLength: key.chunkLength
            )
        } else {
            playbackParagraphs = processed.paragraphs
        }

        guard let firstParagraph = playbackParagraphs.first else { return }
        let textToSpeak = TTSReplacementManager.shared.applyReplacements(to: firstParagraph.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSpeak.isEmpty else { return }

        if key.tool == "nghitts" && nghiService == nil {
            handleSynthesisFailure(
                key: key,
                gen: gen,
                processed: processed,
                loadMs: loadMs,
                processMs: processMs,
                reason: "service_unavailable"
            )
            return
        }

        currentState = .synthesizingAudio(key: key, generation: gen, processed: processed, loadMs: loadMs, processMs: processMs)

        audioTask?.cancel()
        audioTask = Task(priority: .utility) { [weak self] in
            let synthStartTime = ProcessInfo.processInfo.systemUptime
            var audioData: Data? = nil
            let reqID = UUID()

            do {
                if key.tool == "nghitts", let service = nghiService {
                    audioData = try await service.synthesize(
                        text: textToSpeak,
                        voice: key.selectedVoice,
                        speed: 1.0,
                        boundaryKind: firstParagraph.boundaryKind,
                        priority: .low,
                        requestID: reqID
                    )
                } else if key.tool == "google" {
                    audioData = try await googleService.synthesize(text: textToSpeak, voice: key.selectedVoice, speed: 1.0, pitch: 1.0)
                } else if key.tool != "system" {
                    audioData = try await extService.synthesizeData(text: textToSpeak, voice: key.selectedVoice, localPath: key.extensionLocalPath, configJson: key.extensionConfigJson)
                }
            } catch {
                if !Task.isCancelled {
                    self?.handleSynthesisFailure(
                        key: key,
                        gen: gen,
                        processed: processed,
                        loadMs: loadMs,
                        processMs: processMs,
                        reason: "synthesis_failed"
                    )
                }
                return
            }

            let synthEndTime = ProcessInfo.processInfo.systemUptime
            let synthMs = (synthEndTime - synthStartTime) * 1000

            if let data = audioData, !data.isEmpty, !Task.isCancelled {
                self?.updateStateIfGenerationMatches(
                    .audioReady(key: key, generation: gen, processed: processed, audioData: data, loadMs: loadMs, processMs: processMs, synthMs: synthMs),
                    expectedGen: gen
                )
            } else if !Task.isCancelled {
                self?.handleSynthesisFailure(
                    key: key,
                    gen: gen,
                    processed: processed,
                    loadMs: loadMs,
                    processMs: processMs,
                    reason: "empty_audio"
                )
            }
        }
    }

    private func handleSynthesisFailure(
        key: TTSPreparedNextChapterKey,
        gen: UInt64,
        processed: ProcessedChapterDTO,
        loadMs: Double,
        processMs: Double,
        reason: String
    ) {
        guard activeGeneration == gen else { return }
        switch currentState {
        case .processedReady(let k, let g, _, _, _),
             .synthesizingAudio(let k, let g, _, _, _):
            guard g == gen && k == key else { return }
        default:
            return
        }

        self.currentState = .processedReady(
            key: key,
            generation: gen,
            processed: processed,
            loadMs: loadMs,
            processMs: processMs
        )

        if AppLogger.shared.isLoggingEnabled {
            AppLogger.shared.log("[TTSPerf] NextChapterPrefetchFailure chapter=\(key.chapterIndex) engine=\(key.tool) stage=synthesis reason=\(reason)")
        }
    }

    private func updateStateIfGenerationMatches(_ newState: TTSNextChapterState, expectedGen: UInt64) {
        guard activeGeneration == expectedGen else { return }
        self.currentState = newState

        if AppLogger.shared.isLoggingEnabled {
            switch newState {
            case .processedReady(let key, _, _, let loadMs, let processMs):
                AppLogger.shared.log(String(format: "[TTSPerf] NextChapterPrefetchReady chapter=%d engine=%@ stage=dto_ready loadMs=%.2f processMs=%.2f", key.chapterIndex, key.tool, loadMs, processMs))
            case .audioReady(let key, _, _, _, let loadMs, let processMs, let synthMs):
                AppLogger.shared.log(String(format: "[TTSPerf] NextChapterPrefetchReady chapter=%d engine=%@ stage=audio_ready loadMs=%.2f processMs=%.2f synthMs=%.2f", key.chapterIndex, key.tool, loadMs, processMs, synthMs))
            case .failed(let key, _, let stage, let reason):
                AppLogger.shared.log("[TTSPerf] NextChapterPrefetchFailure chapter=\(key.chapterIndex) engine=\(key.tool) stage=\(stage) reason=\(reason)")
            default:
                break
            }
        }
    }

    internal func consumeCache(matching key: TTSPreparedNextChapterKey) -> TTSNextChapterState {
        let state = currentState
        switch state {
        case .audioReady(let k, _, _, _, _, _, _),
             .processedReady(let k, _, _, _, _),
             .synthesizingAudio(let k, _, _, _, _):
            if k == key {
                self.activeGeneration += 1
                self.audioTask?.cancel()
                self.audioTask = nil
                self.prefetchTask?.cancel()
                self.prefetchTask = nil
                self.currentState = .idle
                return state
            }
        default:
            break
        }
        return .idle
    }

    internal func cancel() {
        activeGeneration += 1
        prefetchTask?.cancel()
        prefetchTask = nil
        audioTask?.cancel()
        audioTask = nil
        currentState = .idle
    }
}
