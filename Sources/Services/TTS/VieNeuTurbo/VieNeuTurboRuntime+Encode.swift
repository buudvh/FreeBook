import Foundation
#if canImport(AudioCpp)
import AudioCpp
#endif

/// Mã hoá **mẫu giọng** thành mã tham chiếu Turbo bằng chính audio.cpp (1.3.892) — bước "ref_codes" của nhân bản giọng.
///
/// audio.cpp có sẵn đường này: `encode_reference_only = true` + `audiocpp_request_set_voice_audio` ⇒ chạy MOSS encoder
/// (đã nằm trong GGUF), trả artifact `ACOUSTIC_TOKENS` id `vieneu_v3_turbo.reference_codes` mà **nội dung đúng định
/// dạng `ref_codes.txt`** (mỗi dòng một khung 80 ms, 16 số cách nhau dấu cách — `session.cpp:53-79, 569-590` bản
/// v0.9.4). Nó tự trộn mono, tự lên 48 kHz, tự cắt 8 giây; **không** cắt im lặng, **không** khử nhiễu (việc của
/// `VieNeuTurboReferencePreparer`). Không cần chữ để đọc.
///
/// ## Bộ nhớ
/// Encoder dùng attention đầy đủ (8 s ≈ 200–250 MB graph, ước tính) và vùng đó ở lại trong session, cộng
/// `voice_prompt_cache_` giữ prompt của đoạn mẫu. Xong lượt ⇒ model đã nạp sẵn từ trước (trình đọc / nghe thử đang dùng)
/// thì **dựng lại session** cùng số luồng; model chỉ nạp cho lượt này thì **nhả hết** (`freeAll`).
///
/// ## Không chạy chồng
/// Cùng hàng đợi tuần tự với `synthesize` ⇒ tự chờ lượt tổng hợp đang dở; lượt đọc kế của trình đọc cũng phải chờ lượt
/// mã hoá. `VieNeuTurboVoiceCloneCoordinator` chặn tạo giọng khi trình đọc đang đọc bằng Turbo để không ai phải chờ.
extension VieNeuTurboRuntime {
    struct ReferenceEncoding: Sendable {
        /// Nguyên văn payload của artifact — ghi thẳng ra `ref_codes.txt`.
        let referenceCodesText: String
        let frames: Int
        let codeGroups: Int
        /// Thời gian tường của riêng `audiocpp_session_run` (kể cả lần thử lại nếu có).
        let encodeMs: Double
        /// Nạp model cho lượt này (`nil` khi model đã nạp sẵn).
        let modelLoadMs: Double?
        /// Dựng lại session sau lượt (`nil` khi đã nhả hết model thay vì dựng lại).
        let sessionRebuildMs: Double?
        let memoryBefore: String
        let memoryAfterEncode: String
        let memoryAfterCleanup: String
    }

    static let referenceCodesArtifactId = "vieneu_v3_turbo.reference_codes"
    /// 16 codebook mỗi khung (`kCodeGroups` của audio.cpp).
    static let referenceCodeGroups = 16
    /// Cỡ codebook MOSS: mã hợp lệ 0…1023 (đo trên 25 giọng đóng gói: min 0, max 1023).
    static let referenceCodebookSize = 1_024
    /// 8 giây × 12,5 khung/giây.
    static let maximumReferenceFrames = 100

    /// `samples` mono float ở `sampleRate` bất kỳ. `speakerEmbeddingURL` = `speaker.emb.txt` đã ghi (đưa vào để audio.cpp
    /// không tự chạy speaker encoder của GGUF nếu có — `prompt_tts_voice_clone.cpp:42-46` — và để file đi qua đúng bộ
    /// đọc của audio.cpp một lần trước khi lưu). `modelURL` / `threads` dùng khi runtime chưa nạp model.
    func encodeReference(
        samples: [Float],
        sampleRate: Double,
        speakerEmbeddingURL: URL,
        modelURL: URL,
        threads: Int,
        qos: DispatchQoS.QoSClass = .userInitiated
    ) async throws -> ReferenceEncoding {
        try await perform(qos: qos) { [self] in
            try encodeReferenceLocked(
                samples: samples,
                sampleRate: sampleRate,
                speakerEmbeddingPath: speakerEmbeddingURL.path,
                modelPath: modelURL.path,
                threads: max(1, threads)
            )
        }
    }

    /// Kiểm payload trước khi lưu: đúng 16 số nguyên 0…1023 mỗi dòng, 1…100 dòng. Trả số khung.
    static func validateReferenceCodes(_ text: String) throws -> Int {
        let rows = text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard !rows.isEmpty, rows.count <= maximumReferenceFrames else {
            throw RuntimeError.call("encode_reference_only", "mã tham chiếu có \(rows.count) khung, cần 1…\(maximumReferenceFrames)")
        }
        for (index, row) in rows.enumerated() {
            let values = row.split(separator: " ").compactMap { Int($0) }
            let tokenCount = row.split(separator: " ").count
            guard values.count == referenceCodeGroups, tokenCount == referenceCodeGroups,
                  values.allSatisfy({ (0..<referenceCodebookSize).contains($0) }) else {
                throw RuntimeError.call("encode_reference_only", "dòng \(index + 1) của mã tham chiếu sai định dạng")
            }
        }
        return rows.count
    }

