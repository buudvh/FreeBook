import SwiftUI

/// Màn hình quản lý danh sách toàn bộ phiên chat AI trên tất cả các cuốn truyện.
public struct AIChatAllSessionsManagerView: View {
    @State private var sessions: [AIChatSessionSummary] = []
    @State private var searchText: String = ""
    @State private var sessionToDelete: AIChatSessionSummary? = nil
    @State private var showingClearAllAlert: Bool = false
    @State private var isLoading: Bool = true

    public init() {}

    private var filteredSessions: [AIChatSessionSummary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return sessions
        }
        return sessions.filter {
            $0.title.lowercased().contains(trimmed) ||
            $0.model.lowercased().contains(trimmed) ||
            $0.bookId.lowercased().contains(trimmed)
        }
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView("Đang tải danh sách phiên chat...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Chưa có phiên chat nào")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Các cuộc trò chuyện với AI trong trình đọc sẽ được lưu trữ tại đây.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: Text("Tất cả phiên chat (\(filteredSessions.count))")) {
                        ForEach(filteredSessions) { session in
                            sessionRow(session)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        sessionToDelete = session
                                    } label: {
                                        Label("Xóa", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Tìm theo tiêu đề hoặc model...")
            }
        }
        .navigationTitle("Lịch sử phiên chat AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                if !sessions.isEmpty {
                    Button(role: .destructive) {
                        showingClearAllAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Dọn dẹp tất cả phiên chat")
                }
            }
        }
        .onAppear(perform: loadAllSessions)
        .alert("Xóa phiên chat này?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Xóa", role: .destructive) {
                if let target = sessionToDelete {
                    deleteSingleSession(target)
                }
            }
            Button("Hủy", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            if let target = sessionToDelete {
                Text("Bạn có chắc muốn xóa phiên chat \"\(target.title)\"?")
            }
        }
        .alert("Dọn dẹp tất cả phiên chat?", isPresented: $showingClearAllAlert) {
            Button("Dọn dẹp tất cả", role: .destructive) {
                clearAll()
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Hành động này sẽ xóa vĩnh viễn toàn bộ lịch sử trò chuyện AI của tất cả truyện và không thể hoàn tác.")
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: AIChatSessionSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(session.messageCount) tin nhắn")
                    Text("•")
                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("•")
                    Text(session.model)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                sessionToDelete = session
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func loadAllSessions() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let loaded = AIChatHistoryStore.shared.loadAllSessionsAcrossAllBooks()
            await MainActor.run {
                self.sessions = loaded
                self.isLoading = false
            }
        }
    }

    private func deleteSingleSession(_ session: AIChatSessionSummary) {
        AIChatHistoryStore.shared.deleteSession(sessionId: session.id, for: session.bookId)
        sessions.removeAll(where: { $0.id == session.id })
        sessionToDelete = nil
    }

    private func clearAll() {
        AIChatHistoryStore.shared.clearAllSessionsAcrossAllBooks()
        sessions.removeAll()
    }
}
