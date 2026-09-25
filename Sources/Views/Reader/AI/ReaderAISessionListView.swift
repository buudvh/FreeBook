import SwiftUI

/// Sheet quản lý và chuyển đổi giữa các phiên chat của cuốn truyện.
public struct ReaderAISessionListView: View {
    @Environment(\.dismiss) private var dismiss

    public let bookId: String
    @Binding public var currentSessionId: UUID
    public let onSelectSession: (AIChatSession) -> Void
    public let onNewSession: () -> Void

    @State private var sessions: [AIChatSession] = []
    @State private var showingClearAllAlert = false

    public init(
        bookId: String,
        currentSessionId: Binding<UUID>,
        onSelectSession: @escaping (AIChatSession) -> Void,
        onNewSession: @escaping () -> Void
    ) {
        self.bookId = bookId
        self._currentSessionId = currentSessionId
        self.onSelectSession = onSelectSession
        self.onNewSession = onNewSession
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: {
                        onNewSession()
                        dismiss()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color(red: 36/255.0, green: 44/255.0, blue: 56/255.0))
                                .font(.system(size: 20))
                            Text("Bắt đầu phiên chat mới")
                                .fontWeight(.medium)
                        }
                    }
                }

                Section(header: Text("Các phiên chat đã lưu (\(sessions.count))")) {
                    if sessions.isEmpty {
                        Text("Chưa có phiên chat nào.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(sessions) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(session.title)
                                            .font(.subheadline)
                                            .fontWeight(session.id == currentSessionId ? .bold : .medium)
                                            .foregroundColor(session.id == currentSessionId ? Color(red: 36/255.0, green: 44/255.0, blue: 56/255.0) : .primary)
                                            .lineLimit(1)

                                        if session.id == currentSessionId {
                                            Text("Hiện tại")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color(red: 36/255.0, green: 44/255.0, blue: 56/255.0).opacity(0.15))
                                                .foregroundColor(Color(red: 36/255.0, green: 44/255.0, blue: 56/255.0))
                                                .cornerRadius(4)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Text("\(session.messages.count) tin nhắn")
                                        Text("•")
                                        Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        Text("•")
                                        Text(session.model)
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    deleteSession(session)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.7))
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.borderless)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectSession(session)
                                dismiss()
                            }
                        }
                        .onDelete(perform: deleteSessionsAtOffsets)
                    }
                }

                if !sessions.isEmpty {
                    Section {
                        Button(role: .destructive, action: { showingClearAllAlert = true }) {
                            HStack {
                                Spacer()
                                Text("Xóa toàn bộ phiên chat của truyện này")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lịch sử phiên chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .alert("Xóa toàn bộ phiên chat?", isPresented: $showingClearAllAlert) {
                Button("Xóa tất cả", role: .destructive) {
                    clearAll()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Hành động này sẽ xóa toàn bộ lịch sử các cuộc trò chuyện AI của cuốn truyện này và không thể hoàn tác.")
            }
            .onAppear(perform: loadSessions)
        }
    }

    private func loadSessions() {
        sessions = AIChatHistoryStore.shared.loadSessions(for: bookId)
    }

    private func deleteSession(_ session: AIChatSession) {
        AIChatHistoryStore.shared.deleteSession(sessionId: session.id, for: bookId)
        loadSessions()
    }

    private func deleteSessionsAtOffsets(_ offsets: IndexSet) {
        for idx in offsets {
            let session = sessions[idx]
            AIChatHistoryStore.shared.deleteSession(sessionId: session.id, for: bookId)
        }
        loadSessions()
    }

    private func clearAll() {
        AIChatHistoryStore.shared.clearAllSessions(for: bookId)
        loadSessions()
        onNewSession()
        dismiss()
    }
}
