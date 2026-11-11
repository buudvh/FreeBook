import Foundation

/// Phần dịch của `VideoHardSubtitleEngine` (1.3.840): dịch phụ đề cứng **y như phụ đề mềm / truyện chữ / truyện tranh**.
///
/// - Cổng dịch + phồn→giản + ảnh chụp từ điển / rule: `MediaCaptionTranslator.prepare(bookId:packageId:)` — phim này > nguồn >
///   nguồn tự khai tiếng Trung > toàn cục (cùng kho `TranslationConfigStore` với Chi tiết, Reader, truyện tranh); phồn→giản
///   theo phim / nguồn (sheet "Dịch phụ đề"). Một `Pass` dùng cho mọi câu tới khi cấu hình / từ điển / rule đổi.
/// - Chỉ đọc khi **dịch** bật (`Pass.translates`) — như dịch ảnh truyện tranh: lượt chỉ chuyển phồn → giản (tắt dịch) không
///   vẽ chữ Trung lên hình ⇒ `isTranslationActive = false` ⇒ engine ngưng đọc, lớp phủ không vẽ, phụ đề mềm hiện lại.
/// - Đang đọc mà phồn → giản bật ⇒ câu Trung của Song ngữ (`DisplayedCue.original`) là chữ **đã chuyển**.
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
            // Lượt chỉ chuyển phồn → giản (tắt dịch) ⇒ coi như cổng tắt: không vẽ chữ Trung lên hình.
            let prepared = await MediaCaptionTranslator.prepare(bookId: bookId, packageId: packageId)
            let pass = prepared?.translates == true ? prepared : nil
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
            show(recognition, result: cached, frameSize: frameSize)
            return
        }
        guard let pass = translationPass else { return }
        let runGeneration = generation
        let epoch = passEpoch
        let text = recognition.text
        Task {
            guard let results = await MediaCaptionTranslator.translate([text], pass: pass),
                  runGeneration == generation, epoch == passEpoch else { return }
            let result = results.first ?? .unchanged
            remember(result, for: text)
            let source = Self.logText(result.converted ?? text)
            AppLogger.shared.log("🔤 [VideoOCR] «\(source)» ⇒ «\(result.translation.map(Self.logText) ?? "(không dịch)")»")
            guard let current = tracker.current, current.text == text else { return }
            show(current, result: result, frameSize: frameSize)
        }
    }

    private func setTranslationActive(_ active: Bool) {
        guard active != isTranslationActive else { return }
        isTranslationActive = active
        AppLogger.shared.log(active
            ? "🔤 [VideoOCR] Phim đang bật dịch ⇒ đọc và dịch phụ đề cứng"
            : "🔤 [VideoOCR] Phim đang tắt dịch ⇒ ngưng đọc phụ đề cứng, để chữ gốc")
    }

    /// `original` = câu Trung đã chuyển phồn → giản nếu bật (dòng phụ của Song ngữ).
    private func show(_ recognition: Recognition, result: MediaCaptionTranslator.LineResult, frameSize: CGSize) {
        displayedCue = DisplayedCue(
            original: result.converted ?? recognition.text,
            translation: result.translation,
            rect: recognition.rect,
            frameSize: frameSize,
            lineCount: recognition.lineCount
        )
    }

    private func remember(_ result: MediaCaptionTranslator.LineResult, for text: String) {
        guard translations[text] == nil else { return }
        translations[text] = result
        translationOrder.append(text)
        if translationOrder.count > Self.translationCacheLimit {
            translations[translationOrder.removeFirst()] = nil
        }
    }

    private static func logText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }
}
