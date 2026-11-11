import Foundation

/// Chữ → chuỗi phiên âm **sea-g2p** cho Turbo. audio.cpp đọc phiên âm, không đọc chữ thô (doc `vieneu_v3_turbo.md`).
///
/// Đi **đúng hai lớp tiền xử lý** của đường Nano (`VieNeuTTSService.executeInternalSynthesis`), không viết bản thứ hai:
/// 1. `TextPreprocessor.normalizeVietnameseText` — mở rộng số / ngày / đơn vị (`sea_g2p.bin` không có chữ số);
/// 2. `VieNeuJapanesePreprocessor.applyUsingStoredFlags` — gấp macron + từ điển / romaji tiếng Nhật theo cờ của VieNeu;
/// rồi `SeaG2P.phonemizeTextWithEmotions` — cùng hàm Nano dùng. **Không** áp `VieNeuConfig.applyingEmotionTags`: ký
/// hiệu ①…③ là từ vựng của Nano; Turbo nhận nguyên `<|emotion_k|>` như bản Python.
///
/// Lớp thay thế ký tự (`TTSReplacementManager.applyReplacements`) là việc của **người gọi** — y như màn thử Nano.
///
/// `SeaG2P` không an toàn đa luồng (cache `var` trần) ⇒ thực thể **riêng** của Turbo (không dùng chung của engine Nano),
/// bọc bằng `lock`.
final class VieNeuTurboTextFrontend: @unchecked Sendable {
    enum FrontendError: LocalizedError {
        case missingDictionary

        var errorDescription: String? {
            switch self {
            case .missingDictionary: return "Chưa có sea_g2p.bin (bộ phiên âm) — tải model Turbo trước."
            }
        }
    }

    struct Prepared: Sendable {
        let phonemes: String
        /// Thời gian tiền xử lý + phiên âm (ms) — để tách khỏi thời gian của audio.cpp khi đọc số đo.
        let frontendMs: Double
    }

    /// Một bộ phiên âm Turbo cho cả app (trình đọc + màn thử) — mỗi thực thể giữ riêng một bản `sea_g2p.bin` 62,8 MB.
    /// `nil` khi không dựng được thư mục của Nano (nơi đặt `sea_g2p.bin`).
    static let shared: VieNeuTurboTextFrontend? = (try? VieNeuModelStore()).map {
        VieNeuTurboTextFrontend(dictionaryURL: $0.url(for: "sea_g2p.bin"))
    }

    private let dictionaryURL: URL
    private let lock = NSLock()
    private var g2p: SeaG2P?

    init(dictionaryURL: URL) {
        self.dictionaryURL = dictionaryURL
    }

    var hasDictionary: Bool {
        FileManager.default.fileExists(atPath: dictionaryURL.path)
    }

    func prepare(_ text: String) async throws -> Prepared {
        let started = ProcessInfo.processInfo.systemUptime
        let normalized = await VieNeuJapanesePreprocessor.applyUsingStoredFlags(
            text: TextPreprocessor.normalizeVietnameseText(text)
        )
        let phonemes = try phonemize(normalized)
        return Prepared(
            phonemes: phonemes,
            frontendMs: (ProcessInfo.processInfo.systemUptime - started) * 1_000
        )
    }

    /// Phiên âm **từng dòng** rồi nối bằng `\n`: `phonemize` bỏ mọi khoảng trắng kể cả xuống dòng, mà bộ cắt chunk của
    /// audio.cpp dựa vào ranh giới đoạn để chèn khoảng nghỉ dài hơn.
    private func phonemize(_ text: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if g2p == nil {
            guard hasDictionary else { throw FrontendError.missingDictionary }
            g2p = try SeaG2P(binURL: dictionaryURL)
        }
        guard let g2p else { throw FrontendError.missingDictionary }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { g2p.phonemizeTextWithEmotions(text: $0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Nhả bản đồ bộ nhớ của `sea_g2p.bin` (62,8 MB) khi rời màn thử / khi trình đọc chuyển về Nano. Lần phiên âm sau tự
    /// nạp lại.
    func unload() {
        lock.lock()
        g2p = nil
        lock.unlock()
    }
}
