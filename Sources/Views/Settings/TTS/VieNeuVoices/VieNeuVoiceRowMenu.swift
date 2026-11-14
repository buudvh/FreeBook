import SwiftUI

/// Menu **nhấn giữ** của một hàng ở sheet chọn giọng VieNeu: "Tạo bản Turbo" / "Tạo bản Nano" (1.3.937) khi giọng chưa có
/// bản ở model kia (`VieNeuVoiceDirectory.copySource(for:)`), cộng Đổi tên / Xoá cho giọng nhân bản (1.3.900). Không có
/// mục nào ⇒ không gắn menu (hàng giọng có sẵn đã có cặp).
struct VieNeuVoiceRowMenu: ViewModifier {
    let entry: VieNeuVoiceEntry
    let copySource: VieNeuVoiceCopySource?
    /// Giọng nguồn đã tải đủ và không có lượt tạo nào đang chạy.
    let canCopy: Bool
    let onCopy: (VieNeuVoiceCopySource) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if entry.isMine || copySource != nil {
            content.contextMenu {
                if let copySource {
                    Button {
                        onCopy(copySource)
                    } label: {
                        Label("Tạo bản \(copySource.target.label)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!canCopy)
                }
                if entry.isMine {
                    Button(action: onRename) {
                        Label("Đổi tên", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Xoá giọng", systemImage: "trash")
                    }
                }
            }
        } else {
            content
        }
    }
}
