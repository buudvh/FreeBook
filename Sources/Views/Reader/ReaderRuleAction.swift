import Foundation

/// Thao tác trên **một** rule, phát từ dải chip rule của panel Dịch.
///
/// Trước 1.3.334 enum này nằm trong `ReaderRuleTraceOverlayView` (màn Check rule riêng, đã bị xoá khi
/// gộp vào panel Dịch). Đặt ở file riêng để không phụ thuộc vào một view cụ thể nào.
enum ReaderRuleAction: Equatable {
    case setDisabled(Bool, QuickTranslationRuleScope)
    case edit
    case delete
    /// Chuyển rule sang phạm vi còn lại (riêng ⇄ chung). Là **move**: ghi ở đích rồi xoá ở nguồn.
    case moveScope(QuickTranslationRuleScope)
}
