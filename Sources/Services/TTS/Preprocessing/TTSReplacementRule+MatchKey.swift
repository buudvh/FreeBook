import Foundation

/// Khoá khớp của luật thay thế TTS — **không phân biệt hoa thường** (1.3.978, anh Bửu: chip R/C không hiện vì "R/C phân
/// biệt hoa thường", chọn "cả lúc đọc cũng không phân biệt").
///
/// Một chỗ duy nhất quyết định hai mẫu có phải "cùng một luật" hay không. Mọi phép so mẫu của luật thay thế đi qua đây:
/// lúc đọc (`TTSReplacementPlan` — luật chữ), gộp tầng riêng với tầng chung (`mergedRules`), thêm / sửa / nhập / khôi phục
/// (đè hoặc bỏ qua luật trùng), cảnh báo trùng mẫu (`TTSReplacementRuleValidator`) và chip R/C
/// (`TTSReplacementSuggestionSection`). So bằng `==` trên `pattern` ở chỗ mới là lặp lại lỗi cũ.
///
/// Chỉ hạ chữ thường — **giữ** dấu tiếng Việt (`Hà` ≠ `Ha`) và giữ nguyên chuỗi thay thế (`replacement` đi vào trình đọc
/// đúng như người dùng gõ).
extension TTSReplacementRule {
    static func matchKey(for pattern: String) -> String {
        pattern.lowercased()
    }

    var matchKey: String {
        Self.matchKey(for: pattern)
    }
}
