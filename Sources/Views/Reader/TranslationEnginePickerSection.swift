import SwiftUI

/// Mục **BỘ DỊCH** của popup dịch (`TranslationScopePopupView`): hàng bộ dịch đang chọn; bấm ⇒ danh sách xổ **tại chỗ**
/// ngay trong popup, đẩy các hàng bên dưới xuống (không đè). Không dùng `Menu` hệ thống: iOS đặt ảnh ở cuối dòng và hay
/// tô ảnh một màu, mất icon tiện ích.
///
/// Thứ tự: "Theo cấp trên (<bộ dịch cấp trên>)" (chỉ phạm vi Truyện / Nguồn) → QT (icon app) → tiện ích loại
/// `translate` đã cài. Lựa chọn đã lưu trỏ tới tiện ích đã gỡ vẫn hiện ở hàng đang chọn (kèm "đã gỡ") để thấy mà đổi.
/// Chọn xong danh sách tự đóng.
struct TranslationEnginePickerSection: View {
    typealias Choice = TranslationEngineDraft.Choice

    let choice: Choice
    /// Tên bộ dịch cấp trên đang hiệu lực; `nil` ⇒ không có dòng "Theo cấp trên" (phạm vi Toàn cục).
    let inheritedEngineName: String?
    /// Tiện ích loại `translate` đã cài.
    let engines: [Extension]
    let onSelect: (Choice) -> Void

    @State private var isExpanded = false

    private static let iconSize: CGFloat = 22
    private static let iconCornerRadius: CGFloat = 5
    /// Icon app trong Assets (cùng ảnh với màn khoá khi phát phim / nhạc 18+).
    private static let appIconAssetName = "LockScreenAppIcon"
    /// Quá số dòng này thì danh sách cuộn trong khung cố định, popover không cao quá màn.
    private static let maxVisibleRows = 6
    private static let rowHeight: CGFloat = 37

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BỘ DỊCH")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                currentRow
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bộ dịch: \(title(for: choice))")
            .accessibilityHint(isExpanded ? "Đóng danh sách bộ dịch" : "Mở danh sách bộ dịch")

            if isExpanded {
                optionList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Hàng đang chọn

    private var currentRow: some View {
        HStack(spacing: 8) {
            icon(for: choice)
            Text(verbatim: title(for: choice))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.top, 7)
        .padding(.trailing, 12)
        .padding(.bottom, 7)
        .padding(.leading, 8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Danh sách xổ

    private var options: [Choice] {
        var list: [Choice] = []
        if inheritedEngineName != nil { list.append(.inherit) }
        list.append(.quickTranslator)
        list.append(contentsOf: engines.map { Choice.extensionEngine($0.packageId) })
        return list
    }

    @ViewBuilder
    private var optionList: some View {
        let rowCount = options.count + (engines.isEmpty ? 1 : 0)
        if rowCount > Self.maxVisibleRows {
            ScrollView {
                optionStack
            }
            .frame(height: CGFloat(Self.maxVisibleRows) * Self.rowHeight)
            .modifier(OptionListFrame())
        } else {
            optionStack
                .modifier(OptionListFrame())
        }
    }

    private var optionStack: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                if index > 0 { separator }
                optionRow(option)
            }
            if engines.isEmpty {
                separator
                emptyRow
            }
        }
    }

    private func optionRow(_ option: Choice) -> some View {
        let isSelected = option == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded = false }
            onSelect(option)
        } label: {
            HStack(spacing: 8) {
                icon(for: option)
                Text(verbatim: title(for: option))
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Dòng mờ khi chưa cài tiện ích dịch nào — không bấm được.
    private var emptyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: Self.iconSize, height: Self.iconSize)
            Text("Chưa cài tiện ích dịch nào")
                .font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .foregroundColor(.secondary)
        .opacity(0.7)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 0.5)
    }

    // MARK: - Tên + icon

    private func engine(_ packageId: String) -> Extension? {
        engines.first { $0.packageId == packageId }
    }

    private func title(for option: Choice) -> String {
        switch option {
        case .inherit:
            return "Theo cấp trên (\(inheritedEngineName ?? TranslationEngineStore.quickTranslatorName))"
        case .quickTranslator:
            return TranslationEngineStore.quickTranslatorName
        case .extensionEngine(let id):
            // Tiện ích đã gỡ / không còn là loại dịch: `TranslationEngineStore.resolve` đang lùi về QT.
            return engine(id)?.name ?? "\(id) (đã gỡ — đang dùng QT)"
        }
    }

    @ViewBuilder
    private func icon(for option: Choice) -> some View {
        switch option {
        case .inherit:
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.iconCornerRadius)
                        .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                )
        case .quickTranslator:
            Image(Self.appIconAssetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: Self.iconCornerRadius))
        case .extensionEngine(let id):
            if let ext = engine(id) {
                ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: Self.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: Self.iconCornerRadius))
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Self.iconCornerRadius))
            }
        }
    }

    /// Khung của danh sách xổ: viền mảnh, bo góc như hàng đang chọn.
    private struct OptionListFrame: ViewModifier {
        func body(content: Content) -> some View {
            content
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}