    // MARK: - Nội bộ (chạy trong `queue`)

    #if canImport(AudioCpp)
    private func encodeReferenceLocked(
        samples: [Float],
        sampleRate: Double,
        speakerEmbeddingPath: String,
        modelPath: String,
        threads: Int
    ) throws -> ReferenceEncoding {
        guard !samples.isEmpty, sampleRate >= 1 else { throw RuntimeError.noAudio }
        let memoryBefore = ProcessMemoryProbe.snapshot().summary
        let wasLoaded = model != nil && loadedModelPath == modelPath
        // Giữ đúng số luồng của session người khác đang dùng (dựng lại y như cũ sau lượt); chưa có session ⇒ `threads`.
        let sessionThreadCount = (wasLoaded && sessionThreads > 0) ? sessionThreads : threads
        let load: LoadReport
        do {
            load = try prepareLocked(modelPath: modelPath, threads: sessionThreadCount)
        } catch {
            if !wasLoaded { freeAll() } // nạp dở cho riêng lượt này ⇒ đừng giữ registry / model nửa vời
            throw error
        }

        let outcome: Result<(text: String, encodeMs: Double), Error>
        do {
            outcome = .success(try runEncodeLocked(samples: samples, sampleRate: sampleRate, speakerEmbeddingPath: speakerEmbeddingPath))
        } catch {
            outcome = .failure(error)
        }
        let memoryAfterEncode = ProcessMemoryProbe.snapshot().summary

        // Trả bộ nhớ của encoder (kể cả khi lượt hỏng): dựng lại session cho người đang dùng, hoặc nhả hết.
        var rebuildMs: Double?
        if wasLoaded {
            do {
                rebuildMs = try createSessionLocked(threads: sessionThreadCount)
            } catch {
                AppLogger.shared.log("❌ [VieNeuTurbo] Dựng lại session sau khi mã hoá giọng mẫu lỗi: \(error.localizedDescription)")
                freeAll()
            }
        } else {
            freeAll()
        }
        let memoryAfterCleanup = ProcessMemoryProbe.snapshot().summary

        let encoded = try outcome.get()
        let frames = try Self.validateReferenceCodes(encoded.text)
        AppLogger.shared.log(
            "🎙️ [VieNeuTurbo] Mã hoá giọng mẫu: \(frames) khung, \(String(format: "%.0f", encoded.encodeMs)) ms, " +
            "\(samples.count) mẫu @ \(Int(sampleRate)) Hz — trước \(memoryBefore) · sau mã hoá \(memoryAfterEncode) · " +
            "sau \(wasLoaded ? "dựng lại session" : "nhả model") \(memoryAfterCleanup)"
        )
        return ReferenceEncoding(
            referenceCodesText: encoded.text,
            frames: frames,
            codeGroups: Self.referenceCodeGroups,
            encodeMs: encoded.encodeMs,
            modelLoadMs: load.modelLoadMs,
            sessionRebuildMs: rebuildMs,
            memoryBefore: memoryBefore,
            memoryAfterEncode: memoryAfterEncode,
            memoryAfterCleanup: memoryAfterCleanup
        )
    }

