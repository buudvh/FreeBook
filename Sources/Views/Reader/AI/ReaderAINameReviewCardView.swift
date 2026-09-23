import SwiftUI

/// Bảng duyệt danh sách tên riêng trích xuất từ văn bản truyện.
public struct ReaderAINameReviewCardView: View {
    @Binding public var names: [AIExtractedName]
    public let onSave: ([AIExtractedName], Bool, Bool) -> Void
    public var onDelete: ((UUID) -> Void)? = nil

    @State private var showingModeDialog: Bool = false
    @State private var pendingIsName: Bool = true
    @State private var savedConfirmationMessage: String? = nil

    public init(
        names: Binding<[AIExtractedName]>,
        onSave: @escaping ([AIExtractedName], Bool, Bool) -> Void,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self._names = names
        self.onSave = onSave
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.blue)
                    Text("Tên riêng tìm thấy (\(names.count))")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                Button(allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả") {
                    toggleSelectAll()
                }
                .font(.system(size: 11))
            }
            .padding(.bottom, 2)

            // Danh sách tên riêng
            VStack(spacing: 6) {
                ForEach($names) { $item in
                    HStack(spacing: 8) {
                        Button(action: {
                            item.isSelected.toggle()
                        }) {
                            Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isSelected ? .blue : .secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.original)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)

                                Text(item.category)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)

                                if item.occurrenceCount > 1 {
                                    Text("\(item.occurrenceCount) lần")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }

                            TextField("Nghĩa Hán-Việt/Dịch", text: $item.suggestedMeaning)
                                .font(.system(size: 12))
                                .textFieldStyle(.plain)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Nút xóa từng mục
                        Button(action: {
                            deleteItem(id: item.id)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }

            // Phần lưu từ điển hoặc banner thông báo sau khi lưu
            if let confirmation = savedConfirmationMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text(confirmation)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
                .cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    // Nút Lưu vào Name riêng
                    Button(action: {
                        pendingIsName = true
                        showingModeDialog = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.rectangle.stack")
                            Text("Lưu Name riêng (\(selectedCount))")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(selectedCount == 0)

                    // Nút Lưu vào VP riêng
                    Button(action: {
                        pendingIsName = false
                        showingModeDialog = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.book.closed")
                            Text("Lưu VP riêng (\(selectedCount))")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(selectedCount == 0)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .confirmationDialog(
            "Lựa chọn chế độ lưu vào \(pendingIsName ? "Name riêng" : "VietPhrase riêng")",
            isPresented: $showingModeDialog,
            titleVisibility: .visible
        ) {
            Button("Gộp (trùng từ thì thay mới)") {
                executeSave(isName: pendingIsName, isMerge: true)
            }
            Button("Thay thế hoàn toàn", role: .destructive) {
                executeSave(isName: pendingIsName, isMerge: false)
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text(pendingIsName
                 ? "Chế độ Gộp sẽ thêm các tên mới vào Names.txt và giữ nguyên các tên cũ. Chế độ Thay thế sẽ làm mới hoàn toàn Names.txt của truyện."
                 : "Chế độ Gộp sẽ thêm các từ mới vào VietPhrase.txt và giữ nguyên các từ cũ. Chế độ Thay thế sẽ làm mới hoàn toàn VietPhrase.txt của truyện."
            )
        }
    }

    private var allSelected: Bool {
        names.allSatisfy { $0.isSelected }
    }

    private var selectedCount: Int {
        names.filter { $0.isSelected }.count
    }

    private func toggleSelectAll() {
        let target = !allSelected
        for idx in names.indices {
            names[idx].isSelected = target
        }
    }

    private func deleteItem(id: UUID) {
        names.removeAll(where: { $0.id == id })
        onDelete?(id)
    }

    private func executeSave(isName: Bool, isMerge: Bool) {
        let chosen = names.filter { $0.isSelected }
        guard !chosen.isEmpty else { return }
        onSave(chosen, isName, isMerge)
        let targetName = isName ? "Name riêng" : "VP riêng"
        savedConfirmationMessage = "Đã lưu \(chosen.count) mục vào \(targetName) của truyện"
    }
}
