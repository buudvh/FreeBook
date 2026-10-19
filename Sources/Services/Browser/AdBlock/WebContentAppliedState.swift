import Foundation

/// Trạng thái `WebContentConfigurator` đã áp lên một webview — caller giữ lại để so với trạng thái cần cho lượt
/// điều hướng kế tiếp (khác ⇒ áp lại / nạp lại).
///
/// `adBlock` là **quyết định** gắn luật, không phải "đã có rule list": webview tạo trước khi
/// `AdBlockRuleListProvider` sẵn sàng có `adBlock == true` nhưng chưa có luật nào.
struct WebContentAppliedState: Equatable, Sendable {
    let adBlock: Bool
    let userAgent: String
    let desktop: Bool
}
