import SwiftUI

/// Nạp **chip phiên âm** cho `TTSReplacementSuggestionSection` (1.3.974) — gắn lên `Form` của sheet bằng
/// `.phoneticSuggestions(for:mode:into:)`.
///
/// Là modifier chứ không nằm trong chính section: section không vẽ gì khi chưa có chip, mà `.task` gắn lên view rỗng
/// thì không bao giờ chạy.
///
/// Việc nặng nằm **ngoài main thread** như `AddWordSheet` (1.3.336): đường tiếng Anh gọi `EspeakPhonemizer` — hàm C
/// đồng bộ giữ một `NSLock` dùng chung với đường tổng hợp NghiTTS, mở sheet lúc đang nghe TTS mà tính trên main là
/// đứng UI. `Task.detached` chứ không phải `Task`: `Task` thừa hưởng `@MainActor` của chỗ tạo.
///
/// Lượt đầu (từ có sẵn lúc mở sheet) chạy ngay; các lượt sau chờ người dùng ngừng gõ 0,3 s. `.task(id:)` tự huỷ lượt
/// cũ khi từ đổi hoặc sheet đóng; lượt bị huỷ không ghi gì. Trong lúc chờ, chip của từ cũ còn nguyên (không xoá trước
/// để section khỏi nháy theo từng phím).
struct TTSPhoneticSuggestionLoadModifier: ViewModifier {
    enum Mode: Sendable {
        /// Ô chuỗi thay thế của luật thay thế TTS: chỉ phiên âm tự động JP / EN, chỉ khi từ **có** phiên âm
        /// (`TTSPhoneticSuggestionBuilder.transliterations`).
        case replacementRule
        /// Sheet sửa một mục từ điển phiên âm: cách đọc đang lưu ở **cả hai** từ điển (NGI / VIE) + JP + EN
        /// (`TTSPhoneticSuggestionBuilder.suggestions`, như sheet Thêm từ).
        case phoneticDictionary
    }

    let word: String
    let mode: Mode
    @Binding var suggestions: [TTSPhoneticSuggestion]

    @State private var hasLoadedOnce = false

    func body(content: Content) -> some View {
        content.task(id: word.trimmingCharacters(in: .whitespacesAndNewlines)) {
            await reload()
        }
    }

    @MainActor
    private func reload() async {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFirstLoad = !hasLoadedOnce
        hasLoadedOnce = true

        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }
        if !isFirstLoad {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        guard !Task.isCancelled else { return }

        let built: [TTSPhoneticSuggestion]
        switch mode {
        case .replacementRule:
            built = await Task.detached(priority: .userInitiated) {
                TTSPhoneticSuggestionBuilder.transliterations(for: trimmed)
            }.value
        case .phoneticDictionary:
            // Tra bằng khoá đã gấp dấu phụ, giống lúc đọc. Hai `String?` rời (không gộp tuple) để closure
            // `@Sendable` của `Task.detached` chắc chắn bắt được.
            let lookupKey = TTSPhoneticSuggestionBuilder.normalizedKey(trimmed)
            let nghiTTSHit = await TextPreprocessor.shared.lookupWord(lookupKey)
            let vieNeuHit = await VieNeuJapaneseDictionary.shared.lookup(lookupKey)
            // vtts giữ dấu trong khoá (`VttsPhoneticDictionary.normalizedKey`) ⇒ tra bằng chữ gốc, không bằng khoá gấp dấu.
            let vttsHit = await VttsPhoneticDictionary.shared.lookup(trimmed)
            guard !Task.isCancelled else { return }
            built = await Task.detached(priority: .userInitiated) {
                TTSPhoneticSuggestionBuilder.suggestions(
                    for: trimmed, nghiTTSHit: nghiTTSHit, vieNeuHit: vieNeuHit, vttsHit: vttsHit
                )
            }.value
        }
        guard !Task.isCancelled else { return }

        suggestions = built
    }
}

extension View {
    /// Nạp chip phiên âm của `word` vào `suggestions` (ngoài main thread, tự nạp lại khi `word` đổi) — xem
    /// `TTSPhoneticSuggestionLoadModifier`.
    func phoneticSuggestions(
        for word: String,
        mode: TTSPhoneticSuggestionLoadModifier.Mode,
        into suggestions: Binding<[TTSPhoneticSuggestion]>
    ) -> some View {
        modifier(TTSPhoneticSuggestionLoadModifier(word: word, mode: mode, suggestions: suggestions))
    }
}
