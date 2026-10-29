import SwiftUI

/// Sheet xác nhận "Nhập phim" (mockup đã duyệt): tên phim sửa được, dòng "N file → 1 phim, xếp theo tên file" và danh
/// sách "Tập N · tên file" theo thứ tự sẽ nhập.
///
/// Không có nút "Huỷ": vuốt xuống là bỏ. Sheet tự gọi `onDiscard` khi biến mất mà chưa bấm "Nhập", nên các file đã nhận
/// luôn được dọn dù đóng bằng cách nào.
struct LocalVideoImportSheet: View {
    let plan: LocalVideoImportPlan
    let onConfirm: (String) -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var didConfirm = false

    init(plan: LocalVideoImportPlan, onConfirm: @escaping (String) -> Void, onDiscard: @escaping () -> Void) {
        self.plan = plan
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        _title = State(initialValue: plan.defaultTitle)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Tên phim", text: $title)
                        .textInputAutocapitalization(.sentences)
                    Text("\(plan.episodes.count) file → 1 phim, xếp theo tên file")
                    LabeledContent("Dung lượng", value: ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))
                } header: {
                    Text("Phim")
                }

                Section {
                    ForEach(plan.episodes) { episode in
                        episodeRow(episode)
                    }
                } header: {
                    Text("Tập")
                }
            }
            .listStyle(.insetGrouped)
            .pageTitle("Nhập phim")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Nhập") {
                        didConfirm = true
                        onConfirm(trimmedTitle)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onDisappear {
            if !didConfirm {
                onDiscard()
            }
        }
    }

    private func episodeRow(_ episode: LocalVideoImportPlan.Episode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tập \(episode.id + 1) · \(episode.fileName)")
                .font(.headline)
                .lineLimit(2)
            Text(ByteCountFormatter.string(fromByteCount: episode.bytes, countStyle: .file))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
