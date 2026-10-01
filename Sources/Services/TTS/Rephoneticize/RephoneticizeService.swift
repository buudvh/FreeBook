import Foundation

/// Sinh lại cách đọc cho **toàn bộ** một từ điển phiên âm, rồi ghi ra **file kết quả riêng** — không đụng
/// từ điển đang dùng.
///
/// ## Vì sao không ghi thẳng
/// Cùng lý do và cùng khuôn với `DictionaryMergeService`: bước tính chỉ **đọc** rồi sinh một file để người
/// dùng xem/xuất trước; việc áp vào từ điển là hành động **do người dùng chọn** (nút "Nhập vào từ điển").
/// Nhờ vậy một lỗi ở bước tính **không** thể làm hỏng từ điển — nó chỉ tạo ra một file sai mà người dùng
/// thấy được trước khi quyết định.
///
/// ## Hai từ điển, hai thuật toán
/// `Target.vieNeu` → chỉ đường tiếng Nhật (`JapaneseTransliterator`), vì `VieNeuJapanesePreprocessor`
/// **không** có nhánh tiếng Anh (ràng buộc cứng của tính năng từ điển tiếng Nhật).
/// `Target.nghiTTS` → **đúng thứ tự** của `TextPreprocessor.transliterateToken`: tiếng Nhật trước (qua cổng
/// `ForeignScriptClassifier`), còn lại đi `EnglishPhonemeTransliterator` (espeak IPA, rơi về bộ luật chính
/// tả khi espeak không cho IPA).
///
/// ## Mục không phiên âm được thì GIỮ NGUYÊN giá trị cũ
/// Cả hai đường đều trả về **nguyên khoá** khi không cắt được âm tiết. Chuỗi đó không phải bản dịch ⇒ ghi
/// đè là mất dữ liệu. Người dùng chốt 2026-10-01: giữ nguyên và đếm vào `keptCount`.
enum RephoneticizeService {

    /// Từ điển đích. Hai đích **độc lập hoàn toàn** — sửa bên này không bao giờ làm đổi bên kia.
    enum Target: String, Sendable, CaseIterable {
        case nghiTTS
        case vieNeu

        /// Tên file kết quả trong `FreeBook/TTS/`. **Khác** tên từ điển thật để một lượt "áp" không bao giờ
        /// ghi nhầm vào file đang dùng.
        var resultFileName: String {
            switch self {
            case .nghiTTS: return "phien-am-lai-nghi.plist"
            case .vieNeu: return "phien-am-lai-vieneu.plist"
            }
        }

        /// Tên file sao lưu từ điển hiện có, tạo **trước** khi áp kết quả.
        var backupFileName: String {
            switch self {
            case .nghiTTS: return "non-vietnamese-words.plist.bak-rephoneticize"
            case .vieNeu: return "phien-am-tieng-nhat.plist.bak-rephoneticize"
            }
        }

        var displayName: String {
            switch self {
            case .nghiTTS: return "NghiTTS"
            case .vieNeu: return "VieNeu-TTS"
            }
        }
    }

    /// Bản ghi số liệu của một lượt phiên âm lại, ghi **kèm** file kết quả.
    ///
    /// Vì sao tồn tại (bài học 1.3.448): màn Thông báo từng parse cả `VietPhraseMerged.txt` (~1,4 triệu
    /// dòng) **trên main thread** mỗi lần render để suy ra số liệu ⇒ đơ app và nghẽn luôn TTS. Ở đây số
    /// liệu đã biết chính xác ngay lúc ghi file, nên ghi ra JSON vài trăm byte để lần sau chỉ cần
    /// `JSONDecoder`. **Card ở màn Thông báo chỉ đọc file này** — không bao giờ parse plist kết quả.
    struct Meta: Codable, Equatable, Sendable {
        /// Phiên bản lược đồ. Gặp giá trị lạ ⇒ coi như **không có meta**, không crash.
        static let currentVersion = 1

        let version: Int
        /// Tổng số mục **sau** khi chuẩn hoá khoá và gộp trùng.
        let totalCount: Int
        /// Số mục có giá trị **đổi** so với bản cũ.
        let changedCount: Int
        /// Số mục engine không phiên âm được ⇒ giữ nguyên giá trị cũ.
        let keptCount: Int
        /// Số khoá bị gộp vì sau khi gấp dấu phụ trùng nhau.
        let keysMergedCount: Int
        /// Thời điểm sinh file — thay cho `attributesOfItem` khi cần ngày hiển thị.
        let createdAt: Date

