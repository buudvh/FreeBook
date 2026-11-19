import SwiftUI

/// Thẻ của popup **chọn cách nhập** (1.3.982, anh Bửu duyệt mockup 2026-11-19: "popup giữa màn hình, gồm 3 radio cho 3
/// option, mỗi option có mô tả và cuối cùng là nút nhập file"). Trình bày qua `.dataImportModePopup(...)`
/// (`DataImportModePopupModifier`) — đừng dựng view này trực tiếp.
///
/// - Lớp tối phủ cả màn; chạm ra ngoài thẻ ⇒ `onCancel` (không có nút Huỷ, như chuẩn sheet của app).
/// - Mỗi hàng: vòng radio (màu nhấn khi chọn) + tên chế độ (`DataImportMode.actionTitle`) + một dòng mô tả
///   (`DataImportMode.explanation`). Nút cuối nền đặc màu nhấn (`.appFilled`) ⇒ `onConfirm(selection)`.
/// - Tông tối cục bộ (`colorScheme` của environment, không `preferredColorScheme` — không đổi giao diện màn bên dưới).
struct DataImportModePopup: View {
    let title: String
    let confirmTitle: String
    let confirmSystemImage: String
    let modes: [DataImportMode]
    let onConfirm: (DataImportMode) -> Void
    let onCancel: () -> Void

    @State private var selection: DataImportMode
    @State private var appeared = false

    init(
        title: String,
        confirmTitle: String,
        confirmSystemImage: String,
        modes: [DataImportMode],
        initialMode: DataImportMode,
        onConfirm: @escaping (DataImportMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.confirmSystemImage = confirmSystemImage
        self.modes = modes.isEmpty ? DataImportMode.allCases : modes
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selection = State(initialValue: self.modes.contains(initialMode) ? initialMode : self.modes[0])
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Đóng")

            card
                .frame(maxWidth: 320)
                .padding(.horizontal, 24)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) { appeared = true }
        }
        .appAccentTint()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            Text("Chọn cách nhập")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, 6)

            ForEach(modes, id: \.self) { mode in
                Divider().opacity(0.6)
                modeRow(mode)
            }

            Button {
                onConfirm(selection)
            } label: {
                Label(confirmTitle, systemImage: confirmSystemImage)
            }
            .buttonStyle(.appFilled)
            .padding(.top, 12)
        }
        .padding(16)
        .background { DrawerGlassSheetBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
        // Chạm trong thẻ không rơi xuống lớp tối bên dưới.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {}
    }

    private func modeRow(_ mode: DataImportMode) -> some View {
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(mode.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
