import SwiftUI

/// Sheet "Có gì mới ở bản này" (nút "?" cạnh "Phiên bản ứng dụng" ở Cài đặt › Thông Tin, 1.3.810): danh sách thay đổi của
/// **bản đang chạy**, theo khuôn `AppUpdateSheet` (icon màu nhấn + tiêu đề 22 đậm, dòng phụ, panel bo 12). Không có nút
/// cập nhật, không có nút chỉ để đóng — vuốt xuống.
///
/// Ghi chú lấy qua `AppReleaseNotesLoader`: `ReleaseNotes.txt` CI nhét vào IPA → bản cùng số build trên nguồn cập nhật
/// (`apps.json`, chỉ 5 bản gần nhất) → không có ⇒ "Không còn ghi chú cho bản này".
struct AppReleaseNotesSheet: View {
    /// `nil` = đang tải.
    @State private var notes: [String]? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                panel {
                    if let notes {
                        if notes.isEmpty {
                            Text("Không còn ghi chú cho bản này")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                                    Text(verbatim: "• \(note)")
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Đang tải ghi chú…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard notes == nil else { return }
            notes = await AppReleaseNotesLoader.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Có gì mới ở bản này")
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text("\(AppVersionInfo.display) · bản đang dùng")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