        init(
            version: Int = Meta.currentVersion,
            totalCount: Int,
            changedCount: Int,
            keptCount: Int,
            keysMergedCount: Int,
            createdAt: Date = Date()
        ) {
            self.version = version
            self.totalCount = totalCount
            self.changedCount = changedCount
            self.keptCount = keptCount
            self.keysMergedCount = keysMergedCount
            self.createdAt = createdAt
        }
    }

    struct Outcome: Equatable, Sendable {
        let fileURL: URL
        let totalCount: Int
        let changedCount: Int
        let keptCount: Int
        let keysMergedCount: Int
    }

    enum RephoneticizeError: LocalizedError {
        case dictionaryEmpty
        case emptyResult
        case directoryUnavailable

        var errorDescription: String? {
            switch self {
            case .dictionaryEmpty:
                return "Từ điển đang trống — không có gì để phiên âm lại."
            case .emptyResult:
                return "Kết quả rỗng — không tạo file."
            case .directoryUnavailable:
                return "Không định vị được thư mục FreeBook/TTS."
            }
        }
    }

    // MARK: - Đường dẫn

    private static func rootURL() -> URL? {
        (try? ModelStore())?.rootURL
    }

    static func resultFileURL(for target: Target) -> URL? {
        rootURL()?.appendingPathComponent(target.resultFileName)
    }

    /// Tên file meta **dẫn xuất** từ tên file kết quả để không lệch tên nếu sau này đổi tên file.
    static func metaFileName(for target: Target) -> String {
        (target.resultFileName as NSString).deletingPathExtension + ".meta.json"
    }

    static func metaURL(for target: Target) -> URL? {
        rootURL()?.appendingPathComponent(metaFileName(for: target))
    }

    static func backupURL(for target: Target) -> URL? {
        rootURL()?.appendingPathComponent(target.backupFileName)
    }

    /// File từ điển **đang dùng** của từng đích — để sao lưu trước khi áp kết quả.
    static func liveDictionaryURL(for target: Target) -> URL? {
        switch target {
        case .nghiTTS: return TextPreprocessor.getWordsURL()
        case .vieNeu: return VieNeuJapaneseDictionary.fileURL()
        }
    }

