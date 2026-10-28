import SwiftUI

/// Hàng quy tắc của `TOCRulesConfigView`, theo mẫu hàng VP/Name (`QuickTranslationRuleEntryRow`):
/// chữ (chạm để sửa) + icon `[Sửa] [Tắt|Bật] [Xoá]`.
///
/// Tách khỏi file chính vì file đó là legacy sát baseline dòng (585). Thành viên dùng chéo file
/// (`isDefaultRule`, `prepareForEdit`, `setRuleEnabled`, `deleteCustomRule(id:)`) đã hạ `private` → `internal`.
extension TOCRulesConfigView {

    /// Hàng **không** bọc `Button` ngoài — nút lồng nút thì icon không bấm riêng được. Chạm chỉ gắn vào khối chữ.
    @ViewBuilder
    func ruleRow(for rule: TOCRule) -> some View {
        let isDefault = isDefaultRule(rule)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.name)
                        .font(.headline)
                        .foregroundColor(rule.enabled ? .primary : .secondary)

                    if isDefault {
                        Text("Mặc định")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }

                Text(rule.rule)
                    .font(.subheadline)
                    .foregroundColor(rule.enabled ? .secondary : Color.secondary.opacity(0.6))
                    .lineLimit(2)

                if let ex = rule.example, !ex.isEmpty {
                    Text("Ví dụ: \(ex)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { prepareForEdit(rule) }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Quy tắc \(rule.name)")
            .accessibilityHint("Nhấn hai lần để chỉnh sửa quy tắc này")

            ruleActionIcons(for: rule, isDefault: isDefault)
        }
    }

    /// Tắt/Bật ghi y như `Toggle` cũ (`setRuleEnabled` → `onRulesChanged`). Rule mặc định không xoá được
    /// (cùng luật `deleteCustomRules`) nên icon Xoá mờ và vô hiệu, vẫn giữ chỗ cho thẳng cột.
    private func ruleActionIcons(for rule: TOCRule, isDefault: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                prepareForEdit(rule)
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sửa quy tắc \(rule.name)")

            Button {
                setRuleEnabled(rule, !rule.enabled)
            } label: {
                Image(systemName: rule.enabled ? "pause.circle" : "play.circle")
                    .foregroundColor(rule.enabled ? .orange : .green)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rule.enabled ? "Tắt quy tắc \(rule.name)" : "Bật quy tắc \(rule.name)")
            .accessibilityValue(rule.enabled ? "Đã bật" : "Đã tắt")

            Button {
                deleteCustomRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(isDefault ? .secondary : .red)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(isDefault)
            .accessibilityLabel(isDefault ? "Quy tắc mặc định, không xoá được" : "Xoá quy tắc \(rule.name)")
        }
    }
}
