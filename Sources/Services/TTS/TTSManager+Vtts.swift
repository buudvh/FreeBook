import Foundation

/// Nối trình đọc **vtts** (Việt–Anh, runtime C siêu nhẹ — `Services/TTS/Vtts/`) vào `TTSManager`, cùng khuôn VieNeu
/// (`TTSManager+VieNeu.swift`). `TTSManager.swift` là file legacy chỉ được giảm dòng nên mọi logic của vtts nằm ở đây; file
/// legacy chỉ đổi tại chỗ hai dòng: dòng log của `tool.didSet` ⇒ `noteReaderToolChanged(from:)`, nhánh `vieneu` của
/// `loadParamsForCurrentTool()` ⇒ `applyOfflineModelParamsIfNeeded()`.
///
/// vtts là engine **local** (`isLocalEngine`, đồng thời bị loại khỏi `isExtensionTool` — hai hàm phải sửa cùng lúc), đi
/// chung đường phát của NghiTTS / VieNeu: `NghiAudioPlayerQueue`, cửa sổ tải trước theo ngưỡng giây,
/// `PiperSynthesisCoordinator`, chia đoạn bằng `NghiUtteranceSegmenter` theo `chunkLength`. **Tự đọc nhanh** (1.3.1036):
/// tốc độ tạo tiếng = thanh Tốc độ, không quá "vtts tự đọc nhanh tối đa" (1.3.1037), kẹp 1,0–2,0× (`vttsSynthesisSpeed`),
/// queue chỉ kéo phần còn lại (`localPlaybackRate`); trần nằm trong `TTSSettingsSnapshot` như tốc độ;
/// tốc độ chỉ đổi được ở sheet Cài đặt TTS và nằm trong `TTSSettingsSnapshot` ⇒ đóng sheet là dựng lại đoạn + xoá mọi phần
/// đệm (kể cả đầu chương kế), không cần lối bỏ tiếng riêng như "Tốc độ tổng hợp" của VieNeu. Nhẹ như Piper ⇒ dùng chung
/// ngưỡng đệm `nghittsSafeCachedTimeThreshold`, 1 lượt refill, 2 optional reserve (các nhánh `== "vieneu"` không đụng vtts).
extension TTSManager {
    /// Khoá `UserDefaults` + hằng của vtts. Khoá riêng, không dùng chung `nghitts*` / `vieneu*`: chỉnh bên này không ghi đè
    /// bên kia (bài học "hai khoá cho một giá trị" của VieNeu).
    enum VttsSettings {
        /// `TTSManager.tool` của vtts.
        static let tool = "vtts"
        static let voiceKey = "vttsVoice"
        static let rateKey = "vttsRate"
        /// Engine không chỉnh được cao độ (dòng chú thích "(*)" ở Cài đặt TTS); vẫn lưu riêng để không lọt vào `extPitch_vtts`.
        static let pitchKey = "vttsPitch"
        static let chunkKey = "vttsChunk"
        /// Độ dài phân đoạn mặc định. 150 (mockup 2026-11-20) → **500** (1.3.1035): `NghiUtteranceSegmenter` luôn cắt ở dấu
        /// hết câu đầu tiên nên chunk vẫn là từng câu; 150 chỉ xẻ đôi câu dài ở dấu phẩy — vtts tự cắt câu ở 40 âm tiết đúng
        /// dấu phẩy đó (cùng tiếng), nên chỗ xẻ chỉ thêm một lần đổi `AVAudioPlayer` giữa câu, anh Bửu nghe thành tiếng
        /// "xoẹt" / vấp (1× + 500 sạch, 1× + 150 bị).
        static let defaultChunkLength = 500
        /// "vtts tự đọc nhanh tối đa" (1.3.1037, anh Bửu duyệt mockup): vtts tự tạo tiếng nhanh tới mức này, phần còn lại
        /// của thanh Tốc độ để trình phát kéo. Anh nghe 1.3.1036 (tự đọc trọn 1,8×): hết tiếng "vụt" nhưng "âm điệu khác",
        /// "không rõ lời" ⇒ để anh tự chỉnh giữa hai cái. Mặc định 1,4 là **ước lượng**. Khoá không dấu chấm (`@AppStorage`).
        static let nativeSpeedMaxKey = "vttsNativeSpeedMax"
        static let defaultNativeSpeedMax = 1.4
    }

    /// Tên trình đọc local trong toast / log lỗi tổng hợp của đường phát chung (`playNghiTTS`) — trước đó luôn ghi "NghiTTS"
    /// kể cả khi đang đọc bằng VieNeu / vtts.
    nonisolated static func localReaderLabel(_ tool: String) -> String {
        switch tool {
        case VttsSettings.tool: return "vtts"
        case "vieneu": return "VieNeu"
        default: return "NghiTTS"
        }
    }

