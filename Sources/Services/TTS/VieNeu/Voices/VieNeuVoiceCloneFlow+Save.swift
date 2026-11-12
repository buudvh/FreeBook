import Foundation

/// Lượt **Lưu** của sheet nhân bản giọng (1.3.901): tải gói thiếu → giọng Nano → giọng Turbo → chọn giọng vừa tạo + đọc
/// thử câu mẫu. Tách file cho `VieNeuVoiceCloneFlow.swift` gọn.
extension VieNeuVoiceCloneFlow {
    enum SaveError: LocalizedError {
        case engineUnavailable

        var errorDescription: String? { "Không dựng được engine VieNeu." }
    }

    /// Huỷ lượt Lưu (nút "Huỷ tải" khi đang tải gói, hoặc bỏ sheet giữa chừng). Đang tải ⇒ huỷ các lượt tải; đang tạo
    /// giọng ⇒ lượt ORT / audio.cpp dở chạy nốt ở nền (không dừng được giữa chừng), giọng tạo xong vẫn lưu nhưng không
    /// được chọn / đọc thử. Mẫu giữ nguyên để Lưu lại.
    func cancelSave() {
        guard isSaving else { return }
        AppLogger.shared.log("🎙️ [VieNeuClone] Huỷ lượt lưu (bước \(String(describing: step)))")
        // Chỉ huỷ đích chính lượt này khởi tạo — lượt tải người dùng tự bấm ở sheet chọn giọng chạy tiếp.
        for id in ownedDownloadTargets { ModelDownloadCenter.shared.cancel(id: id) }
        saveTask?.cancel()
        saveTask = nil
        isSaving = false
        step = nil
        completedSteps = []
        downloadTargets = []
        ownedDownloadTargets = []
        downloadTotal = 0
        isError = false
        statusMessage = ""
    }

    func save() {
        guard canSave, let sampleURL else { return }
        stopSample()
        VieNeuVoicePreviewPlayer.shared.stop()
        let wantsNano = target.includesNano
        let wantsTurbo = target.includesTurbo
        let voiceName = name.trimmed
        let denoise = self.denoise
        isSaving = true
        isError = false
        statusMessage = ""
        completedSteps = []
        step = nil
        AppLogger.shared.log("🎙️ [VieNeuClone] Lưu giọng \"\(voiceName)\" nano=\(wantsNano) turbo=\(wantsTurbo) khửNhiễu=\(denoise)")

        saveTask = Task { [weak self] in
            guard let self else { return }
            var nanoRecordId: String?
            var created: [VieNeuVoiceSelection] = []
            do {
                if !VieNeuClonePackages.isReady(nano: wantsNano, turbo: wantsTurbo) {
                    step = .downloading
                    downloadTotal = VieNeuClonePackages.missingBytes(nano: wantsNano, turbo: wantsTurbo)
                    try await VieNeuClonePackages.ensure(nano: wantsNano, turbo: wantsTurbo) { [weak self] jobs in
                        self?.downloadTargets = jobs.all
                        self?.ownedDownloadTargets = jobs.owned
                    }
                    completedSteps.insert(.downloading)
                }
                try Task.checkCancellation()
                if wantsNano {
                    step = .nano
                    nanoRecordId = try await createNanoVoice(name: voiceName, sampleURL: sampleURL)
                    created.append(VieNeuVoiceSelection(model: .nano, voiceId: voiceName))
                    completedSteps.insert(.nano)
                }
                try Task.checkCancellation()
                if wantsTurbo {
                    step = .turbo
                    let coordinator = VieNeuTurboVoiceCloneCoordinator.shared
                    let outcome: VieNeuTurboVoiceCloneCoordinator.Outcome
                    if let nanoRecordId {
                        outcome = try await coordinator.createVoice(fromNanoVoiceId: nanoRecordId, name: voiceName, denoise: denoise)
                    } else {
                        outcome = try await coordinator.createVoice(fromFile: sampleURL, name: voiceName, denoise: denoise, keepsSample: true)
                    }
                    created.append(VieNeuVoiceSelection(model: .turbo, voiceId: outcome.record.id))
                    completedSteps.insert(.turbo)
                }
                try Task.checkCancellation()
                finishSave(created: created)
            } catch {
                // Huỷ: `cancelSave` đã đặt lại trạng thái; giọng lỡ tạo xong vẫn hiện trong danh sách.
                if Task.isCancelled {
                    completedSteps = []
                    step = nil
                    VieNeuVoiceDirectory.shared.reload()
                    return
                }
                handleSaveFailure(error, created: created)
            }
        }
    }

    /// Đường Nano **giữ nguyên** như màn "Giọng của tôi": `enrollVoice` (ngữ cảnh ORT riêng, không khử nhiễu) → lưu vào kho
    /// Nano (chép mẫu) → nạp lại catalog của engine (nạp một lần ⇒ thiếu bước này giọng mới rơi về giọng mặc định).
    private func createNanoVoice(name: String, sampleURL: URL) async throws -> String {
        guard let service = VieNeuTTSService.shared else { throw SaveError.engineUnavailable }
        nanoStage = nil
        let enrollment = try await service.enrollVoice(sampleURL: sampleURL) { stage in
            Task { @MainActor [weak self] in self?.nanoStage = stage }
        }
        let record = try service.customVoiceStore.add(
            name: name,
            speakerEmbedding: enrollment.speakerEmbedding,
            style: enrollment.style,
            sampleSourceURL: sampleURL
        )
        do {
            try service.refreshVoiceCatalog()
        } catch {
            AppLogger.shared.log("❌ [VieNeuClone] Nạp lại danh sách giọng Nano lỗi: \(error.localizedDescription)")
        }
        return record.id
    }

    /// Chọn giọng vừa tạo (ưu tiên model đang đọc khi tạo cả hai), đọc thử câu mẫu, báo View đóng sheet.
    private func finishSave(created: [VieNeuVoiceSelection]) {
        markSaved()
        if let sampleURL { Self.removeIfTemporary(sampleURL) }
        isSaving = false
        step = nil
        VieNeuVoiceDirectory.shared.reload()
        let current = VieNeuModelChoice.current
        if let chosen = created.first(where: { $0.model == current }) ?? created.first {
            TTSManager.shared.selectVieNeuVoice(chosen)
            VieNeuVoicePreviewPlayer.shared.play(chosen)
        }
        finishToken += 1
    }

    /// Lỗi giữa chừng: giọng đã tạo xong (vd Nano khi Turbo lỗi) vẫn giữ và được chọn; sheet ở lại để báo lỗi. **Không**
    /// `markSaved()`: kho Nano / Turbo đã chép mẫu của nó, mẫu tạm vẫn phải bị xoá khi sheet đóng (`cleanUp`).
    private func handleSaveFailure(_ error: Error, created: [VieNeuVoiceSelection]) {
        isSaving = false
        step = nil
        VieNeuVoiceDirectory.shared.reload()
        let prefix: String
        if let first = created.first {
            TTSManager.shared.selectVieNeuVoice(first)
            prefix = "Đã tạo giọng \(first.model.label); bản còn lại lỗi: "
        } else {
            prefix = "Lưu thất bại: "
        }
        showError(prefix + error.localizedDescription)
        AppLogger.shared.log("❌ [VieNeuClone] \(prefix)\(error.localizedDescription)")
    }
}
