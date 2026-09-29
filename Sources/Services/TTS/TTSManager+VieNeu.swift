import Foundation

/// Nối engine **VieNeu-TTS** vào đường đọc truyện.
///
/// Tách file vì `TTSManager.swift` vượt trần ratchet-down (**4025** dòng so với baseline **3470** trong
/// `architecture_allowlist.json`) — extension không thêm được stored property, nên phần khai báo `vieneu*`
/// vẫn phải nằm ở file legacy, còn mọi thứ khác gom về đây.
extension TTSManager {
    /// Khoá `UserDefaults` của engine VieNeu. Tách khỏi khoá `nghitts*` vì ngưỡng đệm là **hiệu năng**
    /// (mỗi engine một đặc tính RTF), còn khoảng nghỉ giữa các đoạn là **nội dung** nên vẫn dùng chung
    /// (`paragraphPauseDuration` / `sentencePauseDuration` / `phrasePauseDuration`).
    enum VieNeuSettingsKey {
        static let voice = "vieneuVoice"
        static let rate = "vieneuRate"
        static let pitch = "vieneuPitch"
        static let chunk = "vieneuChunk"
        static let prefetchCount = "vieneuPrefetchCount"
        static let safeCachedTimeThreshold = "vieneuSafeCachedTimeThreshold"
    }

    /// `true` khi `tool` là **extension của người dùng**, không phải engine có sẵn trong app.
    ///
    /// Bản cũ viết thẳng `tool != "system" && tool != "nghitts" && tool != "google"` ở **6 chỗ** (4 trong
    /// `TTSSettingsView`, 2 trong `TTSManager`). Thêm `vieneu` mà không sửa cả 6 thì VieNeu bị xếp nhầm
    /// vào nhánh extension: màn Cài đặt hiện danh sách giọng của extension (rỗng ⇒ "Không có giọng đọc
    /// nào") và dòng "Extension TTS không hỗ trợ chỉnh cao độ". Đó đúng là lỗi người dùng báo.
    ///
    /// Là `static` để gọi được từ cả View mà không cần thực thể.
    static func isExtensionTool(_ tool: String) -> Bool {
        tool != "system" && tool != "nghitts" && tool != "google" && tool != "vieneu"
    }

    /// `true` khi `tool` là engine chạy **trên máy** và đi chung đường phát của NghiTTS (queue + cửa sổ
    /// tải trước + `PiperSynthesisCoordinator`).
    ///
    /// Đây là cặp sinh đôi với `isExtensionTool`, và là **nguyên nhân lỗi "chọn VieNeu không ra tiếng"**:
    /// `playAudioData` chỉ định tuyến `tool == "nghitts"` sang `playNghiAudioData`, nên VieNeu rơi xuống
    /// nhánh `AVAudioPlayer` chung — trong khi tốc độ lại được đặt trên `nghiAudioPlayerQueue`. Hai bên
    /// lệch nhau nên không có tiếng, và **không có lỗi nào được ném ra**.
    ///
    /// **Quy ước**: mọi chỗ hỏi *"đây có phải engine local không?"* phải dùng hàm này, đừng viết lại
    /// `tool == "nghitts"`.
    ///
    /// **Ngoại lệ đã xác nhận duy nhất** là khoá `nghittsPrefetchDelay` trong `prefetchDelayMs.didSet`:
    /// đó là khoá **của Piper**, và `applyVieNeuParamsIfNeeded()` luôn đặt `prefetchDelayMs = 500` nên để
    /// VieNeu đi vào nhánh đó sẽ ghi đè độ trễ người dùng đã chỉnh cho NghiTTS.
    ///
    /// **Cảnh báo đừng đoán**: `chunkLength` và `NghiUtteranceSegmenter` **không** phải Piper-only —
    /// `TTSManager.playbackParagraphs` cho `vieneu` đi qua `NghiUtteranceSegmenter.expand(…)` với
    /// `chunkLength` giống Piper, nên VieNeu **cần** cả hai. Trước khi thay một predicate bằng hàm này,
    /// hãy đọc **thân** nhánh xem nó ghi/đọc khoá của ai.
    static func isLocalEngine(_ tool: String) -> Bool {
        tool == "nghitts" || tool == "vieneu"
    }

