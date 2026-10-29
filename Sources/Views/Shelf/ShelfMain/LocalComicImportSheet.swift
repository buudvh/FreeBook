import SwiftUI

/// Sheet xác nhận "Nhập truyện tranh" (mockup đã duyệt): tên truyện sửa được (mặc định = tên file), tên file, số thư mục
/// con và danh sách "Chương N · X ảnh" theo thứ tự sẽ nhập.
///
/// Không có nút "Huỷ": vuốt xuống là bỏ. Sheet tự gọi `onDiscard` khi biến mất mà chưa bấm "Nhập", nên thư mục giải nén
/// luôn được dọn dù đóng bằng cách nào.
struct LocalComicImportSheet: View {
    let plan: LocalComicImportPlan
    let onConfirm: (String) -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var didConfirm = false

    init(plan: LocalComicImportPlan, onConfirm: @escaping (String) -> Void, onDiscard: @escaping () -> Void) {
        self.plan = plan
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        _title = State(initialValue: plan.defaultTitle)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var folderSummary: String {
        plan.folderCount == 0 ? "Không có — cả file là 1 chương" : "\(plan.folderCount) thư mục"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Tên truyện", text: $title)
                        .textInputAutocapitalization(.sentences)
                    LabeledContent("File", value: plan.fileName)
                    LabeledContent("Thư mục con", value: folderSummary)
                    LabeledContent("Tổng", value: "\(plan.chapters.count) chương · \(plan.pageCount) ảnh")
                } header: {
                    Text("Truyện tranh")
                }

                Section {
                    ForEach(plan.chapters) { chapter in
                        chapterRow(chapter)
                    }
                } header: {
                    Text("Chương (xếp theo tên thư mục)")
                }
            }
            .listStyle(.insetGrouped)
            .pageTitle("Nhập truyện tranh")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Nhập") {
                        didConfirm = true
                        onConfirm(trimmedTitle)
                        dismiss()
                    }
                    .headerTextButton()
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

    private func chapterRow(_ chapter: LocalComicImportPlan.Chapter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Chương \(chapter.id + 1) · \(chapter.pages.count) ảnh")
                .font(.headline)
            if !chapter.folderPath.isEmpty {
                Text(chapter.folderPath)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
