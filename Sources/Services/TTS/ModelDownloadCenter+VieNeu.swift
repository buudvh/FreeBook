import Foundation

/// Các đích tải **VieNeu** của `ModelDownloadCenter` (1.3.900): model Nano (8 file lõi), gói nhân bản Nano, gói nhân bản
/// Turbo, model Turbo và từng giọng Turbo.
///
/// ## Chạy lần lượt
/// Các đích này ghi chung file: `sea_g2p.bin` (model Nano + model Turbo), `speaker_encoder.onnx` (hai gói nhân bản),
/// GGUF 188 MB (mọi giọng Turbo khi máy chưa có model). Hai lượt cùng tải một file là cùng ghi `<file>.partial` ⇒ hỏng.
/// Nên lượt mới **xếp hàng** sau lượt VieNeu đang chạy (`vieNeuTail`); trong lúc chờ, dòng tiến độ có `isQueued`. File
/// đã có thì lượt sau bỏ qua — giọng Turbo thứ hai chờ model tải xong rồi chỉ tải vài KB.
///
/// ## Tiến độ theo byte, ngoài main
/// Việc tải chạy trong hàm `nonisolated` (luồng của `URLSession` async, không phải main); main chỉ nhận cập nhật tiến
/// độ, đã tiết chế theo phần nghìn ở `VieNeuTurboModelClient`. Tổng = dung lượng mọi file còn thiếu của lượt.
///
/// ## Huỷ
/// `cancel(id:)` huỷ `Task` ⇒ `URLSession` dừng file đang tải (lỗi huỷ không tính là lỗi); dòng biến mất ngay, không
/// toast. Lượt đang xếp hàng bị huỷ thì khi tới lượt tự thoát.
extension ModelDownloadCenter {
    typealias VieNeuProgressReport = @Sendable (VieNeuModelClient.Progress) -> Void
    typealias VieNeuJob = @Sendable (_ report: @escaping VieNeuProgressReport) async throws -> Void

    // MARK: - Các đích

    /// 8 file lõi của VieNeu-TTS v3 Nano (~347 MB) — mọi giọng Nano dùng chung.
    @discardableResult
    func startVieNeuModel() -> Task<Void, Never>? {
        startVieNeuJob(id: Target.vieNeuModel, title: "Model VieNeu Nano") { report in
            _ = try await VieNeuModelClient(store: try VieNeuModelStore()).prefetch(progressHandler: report)
        }
    }

    /// Gói graph **nhân bản giọng** của Nano (3 file, ~96 MB, tuỳ chọn).
    @discardableResult
    func startVieNeuCloneGraphs() -> Task<Void, Never>? {
        startVieNeuJob(id: Target.vieNeuClone, title: "Gói nhân bản giọng Nano") { report in
            _ = try await VieNeuModelClient(store: try VieNeuModelStore()).prefetchCloneGraphs(progressHandler: report)
        }
    }

    /// Gói **nhân bản giọng Turbo** (2 file, ~71 MB, tuỳ chọn) vào kho của Nano (`Models/`).
    @discardableResult
    func startVieNeuTurboClonePack() -> Task<Void, Never>? {
        startVieNeuJob(id: Target.vieNeuTurboClone, title: "Gói nhân bản giọng Turbo") { report in
            _ = try await VieNeuModelClient(store: try VieNeuModelStore()).prefetchTurboCloneGraphs(progressHandler: report)
        }
    }

    /// Model Turbo nếu thiếu (manifest + `sea_g2p.bin` + GGUF 188 MB) rồi cặp file của giọng `voiceId` (`nil` = chỉ model).
    @discardableResult
    func startVieNeuTurbo(voiceId: String?, title: String) -> Task<Void, Never>? {
        let id = voiceId.map(Target.vieNeuTurboVoice) ?? Target.vieNeuTurboModel
        return startVieNeuJob(id: id, title: title) { report in
            try await ModelDownloadCenter.downloadTurbo(voiceId: voiceId, report: report)
        }
    }

