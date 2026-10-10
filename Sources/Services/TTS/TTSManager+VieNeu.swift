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
    /// Là `nonisolated static` vì `TTSManager` bị `@MainActor`: nếu để mặc định, hàm này cũng bị cô lập
    /// actor và mọi nơi gọi nó ngoài `MainActor` (ví dụ `TTSNextChapterPrefixSynthesizer` — một `enum`
    /// `nonisolated`) đều phải `await`. Đây là so sánh chuỗi thuần tuý nên **không** cần nhảy actor.
    nonisolated static func isExtensionTool(_ tool: String) -> Bool {
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
    /// `nonisolated` vì cùng lý do như `isExtensionTool`: đây là so sánh chuỗi thuần tuý, và hàm này được
    /// gọi từ cả `MainActor` (View, `TTSManager`) lẫn ngoài (`TTSNextChapterPrefixSynthesizer`,
    /// `TTSNextChapterPrefixCache`).
    nonisolated static func isLocalEngine(_ tool: String) -> Bool {
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
    /// Gọi từ **hai** chỗ, cả hai đều là một dòng trong file legacy:
    /// 1. nhánh `else if tool == "vieneu"` của `loadParamsForCurrentTool()` — khi Picker đổi engine;
    /// 2. `initialize(container:)` — vì `TTSManager.init` nạp tham số **trước `super.init()`** nên không
    ///    gọi được instance method, và chuỗi `if/else` ở đó **thiếu nhánh `vieneu`** ⇒ khởi động app khi
    ///    đang chọn VieNeu sẽ nạp nhầm `extRate_vieneu`/`extPitch_vieneu`/`extVoice_vieneu`. Gọi lại ở đây
    ///    sửa sai đó bằng **một nguồn sự thật** thay vì chép danh sách khoá lần thứ ba.
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
            : VieNeuSynthesisPolicy.bufferedSecondsTarget
        let clamped = NghiSynthesisPolicy.clampSafeCachedTimeThreshold(savedThreshold)
        self.vieneuSafeCachedTimeThreshold = clamped
        defaults.set(clamped, forKey: VieNeuSettingsKey.safeCachedTimeThreshold)

        // VieNeu **có** dùng `chunkLength`: `TTSManager.playbackParagraphs` cho `vieneu` đi qua
        // `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)` giống Piper. Trước
        // lượt này hàm này không nạp `chunkLength`, nên VieNeu thừa hưởng giá trị còn sót của engine
        // trước đó — đúng loại lỗi "hai khoá cho một giá trị" mà lượt này đang dẹp.
        let savedChunk = defaults.object(forKey: VieNeuSettingsKey.chunk) != nil
            ? defaults.integer(forKey: VieNeuSettingsKey.chunk)
            : 100
        self.chunkLength = savedChunk > 0 ? savedChunk : 100
        self.prefetchDelayMs = 500

        AppLogger.shared.log("[TTSRoute] nap tham so VieNeu voice=\(self.selectedVoice) rate=\(self.speed) pitch=\(self.pitch) prefetch=\(self.vieneuPrefetchCount) nguongAnToan=\(clamped)")
    }

    /// Ngưỡng nạp bộ đệm của **engine local đang chọn**.
    ///
    /// Có hàm này thì `vieneuSafeCachedTimeThreshold` mới thực sự được **đọc** — trước lượt 1.3.435 nó
    /// chỉ được lưu và hiển thị, còn mọi nơi tiêu thụ đều đọc thẳng `nghittsSafeCachedTimeThreshold`.
    internal var currentSafeCachedTimeThreshold: Double {
        tool == "vieneu" ? vieneuSafeCachedTimeThreshold : nghittsSafeCachedTimeThreshold
    }

    /// `chunkLength` mà **Reader** dùng cho VieNeu — đọc thẳng khoá `vieneuChunk` với mặc định 100, đúng
    /// như `applyVieNeuParamsIfNeeded()` nạp.
    ///
    /// **Không** dùng `TTSManager.shared.chunkLength`: giá trị đó thuộc **engine đang chọn**, nên khi
    /// Picker đang ở NghiTTS thì màn thử VieNeu sẽ cắt đoạn theo con số của Piper — lệch đúng thứ màn thử
    /// cần tái hiện (plan §2.2). `nonisolated` cùng lý do như `isExtensionTool`: đọc `UserDefaults` thuần,
    /// không cần nhảy actor.
    nonisolated static var vieNeuChunkLength: Int {
        let saved = UserDefaults.standard.object(forKey: VieNeuSettingsKey.chunk) != nil
            ? UserDefaults.standard.integer(forKey: VieNeuSettingsKey.chunk)
            : 100
        return saved > 0 ? saved : 100
    }

    /// Tốc độ **tổng hợp** của VieNeu — đưa thẳng vào model (`secs = exp(log_s)/speed`), mặc định 1,0.
    ///
    /// `nonisolated` cùng lý do với `isExtensionTool` và `vieNeuChunkLength`: đọc `UserDefaults` thuần,
    /// được gọi từ cả `MainActor` lẫn nơi `nonisolated` (`TTSNextChapterPrefixCache`).
    ///
    /// **Không** nhầm với `speed` (tốc độ phát): hai thứ này **nhân** với nhau thành tốc độ nghe.
    nonisolated static var vieNeuSynthesisSpeed: Double {
        VieNeuSynthesisPolicy.synthesisSpeed(from: .standard)
    }

    /// Tốc độ truyền vào engine cho một lượt tổng hợp local: VieNeu dùng **tốc độ tổng hợp**, các
    /// engine local khác giữ 1,0 như cũ. **Không** có cache nào tự vô hiệu theo giá trị này (khoá prefix
    /// chương kế không chứa nó) ⇒ đổi tốc độ tổng hợp phải đi qua `invalidateVieNeuSynthesisSpeed()`.
    nonisolated static func localSynthesisSpeed(forTool tool: String) -> Double {
        tool == "vieneu" ? vieNeuSynthesisSpeed : 1.0
    }

    /// Đổi "Tốc độ tổng hợp" **giữa lúc đang đọc**: phát nốt đoạn hiện tại, nạp lại phần còn lại.
    ///
    /// Ba việc phải làm, thiếu một là nghe sai tốc độ mà không có lỗi gì:
    /// 1. `cancelNghiRefill()` — huỷ các lượt đang bay (chúng đang tổng hợp ở tốc độ cũ).
    /// 2. Bỏ `preloadedData` từ đoạn **sau** đoạn hiện tại — giữ lại đoạn hiện tại để không mất audio
    ///    đang phát.
    /// 3. `clearPreparedNext()` — đoạn N+1 đã `prepareToPlay()` vẫn phát ở tốc độ cũ nếu không bỏ.
    ///
    /// **Không** đụng player của đoạn đang phát ⇒ không khựng (đúng quyết định đã chốt: "đợi hết đoạn đang
    /// phát, áp từ đoạn kế"). Hai chỗ audio tốc độ cũ còn lọt (sửa ở 1.3.501, giữ khi bỏ công tắc chống đọc
    /// lặp ở 1.3.503): (a) prefix chương kế đã tổng hợp — khoá của nó không có tốc độ tổng hợp ⇒ phải
    /// `resetNextChapterPrefixCache()`; (b) đoạn hiện tại **chưa vào player** (đang hụt tiếng chờ tổng hợp) —
    /// audio/lượt đang bay của nó mang tốc độ cũ ⇒ bỏ và tổng hợp lại.
    internal func invalidateVieNeuSynthesisSpeed() {
        guard tool == "vieneu" else { return }
        let currentInPlayer = nghiAudioPlayerQueue.currentItem?.paragraphIndex == currentParagraphIndex
        AppLogger.shared.log("[TTSRoute] doi toc do tong hop = \(Self.vieNeuSynthesisSpeed)x (doan \(currentParagraphIndex) \(currentInPlayer ? "giu" : "tong hop lai"))")
        cancelNghiRefill()
        if !currentInPlayer { cancelNghiPlaybackTask() }
        let keepUpTo = currentInPlayer ? currentParagraphIndex : currentParagraphIndex - 1
        preloadedData = preloadedData.filter { $0.key <= keepUpTo }
        preloadedDurations = preloadedDurations.filter { $0.key <= keepUpTo }
        nghiAudioPlayerQueue.clearPreparedNext()
        nextChapterPrefetcher.cancel()
        resetNextChapterPrefixCache()
        guard isPlaying else { return }
        if currentInPlayer { updateNghiPrefetchWindow() } else { speakCurrent() }
    }

    /// Đặt lại tham số "Tải trước dữ liệu" cho **engine đang chọn**.
    ///
    /// Gom về đây (thay vì để chuỗi `if/else` trong header của `Section` ở `TTSSettingsView`) vì hai lý do:
    /// (1) file đó đang ở trần **519** dòng; (2) chuỗi cũ **thiếu nhánh `vieneu`** nên bấm "Đặt lại" khi
    /// đang chọn VieNeu sẽ ghi vào `extPrefetchCount` / `nghittsPrefetchDelay` — tức đặt lại **nhầm engine**.
    internal func resetPrefetchSettings() {
        switch tool {
        case "google":
            googlePrefetchCount = 2
            chunkLength = 100
            prefetchDelayMs = 350
        case "nghitts":
            chunkLength = 100
            prefetchDelayMs = 350
            setNghiTTSSafeCachedTimeThreshold(8.0)
        case "vieneu":
            // Giá trị mặc định phải **trùng** với `applyVieNeuParamsIfNeeded()`: 3 đoạn, 200 ký tự,
            // ngưỡng `NghiSynthesisPolicy.defaultSafeCachedTimeThreshold`, độ trễ 500 ms.
            vieneuPrefetchCount = 3
            chunkLength = 100
            setVieNeuSafeCachedTimeThreshold(VieNeuSynthesisPolicy.bufferedSecondsTarget)
            prefetchDelayMs = 500
        case "system":
            chunkLength = 100
            prefetchDelayMs = 350
        default:
            let parsed = parseExtensionConfigParams(jsonString: extensionConfigJson, localPath: extensionLocalPath)
            if parsed.preloadSize == nil { extPrefetchCount = 2 }
            if parsed.maxLength == nil { chunkLength = 100 }
            prefetchDelayMs = 350
        }
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
