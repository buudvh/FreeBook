import SwiftUI

/// Sheet danh sách toàn bộ lịch sử duyệt web dạng LazyVStack cuộn mượt, tìm kiếm và xoá từng mục.
public struct BrowserHistorySheetView: View {
    public let onSelectUrl: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var historyItems: [BrowserHistoryStore.Item] = []
    @State private var searchText: String = ""
    @State private var showingClearConfirmation: Bool = false

    public init(onSelectUrl: @escaping (String) -> Void) {
        self.onSelectUrl = onSelectUrl
    }

    private var filteredItems: [BrowserHistoryStore.Item] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return historyItems }
        return historyItems.filter {
            $0.title.lowercased().contains(query) || $0.urlString.lowercased().contains(query)
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "Chưa có lịch sử duyệt web" : "Không tìm thấy kết quả phù hợp")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredItems) { item in
                                Button(action: {
                                    onSelectUrl(item.urlString)
                                    dismiss()
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "globe")
                                            .font(.system(size: 16))
                                            .foregroundColor(.blue)
                                            .frame(width: 32, height: 32)
                                            .background(Color.blue.opacity(0.12))
                                            .clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(item.urlString)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Button(action: {
                                            deleteItem(item.id)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.secondary)
                                                .padding(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Lịch sử duyệt web")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Tìm kiếm tiêu đề hoặc link...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    if !historyItems.isEmpty {
                        Button("Xóa tất cả") {
                            showingClearConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("Xác nhận xóa lịch sử", isPresented: $showingClearConfirmation) {
                Button("Xóa toàn bộ", role: .destructive) {
                    BrowserHistoryStore.shared.clearAll()
                    historyItems = []
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Toàn bộ lịch sử duyệt web bypass sẽ bị xóa vĩnh viễn.")
            }
            .onAppear {
                reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: BrowserHistoryStore.didChangeNotification)) { _ in
                reload()
            }
        }
    }

    private func reload() {
        historyItems = BrowserHistoryStore.shared.load()
    }

    private func deleteItem(_ id: String) {
        BrowserHistoryStore.shared.delete(id: id)
        historyItems.removeAll { $0.id == id }
    }
}