    // MARK: - Truy vấn / huỷ

    /// Có lượt VieNeu nào đang chạy / chờ không.
    var isVieNeuBusy: Bool {
        entries.contains { Self.isVieNeuTarget($0.id) && $0.state.isRunning }
    }

    /// Huỷ một lượt VieNeu (đang chạy hoặc đang chờ). Dòng tiến độ biến mất ngay.
    func cancel(id: String) {
        guard let task = tasks[id] else { return }
        task.cancel()
        tasks[id] = nil
        tokens[id] = nil
        entries.removeAll { $0.id == id }
        AppLogger.shared.log("⬇️ [ModelDownload] Huỷ tải \(id)")
    }

    /// Chờ lượt của `id` xong (không có lượt ⇒ trả ngay). Trả trạng thái cuối; `nil` = không có dòng (đã huỷ / chưa tải).
    func waitForJob(id: String) async -> State? {
        if let task = tasks[id] { await task.value }
        return entry(id: id)?.state
    }

    static func isVieNeuTarget(_ id: String) -> Bool {
        [Target.vieNeuModel, Target.vieNeuClone, Target.vieNeuTurboClone, Target.vieNeuTurboModel].contains(id)
            || id.hasPrefix(Target.vieNeuTurboVoicePrefix)
    }

    // MARK: - Nội bộ

    private func startVieNeuJob(id: String, title: String, work: @escaping VieNeuJob) -> Task<Void, Never>? {
        if let running = tasks[id] { return running }
        let token = UUID()
        tokens[id] = token
        // **Luôn** chờ lượt cuối hàng (đã xong thì `value` trả ngay): lượt vừa bấm ■ không còn dòng (`isVieNeuBusy` sai)
        // nhưng `Task` của nó có thể còn đang dừng `URLSession` — bấm ⬇ lại ngay mà không chờ là hai lượt cùng ghi `.partial`.
        let previous = vieNeuTail
        let isQueued = isVieNeuBusy
        var entry = Entry(id: id, title: title, message: isQueued ? "Đang chờ lượt tải khác…" : "Bắt đầu tải…", fraction: 0)
        entry.isQueued = isQueued
        upsert(entry)

        let report: VieNeuProgressReport = { progress in
            Task { @MainActor in ModelDownloadCenter.shared.applyVieNeuProgress(id: id, token: token, progress: progress) }
        }
        let task = Task { [weak self] in
            await previous?.value
            guard let self, self.tokens[id] == token, !Task.isCancelled else { return }
            self.markVieNeuStarted(id: id)
            let modelBefore = VieNeuModelChoice.current
            var failure: String?
            var cancelled = false
            do {
                try await Self.run(work, report: report)
            } catch {
                if Task.isCancelled || Self.isCancellation(error) {
                    cancelled = true
                } else {
                    failure = error.localizedDescription
                }
            }
            // Đã huỷ (và có thể đã bấm tải lại cùng đích) ⇒ dòng hiện tại không còn của lượt này.
            guard self.tokens[id] == token else { return }
            self.tokens[id] = nil
            if cancelled {
                self.tasks[id] = nil
                self.entries.removeAll { $0.id == id }
            } else {
                self.finish(id: id, title: title, failure: failure)
            }
            VieNeuVoiceDirectory.shared.refreshAvailability()
            Self.reapplyReaderIfModelChanged(from: modelBefore)
            // Core ML luôn bật (1.3.919): tải xong gói Nano ⇒ tự tải + biên dịch + tự kiểm Tăng tốc Core ML ngay.
            if id == Target.vieNeuModel, !cancelled, failure == nil {
                VieNeuCoreMLAccelerator.shared.prepareIfNeeded(reason: "tải xong gói Nano")
            }
        }
        tasks[id] = task
        vieNeuTail = task
        return task
    }

    /// Chạy việc tải **ngoài main**: hàm `nonisolated async` chạy trên executor chung. Không dùng `Task.detached` vì
    /// mất đường huỷ từ `Task` cha (nút ■).
    private nonisolated static func run(_ work: VieNeuJob, report: @escaping VieNeuProgressReport) async throws {
        try await work(report)
    }

