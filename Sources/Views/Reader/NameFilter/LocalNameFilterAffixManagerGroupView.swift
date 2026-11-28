import SwiftUI

/// Một nhóm của màn Quản lý tiền tố, hậu tố (`LocalNameFilterAffixManagerView`, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M3): tiêu đề "TIỀN TỐ [R] RIÊNG TRUYỆN" / "HẬU TỐ [C] CHUNG" rồi các
/// chip tràn dòng "语 · ngữ  Thuật ngữ ⓧ", chip "+ Thêm" viền đứt cuối nhóm; nhóm rỗng ghi "Chưa có". Chạm thân chip ⇒ sửa
/// (`onTap`), ⓧ ⇒ xoá (`onDelete`, màn cha hỏi lại), "+ Thêm" ⇒ thêm vào nhóm này (`onAdd`).
///
/// Badge R / C dùng **màu badge phạm vi của chip nghĩa** (`SuggestionChip.Scope` — R đỏ, C xám) cho cùng màu ở mọi nơi; mockup
/// vẽ R vàng. Chip theo khuôn chip của màn Quản lý nghĩa từ (`ManageDefinitionChipView`: nền `Color.primary` mờ, viền mờ) nhưng
/// nút ⓧ nằm **trong** chip bên phải như mockup.
struct LocalNameFilterAffixManagerGroupView: View {
    typealias Scoped = LocalNameFilterAffixScopedEntry
    typealias Scope = LocalNameFilterAffixListStore.Scope

    private static let chipHeight: CGFloat = 34

    let flavor: LocalNameFilterAffixListFlavor
    let scope: Scope
    let items: [Scoped]
    /// Chữ đang bị bản Riêng che (chỉ nhóm Chung) — chip ghi thêm "bị che".
    let shadowedKeys: Set<String>
    let onTap: (Scoped) -> Void
    let onDelete: (Scoped) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            FlowLayout(spacing: 8) {
                if items.isEmpty {
                    Text("Chưa có")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(height: Self.chipHeight)
                }
                ForEach(items) { item in
                    chip(item)
                }
                addChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var scopeLabel: String { scope == .book ? "Riêng truyện" : "Chung" }

    private var title: some View {
        let badgeScope: SuggestionChip.Scope = scope == .book ? .book : .global
        return HStack(spacing: 6) {
            Text(verbatim: flavor.noun)
            Text(verbatim: badgeScope.badgeLetter)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(badgeScope.badgeTextColor)
                .padding(.horizontal, 5)
                .frame(minHeight: 16)
                .background(badgeScope.badgeBackground, in: RoundedRectangle(cornerRadius: 3))
                .textCase(nil)
            Text(verbatim: scopeLabel)
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(flavor.noun) \(scopeLabel.lowercased())")
        .accessibilityAddTraits(.isHeader)
    }

    private func chip(_ item: Scoped) -> some View {
        let isShadowed = scope == .common && shadowedKeys.contains(item.key)
        let kindLabel = LocalNameFilterSuffixRow.kindLabel(item.entry.kind)
        let shadowNote = isShadowed ? ", đang bị bản riêng truyện che" : ""
        return HStack(spacing: 6) {
            Button {
                onTap(item)
            } label: {
                HStack(spacing: 5) {
                    Text(verbatim: "\(item.key) · \(item.entry.meaning)")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(verbatim: isShadowed ? "\(kindLabel) · bị che" : kindLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sửa \(flavor.lowercasedNoun) \(item.key), \(item.entry.meaning), \(kindLabel)\(shadowNote)")

            Button {
                onDelete(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(0.22), in: Circle())
                    .frame(width: 26, height: Self.chipHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xoá \(flavor.lowercasedNoun) \(item.key)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: Self.chipHeight)
        .background(Color.primary.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
        .opacity(isShadowed ? 0.6 : 1)
    }

    private var addChip: some View {
        Button(action: onAdd) {
            Text("+ Thêm")
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 14)
                .frame(height: Self.chipHeight)
                .overlay(
                    Capsule().strokeBorder(
                        Color.accentColor.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thêm \(flavor.lowercasedNoun) \(scopeLabel.lowercased())")
    }
}