    /// Engine local đang chọn.
    ///
    /// **Tính chất an toàn của lượt nối này**: trả `nghiTTSService` cho **mọi** tool trừ `vieneu`, nên
    /// đường NghiTTS đi y hệt code cũ. Nếu sửa hàm này, phải giữ nguyên tính chất đó.
    internal var localEngine: (any LocalTTSEngine)? {
        tool == "vieneu" ? VieNeuTTSService.shared : nghiTTSService
    }

    /// Nạp tham số riêng của VieNeu.
    ///
    /// Gọi từ nhánh **`else if tool == "vieneu"`** của `loadParamsForCurrentTool()` — **một dòng** duy
    /// nhất phải thêm vào file legacy, phần thân nằm ở đây.
    ///
    /// **Đừng gọi hàm này từ nhánh `else` cuối**: nhánh đó là nhánh **extension**, và nó ghi đè ngay
    /// `speed`/`pitch`/`selectedVoice` bằng `extRate_vieneu`/`extPitch_vieneu`/`extVoice_vieneu`, tức mọi
    /// thứ dưới đây bị vứt bỏ **im lặng**. Đó chính là bug của bản trước.
    internal func applyVieNeuParamsIfNeeded() {
        guard tool == "vieneu" else { return }
        let defaults = UserDefaults.standard

        let defaultRate = defaults.object(forKey: "ttsRate") != nil ? defaults.double(forKey: "ttsRate") : 1.0
        let savedRate = defaults.double(forKey: VieNeuSettingsKey.rate)
        self.speed = savedRate > 0 ? savedRate : defaultRate

        // Cao độ: `NghiAudioPlayerQueue` mới chỉ áp `rate`, chưa có `AVAudioUnitTimePitch`, nên giá trị
        // này **hiện chưa nghe thấy được**. Vẫn nạp/lưu để khoá `vieneuPitch` không trôi mất khi engine
        // được nối vào pitch — và để VieNeu không dùng chung khoá `nghittsPitch`.
        let defaultPitch = defaults.object(forKey: "ttsPitch") != nil ? defaults.double(forKey: "ttsPitch") : 1.0
        let savedPitch = defaults.double(forKey: VieNeuSettingsKey.pitch)
        self.pitch = savedPitch > 0 ? savedPitch : defaultPitch

        let voices = (try? VieNeuTTSService.shared?.availableVoices()) ?? []
        self.selectedVoice = defaults.string(forKey: VieNeuSettingsKey.voice) ?? voices.first?.name ?? ""

        let savedCount = defaults.object(forKey: VieNeuSettingsKey.prefetchCount) != nil
            ? defaults.integer(forKey: VieNeuSettingsKey.prefetchCount)
            : 3
        self.vieneuPrefetchCount = max(2, min(10, savedCount))

        let savedThreshold = defaults.object(forKey: VieNeuSettingsKey.safeCachedTimeThreshold) != nil
            ? defaults.double(forKey: VieNeuSettingsKey.safeCachedTimeThreshold)
            : NghiSynthesisPolicy.defaultSafeCachedTimeThreshold
        let clamped = NghiSynthesisPolicy.clampSafeCachedTimeThreshold(savedThreshold)
        self.vieneuSafeCachedTimeThreshold = clamped
        defaults.set(clamped, forKey: VieNeuSettingsKey.safeCachedTimeThreshold)

        // VieNeu **có** dùng `chunkLength`: `TTSManager.playbackParagraphs` cho `vieneu` đi qua
        // `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)` giống Piper. Trước
        // lượt này hàm này không nạp `chunkLength`, nên VieNeu thừa hưởng giá trị còn sót của engine
        // trước đó — đúng loại lỗi "hai khoá cho một giá trị" mà lượt này đang dẹp.
        let savedChunk = defaults.object(forKey: VieNeuSettingsKey.chunk) != nil
            ? defaults.integer(forKey: VieNeuSettingsKey.chunk)
            : 200
        self.chunkLength = savedChunk > 0 ? savedChunk : 200
        self.prefetchDelayMs = 500

        AppLogger.shared.log("[TTSRoute] nap tham so VieNeu voice=\(self.selectedVoice) rate=\(self.speed) pitch=\(self.pitch) prefetch=\(self.vieneuPrefetchCount) nguongAnToan=\(clamped)")
    }

