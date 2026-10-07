import Foundation

/// Kiểm tra hợp lệ cho **pattern quy tắc mục lục**, và ngoại lệ dành cho quy tắc **mặc định của app**.
///
/// ## Vì sao tách khỏi `TranslateUtils.swift`
/// Hai lý do, cả hai đều có thật:
/// 1. File đó đang **916/917 dòng** theo trần ratchet của `check_architecture.py` — chỉ dư **một** dòng, nên
///    nhồi thêm logic vào là vượt trần ngay. Repo chỉ cho file legacy **giảm**, không cho tăng; tách ra vừa
///    giữ đúng luật vừa trả lại headroom.
/// 2. Phần "rule mặc định được miễn trần độ dài" là logic **mới** và có lý do riêng — đứng cùng chỗ với
///    `validateTOCRulePattern` thì đọc một mạch là hiểu, thay vì nằm lẫn trong file 900 dòng.
///
/// ## Vì sao có ngoại lệ
/// App tự ship `rule21` "Quy tắc mở rộng nâng cao" dài **254** ký tự, tức **vượt trần 250 của chính nó**:
/// trần ra đời 2026-07-28 (`5d99d67`), rule21 được thêm 2026-07-30 (`c3f83ba`) — vượt đúng 4 ký tự, và không
/// ai phát hiện vì thêm rule mặc định thì không chạy validator.
///
/// Hậu quả thật (1.3.474): **khôi phục cấu hình từ bản sao lưu báo lỗi**
/// `Quy tắc mục lục: Biểu thức chính quy không hợp lệ cho 'Quy tắc mở rộng nâng cao': Độ dài Regex không được
/// vượt quá 250 ký tự.` — dù bản sao lưu chỉ chứa **đúng bộ rule mặc định của app**. Cùng lỗi đó cũng làm
/// hỏng đường nhập file `toc_rules.json` và khiến rule21 hiện là "không hợp lệ" ở màn Quy tắc mục lục.
///
/// Cách chữa **không** phải rút ngắn pattern: regex đó đang chạy thật để tách mục lục, sửa nó là đổi hành vi
/// tách chương của mọi người dùng. Chữa ở đúng chỗ sai — trần không được áp lên chính dữ liệu mặc định của app.
extension TranslateUtils {
    /// `true` khi `pattern` trùng **y hệt** pattern của một quy tắc mặc định của app.
    ///
    /// So khớp theo **pattern**, không theo `id`: người dùng sửa pattern của `rule21` thì bản sửa là **dữ liệu
    /// người dùng** và phải chịu đúng trần 250 như mọi pattern khác — chỉ bản gốc của app mới được miễn.
    ///
    /// Trả `false` cho chuỗi rỗng: rỗng đã có câu lỗi riêng ở `validateTOCRulePattern`, và ở đây rỗng không
    /// thể là "mặc định".
    static func isBuiltInTOCRulePattern(_ pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return defaultTOCRules.contains {
            $0.rule.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }
    }

    /// `nil` = hợp lệ; ngược lại là **câu lỗi** để màn Quy tắc mục lục hiện được lý do cụ thể.
    ///
    /// Là cửa kiểm tra **duy nhất** cho pattern: màn soạn rule, đường nhập file và đường khôi phục cấu hình đều
    /// đi qua đây, nên ngoại lệ cho rule mặc định tự động đúng ở cả ba — không phải vá riêng từng đường.
    public static func validateTOCRulePattern(_ pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Chuỗi mẫu Regex không được để trống." }
        if trimmed.count > 250, !isBuiltInTOCRulePattern(trimmed) {
            return "Độ dài Regex không được vượt quá 250 ký tự."
        }
        do {
            _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            return nil
        } catch {
            return "Cú pháp Regex không hợp lệ: \(error.localizedDescription)"
        }
    }
}