    // MARK: - Tốc độ

    /// "vtts tự đọc nhanh tối đa" đã lưu, kẹp `VttsTTSService.nativeSpeedRange`; chưa có ⇒ `defaultNativeSpeedMax`.
    nonisolated static var vttsNativeSpeedMax: Double {
        let saved = UserDefaults.standard.double(forKey: VttsSettings.nativeSpeedMaxKey)
        return VttsTTSService.clampedNativeSpeed(saved > 0 ? saved : VttsSettings.defaultNativeSpeedMax)
    }

    /// Tốc độ vtts tự đọc khi nghe ở `listeningSpeed`: `min(tốc độ nghe, tự đọc nhanh tối đa)` kẹp 1,0–2,0 (dưới 1,0× vẫn tạo
    /// tiếng 1× rồi để trình phát kéo chậm như cũ).
    nonisolated static func vttsNativeSpeed(forListeningSpeed listeningSpeed: Double) -> Double {
        VttsTTSService.clampedNativeSpeed(min(listeningSpeed, Self.vttsNativeSpeedMax))
    }

    /// Tốc độ vtts **tự đọc** (đưa vào model qua `length_scale`, 1.3.1036; có trần "tự đọc nhanh tối đa" từ 1.3.1037) theo
    /// tốc độ nghe đã lưu của vtts (khoá `vttsRate`, chưa có ⇒ `ttsRate` ⇒ 1 — cùng luật `applyVttsParamsIfNeeded`). Một giá
    /// trị cho cả trình đọc chính lẫn giọng dự phòng (cả hai đọc chung khoá). `nonisolated`: đọc `UserDefaults` thuần, gọi
    /// được từ `TTSNextChapterPrefixCache` / prefetcher ngoài `MainActor` qua `localSynthesisSpeed(forTool:)`.
    nonisolated static var vttsSynthesisSpeed: Double {
        Self.vttsNativeSpeed(forListeningSpeed: TTSOnlineFallbackSettings.playbackSpeed(for: .vtts))
    }

    /// Tốc độ `NghiAudioPlayerQueue` của trình đọc local đang chọn: vtts đã tự đọc nhanh tới `vttsSynthesisSpeed` nên trình
    /// phát chỉ kéo phần còn lại (tối đa 1,4: 1,8× ⇒ 1,29; 1,2× ⇒ 1,0; 0,8× ⇒ 0,8). NghiTTS / VieNeu giữ `speed` — với VieNeu
    /// tốc độ nghe **cố ý** là tích "Tốc độ tổng hợp" × `speed`.
    var localPlaybackRate: Double {
        guard tool == VttsSettings.tool else { return speed }
        return speed / Self.vttsNativeSpeed(forListeningSpeed: speed)
    }

    // MARK: - Giọng

    /// Giọng vtts đã lưu — chung cho trình đọc chính, giọng dự phòng và sheet chọn giọng. Luôn là một giọng có thật
    /// (`VttsVoice.resolve`). `nonisolated`: đọc `UserDefaults` thuần, gọi được ngoài `MainActor`.
    nonisolated static var storedVttsVoice: String {
        let saved = UserDefaults.standard.string(forKey: VttsSettings.voiceKey) ?? VttsVoice.defaultVoice.id
        return VttsVoice.resolve(saved).id
    }

    /// Giọng vtts mà hàng "Giọng đọc" / sheet chọn giọng hiện: `selectedVoice` khi trình đọc là vtts, không thì giọng đã lưu
    /// (màn Giọng dự phòng: trình đọc chính là Google / tiện ích, `selectedVoice` là giọng của engine đó) — khuôn
    /// `NghiVoiceDirectory.readerVoiceName`.
    func vttsDisplayedVoice() -> VttsVoice {
        VttsVoice.resolve(tool == VttsSettings.tool ? selectedVoice : Self.storedVttsVoice)
    }

    /// Chọn giọng vtts (sheet chọn giọng). Trình đọc là vtts ⇒ gán `selectedVoice` (`didSet` lưu `vttsVoice` + bỏ phần đệm;
    /// giọng khác ⇒ `TTSSettingsSnapshot` khác ⇒ đóng Cài đặt là dựng lại đoạn) rồi nạp sẵn giọng mới. Trình đọc khác (chọn
    /// cho giọng dự phòng) ⇒ chỉ ghi khoá `vttsVoice` — gán `selectedVoice` lúc đó là ghi đè giọng của engine kia.
    func selectVttsVoice(_ voice: VttsVoice) {
        AppLogger.shared.log("[TTSRoute] chon giong vtts \(voice.id) (trinh doc=\(tool))")
        guard tool == VttsSettings.tool else {
            UserDefaults.standard.set(voice.id, forKey: VttsSettings.voiceKey)
            return
        }
        guard selectedVoice != voice.id else { return }
        selectedVoice = voice.id
        scheduleNghiWarmUp()
    }

