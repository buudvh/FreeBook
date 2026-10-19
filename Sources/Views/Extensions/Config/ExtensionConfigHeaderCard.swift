import SwiftUI

/// Thẻ đầu màn **Cấu hình tiện ích**: icon, tên, "<tác giả> · Phiên bản N", nhãn loại + ngôn ngữ, mô tả 2 dòng có
/// "Xem thêm", rồi hàng 3 nút ngang nhau **Trình duyệt · Ghim · Gỡ**.
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
            HStack(alignment: .top, spacing: 12) {
                // Nhãn 18+ của icon đọc bảng chụp có lock (không observe được) và tham số icon không đổi khi đổi
                // "Nội dung 18+" ở dưới ⇒ gắn `id` theo trạng thái NSFW để icon dựng lại ngay.
                ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 46)
                    .id(ExtensionNsfwClassifier.isNsfw(ext))

                VStack(alignment: .leading, spacing: 4) {
                    Text(ext.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        kindTag
                        if !ext.locale.isEmpty {
                            chip(ExtensionDisplayCatalog.label(forLocale: ext.locale))
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if !descriptionText.isEmpty {
                ExpandableTextView(text: descriptionText, lineLimit: 2, font: .footnote, foregroundColor: .secondary)
            }

            actionRow
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
    }

    // MARK: - Thông tin

    private var subtitle: String {
        let version = "Phiên bản \(ext.version)"
        let author = ext.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return author.isEmpty ? version : "\(author) · \(version)"
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
        HStack(spacing: 8) {
            if let onOpenBrowser {
                actionButton(title: "Trình duyệt", systemImage: "safari", tint: .primary, action: onOpenBrowser)
            }
            actionButton(
                title: ext.isPinned ? "Bỏ ghim" : "Ghim",
                systemImage: ext.isPinned ? "pin.fill" : "pin",
                tint: ext.isPinned ? .orange : .primary,
                isHighlighted: ext.isPinned,
                action: { togglePin() }
            )
            if let onUninstall {
                actionButton(title: "Gỡ", systemImage: "trash", tint: .red, action: onUninstall)
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button(action: { action() }) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isHighlighted ? tint.opacity(0.15) : Color(.tertiarySystemFill))
                .clipShape(shape)
                .contentShape(shape)
        }
        .frame(maxWidth: .infinity)
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
