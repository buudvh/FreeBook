import SwiftUI

/// Section **Bộ lọc** của màn Cài đặt → Trình duyệt (plan §3.2): 7 bộ của `AdBlockFilter.catalog` (đúng thứ tự danh
/// mục), mỗi dòng tên + chữ phụ trạng thái + công tắc, rồi dòng "Cập nhật ngay".
///
/// Đọc/ghi qua `AdBlockRuleListProvider.shared` (`@Observable`): công tắc ⇒ `setFilter(id:enabled:)`, trạng thái ⇒
/// `statuses`, nút ⇒ `updateNow()`. Đổi bộ lọc có hiệu lực từ lượt nạp trang kế tiếp của mỗi webview.
///
/// Chữ phụ (ưu tiên từ trên xuống):
/// 1. `Đang cập nhật…` — bộ đang tải/biên dịch lại;
/// 2. `Lỗi tải, đang dùng bản 14/10` (màu cảnh báo) — tải lỗi nhưng còn bản cũ; không còn bản nào ⇒ `Lỗi tải`;
/// 3. `48.120 luật · 19/10 14:20` — đã có số luật (ngày = lúc tải file / ngày của bản đóng gói);
/// 4. còn lại ⇒ ghi chú của bộ (Tracking: `Nặng, dễ lỗi trang`) hoặc `Chưa tải`.
struct BrowserFilterListSection: View {
    private var provider: AdBlockRuleListProvider { AdBlockRuleListProvider.shared }

    var body: some View {
        let isUpdating = provider.isUpdating
        Section {
            ForEach(AdBlockFilter.catalog) { filter in
                filterRow(filter)
            }
            Button {
                AdBlockRuleListProvider.shared.updateNow()
            } label: {
                HStack(spacing: 12) {
                    Label("Cập nhật ngay", systemImage: "arrow.clockwise")
                        .foregroundColor(isUpdating ? .secondary : .primary)
                    Spacer(minLength: 8)
                    if isUpdating {
                        Text(provider.progressText ?? "Đang cập nhật…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .disabled(isUpdating)
        } header: {
            Text("Bộ lọc")
        } footer: {
            Text("Tự cập nhật khi bộ lọc quá 5 ngày. Bộ lọc của AdGuard và ABPVN.")
        }
    }

    private func filterRow(_ filter: AdBlockFilter) -> some View {
        let status = provider.statuses[filter.id] ?? .empty
        let line = Self.statusLine(for: filter, status: status)
        return Toggle(isOn: enabledBinding(for: filter.id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.name)
                Text(line.text)
                    .font(.caption)
                    .foregroundColor(line.isWarning ? .orange : .secondary)
            }
        }
    }

    /// Như `ExtensionConfigView.savesHistoryBinding`: chụp giá trị trong lượt vẽ, ghi qua `MainActor.assumeIsolated`.
    private func enabledBinding(for id: Int) -> Binding<Bool> {
        let isOn = provider.isFilterEnabled(id)
        return Binding(
            get: { isOn },
            set: { value in
                MainActor.assumeIsolated {
                    AdBlockRuleListProvider.shared.setFilter(id: id, enabled: value)
                    AppLogger.shared.log("🛡️ [BrowserSettings] \(value ? "Bật" : "Tắt") bộ lọc \(id)")
                }
            }
        )
    }

    // MARK: - Chữ phụ trạng thái

    private static func statusLine(for filter: AdBlockFilter, status: AdBlockFilterStatus) -> (text: String, isWarning: Bool) {
        if status.isUpdating {
            return ("Đang cập nhật…", false)
        }
        if status.lastError != nil {
            guard status.hasData || status.safariRuleCount != nil else { return ("Lỗi tải", true) }
            let version = status.updatedAt.map { dayFormatter.string(from: $0) } ?? "cũ"
            return ("Lỗi tải, đang dùng bản \(version)", true)
        }
        if let count = status.safariRuleCount {
            let rules = "\(ruleCountText(count)) luật"
            guard let updatedAt = status.updatedAt else { return (rules, false) }
            return ("\(rules) · \(dateTimeFormatter.string(from: updatedAt))", false)
        }
        return (filter.note ?? "Chưa tải", false)
    }

    /// `48120` ⇒ `48.120` (dấu chấm ngăn nghìn như mockup, không phụ thuộc vùng của máy).
    private static func ruleCountText(_ count: Int) -> String {
        ruleCountFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static let ruleCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "."
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// `19/10 14:20`
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()

    /// `14/10`
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM"
        return formatter
    }()
}
