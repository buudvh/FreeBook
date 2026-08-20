import SwiftUI

/// Sheet xác nhận thông tin trước khi nhập truyện TXT vào CSDL.
/// Hiển thị tên truyện, số chương, tên file và danh sách toàn bộ chương
/// để người dùng kiểm tra kết quả parse trước khi bấm "Nhập".
struct TXTImportConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let fileName: String
    let totalChapters: Int
    let chapterTitles: [String]

    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.title2)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.headline)
                                    .lineLimit(3)

                                Text("\(totalChapters) chương")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("File: \(fileName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Danh sách chương")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            ForEach(Array(chapterTitles.enumerated()), id: \.offset) { index, chapterTitle in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 32, alignment: .trailing)

                                    Text(chapterTitle)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(16)
                }

                Divider()

                HStack(spacing: 12) {
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("Hủy")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Text("Nhập")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(16)
            }
            .navigationTitle("Xác nhận nhập truyện")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}