import SwiftUI

/// Thẻ đầu màn **Cấu hình tiện ích**, căn giữa kiểu hồ sơ: icon bo góc 84pt, tên, **một hàng badge** cờ ngôn ngữ ·
/// tác giả · loại · phiên bản, mô tả 2 dòng có "Xem thêm", rồi hàng 3 nút tròn có nhãn **Trình duyệt · Ghim · Gỡ**.
///
/// Hàng badge không xuống dòng: chỉ badge tác giả được co "…" (`layoutPriority(-1)`); thiếu ngôn ngữ/tác giả thì bỏ
/// badge đó. Cờ dùng chung bảng của chip lọc ngôn ngữ (`ExtensionFilterGroups.localeGroupFlag`).
///
/// Chỉ đọc bản ghi `Extension` (caller truyền `current` — bản tra lại theo `packageId`, nên ghim xong là thẻ vẽ lại
/// "Bỏ ghim"); không đọc `plugin.json`. Sửa các trường metadata ở màn con "Thông tin plugin.json".
///
/// Thiếu nút nào (không có `onOpenBrowser` / `onUninstall`) thì các nút còn lại giãn đều. Mọi nút dùng
/// `.buttonStyle(.borderless)`: trong một dòng của `Form`, nút kiểu mặc định khiến chạm bất kỳ đâu trên dòng là
/// bấm **tất cả** nút của dòng đó.
struct ExtensionConfigHeaderCard: View {
    let ext: Extension
    /// `nil` ⇒ ẩn nút Trình duyệt (không có link nguồn, hoặc tiện ích TTS/dịch…).
    var onOpenBrowser: (() -> Void)? = nil
    /// `nil` ⇒ ẩn nút Gỡ (tiện ích chưa cài).
    var onUninstall: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                // Nhãn 18+ của icon đọc bảng chụp có lock (không observe được) và tham số icon không đổi khi đổi
                // "Nội dung 18+" ở dưới ⇒ gắn `id` theo trạng thái NSFW để icon dựng lại ngay.
                ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 84)
                    .id(ExtensionNsfwClassifier.isNsfw(ext))

                Text(ext.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                badgeRow
            }
            .frame(maxWidth: .infinity)

            if !descriptionText.isEmpty {
                ExpandableTextView(text: descriptionText, lineLimit: 2, font: .footnote, foregroundColor: .secondary)
            }

            actionRow
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
    }

    // MARK: - Thông tin

    /// Cờ ngôn ngữ · tác giả · loại · phiên bản trên một hàng.
    private var badgeRow: some View {
        HStack(spacing: 4) {
            if !ext.locale.isEmpty {
                Text(ExtensionFilterGroups.localeGroupFlag(ExtensionFilterGroups.localeGroup(for: ext.locale)))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.gray.opacity(0.35))
                    .cornerRadius(4)
                    .fixedSize()
                    .accessibilityLabel(ExtensionDisplayCatalog.label(forLocale: ext.locale))
            }
            if !authorText.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text(authorText)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundColor(.white)
                .background(Color.gray.opacity(0.35))
                .cornerRadius(4)
                .layoutPriority(-1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tác giả \(authorText)")
            }
            kindTag
                .fixedSize()
            chip("v\(ext.version)")
                .fixedSize()
                .accessibilityLabel("Phiên bản \(ext.version)")
        }
    }

    private var authorText: String {
        ext.author.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mô tả có thể là HTML (registry/`plugin.json`) — bỏ thẻ như các màn khác (`cleanHTML()`).
    private var descriptionText: String {
        (ext.desc ?? "").cleanHTML().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tiện ích nội dung dùng `BookKindBadge` (cùng nhãn với bảng chọn nguồn); TTS/dịch… badge đó không vẽ gì nên
    /// hiện nhãn `type` thô qua `ExtensionDisplayCatalog`.
    @ViewBuilder
    private var kindTag: some View {
        let kind = SearchExtensionScopePolicy.kind(of: ext)
        if kind == .unsupported {
            chip(ExtensionDisplayCatalog.label(forType: ext.type))
        } else {
            BookKindBadge(kind: kind, showsLabel: true, hidesText: false)
        }
    }

    /// Cùng dáng với `BookKindBadge` có nhãn.
    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(.white)
            .background(Color.gray.opacity(0.35))
            .cornerRadius(4)
    }

    // MARK: - Hàng nút

    private var actionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if let onOpenBrowser {
                actionButton(title: "Trình duyệt", systemImage: "safari", action: onOpenBrowser)
            }
            actionButton(
                title: ext.isPinned ? "Bỏ ghim" : "Ghim",
                systemImage: ext.isPinned ? "pin.fill" : "pin",
                iconColor: ext.isPinned ? .orange : .primary,
                circleFill: ext.isPinned ? Color.orange.opacity(0.18) : nil,
                action: { togglePin() }
            )
            if let onUninstall {
                actionButton(title: "Gỡ", systemImage: "trash", iconColor: .red, titleColor: .red, action: onUninstall)
            }
        }
    }

    /// Nút tròn 44pt + nhãn nhỏ bên dưới, chia đều chiều ngang. Không dùng `Label`: trong một dòng của `Form`, iOS
    /// dàn icon và chữ của `Label` ra hai đầu ô (cột icon cố định), chữ bị đẩy lệch và co nhỏ.
    private func actionButton(
        title: String,
        systemImage: String,
        iconColor: Color = .primary,
        titleColor: Color = .secondary,
        circleFill: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { action() }) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                    .background(circleFill ?? Color(.tertiarySystemFill), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundColor(titleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }

    /// Ghim ⇒ lên nhóm ghim ở bảng chọn nguồn và Kho. Bảng tiện ích là `@Observable` nên thẻ tự vẽ lại.
    @MainActor
    private func togglePin() {
        let name = ext.name
        let wasPinned = ext.isPinned
        switch ExtensionTransactionCoordinator.shared.togglePinned(packageId: ext.packageId) {
        case .success:
            AppLogger.shared.log("📌 [ExtConfig] \(name): \(wasPinned ? "bỏ ghim" : "ghim")")
        case .failure(let err):
            AppLogger.shared.log("❌ [ExtConfig] Lỗi ghim tiện ích \(name): \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không ghim được tiện ích: \(err.localizedDescription)", type: .error)
        }
    }
}