    /// Tải xong làm model **hiệu lực** đổi (lựa chọn đã lưu là Turbo mà máy thiếu file Turbo nên trình đọc đang lùi về
    /// Nano; tải đủ ⇒ `current` thành Turbo) ⇒ `selectedVoice` còn là tên giọng Nano, Turbo sẽ đọc giọng mặc định. Nạp lại
    /// tham số (giọng theo lựa chọn) + nạp sẵn đúng engine, như lúc đổi model.
    private static func reapplyReaderIfModelChanged(from modelBefore: VieNeuModelChoice) {
        let tts = TTSManager.shared
        let modelAfter = VieNeuModelChoice.current
        guard tts.tool == "vieneu", modelAfter != modelBefore else { return }
        AppLogger.shared.log("[TTSRoute] tai xong => model VieNeu hieu luc \(modelBefore.rawValue)->\(modelAfter.rawValue), nap lai tham so")
        tts.applyVieNeuParamsIfNeeded()
        tts.scheduleNghiWarmUp()
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func markVieNeuStarted(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isQueued = false
        entries[index].message = "Bắt đầu tải…"
    }

    private func applyVieNeuProgress(id: String, token: UUID, progress: VieNeuModelClient.Progress) {
        guard tokens[id] == token, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].state.isRunning else { return }
        entries[index].isQueued = false
        entries[index].message = progress.message
        entries[index].fraction = progress.fraction
        entries[index].completedBytes = progress.completedBytes
        entries[index].totalBytes = progress.totalBytes
    }

    /// Tải những gì Turbo còn thiếu: manifest → `sea_g2p.bin` (chỗ của Nano, dùng chung) → GGUF → cặp file của giọng.
    /// Tổng byte = GGUF + `sea_g2p.bin` nếu thiếu; manifest / file giọng (vài KB) không tính.
    private nonisolated static func downloadTurbo(voiceId: String?, report: @escaping VieNeuProgressReport) async throws {
        let store = try VieNeuTurboModelStore()
        let client = VieNeuTurboModelClient(store: store)
        let g2pURL = try VieNeuModelStore().url(for: "sea_g2p.bin")
        let needsG2P = !FileManager.default.fileExists(atPath: g2pURL.path)
        let needsModel = !store.hasModel
        let g2pBytes = VieNeuModelStore.fileByteCounts["sea_g2p.bin"] ?? 0
        let total = (needsModel ? VieNeuTurboModelStore.modelByteCount : 0) + (needsG2P ? g2pBytes : 0)
        var completed: Int64 = 0

        if !store.hasManifest {
            report(.init(message: "Đang tải danh sách giọng Turbo…", completedBytes: 0, totalBytes: total))
            try await client.downloadManifest()
        }
        if needsG2P {
            try Task.checkCancellation()
            let base = completed
            let message = "Đang tải bộ phiên âm sea_g2p.bin…"
            report(.init(message: message, completedBytes: base, totalBytes: total))
            try await VieNeuTurboModelClient.downloadG2PDictionary(to: g2pURL) { done, _ in
                report(.init(message: message, completedBytes: base + done, totalBytes: total))
            }
            completed += g2pBytes
        }
        if needsModel {
            try Task.checkCancellation()
            let base = completed
            let message = "Đang tải model Turbo…"
            report(.init(message: message, completedBytes: base, totalBytes: total))
            try await client.downloadModel { done, _ in
                report(.init(message: message, completedBytes: base + done, totalBytes: total))
            }
            completed += VieNeuTurboModelStore.modelByteCount
        }
        if let voiceId {
            try Task.checkCancellation()
            report(.init(message: "Đang tải giọng…", completedBytes: completed, totalBytes: total))
            try await client.downloadVoice(voiceId: voiceId)
        }
        report(.init(message: "Tải xong", completedBytes: total, totalBytes: total))
    }
}
