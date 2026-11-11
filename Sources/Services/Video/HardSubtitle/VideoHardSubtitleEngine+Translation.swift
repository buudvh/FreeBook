import Foundation

/// Phần dịch của `VideoHardSubtitleEngine` (1.3.840): dịch phụ đề cứng **y như phụ đề mềm / truyện chữ / truyện tranh**.
///
/// - Cổng dịch + phồn→giản + ảnh chụp từ điển / rule: `MediaCaptionTranslator.prepare(bookId:packageId:)` — phim này > nguồn >
///   nguồn tự khai tiếng Trung > toàn cục (cùng kho `TranslationConfigStore` với Chi tiết, Reader, truyện tranh); phồn→giản
///   theo phim / nguồn (sheet "Dịch phụ đề"). Một `Pass` dùng cho mọi câu tới khi cấu hình / từ điển / rule đổi.
/// - Cổng tắt ⇒ `isTranslationActive = false` ⇒ engine ngưng đọc, lớp phủ không vẽ, phụ đề mềm hiện lại.
/// - Đổi cấu hình dịch (`TranslationConfigStore.didChangeNotification`), từ điển (`.translationDictionariesDidUpdate` — gồm
///   "Từ điển truyện" của ngăn kéo `⋯`), rule (`.quickTranslationRulesDidUpdate`) ⇒ dựng `Pass` mới, xoá đệm, dịch lại câu
///   đang hiện.
/// - Câu có xuống dòng (thoại hai người) dịch từng hàng (`MediaCaptionTranslator.translate`); câu không đổi sau khi dịch ⇒
///   coi như không có bản dịch.
extension VideoHardSubtitleEngine {
    typealias Recognition = VideoHardSubtitleRecognizer.Recognition

    /// Gọi một lần trong `init` của singleton.
    func observeTranslationChanges() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            TranslationConfigStore.didChangeNotification,
            .translationDictionariesDidUpdate,
            .quickTranslationRulesDidUpdate
        ]
        notificationTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let engine = VideoHardSubtitleEngine.shared
                    guard engine.isRunning else { return }
                    engine.refreshTranslationPass()
                }
            }
        }
    }

    /// Dựng lại cổng dịch (ngoài main) rồi dịch lại câu đang hiện nếu còn dịch.
    func refreshTranslationPass() {
        passTask?.cancel()
        passEpoch += 1
        translations = [:]
        translationOrder = []
        guard let launch = session.launch else {
            translationPass = nil
            setTranslationActive(false)
            return
        }
        let epoch = passEpoch
        let bookId = launch.bookId
        let packageId = launch.extensionPackageId
        passTask = Task {
            let pass = await MediaCaptionTranslator.prepare(bookId: bookId, packageId: packageId)
            guard epoch == passEpoch, !Task.isCancelled else { return }
            translationPass = pass
            setTranslationActive(pass != nil)
            if pass != nil, let current = tracker.current {
                translate(current, frameSize: displayedCue?.frameSize ?? .zero)
            }
        }
    }

    func translate(_ recognition: Recognition, frameSize: CGSize) {
        if let cached = translations[recognition.text] {
            show(recognition, translation: cached.isEmpty ? nil : cached, frameSize: frameSize)
            return
        }
        guard let pass = translationPass else { return }
        let runGeneration = generation
        let epoch = passEpoch
        let text = recognition.text
        Task {
            guard let results = await MediaCaptionTranslator.translate([text], pass: pass),
                  runGeneration == generation, epoch == passEpoch else { return }
            let translated = results.first ?? nil
            remember(translated ?? "", for: text)
            AppLogger.shared.log("🔤 [VideoOCR] «\(Self.logText(text))» ⇒ «\(translated.map(Self.logText) ?? "(không dịch)")»")
            guard let current = tracker.current, current.text == text else { return }
            show(current, translation: translated, frameSize: frameSize)
        }
    }

    private func setTranslationActive(_ active: Bool) {
        guard active != isTranslationActive else { return }
        isTranslationActive = active
        AppLogger.shared.log(active
            ? "🔤 [VideoOCR] Phim đang bật dịch ⇒ đọc và dịch phụ đề cứng"
            : "🔤 [VideoOCR] Phim đang tắt dịch ⇒ ngưng đọc phụ đề cứng, để chữ gốc")
    }

    private func show(_ recognition: Recognition, translation: String?, frameSize: CGSize) {
        displayedCue = DisplayedCue(
            original: recognition.text,
            translation: translation,
            rect: recognition.rect,
            frameSize: frameSize,
            lineCount: recognition.lineCount
        )
    }

    private func remember(_ translated: String, for text: String) {
        guard translations[text] == nil else { return }
        translations[text] = translated
        translationOrder.append(text)
        if translationOrder.count > Self.translationCacheLimit {
            translations[translationOrder.removeFirst()] = nil
        }
    }

    private static func logText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }
}