    static func hasResult(for target: Target) -> Bool {
        guard let url = resultFileURL(for: target) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Meta

    /// Ghi meta atomically (`tmp` + `replaceItemAt`), **luôn sau khi** plist kết quả đã ghi xong: nếu meta
    /// hỏng thì trạng thái tệ nhất là "có file, thiếu meta" (UI lùi về nhánh chậm), chứ không bao giờ thành
    /// "có meta, thiếu file".
    static func writeMeta(_ meta: Meta, for target: Target) {
        guard let destination = metaURL(for: target), let data = try? JSONEncoder().encode(meta) else { return }
        let temporary = destination.deletingPathExtension().appendingPathExtension("tmp")
        guard (try? data.write(to: temporary, options: .atomic)) != nil else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try? FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    /// Đọc meta kèm theo. File không tồn tại / decode lỗi / `version` lạ ⇒ `nil` (UI lùi về nhánh "chưa có
    /// số liệu"), **không** parse plist để bù — đó chính là thứ từng gây đơ app.
    static func loadMeta(for target: Target) -> Meta? {
        guard let url = metaURL(for: target),
              let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(Meta.self, from: data),
              meta.version == Meta.currentVersion else {
            return nil
        }
        return meta
    }

    /// Xoá meta — **luôn** gọi cùng lượt với xoá file kết quả để không để lại meta mồ côi.
    static func deleteMeta(for target: Target) {
        guard let url = metaURL(for: target) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Chạy

    /// Đọc từ điển hiện tại, chuẩn hoá khoá, tính lại giá trị, ghi file kết quả + meta. Chạy được **ngoài**
    /// `MainActor` (không chạm UI, không `ToastManager`).
    ///
    /// - Parameter progress: 0…1, gọi theo mốc (không theo từng mục) để không spam `MainActor`.
    static func run(target: Target, progress: (Double) -> Void) async throws -> Outcome {
        let source = await currentWords(for: target)
        guard !source.isEmpty else { throw RephoneticizeError.dictionaryEmpty }

        let entries = Array(source)
        var newWords: [String: String] = [:]
        newWords.reserveCapacity(entries.count)

        var changedCount = 0
        var keptCount = 0
        var keysMergedCount = 0
        // Báo tiến độ ~100 lần cho cả lượt, không theo từng mục (30k mục ⇒ 30k lượt nhảy `MainActor`).
        let reportEvery = max(1, entries.count / 100)

        for (index, entry) in entries.enumerated() {
            let key = normalizedKey(entry.key, target: target)
            if key.isEmpty { continue }

            if newWords[key] != nil { keysMergedCount += 1 }

            if let newValue = recomputedValue(for: key, target: target) {
                if newValue != entry.value { changedCount += 1 }
                newWords[key] = newValue
            } else {
                // Engine không phiên âm được ⇒ **giữ nguyên** giá trị cũ. Khoá đã bị gộp trước đó thì giữ
                // bản ghi đầu tiên, không ghi đè.
                keptCount += 1
                if newWords[key] == nil { newWords[key] = entry.value }
            }

            if index % reportEvery == 0 {
                progress(Double(index + 1) / Double(entries.count))
            }
        }

        guard !newWords.isEmpty else { throw RephoneticizeError.emptyResult }
        guard let destination = resultFileURL(for: target) else { throw RephoneticizeError.directoryUnavailable }

        let data = try PropertyListSerialization.data(fromPropertyList: newWords, format: .xml, options: 0)
        try data.write(to: destination, options: .atomic)

        // Meta **sau** file: trạng thái xấu nhất là "có file, thiếu meta".
        writeMeta(
            Meta(
                totalCount: newWords.count,
                changedCount: changedCount,
                keptCount: keptCount,
                keysMergedCount: keysMergedCount
            ),
            for: target
        )
        progress(1)

        AppLogger.shared.log("🔁 [Rephoneticize] \(target.displayName): \(entries.count) mục → \(newWords.count) mục (đổi \(changedCount), giữ \(keptCount), gộp khoá \(keysMergedCount))")

        return Outcome(
            fileURL: destination,
            totalCount: newWords.count,
            changedCount: changedCount,
            keptCount: keptCount,
            keysMergedCount: keysMergedCount
        )
    }

    /// Bảng từ điển **đang dùng** của đích — đi qua actor nên an toàn ngoài main.
    private static func currentWords(for target: Target) async -> [String: String] {
        switch target {
        case .nghiTTS: return await TextPreprocessor.shared.getWordMap()
        case .vieNeu: return await VieNeuJapaneseDictionary.shared.all()
        }
    }

    /// Chuẩn hoá khoá y hệt lúc tra cứu.
    ///
    /// NghiTTS: `updateWord` chỉ `lowercased()` (`TextPreprocessor.swift:179`) nhưng lúc đọc lại tra bằng
    /// khoá **đã gấp dấu** (`:982`) ⇒ mục còn macron/dấu là **mục chết**; gấp ở đây để vá luôn.
    /// VieNeu: đã có sẵn `normalizedKey`.
    private static func normalizedKey(_ raw: String, target: Target) -> String {
        switch target {
        case .nghiTTS:
            return raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
                .lowercased()
        case .vieNeu:
            return VieNeuJapaneseDictionary.normalizedKey(raw)
        }
    }

    /// Cách đọc mới cho một khoá, hoặc `nil` khi **không** tính được (⇒ caller giữ giá trị cũ).
    ///
    /// Bám **đúng thứ tự** `TextPreprocessor.transliterateToken` (`TextPreprocessor.swift:979-1034`) trừ
    /// bước tra từ điển (chính là thứ đang tính lại):
    /// 1. `ForeignScriptClassifier.isJapaneseRomaji` → `JapaneseTransliterator.transliterateRomaji`.
    ///    **Không** rơi tiếp xuống đường tiếng Anh khi cắt hụt — pipeline cũng không rơi (`:992-993`), nó trả
    ///    nguyên token; trả nguyên khoá ⇒ `nil` để caller giữ giá trị cũ.
    /// 2. Còn lại → `EnglishPhonemeTransliterator` (espeak IPA, rơi về bộ luật chính tả khi espeak tắt).
    ///    **Chỉ** đích NghiTTS mới có nhánh này — VieNeu không có nhánh tiếng Anh.
    ///
    /// Khác pipeline một chỗ đã biết: nhánh tách theo `-` / `.` (`:994-1027`) **không** được lặp lại. Khoá
    /// từ điển là từ đơn (giá trị đã lưu ở dạng cách trắng theo `stripSyllableDashes`), nên nhánh đó — vốn
    /// dành cho văn bản chạy — hầu như không có cơ hội chạy.
    private static func recomputedValue(for key: String, target: Target) -> String? {
        if ForeignScriptClassifier.isJapaneseRomaji(key) {
            let romaji = JapaneseTransliterator.transliterateRomaji(key)
            guard romaji.lowercased() != key else { return nil }
            return TTSPhoneticSuggestionBuilder.stripSyllableDashes(romaji)
        }
        guard target == .nghiTTS else { return nil }

        let english = EnglishPhonemeTransliterator.detailed(key)
        let text = TTSPhoneticSuggestionBuilder.stripSyllableDashes(english.text)
        guard !text.isEmpty, text.lowercased() != key else { return nil }
        return text
    }
}
