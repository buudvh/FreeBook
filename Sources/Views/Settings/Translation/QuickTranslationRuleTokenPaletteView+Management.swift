import SwiftUI

/// Nhóm "Tùy chọn" + menu nhấn giữ của bảng token (1.3.1063, mockup https://claude.ai/artifact/EPVM1fC9YrAozdyt1H5NUj).
///
/// Menu là `.contextMenu` của iOS (như các danh sách khác trong app); mỗi mục chỉ ghi ý định vào `model`, sheet sửa rule
/// đẩy trang / mở sheet (`QuickTranslationRuleTokenPaletteManagement`). Chip cú pháp nhóm `( | ) )?` không có menu.
extension QuickTranslationRuleTokenPaletteView {
    /// Token cố định có trang danh sách riêng: `<ho>` ⇒ Danh sách họ, `<[>` `<]>` ⇒ Bộ ngoặc (bộ chung).
    static func listRoute(
        for kind: QuickTranslationRuleTokenSettings.Kind
    ) -> (title: String, route: QuickTranslationRuleTokenPaletteModel.Route)? {
        switch kind {
        case .surname: return ("Danh sách họ", .surnameList)
        case .openBracket, .closeBracket: return ("Bộ ngoặc", .bracketList)
        default: return nil
        }
    }

    /// Nhóm luôn hiện (kể cả khi chưa có token nào) vì chip `+` là lối thêm token ngay từ màn sửa rule.
    func customGroup(_ tokens: [QuickTranslationCustomToken]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            caption("Tùy chọn")
            FlowLayout(spacing: 6) {
                ForEach(tokens) { token in
                    customTokenButton(token)
                }
                addTokenButton
            }
        }
    }

    private func customTokenButton(_ token: QuickTranslationCustomToken) -> some View {
        plainButton(token.syntax, caption: token.displayTitle, isDimmed: !token.isEnabled) {
            onInsert(token.syntax)
        }
        .contextMenu { customTokenMenu(token) }
        .accessibilityLabel("Chèn token \(token.syntax) — \(token.displayTitle)")
    }

    private var addTokenButton: some View {
        Button {
            model.isCreatingToken = true
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 16)
                Text("thêm token")
                    .font(.system(size: 9))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thêm token tùy chọn")
    }

    /// Menu nhấn giữ của token cố định: trang danh sách (nếu có) + Tắt / Bật (cùng công tắc ở Cấu hình token rule).
    @ViewBuilder
    func tokenMenu(_ kind: QuickTranslationRuleTokenSettings.Kind) -> some View {
        let isEnabled = QuickTranslationRuleTokenSettings.isEnabled(kind)
        Section(kind.label) {
            if let list = Self.listRoute(for: kind) {
                Button {
                    model.route = list.route
                } label: {
                    Label(list.title, systemImage: "list.bullet")
                }
            }
            Button {
                model.toggle(kind)
            } label: {
                Label(isEnabled ? "Tắt token" : "Bật token", systemImage: isEnabled ? "pause.circle" : "play.circle")
            }
        }
    }

    /// Menu nhấn giữ của token tùy chọn: Danh sách từ, Sửa mô tả, Tắt / Bật, Xoá (có hỏi lại).
    @ViewBuilder
    private func customTokenMenu(_ token: QuickTranslationCustomToken) -> some View {
        Section("\(token.syntax) — \(token.displayTitle) · \(token.entries.count) từ") {
            Button {
                model.route = .customToken(token.name)
            } label: {
                Label("Danh sách từ", systemImage: "list.bullet")
            }
            Button {
                model.editingToken = token
            } label: {
                Label("Sửa mô tả", systemImage: "pencil")
            }
            Button {
                model.toggle(token)
            } label: {
                Label(token.isEnabled ? "Tắt token" : "Bật token", systemImage: token.isEnabled ? "pause.circle" : "play.circle")
            }
        }
        Button(role: .destructive) {
            model.pendingDeletion = token
        } label: {
            Label("Xoá token", systemImage: "trash")
        }
    }
}
