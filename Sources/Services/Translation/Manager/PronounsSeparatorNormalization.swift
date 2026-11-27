import Foundation

/// Lượt **một lần** (anh Bửu, 2026-11-27): nghĩa trong file Pronouns gốc có chỗ ngăn bằng `|` thay vì `/`. Từ bản có chip
/// Pronoun + nhóm Pronoun ở Quản lý nghĩa từ, mọi chỗ tách nghĩa Pronoun nhận cả `|`, và lần đầu mở app sau bản đó file
/// được chuẩn hoá: mọi `|` trong nghĩa đổi thành `/` — **chỉ đổi cú pháp**, khoá và chữ nghĩa giữ nguyên
/// (`GlobalDictionaryEditor.normalizePronounSeparators`, đi qua hàng đợi ghi từ điển gốc, nạp lại riêng Pronouns).
///
/// Gọi từ `TranslationManager.init` **ngay sau** lượt nạp từ điển đầu tiên: lượt đó có thể đang dựng `Pronouns.dat` từ
/// `Pronouns.txt` (không qua hàng đợi) — chạy song song là đọc phải file dở hoặc nạp đè trie cũ. Chưa có file Pronouns
/// ⇒ đánh dấu xong luôn. Lỗi ⇒ không đánh dấu, lần mở sau thử lại.
enum PronounsSeparatorNormalization {
    /// Cờ `UserDefaults` (chữ thường, không dấu chấm).
    static let doneKey = "pronounsPipeNormalizedV1"

    static func runIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        do {
            let result = try await GlobalDictionaryEditor.shared.normalizePronounSeparators()
            defaults.set(true, forKey: doneKey)
            AppLogger.shared.log(
                "📚 [Pronouns] Chuẩn hoá một lần | → /: đổi \(result.changed) / \(result.total) mục"
            )
        } catch {
            AppLogger.shared.log("❌ [Pronouns] Chưa chuẩn hoá được | → / (lần mở sau thử lại): \(error.localizedDescription)")
        }
    }
}