    // MARK: - Nạp tham số

    /// Nhánh "engine model có sẵn trong app" của `loadParamsForCurrentTool()` — VieNeu hoặc vtts. Một lời gọi để file legacy
    /// không mọc thêm nhánh; mỗi hàm con tự kiểm `tool` nên gọi cả hai là đúng.
    func applyOfflineModelParamsIfNeeded() {
        applyVieNeuParamsIfNeeded()
        applyVttsParamsIfNeeded()
    }

    /// Nạp tham số riêng của vtts khi Picker đổi sang vtts (và lúc mở app — `init` gọi `loadParamsForCurrentTool()` sau
    /// `super.init()`). Giá trị mặc định phải **trùng** `resetPrefetchSettings()`.
    ///
    /// `chunkLength` **có** tác dụng: `playbackParagraphs` cắt đoạn của engine local bằng `NghiUtteranceSegmenter` theo nó.
    /// `prefetchDelayMs` ghim 500 như VieNeu — engine local không tiêu thụ giá trị này (chỉ đường remote), ghim để không
    /// thừa hưởng số của engine trước.
    func applyVttsParamsIfNeeded() {
        guard tool == VttsSettings.tool else { return }
        let defaults = UserDefaults.standard

        let defaultRate = defaults.object(forKey: "ttsRate") != nil ? defaults.double(forKey: "ttsRate") : 1.0
        let savedRate = defaults.double(forKey: VttsSettings.rateKey)
        self.speed = savedRate > 0 ? savedRate : defaultRate

        let defaultPitch = defaults.object(forKey: "ttsPitch") != nil ? defaults.double(forKey: "ttsPitch") : 1.0
        let savedPitch = defaults.double(forKey: VttsSettings.pitchKey)
        self.pitch = savedPitch > 0 ? savedPitch : defaultPitch

        self.selectedVoice = Self.storedVttsVoice

        let savedChunk = defaults.object(forKey: VttsSettings.chunkKey) != nil
            ? defaults.integer(forKey: VttsSettings.chunkKey)
            : VttsSettings.defaultChunkLength
        self.chunkLength = savedChunk > 0 ? savedChunk : VttsSettings.defaultChunkLength
        self.prefetchDelayMs = 500

        AppLogger.shared.log("[TTSRoute] nap tham so vtts voice=\(self.selectedVoice) rate=\(self.speed) chunk=\(self.chunkLength)")
    }

    // MARK: - Đổi trình đọc / nhả runtime

    /// `tool.didSet` (thay dòng log cũ trong file legacy): ghi log đổi engine như cũ; trình đọc vừa **rời** vtts ⇒ nhả runtime.
    ///
    /// Chuyển **sang** vtts thì **không** nhả engine VieNeu / Piper: đường hiện có không nhả engine của nhau khi đổi trình đọc
    /// (NghiTTS ↔ VieNeu giữ nguyên; VieNeu chỉ nhả Nano ↔ Turbo trong `prepare` của model kia) — giữ cùng hành vi.
    func noteReaderToolChanged(from oldTool: String) {
        AppLogger.shared.log("[TTSRoute] doi engine=\(tool) local=\(TTSManager.isLocalEngine(tool)) extension=\(TTSManager.isExtensionTool(tool))")
        guard oldTool == VttsSettings.tool, tool != VttsSettings.tool else { return }
        releaseVttsRuntimeIfUnused(reason: "Trình đọc chuyển sang \(tool)")
    }

    /// Nhả runtime vtts (model + từ điển tiếng Anh mmap, vùng làm việc) khi không ai cần nữa: trình đọc không phải vtts và vtts
    /// không phải giọng dự phòng của trình đọc online — giữ lại cho giọng dự phòng để đoạn dự phòng kế tiếp khỏi nạp nguội
    /// (khuôn `restoreVieNeuEngines`). Gọi khi trình đọc rời vtts và khi sheet chọn giọng đóng sau lượt thử giọng vtts.
    func releaseVttsRuntimeIfUnused(reason: String) {
        guard tool != VttsSettings.tool else { return }
        if TTSOnlineFallbackSettings.isOnlineTool(tool), TTSOnlineFallbackSettings.engine == .vtts {
            AppLogger.shared.log("🗣️ [Vtts] \(reason) — giữ runtime vì vtts là giọng dự phòng")
            return
        }
        AppLogger.shared.log("🗣️ [Vtts] \(reason) — trình đọc không dùng vtts, nhả runtime")
        VttsTTSService.shared.releaseRuntime()
    }
}
