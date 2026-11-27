import SwiftUI

/// Thẻ của popup **chọn cách nhập** (1.3.982, anh Bửu duyệt mockup 2026-11-19: "popup giữa màn hình, gồm 3 radio cho 3
/// option, mỗi option có mô tả và cuối cùng là nút nhập file"). Trình bày qua `.dataImportFilePicker(...)` (nhập file —
/// chọn file trước, popup sau, tên file dưới tiêu đề, 1.3.1011) hoặc `.dataImportModePopup(...)` (nhập không qua file) —
/// đừng dựng view này trực tiếp.
///
/// - Lớp tối phủ cả màn; chạm ra ngoài thẻ ⇒ `onCancel` (không có nút Huỷ, như chuẩn sheet của app).
/// - Mỗi hàng: vòng radio (màu nhấn khi chọn) + tên chế độ (`DataImportMode.actionTitle`) + một dòng mô tả
///   (`DataImportMode.explanation`, hoặc lời riêng theo ngữ cảnh ở `explanations`). Nút cuối nền đặc màu nhấn
///   (`.appFilled`) ⇒ `onConfirm(selection)`.
/// - Tông tối cục bộ (`colorScheme` của environment, không `preferredColorScheme` — không đổi giao diện màn bên dưới).
/// - Chỗ không phải nhập file (plan 2026-11-27-phan-loai-name L16: Lưu ở màn duyệt name) truyền icon dòng dưới tiêu đề
///   (`messageSystemImage`) và lời giải thích ba chế độ theo ngữ cảnh (`explanations`) — đừng nói "file" ở đó.
struct DataImportModePopup: View {
    /// Icon mặc định của dòng dưới tiêu đề (tên file).
    static let fileMessageIcon = "doc.text"

    let title: String
    /// Dòng mô tả dưới tiêu đề — tên file vừa chọn (1.3.1011, anh Bửu: "hiển thị tên file nhập ở phần mô tả dưới tiêu đề
    /// nhập"); `nil` ⇒ "Chọn cách nhập".
    let message: String?
    /// Icon trước `message`: mặc định `fileMessageIcon` (tên file); ngữ cảnh khác truyền icon hợp ngữ cảnh.
    let messageSystemImage: String
    /// Lời giải thích riêng theo ngữ cảnh của từng chế độ; chế độ không có ở đây ⇒ `DataImportMode.explanation`.
    let explanations: [DataImportMode: String]
    let confirmTitle: String
    let confirmSystemImage: String
    let modes: [DataImportMode]
    let onConfirm: (DataImportMode) -> Void
    let onCancel: () -> Void

    @State private var selection: DataImportMode
    @State private var appeared = false

    init(
        title: String,
        message: String?,
        messageSystemImage: String = DataImportModePopup.fileMessageIcon,
        explanations: [DataImportMode: String] = [:],
        confirmTitle: String,
        confirmSystemImage: String,
        modes: [DataImportMode],
        initialMode: DataImportMode,
        onConfirm: @escaping (DataImportMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.messageSystemImage = messageSystemImage
        self.explanations = explanations
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
            subtitle
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

    /// Tên file (icon tài liệu + tên, dài thì cắt giữa để thấy cả đuôi `.txt`), dòng mô tả theo ngữ cảnh (icon riêng) hoặc
    /// "Chọn cách nhập".
    @ViewBuilder
    private var subtitle: some View {
        if let message, !message.isEmpty {
            Label {
                Text(message)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: messageSystemImage)
            }
            .accessibilityLabel(messageSystemImage == Self.fileMessageIcon ? "File: \(message)" : message)
        } else {
            Text("Chọn cách nhập")
        }
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
                    Text(explanations[mode] ?? mode.explanation)
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