    // MARK: - Lưu tham số theo từng engine

    /// Lưu tốc độ theo **engine đang chọn**.
    ///
    /// Gom về đây vì `TTSManager.swift` đang vượt trần ratchet-down: chuỗi `if/else` vốn nằm thẳng trong
    /// `didSet` nên mỗi engine mới dài thêm ~2 dòng. Ở đây engine mới chỉ tốn 1 dòng `case`.
    ///
    /// Khoá `vieneu*` **cố ý** tách khỏi `nghitts*`: hai engine có đặc tính RTF khác nhau nên tốc độ và
    /// ngưỡng đệm phải nhớ riêng — dùng chung khoá thì chỉnh bên này ghi đè bên kia.
    internal func persistSpeed(_ value: Double) {
        let key: String
        switch tool {
        case "system": key = "systemRate"
        case "nghitts": key = "nghittsRate"
        case "vieneu": key = VieNeuSettingsKey.rate
        case "google": key = "googleRate"
        default: key = "extRate_\(tool)"
        }
        UserDefaults.standard.set(value, forKey: key)
        AppLogger.shared.logTTSVerbose("[TTSRoute] persistSpeed engine=\(tool) key=\(key) value=\(value)")
    }

    /// Lưu cao độ theo **engine đang chọn**. Cùng lý do gom về đây như `persistSpeed`.
    internal func persistPitch(_ value: Double) {
        let key: String
        switch tool {
        case "system": key = "systemPitch"
        case "nghitts": key = "nghittsPitch"
        case "vieneu": key = VieNeuSettingsKey.pitch
        case "google": key = "googlePitch"
        default: key = "extPitch_\(tool)"
        }
        UserDefaults.standard.set(value, forKey: key)
        AppLogger.shared.logTTSVerbose("[TTSRoute] persistPitch engine=\(tool) key=\(key) value=\(value)")
    }

    /// Lưu giọng theo **engine đang chọn**.
    ///
    /// **Đây là chỗ sửa một bug thật**: trước lượt này `vieneu` rơi vào nhánh `else` nên giọng được ghi
    /// vào `extVoice_vieneu`, còn `applyVieNeuParamsIfNeeded()` lại **đọc** `vieneuVoice` ⇒ chọn giọng
    /// xong thoát ra vào lại là mất. Hai bên phải cùng một khoá.
    internal func persistVoice(_ value: String) {
        let key: String
        switch tool {
        case "system": key = "systemVoice"
        case "nghitts": key = "nghittsVoice"
        case "vieneu": key = VieNeuSettingsKey.voice
        case "google": key = "googleVoice"
        default: key = "extVoice_\(tool)"
        }
        UserDefaults.standard.set(value, forKey: key)
        AppLogger.shared.logTTSVerbose("[TTSRoute] persistVoice engine=\(tool) key=\(key) value=\(value)")
    }

    /// Lưu `chunkLength` theo **engine đang chọn**. Cùng khuôn ba hàm trên — gom về đây để chuỗi `if/else`
    /// trong `didSet` không chiếm dòng của file legacy đang vượt trần.
    internal func persistChunkLength(_ value: Int) {
        let key: String
        switch tool {
        case "system": key = "systemChunk"
        case "nghitts": key = "nghittsChunk"
        case "vieneu": key = VieNeuSettingsKey.chunk
        case "google": key = "googleChunk"
        default: key = "extChunkUser_\(tool)"
        }
        UserDefaults.standard.set(value, forKey: key)
        AppLogger.shared.logTTSVerbose("[TTSRoute] persistChunkLength engine=\(tool) key=\(key) value=\(value)")
    }
}
