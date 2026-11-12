import SwiftUI

/// Sheet "Bản cập nhật mới" (mở từ dải báo ở Kệ hoặc hàng ở Cài đặt › Thông Tin): danh sách thay đổi của bản mới,
/// hướng dẫn cập nhật trong LiveContainer, nút "Mở LiveContainer" và "Bỏ qua bản này".
///
/// Không có nút "Cập nhật ngay": app đang chạy bên trong LiveContainer gọi `livecontainer://install` thì LiveContainer
/// chỉ báo "mở lại LiveContainer để cài" (đọc từ mã LiveContainer). Nút "Mở LiveContainer" dùng
/// `livecontainer://livecontainer-launch?bundle-name=ui` — chuyển về màn chính LiveContainer (có hộp xác nhận); chưa
/// thử trên máy. Mở sheet ⇒ đánh dấu đã xem (tắt chấm đỏ tab Cài Đặt).
struct AppUpdateSheet: View {
    let update: AppUpdateInfo

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if !update.notes.isEmpty {
                    panel {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(update.notes.enumerated()), id: \.offset) { _, note in
                                Text(verbatim: "• \(note)")
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Text("Cách cập nhật")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                panel {
                    Text("Mở LiveContainer › Sources › Refresh › Install, chọn thay app cũ để giữ dữ liệu.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: openLiveContainer) {
                    Label("Mở LiveContainer", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.appFilled)
                .padding(.top, 8)

                Button {
                    AppUpdateRepository.shared.skipCurrent()
                    dismiss()
                } label: {
                    Text("Bỏ qua bản này")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { AppUpdateRepository.shared.markSeen() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Bản cập nhật mới")
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text("\(update.display) · đang dùng \(AppVersionInfo.display)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppGlassSheetModifier.rowFill, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Dừng phát nền trước (`LiveContainerSwitchPreparer`, 1.3.824): đang nghe mà chuyển thì LiveContainer tự tắt app nhưng
    /// iOS không mở lại.
    private func openLiveContainer() {
        guard let url = AppUpdateRepository.shared.openLiveContainerURL else { return }
        let openURL = openURL
        Task {
            await LiveContainerSwitchPreparer.prepare()
            openURL(url) { accepted in
                if !accepted {
                    ToastManager.shared.show(message: "Không mở được LiveContainer", type: .error, recordsInInbox: false)
                }
            }
        }
    }
}