    /// Một lượt `audiocpp_session_run` chỉ mã hoá. Lỗi cấp phát ⇒ dựng lại session, thử lại một lần (như `synthesize`).
    ///
    /// Không cần chữ: đọc code v0.9.4 thì `build_preparation_request` (`framework/runtime/session.cpp:432`) chỉ **chép**
    /// `text_input` (optional) chứ không đọc, `VieNeuTTSSession::prepare` bỏ qua request, và nhánh `encode_reference_only`
    /// trả về trước `make_request` (chỗ duy nhất ném "requires text input"). Chưa chạy thử trên máy ⇒ lỗi khác lỗi cấp
    /// phát ở lượt đầu: ghi `❌`, đặt một chữ giả (vô hại — nhánh mã hoá không đọc chữ) rồi thử lại **một** lần.
    private func runEncodeLocked(
        samples: [Float],
        sampleRate: Double,
        speakerEmbeddingPath: String
    ) throws -> (text: String, encodeMs: Double) {
        guard let request = audiocpp_request_create() else {
            throw RuntimeError.call("audiocpp_request_create", "không cấp phát được request")
        }
        defer { audiocpp_request_free(request) }
        // Mẫu được chép vào request ⇒ con trỏ chỉ cần sống qua lời gọi này.
        let audioStatus: audiocpp_status = samples.withUnsafeBufferPointer { buffer in
            audiocpp_request_set_voice_audio(request, buffer.baseAddress, buffer.count, Int32(sampleRate.rounded()), 1)
        }
        try Self.check(audioStatus, "audiocpp_request_set_voice_audio")
        try Self.check(
            audiocpp_request_set_option(request, "encode_reference_only", "true"),
            "audiocpp_request_set_option(encode_reference_only)"
        )
        try Self.check(
            audiocpp_request_set_option(request, "speaker_embedding_file", speakerEmbeddingPath),
            "audiocpp_request_set_option(speaker_embedding_file)"
        )

        guard session != nil else { throw RuntimeError.notLoaded }
        let started = ProcessInfo.processInfo.systemUptime
        var result: OpaquePointer?
        var status = audiocpp_session_run(session, request, &result)
        if status != AUDIOCPP_OK {
            // Đọc lỗi NGAY (thread-local), trước mọi lời gọi audio.cpp khác.
            let detail = String(cString: audiocpp_last_error())
            let name = String(cString: audiocpp_status_string(status))
            let memory = ProcessMemoryProbe.snapshot().summary
            if Self.isAllocationFailure(status, detail) {
                AppLogger.shared.log("❌ [VieNeuTurbo] Mã hoá giọng mẫu lỗi cấp phát — dựng lại session, thử lại: \(name) — \(detail) — \(memory)")
                try createSessionLocked(threads: max(1, sessionThreads))
            } else {
                AppLogger.shared.log(
                    "❌ [VieNeuTurbo] Mã hoá giọng mẫu lỗi lượt đầu — đặt chữ giả, thử lại một lần: \(name) — \(detail) — \(memory)"
                )
                try Self.check(audiocpp_request_set_text(request, ".", nil), "audiocpp_request_set_text")
            }
            result = nil
            status = audiocpp_session_run(session, request, &result)
            if status != AUDIOCPP_OK {
                let retryDetail = String(cString: audiocpp_last_error())
                let retryName = String(cString: audiocpp_status_string(status))
                AppLogger.shared.log("❌ [VieNeuTurbo] Mã hoá giọng mẫu lỗi cả lần thử lại: \(retryName) — \(retryDetail)")
                throw RuntimeError.call(
                    "audiocpp_session_run(encode_reference_only)",
                    "\(retryName) — \(retryDetail) (lượt đầu: \(name) — \(detail))"
                )
            }
        }
        let encodeMs = Self.elapsedMs(since: started)
        guard let result else { throw RuntimeError.call("encode_reference_only", "audio.cpp không trả kết quả") }
        defer { audiocpp_result_free(result) }
        return (try Self.referenceCodesText(from: result), encodeMs)
    }

    /// Tìm artifact mã tham chiếu và **chép đủ `payload_bytes`** (con trỏ mượn, không phải chuỗi C kết thúc 0) trước khi
    /// `audiocpp_result_free` chạy ở bên gọi.
    private static func referenceCodesText(from result: OpaquePointer) throws -> String {
        let count = audiocpp_result_artifact_count(result)
        for index in 0..<count {
            var kind = AUDIOCPP_ARTIFACT_CUSTOM
            var idPointer: UnsafePointer<CChar>?
            var payload: UnsafeRawPointer?
            var payloadBytes = 0
            try check(
                audiocpp_result_artifact(result, index, &kind, &idPointer, &payload, &payloadBytes),
                "audiocpp_result_artifact"
            )
            let id = idPointer.map { String(cString: $0) } ?? ""
            guard kind == AUDIOCPP_ARTIFACT_ACOUSTIC_TOKENS, id == referenceCodesArtifactId else { continue }
            guard let payload, payloadBytes > 0 else {
                throw RuntimeError.call("encode_reference_only", "artifact mã tham chiếu rỗng")
            }
            let data = Data(bytes: payload, count: payloadBytes)
            AppLogger.shared.log("🎙️ [VieNeuTurbo] Artifact mã tham chiếu: \(payloadBytes) byte, \(metadataSummary(result, index: index))")
            return String(decoding: data, as: UTF8.self)
        }
        throw RuntimeError.call("encode_reference_only", "audio.cpp không trả artifact \(referenceCodesArtifactId) (\(count) artifact)")
    }

    /// "frames=73 code_groups=16 sample_rate=48000" — metadata của artifact, chỉ để log.
    private static func metadataSummary(_ result: OpaquePointer, index: Int) -> String {
        let count = audiocpp_result_artifact_meta_count(result, index)
        var fields: [String] = []
        for metaIndex in 0..<count {
            var key: UnsafePointer<CChar>?
            var value: UnsafePointer<CChar>?
            guard audiocpp_result_artifact_meta(result, index, metaIndex, &key, &value) == AUDIOCPP_OK else { continue }
            fields.append("\(key.map { String(cString: $0) } ?? "?")=\(value.map { String(cString: $0) } ?? "?")")
        }
        return fields.sorted().joined(separator: " ")
    }
    #else
    private func encodeReferenceLocked(
        samples: [Float],
        sampleRate: Double,
        speakerEmbeddingPath: String,
        modelPath: String,
        threads: Int
    ) throws -> ReferenceEncoding {
        throw RuntimeError.unavailable
    }
    #endif
}
